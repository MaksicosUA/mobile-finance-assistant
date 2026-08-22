"""Opt-in PostgreSQL E2E for correcting and removing an operation (ADR 0023).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/operation_correction_postgres_e2e.py

Not collected by pytest — `testpaths` picks up `test_*.py` only — so it never
blocks CI, which provisions no database.

It proves what an in-memory fake cannot: that one transaction withdraws the
original and writes its replacement, that the withdrawn operation stops
counting in every read at once, that the audit trail and the invalidation are
written with it, and that the projector rebuilds Home without it.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceOperationAuditRow,
    FinanceOperationReversalRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_analytics_repository import (
    PostgresAnalyticsRepository,
)
from mobile_finance_api.postgres_category_repository import PostgresCategoryRepository
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-operation-correction-secret-32b"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
TIMEZONE = "Europe/Berlin"
OPENING_ON = (datetime.now(UTC) - timedelta(days=60)).date()


@dataclass(frozen=True, slots=True)
class _Identity:
    user_id: UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


def _now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):
    accounts = PostgresFinanceAccountRepository(session_factory=session_factory)
    categories = PostgresCategoryRepository(session_factory=session_factory)
    operations = PostgresFinanceOperationRepository(session_factory=session_factory)
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
            repository=operations,
            account_directory=accounts,
            category_directory=categories,
        ),
        category_repository=categories,
        finance_operation_repository=operations,
        analytics_repository=PostgresAnalyticsRepository(
            session_factory=session_factory
        ),
    )


async def _register(client: AsyncClient, *, email: str) -> _Identity:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "synthetic-password-123",
            "displayName": "Synthetic Owner",
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
        "openingBalance": "5000.00",
        "openingBalanceOn": OPENING_ON.isoformat(),
        "canonicalTimezone": TIMEZONE,
    }
    evaluation = await client.post(
        "/api/v1/accounts/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text
    return UUID(commit.json()["account"]["accountId"])


def _draft(
    *,
    account_id: UUID,
    amount: str,
    occurred_on: date,
    category_id: UUID | None = None,
) -> dict[str, object]:
    draft: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": "expense",
        "amount": amount,
        "currency": "EUR",
        "accountId": str(account_id),
        "category": None,
        "merchant": None,
        "capturedAt": _now(),
        "capturedTimezone": TIMEZONE,
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": occurred_on.isoformat(),
        "occurredAt": None,
        "source": "manual_text",
    }
    if category_id is not None:
        draft["categoryId"] = str(category_id)
    return draft


async def _commit(
    client: AsyncClient,
    *,
    identity: _Identity,
    draft: dict[str, object],
) -> UUID:
    evaluation = await client.post(
        "/api/v1/operations/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/operations/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text
    return UUID(commit.json()["operation"]["operationId"])


async def _correct(
    client: AsyncClient,
    *,
    identity: _Identity,
    target: UUID,
    draft: dict[str, object],
) -> tuple[int, dict[str, object], dict[str, object]]:
    evaluation = await client.post(
        "/api/v1/operations/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    command: dict[str, object] = {
        "schemaVersion": "1",
        "targetOperationId": str(target),
        "draft": draft,
        "draftHash": evaluation.json()["draftHash"],
        "confirmedAt": _now(),
    }
    response = await client.post(
        "/api/v1/operations/correction",
        json=command,
        headers=identity.headers,
    )
    # The exact command travels back so a replay can be the same bytes.
    return response.status_code, response.json(), command


async def _history_ids(client: AsyncClient, *, identity: _Identity) -> list[str]:
    page = await client.get(
        "/api/v1/operations",
        params={"limit": 100},
        headers=identity.headers,
    )
    assert page.status_code == 200, page.text
    return [item["operationId"] for item in page.json()["operations"]]


async def _month_expense(client: AsyncClient, *, identity: _Identity) -> Decimal:
    report = await client.get("/api/v1/analytics", headers=identity.headers)
    assert report.status_code == 200, report.text
    return Decimal(report.json()["totals"]["expense"])


async def _scenario(engine: AsyncEngine, session_factory: AsyncSessionFactory) -> None:
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-test",
        audience="mfa-test-clients",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    projector = PostgresHomeProjector(session_factory=session_factory)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        identity = await _register(
            client, email=f"correction-{uuid4().hex[:12]}@example.com"
        )
        account_id = await _bootstrap_account(client, identity=identity)
        today = datetime.now(UTC).date()

        kept = await _commit(
            client,
            identity=identity,
            draft=_draft(account_id=account_id, amount="10.00", occurred_on=today),
        )
        wrong = await _commit(
            client,
            identity=identity,
            draft=_draft(account_id=account_id, amount="120.00", occurred_on=today),
        )
        assert await _month_expense(client, identity=identity) == Decimal("130.00")

        # --- a correction replaces one operation with another --------------
        replacement_draft = _draft(
            account_id=account_id, amount="12.00", occurred_on=today
        )
        status_code, body, command = await _correct(
            client,
            identity=identity,
            target=wrong,
            draft=replacement_draft,
        )
        assert status_code == 201, body
        replacement = UUID(str(body["operation"]["operationId"]))
        assert body["reversal"]["operationId"] == str(wrong), body
        assert body["reversal"]["replacementOperationId"] == str(replacement), body

        # --- every read agrees, and it agrees immediately ------------------
        history = await _history_ids(client, identity=identity)
        assert str(wrong) not in history, history
        assert {str(kept), str(replacement)} == set(history), history
        assert await _month_expense(client, identity=identity) == Decimal("22.00")

        # --- the original row is still there, untouched --------------------
        async with session_factory() as database:
            original = await database.scalar(
                select(FinanceOperationRow).where(FinanceOperationRow.id == wrong)
            )
            assert original is not None, "a correction must never delete the row"
            assert original.amount == Decimal("120.00"), original.amount
            assert original.status == "confirmed", original.status

            reversal = await database.scalar(
                select(FinanceOperationReversalRow).where(
                    FinanceOperationReversalRow.operation_id == wrong
                )
            )
            assert reversal is not None
            assert reversal.replacement_operation_id == replacement
            assert reversal.user_id == identity.user_id

            reversed_audit = await database.scalar(
                select(func.count())
                .select_from(FinanceOperationAuditRow)
                .where(
                    FinanceOperationAuditRow.operation_id == wrong,
                    FinanceOperationAuditRow.event_type == "operation_reversed",
                )
            )
            assert reversed_audit == 1, reversed_audit

            invalidation = await database.scalar(
                select(func.count())
                .select_from(FinanceOutboxEventRow)
                .where(
                    FinanceOutboxEventRow.aggregate_id == wrong,
                    FinanceOutboxEventRow.event_type == "finance.operation.reversed.v1",
                )
            )
            assert invalidation == 1, invalidation

        # --- the projector rebuilds Home without the withdrawn operation ---
        for _ in range(10):
            if not await projector.consume_next():
                break
        home = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home.status_code == 200, home.text
        projected = home.json()
        # 5000 opening, minus the 10 that stayed and the 12 that replaced 120.
        assert Decimal(projected["balance"]["amount"]) == Decimal("4978.00"), home.text
        assert Decimal(projected["monthSummary"]["expense"]) == Decimal("22.00")
        # The withdrawn operation is gone from what Home shows, too.
        shown = {item["id"] for item in projected["recentTransactions"]}
        assert str(wrong) not in shown, shown

        # --- correcting the same operation twice is refused ----------------
        again_status, again_body, _ = await _correct(
            client,
            identity=identity,
            target=wrong,
            draft=_draft(account_id=account_id, amount="13.00", occurred_on=today),
        )
        assert again_status == 409, again_body
        assert again_body["detail"]["code"] == "OPERATION_ALREADY_REVERSED", again_body

        # --- replaying the same command changes nothing --------------------
        replay = await client.post(
            "/api/v1/operations/correction",
            json=command,
            headers=identity.headers,
        )
        assert replay.status_code == 200, replay.text
        assert replay.json()["idempotentReplay"] is True, replay.text
        assert replay.json()["operation"]["operationId"] == str(replacement)
        assert await _month_expense(client, identity=identity) == Decimal("22.00")

        # --- removing withdraws without replacing --------------------------
        removal = await client.post(
            "/api/v1/operations/removal",
            json={
                "schemaVersion": "1",
                "targetOperationId": str(kept),
                "commandId": str(uuid4()),
                "confirmedAt": _now(),
            },
            headers=identity.headers,
        )
        assert removal.status_code == 201, removal.text
        assert removal.json()["reversal"]["replacementOperationId"] is None

        assert await _history_ids(client, identity=identity) == [str(replacement)]
        assert await _month_expense(client, identity=identity) == Decimal("12.00")

        # --- another user's operation is not found, never forbidden --------
        stranger = await _register(
            client, email=f"stranger-{uuid4().hex[:12]}@example.com"
        )
        foreign = await client.post(
            "/api/v1/operations/removal",
            json={
                "schemaVersion": "1",
                "targetOperationId": str(replacement),
                "commandId": str(uuid4()),
                "confirmedAt": _now(),
            },
            headers=stranger.headers,
        )
        assert foreign.status_code == 404, foreign.text
        assert foreign.json()["detail"]["code"] == "OPERATION_NOT_FOUND"

        # The stranger's attempt wrote nothing.
        async with session_factory() as database:
            still_there = await database.scalar(
                select(FinanceOperationReversalRow).where(
                    FinanceOperationReversalRow.operation_id == replacement
                )
            )
            assert still_there is None

    await engine.dispose()


def _alembic_config():
    from alembic.config import Config

    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    return config


def _assert_empty_round_trip() -> None:
    """Down to 0013 and back up while nothing has been corrected yet."""

    from alembic import command

    command.downgrade(_alembic_config(), "0013_category_keywords")
    command.upgrade(_alembic_config(), "head")


def _assert_lossy_downgrade_refused() -> None:
    """With reversals present, going back would resurrect corrected money.

    The previous schema cannot represent a withdrawn operation, so the
    migration refuses rather than silently returning it to the ledger.
    """

    from alembic import command

    try:
        command.downgrade(_alembic_config(), "0013_category_keywords")
    except RuntimeError as error:
        assert "Refusing lossy downgrade" in str(error), str(error)
    else:
        raise AssertionError("a populated reversal downgrade was not refused")


def main() -> None:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    from alembic import command

    command.upgrade(_alembic_config(), "head")
    _assert_empty_round_trip()

    engine, session_factory = create_database(DATABASE_URL)
    asyncio.run(_scenario(engine, session_factory))
    _assert_lossy_downgrade_refused()
    print("operation correction PostgreSQL E2E passed")


if __name__ == "__main__":
    main()
