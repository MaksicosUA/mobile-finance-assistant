"""Opt-in PostgreSQL E2E for the planned-cost slice (ADR 0018).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/planned_cost_postgres_e2e.py

It is not collected by pytest: `testpaths` only picks up `test_*.py`, so this
script stays opt-in and never blocks CI, which provisions no database.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

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
    FinanceOperationRow,
    FinanceOutboxEventRow,
    PlannedCostAuditRow,
    PlannedCostOutboxEventRow,
    PlannedCostRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.planned_cost_core import PlannedCostCore
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.postgres_planned_cost_repository import (
    PostgresPlannedCostRepository,
)
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-planned-cost-secret-32-bytes-minimum"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
TIMEZONE = "Europe/Berlin"
OPENING_ON = (datetime.now(UTC) - timedelta(days=60)).date()
FUTURE_ON = (datetime.now(UTC) + timedelta(days=30)).date()
PAST_ON = (datetime.now(UTC) - timedelta(days=1)).date()


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
    command.downgrade(config, "0007_correctable_baseline")
    command.upgrade(config, "head")


def _assert_lossy_downgrade_refused() -> None:
    config = _alembic_config()
    try:
        command.downgrade(config, "0007_correctable_baseline")
    except RuntimeError as error:
        assert "Refusing lossy downgrade" in str(error), str(error)
    else:
        raise AssertionError("populated planned-cost downgrade was not refused")


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
        planned_cost_core=PlannedCostCore(
            repository=PostgresPlannedCostRepository(
                session_factory=session_factory,
            ),
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


async def _bootstrap_account(
    client: AsyncClient,
    *,
    identity: _Identity,
    name: str = "Synthetic primary account",
    currency: str = "EUR",
) -> UUID:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": name,
        "currency": currency,
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
    assert evaluated["decision"] == "NEEDS_CONFIRMATION", evaluated
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


def _plan_body(*, account_id: UUID, **changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "accountId": str(account_id),
        "amount": "800.00",
        "currency": "EUR",
        "title": "Аренда",
        "category": "Жильё",
        "plannedOn": FUTURE_ON.isoformat(),
        "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    body.update(changes)
    return body


async def _commit_operation(
    client: AsyncClient,
    *,
    identity: _Identity,
    account_id: UUID,
) -> UUID:
    """Settle real money through the untouched operation v1 path."""

    captured_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")
    operation_command_id = uuid4()
    draft = {
        "schemaVersion": "1",
        "commandId": str(operation_command_id),
        "type": "expense",
        "amount": "800.00",
        "currency": "EUR",
        "accountId": str(account_id),
        "category": "Жильё",
        "merchant": None,
        "capturedAt": captured_at,
        "capturedTimezone": TIMEZONE,
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": datetime.now(UTC)
        .astimezone(ZoneInfo(TIMEZONE))
        .date()
        .isoformat(),
        "occurredAt": None,
        "source": "manual_text",
    }
    evaluation = await client.post(
        "/api/v1/operations/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    evaluated = evaluation.json()
    assert evaluated["decision"] == "NEEDS_CONFIRMATION", evaluated
    commit = await client.post(
        "/api/v1/operations/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluated["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text
    return operation_command_id


async def _count(session_factory: AsyncSessionFactory, statement: object) -> int:
    async with session_factory() as database:
        return int(await database.scalar(statement) or 0)


async def _exercise() -> tuple[AsyncEngine, AsyncSessionFactory]:
    engine, session_factory = create_database(DATABASE_URL)
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
            email=f"planned-{uuid4().hex}@example.com",
            name="Planned Cost User",
        )
        account_id = await _bootstrap_account(client, identity=identity)

        # --- a future-dated forecast is accepted --------------------------
        body = _plan_body(account_id=account_id)
        created = await client.post(
            "/api/v1/planned-costs",
            json=body,
            headers=identity.headers,
        )
        assert created.status_code == 201, created.text
        payload = created.json()
        assert payload["idempotentReplay"] is False
        plan = payload["plannedCost"]
        plan_id = UUID(plan["plannedCostId"])
        assert plan["status"] == "planned"
        assert plan["isDue"] is False
        assert plan["plannedOn"] == FUTURE_ON.isoformat()
        assert plan["amount"] == "800"
        assert plan["confirmedOperationId"] is None

        # --- the decisive invariant: no authoritative money moved ---------
        assert (
            await _count(
                session_factory,
                select(func.count()).select_from(FinanceOperationRow),
            )
            == 0
        ), "a planned cost must never create a finance operation"
        assert (
            await _count(
                session_factory,
                select(func.count()).select_from(FinanceOutboxEventRow),
            )
            == 0
        ), "a planned cost must never publish an operation outbox event"

        # --- audit and invalidation are written in the same transaction ---
        async with session_factory() as database:
            audit_rows = (
                (
                    await database.execute(
                        select(PlannedCostAuditRow).where(
                            PlannedCostAuditRow.planned_cost_id == plan_id
                        )
                    )
                )
                .scalars()
                .all()
            )
            outbox_rows = (
                (
                    await database.execute(
                        select(PlannedCostOutboxEventRow).where(
                            PlannedCostOutboxEventRow.aggregate_id == plan_id
                        )
                    )
                )
                .scalars()
                .all()
            )
        assert len(audit_rows) == 1, audit_rows
        assert audit_rows[0].event_type == "planned_cost_created"
        assert audit_rows[0].previous_status is None
        assert audit_rows[0].new_status == "planned"
        assert len(outbox_rows) == 1, outbox_rows
        assert outbox_rows[0].event_type == "finance.planned_cost.created.v1"
        assert outbox_rows[0].published_at is None
        # Identifier-only: a substring check would be flaky against UUIDs, so
        # assert the exact payload shape instead.
        assert outbox_rows[0].payload == {
            "schemaVersion": "1",
            "plannedCostId": str(plan_id),
            "userId": str(identity.user_id),
            "commandId": str(body["commandId"]),
        }, outbox_rows[0].payload

        # --- exact replay writes nothing ----------------------------------
        replay = await client.post(
            "/api/v1/planned-costs",
            json=body,
            headers=identity.headers,
        )
        assert replay.status_code == 200, replay.text
        assert replay.json()["idempotentReplay"] is True
        assert replay.json()["plannedCost"]["plannedCostId"] == str(plan_id)
        assert (
            await _count(
                session_factory,
                select(func.count()).select_from(PlannedCostRow),
            )
            == 1
        )

        # --- same command, different content is a conflict ----------------
        conflict = await client.post(
            "/api/v1/planned-costs",
            json={**body, "amount": "900.00"},
            headers=identity.headers,
        )
        assert conflict.status_code == 409, conflict.text
        assert conflict.json()["detail"]["code"] == "COMMAND_CONFLICT"

        # --- a plan before the account baseline is refused -----------------
        too_early = await client.post(
            "/api/v1/planned-costs",
            json=_plan_body(
                account_id=account_id,
                plannedOn=(OPENING_ON - timedelta(days=1)).isoformat(),
            ),
            headers=identity.headers,
        )
        assert too_early.status_code == 422, too_early.text
        assert too_early.json()["detail"] == {
            "code": "PLANNED_COST_REJECTED",
            "issues": [{"code": "PLAN_BEFORE_ACCOUNT_BASELINE", "field": "plannedOn"}],
        }

        # --- a past-dated outstanding plan reads as due --------------------
        overdue = await client.post(
            "/api/v1/planned-costs",
            json=_plan_body(
                account_id=account_id,
                plannedOn=PAST_ON.isoformat(),
                title="Интернет",
            ),
            headers=identity.headers,
        )
        assert overdue.status_code == 201, overdue.text
        overdue_id = UUID(overdue.json()["plannedCost"]["plannedCostId"])
        assert overdue.json()["plannedCost"]["isDue"] is True

        # --- confirmation fails closed without its operation ---------------
        missing = await client.post(
            f"/api/v1/planned-costs/{plan_id}/transition",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "transition": "confirm",
                "operationCommandId": str(uuid4()),
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert missing.status_code == 422, missing.text
        assert missing.json()["detail"] == {
            "code": "PLANNED_COST_REJECTED",
            "issues": [
                {
                    "code": "CONFIRMING_OPERATION_MISSING",
                    "field": "operationCommandId",
                }
            ],
        }
        async with session_factory() as database:
            still_planned = await database.scalar(
                select(PlannedCostRow.status).where(PlannedCostRow.id == plan_id)
            )
        assert still_planned == "planned"

        # --- confirming reuses the operation path unchanged ----------------
        operation_command_id = await _commit_operation(
            client,
            identity=identity,
            account_id=account_id,
        )
        confirm_command_id = uuid4()
        confirm_body = {
            "schemaVersion": "1",
            "commandId": str(confirm_command_id),
            "transition": "confirm",
            "operationCommandId": str(operation_command_id),
            "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        }
        confirmed = await client.post(
            f"/api/v1/planned-costs/{plan_id}/transition",
            json=confirm_body,
            headers=identity.headers,
        )
        assert confirmed.status_code == 200, confirmed.text
        confirmed_plan = confirmed.json()["plannedCost"]
        assert confirmed.json()["idempotentReplay"] is False
        assert confirmed_plan["status"] == "confirmed"
        assert confirmed_plan["isDue"] is False
        assert confirmed_plan["confirmedOperationId"] is not None

        async with session_factory() as database:
            linked = await database.scalar(
                select(FinanceOperationRow.id).where(
                    FinanceOperationRow.user_id == identity.user_id,
                    FinanceOperationRow.command_id == operation_command_id,
                )
            )
        assert confirmed_plan["confirmedOperationId"] == str(linked)

        # --- transition replay returns the original result -----------------
        confirm_replay = await client.post(
            f"/api/v1/planned-costs/{plan_id}/transition",
            json=confirm_body,
            headers=identity.headers,
        )
        assert confirm_replay.status_code == 200, confirm_replay.text
        assert confirm_replay.json()["idempotentReplay"] is True
        assert (
            confirm_replay.json()["plannedCost"]["confirmedOperationId"]
            == confirmed_plan["confirmedOperationId"]
        )

        # --- a settled plan has no path back -------------------------------
        second = await client.post(
            f"/api/v1/planned-costs/{plan_id}/transition",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "transition": "cancel",
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert second.status_code == 422, second.text
        assert second.json()["detail"]["issues"] == [
            {"code": "INVALID_LIFECYCLE_TRANSITION", "field": "transition"}
        ]

        async with session_factory() as database:
            transition_audit = (
                (
                    await database.execute(
                        select(PlannedCostAuditRow).where(
                            PlannedCostAuditRow.planned_cost_id == plan_id,
                            PlannedCostAuditRow.event_type != "planned_cost_created",
                        )
                    )
                )
                .scalars()
                .all()
            )
        assert len(transition_audit) == 1, transition_audit
        assert transition_audit[0].previous_status == "planned"
        assert transition_audit[0].new_status == "confirmed"

        # --- cancelling the overdue plan is independent --------------------
        cancelled = await client.post(
            f"/api/v1/planned-costs/{overdue_id}/transition",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "transition": "cancel",
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["plannedCost"]["status"] == "cancelled"
        assert cancelled.json()["plannedCost"]["isDue"] is False

        # --- listing derives the local evaluation date ---------------------
        listed = await client.get(
            "/api/v1/planned-costs",
            headers=identity.headers,
        )
        assert listed.status_code == 200, listed.text
        listing = listed.json()
        assert len(listing["plannedCosts"]) == 2
        expected_local_today = (
            datetime.now(UTC).astimezone(ZoneInfo(TIMEZONE)).date().isoformat()
        )
        assert listing["evaluatedOn"] == expected_local_today

        bounded = await client.get(
            "/api/v1/planned-costs",
            params={"from": FUTURE_ON.isoformat()},
            headers=identity.headers,
        )
        assert bounded.status_code == 200, bounded.text
        assert len(bounded.json()["plannedCosts"]) == 1

        # --- the projector turns outstanding plans into Home payments ------
        # Both earlier plans are settled by now, so create one that is still
        # outstanding; only an obligation belongs in the block.
        outstanding = await client.post(
            "/api/v1/planned-costs",
            json=_plan_body(
                account_id=account_id,
                title="Страховка",
                plannedOn=FUTURE_ON.isoformat(),
            ),
            headers=identity.headers,
        )
        assert outstanding.status_code == 201, outstanding.text
        outstanding_id = UUID(outstanding.json()["plannedCost"]["plannedCostId"])

        projector = PostgresHomeProjector(session_factory=session_factory)
        await projector.drain_pending()

        home = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home.status_code == 200, home.text
        block = home.json()["upcomingPayments"]
        # The confirmed plan and the cancelled one are settled, so only the
        # future outstanding plan remains an obligation.
        assert len(block) == 1, block
        payment = block[0]
        assert payment["id"] == str(outstanding_id)
        assert payment["dueOn"] == FUTURE_ON.isoformat()
        # A planned cost has no time of day, so no instant is invented.
        assert payment["dueAt"] is None
        # Scale is a storage artifact of NUMERIC(38,18); compare money, not text.
        assert Decimal(payment["amount"]) == Decimal("800.00")
        assert payment["status"] == "scheduled"

        # A forecast must never move an authoritative total. One 800.00 expense
        # was committed above, so the month expense reflects that operation
        # alone and not the identically sized plan.
        assert Decimal(home.json()["monthSummary"]["expense"]) == Decimal("800.00")

        # v1 cannot express a date-only obligation and must fail closed rather
        # than fabricate local midnight.
        legacy = await client.get(
            "/api/v1/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert legacy.status_code == 503, legacy.text

        # --- a bill planned in another wallet is still an obligation ------
        #
        # Home draws the default wallet's revision, so a hryvnia bill filed
        # against the hryvnia wallet has to reach that revision or a person
        # would never see it on the screen they actually look at (ADR 0029).
        hryvnia_id = await _bootstrap_account(
            client,
            identity=identity,
            name="Synthetic hryvnia wallet",
            currency="UAH",
        )
        hryvnia_plan = await client.post(
            "/api/v1/planned-costs",
            json=_plan_body(
                account_id=hryvnia_id,
                title="Интернет",
                amount="1200.00",
                currency="UAH",
                plannedOn=FUTURE_ON.isoformat(),
            ),
            headers=identity.headers,
        )
        assert hryvnia_plan.status_code == 201, hryvnia_plan.text
        hryvnia_plan_id = UUID(hryvnia_plan.json()["plannedCost"]["plannedCostId"])

        projector = PostgresHomeProjector(session_factory=session_factory)
        await projector.drain_pending()

        merged = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert merged.status_code == 200, merged.text
        merged_block = merged.json()["upcomingPayments"]
        assert {payment["id"] for payment in merged_block} == {
            str(outstanding_id),
            str(hryvnia_plan_id),
        }, merged_block
        hryvnia_payment = next(
            payment for payment in merged_block if payment["id"] == str(hryvnia_plan_id)
        )
        # Each line keeps its own currency and nothing is summed.
        assert hryvnia_payment["currency"] == "UAH"
        assert Decimal(hryvnia_payment["amount"]) == Decimal("1200.00")
        assert merged.json()["baseCurrency"] == "EUR"
        # A forecast in any wallet still moves no authoritative total.
        assert Decimal(merged.json()["monthSummary"]["expense"]) == Decimal("800.00")

        # --- another user can neither see nor settle the plan --------------
        intruder = await _register(
            client,
            email=f"intruder-{uuid4().hex}@example.com",
            name="Intruder",
        )
        foreign = await client.post(
            f"/api/v1/planned-costs/{plan_id}/transition",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "transition": "cancel",
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=intruder.headers,
        )
        assert foreign.status_code == 404, foreign.text
        foreign_list = await client.get(
            "/api/v1/planned-costs",
            headers=intruder.headers,
        )
        assert foreign_list.status_code == 200, foreign_list.text
        assert foreign_list.json()["plannedCosts"] == []

    return engine, session_factory


async def main() -> None:
    engine, _ = await _exercise()
    await engine.dispose()


if __name__ == "__main__":
    _empty_migration_round_trip()
    asyncio.run(main())
    _assert_lossy_downgrade_refused()
    print("planned cost PostgreSQL E2E: pass")
