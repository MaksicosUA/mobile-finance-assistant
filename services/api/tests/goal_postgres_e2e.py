"""Opt-in PostgreSQL E2E for the savings-goal slice (ADR 0019).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/goal_postgres_e2e.py

It is not collected by pytest: `testpaths` only picks up `test_*.py`, so this
script stays opt-in and never blocks CI, which provisions no database.

It proves what the in-memory fake cannot: that the SQL balance aggregate agrees
with the Python fold, that the row lock stops a racing withdrawal, that audit
and outbox rows are written in the same transaction as the state change, and
that a contribution changes no authoritative Home figure.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceGoalAuditRow,
    FinanceGoalContributionRow,
    FinanceGoalOutboxEventRow,
    FinanceGoalRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.goal_contracts import (
    RecordGoalContributionCommand,
    apply_contribution,
)
from mobile_finance_api.goal_core import GoalCore, GoalWithdrawalExceedsBalance
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_goal_repository import PostgresGoalRepository
from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-savings-goal-secret-32-bytes-minimum"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
TIMEZONE = "Europe/Berlin"
OPENING_ON = (datetime.now(UTC) - timedelta(days=60)).date()
TARGET_ON = (datetime.now(UTC) + timedelta(days=300)).date()


@dataclass(frozen=True, slots=True)
class _Identity:
    user_id: UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


def _alembic_config() -> Config:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    return config


def _empty_migration_round_trip() -> None:
    config = _alembic_config()
    command.upgrade(config, "head")
    command.downgrade(config, "0009_payment_due_on")
    command.upgrade(config, "head")


def _assert_lossy_downgrade_refused() -> None:
    config = _alembic_config()
    try:
        command.downgrade(config, "0009_payment_due_on")
    except RuntimeError as error:
        assert "Refusing lossy downgrade" in str(error), str(error)
    else:
        raise AssertionError("populated savings-goal downgrade was not refused")


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):
    accounts = PostgresFinanceAccountRepository(session_factory=session_factory)
    return create_app(
        home_repository=PostgresHomeRepository(session_factory=session_factory),
        current_user_authenticator=PostgresCurrentUserAuthenticator(
            session_factory=session_factory,
            access_tokens=tokens,
        ),
        authentication_service=PostgresAuthenticationService(
            session_factory=session_factory,
            password_service=PasswordService(),
            access_tokens=tokens,
        ),
        account_core=AccountCore(repository=accounts),
        finance_core=FinanceCore(
            repository=PostgresFinanceOperationRepository(
                session_factory=session_factory,
            ),
            account_directory=accounts,
        ),
        goal_core=GoalCore(
            repository=PostgresGoalRepository(session_factory=session_factory),
        ),
    )


async def _register(client: AsyncClient, *, email: str, name: str) -> _Identity:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "synthetic-password-123",
            "displayName": name,
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()
    return _Identity(
        user_id=UUID(payload["user"]["id"]),
        token=str(payload["accessToken"]),
    )


async def _bootstrap_account(client: AsyncClient, *, identity: _Identity) -> UUID:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": "Synthetic primary account",
        "currency": "EUR",
        "openingBalance": "1000.00",
        "openingBalanceOn": OPENING_ON.isoformat(),
        "canonicalTimezone": TIMEZONE,
    }
    evaluation = await client.post(
        "/api/v1/accounts/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    evaluated = evaluation.json()
    commit = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluated["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text
    return UUID(commit.json()["account"]["accountId"])


def _goal_body(*, account_id: UUID, **changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "accountId": str(account_id),
        "title": "Отпуск",
        "targetAmount": "3000.00",
        "currency": "EUR",
        "targetOn": TARGET_ON.isoformat(),
        "monthlyContribution": "250.00",
        "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    body.update(changes)
    return body


def _entry_body(**changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "direction": "deposit",
        "amount": "500.00",
        "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    body.update(changes)
    return body


async def _assert_concurrent_withdrawals_cannot_overdraw(
    session_factory: AsyncSessionFactory,
    *,
    user_id: UUID,
    goal_id: UUID,
) -> Decimal:
    """Drive two racing withdrawals straight at the repository.

    The core's pre-check runs outside the write transaction, so both requests
    would see enough balance. Correctness here comes only from re-reading the
    ledger under the goal's row lock. Returns the surviving balance.
    """

    repository = PostgresGoalRepository(session_factory=session_factory)
    before = await repository.list_contributions(user_id=user_id, goal_id=goal_id)
    half = (before.goal.current_amount / 2) + Decimal("50.00")

    async def _withdraw() -> object:
        command_body = RecordGoalContributionCommand.model_validate(
            {
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "direction": "withdrawal",
                "amount": f"{half:f}",
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            }
        )
        try:
            return await repository.record_contribution(
                user_id=user_id,
                goal_id=goal_id,
                command=command_body,
                occurred_on=datetime.now(UTC).date(),
                payload_hash=uuid4().bytes + uuid4().bytes,
            )
        except GoalWithdrawalExceedsBalance:
            return GoalWithdrawalExceedsBalance

    outcomes = await asyncio.gather(_withdraw(), _withdraw())
    refused = [item for item in outcomes if item is GoalWithdrawalExceedsBalance]
    assert len(refused) == 1, outcomes

    after = await repository.list_contributions(user_id=user_id, goal_id=goal_id)
    assert after.goal.current_amount >= 0, after.goal.current_amount
    # Exactly one withdrawal landed, so the balance dropped once, not twice.
    assert after.goal.current_amount == before.goal.current_amount - half, (
        after.goal.current_amount,
        before.goal.current_amount,
    )
    assert len(after.contributions) == len(before.contributions) + 1, (
        after.contributions
    )
    return after.goal.current_amount


async def _scenario(engine: AsyncEngine, session_factory: AsyncSessionFactory) -> None:
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-test",
        audience="mfa-test-client",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        identity = await _register(
            client,
            email=f"goal-{uuid4().hex[:12]}@example.com",
            name="Synthetic Owner",
        )
        account_id = await _bootstrap_account(client, identity=identity)

        created = await client.post(
            "/api/v1/goals",
            json=_goal_body(account_id=account_id),
            headers=identity.headers,
        )
        assert created.status_code == 201, created.text
        goal = created.json()["goal"]
        goal_id = goal["goalId"]
        assert goal["currentAmount"] == "0", goal
        assert goal["progressPercent"] == "0", goal
        assert goal["achieved"] is False, goal

        projector = PostgresHomeProjector(session_factory=session_factory)
        await projector.drain_pending()
        home_before = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home_before.status_code == 200, home_before.text
        balance_before = Decimal(home_before.json()["balance"]["amount"])

        # --- the ledger drives the derived figure --------------------------
        first = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json=_entry_body(amount="500.00"),
            headers=identity.headers,
        )
        assert first.status_code == 201, first.text
        assert first.json()["goal"]["currentAmount"] == "500", first.text

        second_body = _entry_body(amount="1000.00")
        second = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json=second_body,
            headers=identity.headers,
        )
        assert second.status_code == 201, second.text
        assert second.json()["goal"]["currentAmount"] == "1500", second.text
        assert second.json()["goal"]["progressPercent"] == "50", second.text

        # An exact replay returns the original entry and never counts twice.
        replay = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json=second_body,
            headers=identity.headers,
        )
        assert replay.status_code == 200, replay.text
        assert replay.json()["idempotentReplay"] is True, replay.text
        assert replay.json()["goal"]["currentAmount"] == "1500", replay.text

        conflict = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json={**second_body, "amount": "999.00"},
            headers=identity.headers,
        )
        assert conflict.status_code == 409, conflict.text
        assert conflict.json()["detail"]["code"] == "COMMAND_CONFLICT", conflict.text

        withdrawal = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json=_entry_body(direction="withdrawal", amount="200.00"),
            headers=identity.headers,
        )
        assert withdrawal.status_code == 201, withdrawal.text
        assert withdrawal.json()["goal"]["currentAmount"] == "1300", withdrawal.text

        too_much = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json=_entry_body(direction="withdrawal", amount="1300.01"),
            headers=identity.headers,
        )
        assert too_much.status_code == 422, too_much.text
        assert [issue["code"] for issue in too_much.json()["detail"]["issues"]] == [
            "WITHDRAWAL_EXCEEDS_GOAL_BALANCE"
        ], too_much.text

        # --- the row lock, not the pre-check, is what makes this correct ----
        # Two withdrawals of 700 each pass the core's optimistic check against
        # a balance of 1300, so only `FOR UPDATE` can stop the second.
        settled_balance = await _assert_concurrent_withdrawals_cannot_overdraw(
            session_factory,
            user_id=identity.user_id,
            goal_id=UUID(goal_id),
        )

        # --- the projector fills the primaryGoal slot ----------------------
        await projector.drain_pending()
        home_after = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home_after.status_code == 200, home_after.text
        after = home_after.json()
        projected = after["primaryGoal"]
        assert projected is not None, after
        assert projected["id"] == goal_id, projected
        assert projected["title"] == "Отпуск", projected
        assert Decimal(projected["current"]) == settled_balance, projected
        assert Decimal(projected["target"]) == Decimal("3000.00"), projected
        assert projected["dueDate"] == TARGET_ON.isoformat(), projected
        assert Decimal(0) <= Decimal(projected["progressPercent"]) <= Decimal(100), (
            projected
        )

        # --- a contribution is an earmark, never a money movement ----------
        # Scale is a storage artifact of NUMERIC(38,18); compare money, not text.
        assert Decimal(after["balance"]["amount"]) == balance_before, after["balance"]
        assert Decimal(after["monthSummary"]["expense"]) == Decimal(0), after[
            "monthSummary"
        ]
        assert Decimal(after["monthSummary"]["income"]) == Decimal(0), after[
            "monthSummary"
        ]
        assert all(
            Decimal(point["amount"]) == Decimal(0) for point in after["trend"]["points"]
        ), after["trend"]

        # --- the SQL aggregate agrees with the Python fold -----------------
        async with session_factory() as database:
            entries = (
                await database.execute(
                    select(
                        FinanceGoalContributionRow.direction,
                        FinanceGoalContributionRow.amount,
                    )
                    .where(FinanceGoalContributionRow.goal_id == UUID(goal_id))
                    .order_by(FinanceGoalContributionRow.created_at)
                )
            ).all()
            folded = Decimal(0)
            for direction, amount in entries:
                folded = apply_contribution(
                    current=folded,
                    direction=direction,
                    amount=amount,
                )
            assert folded == settled_balance, (folded, settled_balance)

            audit_events = (
                await database.execute(
                    select(
                        FinanceGoalAuditRow.event_type,
                        func.count(),
                    )
                    .where(FinanceGoalAuditRow.goal_id == UUID(goal_id))
                    .group_by(FinanceGoalAuditRow.event_type)
                )
            ).all()
            audited = dict(audit_events)
            assert audited["goal_created"] == 1, audited
            # Three through HTTP plus the one that survived the race.
            assert audited["goal_contribution_recorded"] == 4, audited

            outbox = (
                await database.execute(
                    select(
                        FinanceGoalOutboxEventRow.event_type,
                        FinanceGoalOutboxEventRow.payload,
                    ).where(FinanceGoalOutboxEventRow.aggregate_id == UUID(goal_id))
                )
            ).all()
            assert len(outbox) == 5, outbox
            for event_type, payload in outbox:
                assert event_type.startswith("finance.goal."), event_type
                # Identifier-only: never an amount and never a title.
                assert set(payload) == {
                    "schemaVersion",
                    "goalId",
                    "userId",
                    "commandId",
                }, payload

        # --- cancellation keeps the evidence -------------------------------
        cancelled = await client.post(
            f"/api/v1/goals/{goal_id}/cancel",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["goal"]["status"] == "cancelled", cancelled.text
        assert Decimal(cancelled.json()["goal"]["currentAmount"]) == settled_balance, (
            cancelled.text
        )

        refused = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json=_entry_body(),
            headers=identity.headers,
        )
        assert refused.status_code == 422, refused.text
        assert [issue["code"] for issue in refused.json()["detail"]["issues"]] == [
            "GOAL_NOT_ACTIVE"
        ], refused.text

        # A cancelled goal stops being primary, and Home says so rather than
        # keeping a stale card the user already dismissed.
        await projector.drain_pending()
        home_cancelled = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home_cancelled.status_code == 200, home_cancelled.text
        assert home_cancelled.json()["primaryGoal"] is None, home_cancelled.text

        ledger = await client.get(
            f"/api/v1/goals/{goal_id}/contributions",
            headers=identity.headers,
        )
        assert ledger.status_code == 200, ledger.text
        assert len(ledger.json()["contributions"]) == 4, ledger.text

        # --- another user can never reach this goal ------------------------
        stranger = await _register(
            client,
            email=f"stranger-{uuid4().hex[:12]}@example.com",
            name="Synthetic Stranger",
        )
        foreign = await client.get(
            f"/api/v1/goals/{goal_id}/contributions",
            headers=stranger.headers,
        )
        assert foreign.status_code == 404, foreign.text
        assert "Отпуск" not in foreign.text

    async with session_factory() as database:
        goals = await database.scalar(select(func.count()).select_from(FinanceGoalRow))
        assert goals == 1, goals

    await engine.dispose()


def main() -> None:
    _empty_migration_round_trip()
    engine, session_factory = create_database(DATABASE_URL)
    asyncio.run(_scenario(engine, session_factory))
    _assert_lossy_downgrade_refused()
    print("savings goal PostgreSQL E2E passed")


if __name__ == "__main__":
    main()
