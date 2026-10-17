from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import DBAPIError, IntegrityError

from mobile_finance_api import postgres_home_projector as projector_module
from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceAccountOutboxEventRow,
    FinanceAccountRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    FinanceTransferOutboxEventRow,
    HomeProjectionActionRow,
    HomeProjectionSnapshotRow,
    HomeProjectionTransactionRow,
    HomeProjectionTrendPointRow,
    UserRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.home_projection import HomeProjectionInvariantError
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.postgres_projector_supervision import (
    acquire_projector_leadership,
    prune_home_revisions,
    read_projector_health,
)
from mobile_finance_api.postgres_transfer_repository import PostgresTransferRepository
from mobile_finance_api.projector_supervision import (
    EventRetryPolicy,
    RevisionRetentionPolicy,
)
from mobile_finance_api.tokens import AccessTokenCodec
from mobile_finance_api.transfer_core import TransferCore

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = b"test-only-home-projector-secret-32-bytes-minimum"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
TIMEZONE_NAME = "Europe/Berlin"
TIMEZONE = ZoneInfo(TIMEZONE_NAME)
_MIGRATION_USER_ID = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
_MIGRATION_SNAPSHOT_ID = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
_MIGRATION_TRANSACTION_ID = "legacy-transaction"


@dataclass(frozen=True, slots=True)
class _Identity:
    user_id: UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


@dataclass(slots=True)
class _MutableClock:
    value: datetime

    def __call__(self) -> datetime:
        return self.value

    def advance(self, delta: timedelta) -> None:
        self.value += delta


def _iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _alembic_config() -> Config:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    return config


def _populated_migration_round_trip() -> None:
    config = _alembic_config()
    command.upgrade(config, "0004_authoritative_accounts")
    asyncio.run(_seed_schema_0004_home_fixture())
    # Pinned to 0005 rather than head: the property under test belongs to that
    # migration, and the fixture models a database with no financial account —
    # which from 0020 on is not a database that can hold a projection at all,
    # because a revision belongs to a wallet (ADR 0029).
    command.upgrade(config, "0005_home_projector")
    asyncio.run(_assert_schema_0005_preserves_legacy_unknowns())
    command.downgrade(config, "0004_authoritative_accounts")
    asyncio.run(_assert_schema_0004_legacy_fixture_and_cleanup())
    command.upgrade(config, "head")


def _assert_projected_revision_blocks_lossy_downgrade() -> None:
    try:
        command.downgrade(_alembic_config(), "0004_authoritative_accounts")
    except (DBAPIError, RuntimeError) as error:
        assert "Refusing lossy downgrade" in str(error)
    else:
        raise AssertionError("schema-v2 Home facts allowed a lossy downgrade")


async def _set_synthetic_retry_metadata() -> tuple[UUID, datetime, int, int]:
    engine, session_factory = create_database(DATABASE_URL)
    try:
        async with session_factory() as database, database.begin():
            event = await database.scalar(
                select(FinanceOutboxEventRow)
                .where(FinanceOutboxEventRow.published_at.is_not(None))
                .order_by(FinanceOutboxEventRow.created_at.asc())
                .limit(1)
                .with_for_update()
            )
            assert event is not None and event.published_at is not None
            original = (
                event.id,
                event.published_at,
                event.attempt_count,
                event.validation_failure_count,
            )
            failed_at = event.created_at + timedelta(seconds=1)
            event.published_at = None
            event.attempt_count = max(1, event.attempt_count)
            event.validation_failure_count = 1
            event.next_attempt_at = failed_at + timedelta(seconds=1)
            event.last_failed_at = failed_at
            event.failure_code = "invalid_outbox_contract"
            event.dead_lettered_at = None
            return original
    finally:
        await engine.dispose()


async def _restore_synthetic_retry_metadata(
    state: tuple[UUID, datetime, int, int],
) -> None:
    event_id, published_at, attempt_count, validation_failure_count = state
    engine, session_factory = create_database(DATABASE_URL)
    try:
        async with session_factory() as database, database.begin():
            event = await database.scalar(
                select(FinanceOutboxEventRow)
                .where(FinanceOutboxEventRow.id == event_id)
                .with_for_update()
            )
            assert event is not None
            event.published_at = published_at
            event.attempt_count = attempt_count
            event.validation_failure_count = validation_failure_count
            event.next_attempt_at = None
            event.last_failed_at = None
            event.failure_code = None
            event.dead_lettered_at = None
    finally:
        await engine.dispose()


def _assert_retry_metadata_blocks_lossy_downgrade() -> None:
    state = asyncio.run(_set_synthetic_retry_metadata())
    try:
        try:
            command.downgrade(_alembic_config(), "0005_home_projector")
        except RuntimeError as error:
            # Whichever guard is newest refuses first: by the time the chain
            # reaches the projector's own metadata, the category, goal, and
            # reversal layers above it have already had their say. What must
            # hold is that the downgrade is refused rather than losing rows.
            assert "Refusing lossy downgrade" in str(error) or (
                "outbox retry or dead-letter metadata exists" in str(error)
            ), str(error)
        else:
            raise AssertionError("projector retry metadata allowed a lossy downgrade")
    finally:
        asyncio.run(_restore_synthetic_retry_metadata(state))


async def _seed_schema_0004_home_fixture() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    try:
        async with session_factory() as database, database.begin():
            await database.execute(
                text(
                    "INSERT INTO users ("
                    "id, email_normalized, password_hash, display_name, "
                    "base_currency, created_at, updated_at, disabled_at, "
                    "canonical_timezone, timezone_revision"
                    ") VALUES ("
                    ":id, :email, :password_hash, :display_name, :currency, "
                    ":created_at, :updated_at, NULL, :timezone, 1"
                    ")"
                ),
                {
                    "id": _MIGRATION_USER_ID,
                    "email": "legacy-home-migration@example.invalid",
                    "password_hash": "synthetic-unused-hash",
                    "display_name": "Synthetic Legacy",
                    "currency": "EUR",
                    "created_at": datetime(2026, 7, 1, 8, tzinfo=UTC),
                    "updated_at": datetime(2026, 7, 1, 8, tzinfo=UTC),
                    "timezone": TIMEZONE_NAME,
                },
            )
            await database.execute(
                text(
                    "INSERT INTO home_projection_snapshots ("
                    "id, user_id, timezone_name, period_start, period_end, "
                    "revision, generated_at, data_as_of, base_currency, "
                    "balance_amount, balance_delta_amount, "
                    "balance_delta_percent, month_income, month_expense, "
                    "month_net_flow, trend_metric, trend_period, trend_total"
                    ") VALUES ("
                    ":id, :user_id, :timezone, :period_start, :period_end, 1, "
                    ":generated_at, :data_as_of, 'EUR', 1, 0, 0, 0, 0, 0, "
                    "'expense', '7d', 0"
                    ")"
                ),
                {
                    "id": _MIGRATION_SNAPSHOT_ID,
                    "user_id": _MIGRATION_USER_ID,
                    "timezone": TIMEZONE_NAME,
                    "period_start": date(2026, 7, 1),
                    "period_end": date(2026, 7, 31),
                    "generated_at": datetime(2026, 7, 15, 10, tzinfo=UTC),
                    "data_as_of": datetime(2026, 7, 15, 10, tzinfo=UTC),
                },
            )
            await database.execute(
                text(
                    "INSERT INTO home_projection_recent_transactions ("
                    "snapshot_id, transaction_id, title, category, occurred_at, "
                    "amount, base_amount, currency, direction, status"
                    ") VALUES ("
                    ":snapshot_id, :transaction_id, :title, :category, "
                    ":occurred_at, -1, -1, 'EUR', 'expense', 'confirmed'"
                    ")"
                ),
                {
                    "snapshot_id": _MIGRATION_SNAPSHOT_ID,
                    "transaction_id": _MIGRATION_TRANSACTION_ID,
                    "title": "Synthetic legacy merchant",
                    "category": "Synthetic legacy category",
                    # Deliberately near a local-date boundary: migration 0005
                    # must preserve unknown occurredOn rather than derive it.
                    "occurred_at": datetime(2026, 7, 14, 22, 30, tzinfo=UTC),
                },
            )
    finally:
        await engine.dispose()


async def _assert_schema_0005_preserves_legacy_unknowns() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    try:
        async with session_factory() as database:
            snapshot = (
                (
                    await database.execute(
                        text(
                            "SELECT projection_schema_version "
                            "FROM home_projection_snapshots WHERE id = :id"
                        ),
                        {"id": _MIGRATION_SNAPSHOT_ID},
                    )
                )
                .mappings()
                .one()
            )
            recent = (
                (
                    await database.execute(
                        text(
                            "SELECT occurred_on, position, title, category, "
                            "occurred_at "
                            "FROM home_projection_recent_transactions "
                            "WHERE snapshot_id = :snapshot_id "
                            "AND transaction_id = :transaction_id"
                        ),
                        {
                            "snapshot_id": _MIGRATION_SNAPSHOT_ID,
                            "transaction_id": _MIGRATION_TRANSACTION_ID,
                        },
                    )
                )
                .mappings()
                .one()
            )

        assert snapshot["projection_schema_version"] == 1
        assert recent["occurred_on"] is None
        assert recent["position"] is None
        assert recent["title"] == "Synthetic legacy merchant"
        assert recent["category"] == "Synthetic legacy category"
        assert recent["occurred_at"] == datetime(2026, 7, 14, 22, 30, tzinfo=UTC)
    finally:
        await engine.dispose()


async def _assert_schema_0004_legacy_fixture_and_cleanup() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    try:
        async with session_factory() as database, database.begin():
            recent = (
                (
                    await database.execute(
                        text(
                            "SELECT title, category, occurred_at, amount, base_amount, "
                            "currency, direction, status "
                            "FROM home_projection_recent_transactions "
                            "WHERE snapshot_id = :snapshot_id "
                            "AND transaction_id = :transaction_id"
                        ),
                        {
                            "snapshot_id": _MIGRATION_SNAPSHOT_ID,
                            "transaction_id": _MIGRATION_TRANSACTION_ID,
                        },
                    )
                )
                .mappings()
                .one()
            )

            assert dict(recent) == {
                "title": "Synthetic legacy merchant",
                "category": "Synthetic legacy category",
                "occurred_at": datetime(2026, 7, 14, 22, 30, tzinfo=UTC),
                "amount": Decimal(-1),
                "base_amount": Decimal(-1),
                "currency": "EUR",
                "direction": "expense",
                "status": "confirmed",
            }

            await database.execute(
                text("DELETE FROM home_projection_snapshots WHERE id = :snapshot_id"),
                {"snapshot_id": _MIGRATION_SNAPSHOT_ID},
            )
            await database.execute(
                text("DELETE FROM users WHERE id = :user_id"),
                {"user_id": _MIGRATION_USER_ID},
            )
    finally:
        await engine.dispose()


def _application(
    *,
    session_factory: AsyncSessionFactory,
    tokens: AccessTokenCodec,
    clock: _MutableClock,
):
    accounts = PostgresFinanceAccountRepository(
        session_factory=session_factory,
        clock=clock,
    )
    return create_app(
        home_repository=PostgresHomeRepository(
            session_factory=session_factory,
            clock=clock,
        ),
        current_user_authenticator=PostgresCurrentUserAuthenticator(
            session_factory=session_factory,
            access_tokens=tokens,
        ),
        authentication_service=PostgresAuthenticationService(
            session_factory=session_factory,
            password_service=PasswordService(),
            access_tokens=tokens,
            clock=clock,
        ),
        account_core=AccountCore(repository=accounts, clock=clock),
        finance_core=FinanceCore(
            repository=PostgresFinanceOperationRepository(
                session_factory=session_factory,
                clock=clock,
            ),
            account_directory=accounts,
        ),
        transfer_core=TransferCore(
            repository=PostgresTransferRepository(
                session_factory=session_factory,
                clock=clock,
            ),
            clock=clock,
        ),
    )


async def _register(
    client: AsyncClient,
    *,
    email: str = "home-projector@example.com",
) -> _Identity:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "synthetic-password-123",
            "displayName": "Synthetic Projector",
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()
    return _Identity(
        user_id=UUID(payload["user"]["id"]),
        token=str(payload["accessToken"]),
    )


async def _open_account(
    client: AsyncClient,
    *,
    identity: _Identity,
    opening_on: date,
    clock: _MutableClock,
    currency: str = "EUR",
    name: str = "Synthetic primary account",
    opening_balance: str = "1000.00",
) -> UUID:
    draft: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": name,
        "currency": currency,
        "openingBalance": opening_balance,
        "openingBalanceOn": opening_on.isoformat(),
        "canonicalTimezone": TIMEZONE_NAME,
    }
    evaluation = await client.post(
        "/api/v1/accounts/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    evaluated = evaluation.json()
    assert evaluated["decision"] == "NEEDS_CONFIRMATION"
    assert evaluated["issues"] == []

    response = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluated["draftHash"],
            "confirmedAt": _iso(clock()),
        },
        headers=identity.headers,
    )
    assert response.status_code == 201, response.text
    return UUID(response.json()["account"]["accountId"])


async def _commit_operation(
    client: AsyncClient,
    *,
    identity: _Identity,
    account_id: UUID,
    operation_type: str,
    amount: str,
    occurred_on: date,
    clock: _MutableClock,
    category: str | None,
    merchant: str | None,
    occurred_at: datetime | None,
) -> UUID:
    draft: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": operation_type,
        "amount": amount,
        "currency": "EUR",
        "accountId": str(account_id),
        "category": category,
        "merchant": merchant,
        "capturedAt": _iso(clock() - timedelta(minutes=5)),
        "capturedTimezone": TIMEZONE_NAME,
        "sourceExpression": "вчера",
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": occurred_on.isoformat(),
        "occurredAt": None if occurred_at is None else _iso(occurred_at),
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
    assert evaluated["issues"] == []

    response = await client.post(
        "/api/v1/operations/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluated["draftHash"],
            "confirmedAt": _iso(clock()),
        },
        headers=identity.headers,
    )
    assert response.status_code == 201, response.text
    return UUID(response.json()["operation"]["operationId"])


async def _home(
    client: AsyncClient,
    identity: _Identity,
    *,
    etag: str | None = None,
):
    headers = dict(identity.headers)
    if etag is not None:
        headers["If-None-Match"] = etag
    return await client.get(
        "/api/v2/home",
        params={"period": "current_month", "timezone": TIMEZONE_NAME},
        headers=headers,
    )


async def _snapshot_count(
    session_factory: AsyncSessionFactory,
    user_id: UUID,
) -> int:
    async with session_factory() as database:
        value = await database.scalar(
            select(func.count())
            .select_from(HomeProjectionSnapshotRow)
            .where(HomeProjectionSnapshotRow.user_id == user_id)
        )
    return int(value or 0)


async def _latest_snapshot(
    session_factory: AsyncSessionFactory,
    user_id: UUID,
) -> HomeProjectionSnapshotRow:
    async with session_factory() as database:
        snapshot = await database.scalar(
            select(HomeProjectionSnapshotRow)
            .where(HomeProjectionSnapshotRow.user_id == user_id)
            .order_by(
                HomeProjectionSnapshotRow.generated_at.desc(),
                HomeProjectionSnapshotRow.revision.desc(),
            )
            .limit(1)
        )
    assert snapshot is not None
    return snapshot


def _amount(value: object) -> Decimal:
    return Decimal(str(value))


async def _assert_opening_projection(
    *,
    client: AsyncClient,
    identity: _Identity,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    unavailable = await _home(client, identity)
    assert unavailable.status_code == 503
    assert unavailable.json() == {"detail": "Home temporarily unavailable"}

    clock.advance(timedelta(seconds=1))
    assert await projector.consume_next() is True
    assert await _snapshot_count(session_factory, identity.user_id) == 1

    response = await _home(client, identity)
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["homeState"] == "ready"
    assert payload["baseCurrency"] == "EUR"
    assert _amount(payload["balance"]["amount"]) == Decimal(1000)
    assert _amount(payload["balance"]["deltaAmount"]) == 0
    assert _amount(payload["balance"]["deltaPercent"]) == 0
    assert _amount(payload["monthSummary"]["income"]) == 0
    assert _amount(payload["monthSummary"]["expense"]) == 0
    assert _amount(payload["monthSummary"]["netFlow"]) == 0
    assert payload["primaryGoal"] is None
    assert payload["upcomingPayments"] == []
    assert payload["recentTransactions"] == []
    assert payload["availableActions"] == ["voice_entry"]
    assert len(payload["trend"]["points"]) == 7
    assert all(_amount(point["amount"]) == 0 for point in payload["trend"]["points"])
    assert _amount(payload["trend"]["total"]) == 0

    etag = response.headers["etag"]
    unchanged = await _home(client, identity, etag=etag)
    assert unchanged.status_code == 304
    assert unchanged.content == b""
    assert unchanged.headers["etag"] == etag

    snapshot = await _latest_snapshot(session_factory, identity.user_id)
    assert snapshot.projection_schema_version == 2
    assert snapshot.revision == 1
    assert snapshot.data_as_of == snapshot.generated_at
    async with session_factory() as database:
        account_events = tuple(
            (
                await database.scalars(
                    select(FinanceAccountOutboxEventRow).where(
                        FinanceAccountOutboxEventRow.user_id == identity.user_id
                    )
                )
            ).all()
        )
        trend_rows = tuple(
            (
                await database.scalars(
                    select(HomeProjectionTrendPointRow).where(
                        HomeProjectionTrendPointRow.snapshot_id == snapshot.id
                    )
                )
            ).all()
        )
    assert len(account_events) == 1
    assert account_events[0].published_at == snapshot.generated_at
    assert account_events[0].attempt_count == 1
    assert account_events[0].payload == {
        "schemaVersion": "1",
        "accountId": str(account_events[0].aggregate_id),
        "userId": str(identity.user_id),
        "commandId": str(account_events[0].command_id),
    }
    assert len(trend_rows) == 7

    assert await projector.consume_next() is False
    assert await _snapshot_count(session_factory, identity.user_id) == 1


async def _assert_operation_projection(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    clock: _MutableClock,
) -> tuple[UUID, UUID, date]:
    local_date = clock().astimezone(TIMEZONE).date()
    occurred_on = local_date - timedelta(days=1)
    income_occurred_at = datetime.combine(
        occurred_on,
        time(hour=12),
        tzinfo=TIMEZONE,
    ).astimezone(UTC)
    income_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="income",
        amount="200.00",
        occurred_on=occurred_on,
        clock=clock,
        category="Synthetic income",
        merchant="Synthetic payer",
        occurred_at=income_occurred_at,
    )
    expense_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="35.50",
        occurred_on=occurred_on,
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )

    unavailable = await _home(client, identity)
    assert unavailable.status_code == 503

    before = await _snapshot_count(session_factory, identity.user_id)
    clock.advance(timedelta(seconds=1))
    consumers = (
        PostgresHomeProjector(session_factory=session_factory, clock=clock),
        PostgresHomeProjector(session_factory=session_factory, clock=clock),
    )
    consumed = await asyncio.gather(
        *(projector.consume_next() for projector in consumers)
    )
    assert sorted(consumed) == [False, True]
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1

    response = await _home(client, identity)
    assert response.status_code == 200, response.text
    payload = response.json()
    assert _amount(payload["balance"]["amount"]) == Decimal("1164.50")
    assert _amount(payload["balance"]["deltaAmount"]) == Decimal("164.50")
    assert _amount(payload["balance"]["deltaPercent"]) == Decimal("16.45")
    assert _amount(payload["monthSummary"]["income"]) == Decimal("200.00")
    assert _amount(payload["monthSummary"]["expense"]) == Decimal("35.50")
    assert _amount(payload["monthSummary"]["netFlow"]) == Decimal("164.50")
    assert payload["trend"]["metric"] == "expense"
    assert payload["trend"]["period"] == "7d"
    assert len(payload["trend"]["points"]) == 7
    points = {
        date.fromisoformat(point["date"]): _amount(point["amount"])
        for point in payload["trend"]["points"]
    }
    assert points == {
        local_date - timedelta(days=offset): (
            Decimal("35.50") if offset == 1 else Decimal(0)
        )
        for offset in range(6, -1, -1)
    }
    assert _amount(payload["trend"]["total"]) == Decimal("35.50")

    recent = payload["recentTransactions"]
    assert [row["id"] for row in recent] == [str(income_id), str(expense_id)]
    assert recent[0]["title"] == "Synthetic payer"
    assert recent[0]["category"] == "Synthetic income"
    assert recent[0]["occurredOn"] == occurred_on.isoformat()
    assert recent[0]["occurredAt"] == _iso(income_occurred_at)
    assert _amount(recent[0]["amount"]) == Decimal("200.00")
    assert recent[0]["direction"] == "income"
    assert recent[1]["title"] is None
    assert recent[1]["category"] is None
    assert recent[1]["occurredOn"] == occurred_on.isoformat()
    assert recent[1]["occurredAt"] is None
    assert _amount(recent[1]["amount"]) == Decimal("-35.50")
    assert recent[1]["direction"] == "expense"

    snapshot = await _latest_snapshot(session_factory, identity.user_id)
    assert snapshot.projection_schema_version == 2
    assert snapshot.revision == 2
    assert snapshot.data_as_of == snapshot.generated_at
    async with session_factory() as database:
        operation_events = tuple(
            (await database.scalars(select(FinanceOutboxEventRow))).all()
        )
        transaction_rows = tuple(
            (
                await database.scalars(
                    select(HomeProjectionTransactionRow)
                    .where(HomeProjectionTransactionRow.snapshot_id == snapshot.id)
                    .order_by(HomeProjectionTransactionRow.position.asc())
                )
            ).all()
        )
        source_operations = {
            operation.id: operation
            for operation in (
                await database.scalars(
                    select(FinanceOperationRow).where(
                        FinanceOperationRow.id.in_((income_id, expense_id))
                    )
                )
            ).all()
        }
    assert len(operation_events) == 2
    assert all(
        event.published_at == snapshot.generated_at for event in operation_events
    )
    assert all(event.attempt_count == 1 for event in operation_events)
    for event in operation_events:
        source = source_operations[event.aggregate_id]
        assert event.payload == {
            "schemaVersion": "1",
            "operationId": str(source.id),
            "userId": str(source.user_id),
            "commandId": str(source.command_id),
        }
    assert len(transaction_rows) == 2
    assert [row.position for row in transaction_rows] == [0, 1]
    assert [row.transaction_id for row in transaction_rows] == [
        str(income_id),
        str(expense_id),
    ]
    for row in transaction_rows:
        source = source_operations[UUID(row.transaction_id)]
        signed_amount = (
            source.amount if source.operation_type == "income" else -source.amount
        )
        assert row.title == source.merchant
        assert row.category == source.category
        assert row.occurred_on == source.occurred_on
        assert row.occurred_at == source.occurred_at
        assert row.amount == signed_amount
        assert row.base_amount == signed_amount
        assert row.currency == source.currency
        assert row.direction == source.operation_type
        assert row.status == source.status
    return income_id, expense_id, occurred_on


async def _drain(
    *,
    session_factory: AsyncSessionFactory,
    clock: _MutableClock,
    limit: int = 8,
) -> int:
    """Consume until the projector says there is nothing left."""

    consumed = 0
    for _ in range(limit):
        clock.advance(timedelta(seconds=1))
        projector = PostgresHomeProjector(session_factory=session_factory, clock=clock)
        if not await projector.consume_next():
            return consumed
        consumed += 1
    raise AssertionError("projector did not drain")


async def _assert_transfer_projection(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    clock: _MutableClock,
) -> None:
    """A transfer moves the balance and touches nothing else (ADR 0029)."""

    before = await _home(client, identity)
    assert before.status_code == 200, before.text
    balance_before = _amount(before.json()["balance"]["amount"])
    income_before = _amount(before.json()["monthSummary"]["income"])
    expense_before = _amount(before.json()["monthSummary"]["expense"])

    local_date = clock().astimezone(TIMEZONE).date()
    wallet_id = await _open_account(
        client,
        identity=identity,
        opening_on=local_date,
        clock=clock,
        currency="UAH",
        name="Synthetic hryvnia wallet",
        opening_balance="0",
    )
    draft: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "fromAccountId": str(account_id),
        "fromAmount": "100.00",
        "fromCurrency": "EUR",
        "toAccountId": str(wallet_id),
        "toAmount": "4800.00",
        "toCurrency": "UAH",
        "capturedAt": _iso(clock()),
        "capturedTimezone": TIMEZONE_NAME,
        "occurredOn": local_date.isoformat(),
    }
    evaluation = await client.post(
        "/api/v1/transfers/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    assert evaluation.json()["decision"] == "NEEDS_CONFIRMATION"

    committed = await client.post(
        "/api/v1/transfers/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _iso(clock()),
        },
        headers=identity.headers,
    )
    assert committed.status_code == 201, committed.text

    assert await _drain(session_factory=session_factory, clock=clock) >= 1

    async with session_factory() as database:
        unpublished = await database.scalar(
            select(func.count())
            .select_from(FinanceTransferOutboxEventRow)
            .where(
                FinanceTransferOutboxEventRow.user_id == identity.user_id,
                FinanceTransferOutboxEventRow.published_at.is_(None),
            )
        )
        dead = await database.scalar(
            select(func.count())
            .select_from(FinanceTransferOutboxEventRow)
            .where(FinanceTransferOutboxEventRow.dead_lettered_at.is_not(None))
        )
    assert unpublished == 0
    assert dead == 0

    after = await _home(client, identity)
    assert after.status_code == 200, after.text
    payload = after.json()
    # Both wallets are reported, and nothing is summed across them: adding
    # euro to hryvnia needs a rate, and there is none (ADR 0029).
    wallets = {item["currency"]: item for item in payload["wallets"]}
    assert set(wallets) == {"EUR", "UAH"}
    assert _amount(wallets["UAH"]["balance"]) == Decimal("4800.00")
    assert wallets["UAH"]["isDefault"] is False
    assert wallets["EUR"]["isDefault"] is True
    assert _amount(wallets["EUR"]["balance"]) == _amount(payload["balance"]["amount"])
    # The euro that left is gone from the euro balance.
    assert _amount(payload["balance"]["amount"]) == balance_before - Decimal("100.00")
    # And it was neither income nor expense.
    assert _amount(payload["monthSummary"]["income"]) == income_before
    assert _amount(payload["monthSummary"]["expense"]) == expense_before
    # The month's result is income minus expense, and a transfer between one's
    # own wallets is neither: the balance above moved, the delta did not. The
    # owner decided this on 2026-10-15 after an exchange read as money lost.
    assert _amount(payload["balance"]["deltaAmount"]) == _amount(
        before.json()["balance"]["deltaAmount"]
    )
    assert (
        payload["balance"]["deltaPercent"] == before.json()["balance"]["deltaPercent"]
    )
    # Read from a NUMERIC(38, 18) column, a percent used to leave with sixteen
    # zeros of padding, and the phone printed every one of them.
    percent = payload["balance"]["deltaPercent"]
    if percent is not None:
        assert len(percent.partition(".")[2]) <= 2, percent


async def _assert_tampered_event_retry(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
    occurred_on: date,
) -> None:
    operation_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="10.00",
        occurred_on=occurred_on,
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    assert (await _home(client, identity)).status_code == 503

    async with session_factory() as database, database.begin():
        event = await database.scalar(
            select(FinanceOutboxEventRow)
            .where(FinanceOutboxEventRow.aggregate_id == operation_id)
            .with_for_update()
        )
        assert event is not None
        original_payload = dict(event.payload)
        event.payload = {**original_payload, "operationId": str(uuid4())}

    before = await _snapshot_count(session_factory, identity.user_id)
    try:
        await projector.consume_next()
    except HomeProjectionInvariantError:
        pass
    else:
        raise AssertionError("tampered identifier payload was projected")

    assert await _snapshot_count(session_factory, identity.user_id) == before
    async with session_factory() as database:
        failed = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == operation_id
            )
        )
        assert failed is not None
        assert failed.published_at is None
        assert failed.attempt_count == 1
        assert failed.next_attempt_at == clock.value + timedelta(seconds=2)
        assert failed.last_failed_at == clock.value
        assert failed.failure_code == "invalid_outbox_contract"
        assert failed.dead_lettered_at is None
    assert (await _home(client, identity)).status_code == 503

    async with session_factory() as database, database.begin():
        failed = await database.scalar(
            select(FinanceOutboxEventRow)
            .where(FinanceOutboxEventRow.aggregate_id == operation_id)
            .with_for_update()
        )
        assert failed is not None
        failed.payload = original_payload

    clock.advance(timedelta(seconds=2))
    assert await projector.consume_next() is True
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1
    async with session_factory() as database:
        recovered = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == operation_id
            )
        )
        assert recovered is not None
        assert recovered.published_at is not None
        assert recovered.attempt_count == 2
        assert recovered.next_attempt_at is None
        assert recovered.last_failed_at is None
        assert recovered.failure_code is None
        assert recovered.dead_lettered_at is None
    recovered_home = await _home(client, identity)
    assert recovered_home.status_code == 200, recovered_home.text
    assert _amount(recovered_home.json()["balance"]["amount"]) == Decimal("1154.50")


async def _assert_writer_and_projector_share_user_account_lock_boundary(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    before_home = await _home(client, identity)
    assert before_home.status_code == 200, before_home.text
    before_balance = _amount(before_home.json()["balance"]["amount"])
    occurred_on = clock().astimezone(TIMEZONE).date() - timedelta(days=1)

    await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="4.00",
        occurred_on=occurred_on,
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    assert (await _home(client, identity)).status_code == 503

    async with session_factory() as database, database.begin():
        locked_user = await database.scalar(
            select(UserRow).where(UserRow.id == identity.user_id).with_for_update()
        )
        assert locked_user is not None
        projection_task = asyncio.create_task(projector.consume_next())
        writer_task = asyncio.create_task(
            _commit_operation(
                client,
                identity=identity,
                account_id=account_id,
                operation_type="expense",
                amount="6.00",
                occurred_on=occurred_on,
                clock=clock,
                category=None,
                merchant=None,
                occurred_at=None,
            )
        )
        await asyncio.sleep(0.1)
        assert not projection_task.done()
        assert not writer_task.done()

    consumed, _ = await asyncio.wait_for(
        asyncio.gather(projection_task, writer_task),
        timeout=5,
    )
    assert consumed is True
    await projector.drain_pending()

    converged = await _home(client, identity)
    assert converged.status_code == 200, converged.text
    assert _amount(converged.json()["balance"]["amount"]) == (
        before_balance - Decimal("10.00")
    )


async def _assert_child_failure_rolls_back_revision_and_acknowledgement(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    operation_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="3.00",
        occurred_on=clock().astimezone(TIMEZONE).date() - timedelta(days=1),
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    before = await _snapshot_count(session_factory, identity.user_id)
    original_children = projector_module._projection_children

    def children_with_duplicate_action(
        snapshot_id: UUID,
        projection,
    ) -> list[object]:
        children = original_children(snapshot_id, projection)
        children.append(
            HomeProjectionActionRow(
                snapshot_id=snapshot_id,
                position=0,
                action="synthetic_duplicate_position",
            )
        )
        return children

    projector_module._projection_children = children_with_duplicate_action
    try:
        try:
            await projector.consume_next()
        except IntegrityError:
            pass
        else:
            raise AssertionError("invalid projection children were committed")
    finally:
        projector_module._projection_children = original_children

    assert await _snapshot_count(session_factory, identity.user_id) == before
    async with session_factory() as database:
        failed = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == operation_id
            )
        )
        assert failed is not None
        assert failed.published_at is None
        assert failed.attempt_count == 0
        assert failed.last_failed_at is None
        assert failed.failure_code is None

    clock.advance(timedelta(seconds=1))
    assert await projector.consume_next() is True
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1
    async with session_factory() as database:
        recovered = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == operation_id
            )
        )
        assert recovered is not None
        assert recovered.published_at is not None
        assert recovered.attempt_count == 1


async def _assert_home_calendar_is_sampled_after_shared_locks(
    *,
    client: AsyncClient,
    identity: _Identity,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    current = await _home(client, identity)
    assert current.status_code == 200, current.text
    before = await _snapshot_count(session_factory, identity.user_id)

    async with session_factory() as database, database.begin():
        locked_user = await database.scalar(
            select(UserRow).where(UserRow.id == identity.user_id).with_for_update()
        )
        assert locked_user is not None
        locked_account = await database.scalar(
            select(FinanceAccountRow)
            .where(FinanceAccountRow.user_id == identity.user_id)
            .with_for_update()
        )
        assert locked_account is not None
        waiting_home = asyncio.create_task(_home(client, identity))
        await asyncio.sleep(0.1)
        assert not waiting_home.done()
        clock.advance(timedelta(days=1))

    stale = await asyncio.wait_for(waiting_home, timeout=5)
    assert stale.status_code == 503
    reconciliation = await projector.reconcile_all()
    assert reconciliation.published == 1
    assert reconciliation.failures_present is False
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1
    assert (await _home(client, identity)).status_code == 200


async def _assert_daily_reconciliation(
    *,
    client: AsyncClient,
    identity: _Identity,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    before = await _snapshot_count(session_factory, identity.user_id)
    clock.advance(timedelta(days=1))
    reconciliation = await projector.reconcile_all()
    assert reconciliation.published == 1
    assert reconciliation.failures_present is False
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1
    no_op = await projector.reconcile_all()
    assert no_op.published == 0
    assert no_op.failures_present is False
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1
    reconciled = await _latest_snapshot(session_factory, identity.user_id)
    assert reconciled.projection_schema_version == 2
    assert reconciled.data_as_of == reconciled.generated_at
    assert (await _home(client, identity)).status_code == 200


async def _assert_watermark_and_newer_schema_guards(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    before = await _snapshot_count(session_factory, identity.user_id)
    latest = await _latest_snapshot(session_factory, identity.user_id)
    stable_clock = clock.value
    operation_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="2.00",
        occurred_on=clock().astimezone(TIMEZONE).date() - timedelta(days=1),
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    future_watermark_id = uuid4()
    future_watermark = stable_clock + timedelta(seconds=1)
    async with session_factory() as database, database.begin():
        database.add(
            HomeProjectionSnapshotRow(
                id=future_watermark_id,
                user_id=latest.user_id,
                account_id=latest.account_id,
                timezone_name=latest.timezone_name,
                period_start=latest.period_start,
                period_end=latest.period_end,
                revision=latest.revision + 1,
                projection_schema_version=latest.projection_schema_version,
                generated_at=future_watermark,
                data_as_of=future_watermark,
                base_currency=latest.base_currency,
                balance_amount=latest.balance_amount,
                balance_delta_amount=latest.balance_delta_amount,
                balance_delta_percent=latest.balance_delta_percent,
                month_income=latest.month_income,
                month_expense=latest.month_expense,
                month_net_flow=latest.month_net_flow,
                trend_metric=latest.trend_metric,
                trend_period=latest.trend_period,
                trend_total=latest.trend_total,
            )
        )
    try:
        await projector.consume_next()
    except HomeProjectionInvariantError as error:
        assert str(error) == "projection watermark cannot move backwards"
    else:
        raise AssertionError("projector accepted a decreasing source watermark")
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1
    async with session_factory() as database:
        failed = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == operation_id
            )
        )
        assert failed is not None
        assert failed.published_at is None
        assert failed.attempt_count == 0
        assert failed.last_failed_at is None
        assert failed.failure_code is None

    async with session_factory() as database, database.begin():
        await database.execute(
            delete(HomeProjectionSnapshotRow).where(
                HomeProjectionSnapshotRow.id == future_watermark_id
            )
        )
    assert await _snapshot_count(session_factory, identity.user_id) == before
    clock.value = stable_clock + timedelta(seconds=1)
    assert await projector.consume_next() is True
    assert await _snapshot_count(session_factory, identity.user_id) == before + 1

    latest = await _latest_snapshot(session_factory, identity.user_id)
    newer_schema_id = uuid4()
    async with session_factory() as database, database.begin():
        database.add(
            HomeProjectionSnapshotRow(
                id=newer_schema_id,
                user_id=latest.user_id,
                account_id=latest.account_id,
                timezone_name=latest.timezone_name,
                period_start=latest.period_start,
                period_end=latest.period_end,
                revision=latest.revision + 1,
                projection_schema_version=3,
                generated_at=latest.generated_at,
                data_as_of=latest.data_as_of,
                base_currency=latest.base_currency,
                balance_amount=latest.balance_amount,
                balance_delta_amount=latest.balance_delta_amount,
                balance_delta_percent=latest.balance_delta_percent,
                month_income=latest.month_income,
                month_expense=latest.month_expense,
                month_net_flow=latest.month_net_flow,
                trend_metric=latest.trend_metric,
                trend_period=latest.trend_period,
                trend_total=latest.trend_total,
            )
        )

    schema_guard_operation_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="1.00",
        occurred_on=clock().astimezone(TIMEZONE).date() - timedelta(days=1),
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    try:
        await projector.consume_next()
    except HomeProjectionInvariantError as error:
        assert str(error) == "newer Home projection schema is already authoritative"
    else:
        raise AssertionError("schema-v2 projector overwrote a newer schema")

    async with session_factory() as database, database.begin():
        await database.execute(
            delete(HomeProjectionSnapshotRow).where(
                HomeProjectionSnapshotRow.id == newer_schema_id
            )
        )
    clock.advance(timedelta(seconds=1))
    assert await projector.consume_next() is True
    async with session_factory() as database:
        recovered = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == schema_guard_operation_id
            )
        )
        assert recovered is not None
        assert recovered.published_at is not None
        assert recovered.attempt_count == 1


async def _assert_poison_dlq_is_exact_and_other_user_progresses(
    *,
    client: AsyncClient,
    identity: _Identity,
    account_id: UUID,
    session_factory: AsyncSessionFactory,
    clock: _MutableClock,
) -> tuple[_Identity, UUID]:
    projector = PostgresHomeProjector(
        session_factory=session_factory,
        clock=clock,
        retry_policy=EventRetryPolicy(
            max_attempts=2,
            initial_seconds=1,
            maximum_seconds=1,
        ),
    )
    other_identity = await _register(
        client,
        email="home-projector-other@example.com",
    )
    other_account_id = await _open_account(
        client,
        identity=other_identity,
        opening_on=clock().astimezone(TIMEZONE).date().replace(day=1),
        clock=clock,
    )
    assert await projector.consume_next() is True

    first_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="1.00",
        occurred_on=clock().astimezone(TIMEZONE).date() - timedelta(days=1),
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    clock.advance(timedelta(seconds=1))
    poison_id = await _commit_operation(
        client,
        identity=identity,
        account_id=account_id,
        operation_type="expense",
        amount="2.00",
        occurred_on=clock().astimezone(TIMEZONE).date() - timedelta(days=1),
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    clock.advance(timedelta(seconds=1))
    await _commit_operation(
        client,
        identity=other_identity,
        account_id=other_account_id,
        operation_type="income",
        amount="3.00",
        occurred_on=clock().astimezone(TIMEZONE).date() - timedelta(days=1),
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )

    async with session_factory() as database, database.begin():
        poison = await database.scalar(
            select(FinanceOutboxEventRow)
            .where(FinanceOutboxEventRow.aggregate_id == poison_id)
            .with_for_update()
        )
        assert poison is not None
        original_payload = dict(poison.payload)
        # Simulate a pre-0006 event whose generic delivery attempts saturated.
        # Only the dedicated validation counter may consume the DLQ budget.
        poison.attempt_count = 32767
        poison.payload = {**original_payload, "operationId": str(uuid4())}

    with pytest.raises(HomeProjectionInvariantError):
        await projector.consume_next()

    async with session_factory() as database:
        first = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == first_id
            )
        )
        poison = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == poison_id
            )
        )
        assert first is not None and poison is not None
        assert first.attempt_count == 0
        assert first.last_failed_at is None
        assert poison.attempt_count == 32767
        assert poison.validation_failure_count == 1
        assert poison.failure_code == "invalid_outbox_contract"
        assert poison.dead_lettered_at is None

    # The delayed first user's stream must not block a different user.
    assert await projector.consume_next() is True
    assert (await _home(client, other_identity)).status_code == 200
    assert (await _home(client, identity)).status_code == 503

    clock.advance(timedelta(seconds=1))
    with pytest.raises(HomeProjectionInvariantError):
        await projector.consume_next()
    async with session_factory() as database:
        dead = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == poison_id
            )
        )
        assert dead is not None
        assert dead.published_at is None
        assert dead.next_attempt_at is None
        assert dead.attempt_count == 32767
        assert dead.validation_failure_count == 2
        assert dead.failure_code == "invalid_outbox_contract"
        assert dead.dead_lettered_at == clock.value
    assert await projector.consume_next() is False
    assert (await _home(client, identity)).status_code == 503

    # Explicit synthetic remediation restores the original identifier-only
    # payload and requeues the event. There is intentionally no operator API.
    async with session_factory() as database, database.begin():
        dead = await database.scalar(
            select(FinanceOutboxEventRow)
            .where(FinanceOutboxEventRow.aggregate_id == poison_id)
            .with_for_update()
        )
        assert dead is not None
        dead.payload = original_payload
        dead.next_attempt_at = clock.value
        dead.last_failed_at = None
        dead.failure_code = None
        dead.dead_lettered_at = None
        dead.validation_failure_count = 0

    assert await projector.consume_next() is True
    assert (await _home(client, identity)).status_code == 200
    async with session_factory() as database:
        first = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == first_id
            )
        )
        recovered = await database.scalar(
            select(FinanceOutboxEventRow).where(
                FinanceOutboxEventRow.aggregate_id == poison_id
            )
        )
        assert first is not None and recovered is not None
        assert first.published_at is not None
        assert first.attempt_count == 1
        assert recovered.published_at is not None
        assert recovered.attempt_count == 32767
        assert recovered.validation_failure_count == 0
        assert recovered.failure_code is None

    return other_identity, other_account_id


async def _assert_generic_failure_is_cycle_local(
    *,
    client: AsyncClient,
    blocked: _Identity,
    blocked_account_id: UUID,
    healthy: _Identity,
    healthy_account_id: UUID,
    session_factory: AsyncSessionFactory,
    projector: PostgresHomeProjector,
    clock: _MutableClock,
) -> None:
    occurred_on = clock().astimezone(TIMEZONE).date() - timedelta(days=1)
    await _commit_operation(
        client,
        identity=blocked,
        account_id=blocked_account_id,
        operation_type="expense",
        amount="4.00",
        occurred_on=occurred_on,
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )
    clock.advance(timedelta(seconds=1))
    await _commit_operation(
        client,
        identity=healthy,
        account_id=healthy_account_id,
        operation_type="income",
        amount="5.00",
        occurred_on=occurred_on,
        clock=clock,
        category=None,
        merchant=None,
        occurred_at=None,
    )

    async with session_factory() as database, database.begin():
        profile = await database.scalar(
            select(UserRow).where(UserRow.id == blocked.user_id).with_for_update()
        )
        assert profile is not None
        profile.canonical_timezone = "UTC"

    result = await projector.drain_available(max_candidates=10)
    assert result.published == 1
    assert result.inspected == 2
    assert result.failures_present is True
    assert (await _home(client, blocked)).status_code != 200
    assert (await _home(client, healthy)).status_code == 200

    async with session_factory() as database, database.begin():
        profile = await database.scalar(
            select(UserRow).where(UserRow.id == blocked.user_id).with_for_update()
        )
        assert profile is not None
        profile.canonical_timezone = TIMEZONE_NAME

    recovered = await projector.drain_available(max_candidates=10)
    assert recovered.published == 1
    assert recovered.failures_present is False
    assert (await _home(client, blocked)).status_code == 200

    async with session_factory() as database, database.begin():
        await database.execute(delete(UserRow).where(UserRow.id == healthy.user_id))


async def _assert_leadership_health_and_takeover(
    *,
    engine,
    session_factory: AsyncSessionFactory,
    clock: _MutableClock,
) -> None:
    async with acquire_projector_leadership(
        engine=engine,
        clock=clock,
    ) as first:
        assert first is not None
        await first.heartbeat(status="idle")
        async with acquire_projector_leadership(
            engine=engine,
            clock=clock,
        ) as contender:
            assert contender is None
        healthy = await read_projector_health(
            session_factory=session_factory,
            clock=clock,
            heartbeat_stale_seconds=30,
            maximum_lag_seconds=120,
        )
        assert healthy.status == "healthy"
        assert healthy.leader == "present"
        assert healthy.heartbeat_age == "fresh"
        assert healthy.pending_lag == "none"
        assert healthy.dead_letters == "none"
        assert healthy.last_cycle == "ok"

        await first.heartbeat(status="degraded")
        degraded_cycle = await read_projector_health(
            session_factory=session_factory,
            clock=clock,
            heartbeat_stale_seconds=30,
            maximum_lag_seconds=120,
        )
        assert degraded_cycle.status == "degraded"
        assert degraded_cycle.last_cycle == "degraded"
        await first.heartbeat(status="idle")

    stopped = await read_projector_health(
        session_factory=session_factory,
        clock=clock,
        heartbeat_stale_seconds=30,
        maximum_lag_seconds=120,
    )
    assert stopped.status == "degraded"
    assert stopped.leader == "absent"

    async with acquire_projector_leadership(
        engine=engine,
        clock=clock,
    ) as successor:
        assert successor is not None
        await successor.heartbeat(status="idle")


async def _assert_revision_retention_is_bounded_and_keeps_two(
    *,
    identity: _Identity,
    session_factory: AsyncSessionFactory,
    clock: _MutableClock,
) -> None:
    latest = await _latest_snapshot(session_factory, identity.user_id)
    old_generated_at = clock.value - timedelta(days=60)
    old_snapshot_ids: list[UUID] = []
    non_deletable_user_id = UUID("00000000-0000-4000-8000-000000000001")
    async with session_factory() as database, database.begin():
        database.add(
            UserRow(
                id=non_deletable_user_id,
                email_normalized="synthetic-retention-skip@example.invalid",
                password_hash="synthetic-unused-hash",
                display_name="Synthetic retention skip",
                base_currency="EUR",
                canonical_timezone=TIMEZONE_NAME,
                timezone_revision=1,
                created_at=old_generated_at,
                updated_at=old_generated_at,
                disabled_at=None,
            )
        )
        # Flushed before the account below: nothing relates the mappers, so
        # the unit of work is free to insert the account first and its foreign
        # key then refuses it.
        await database.flush()
        # A revision belongs to a wallet from 0020 on (ADR 0029), so the
        # synthetic profile needs one before it can hold any.
        non_deletable_account_id = UUID("00000000-0000-4000-8000-000000000002")
        database.add(
            FinanceAccountRow(
                id=non_deletable_account_id,
                user_id=non_deletable_user_id,
                command_id=UUID("00000000-0000-4000-8000-000000000003"),
                command_payload_hash=b"\x00" * 32,
                schema_version="1",
                name="Synthetic retention skip account",
                currency="EUR",
                opening_balance=Decimal("0"),
                opening_balance_on=old_generated_at.date(),
                opening_timezone=TIMEZONE_NAME,
                status="active",
                is_default=True,
                confirmed_at=old_generated_at,
                created_at=old_generated_at,
            )
        )
        await database.flush()
        for revision in range(1, 3):
            generated_at = old_generated_at + timedelta(milliseconds=revision)
            database.add(
                HomeProjectionSnapshotRow(
                    id=uuid4(),
                    user_id=non_deletable_user_id,
                    account_id=non_deletable_account_id,
                    timezone_name=latest.timezone_name,
                    period_start=date(2024, 1, 1),
                    period_end=date(2024, 1, 31),
                    revision=revision,
                    projection_schema_version=2,
                    generated_at=generated_at,
                    data_as_of=generated_at,
                    base_currency=latest.base_currency,
                    balance_amount=latest.balance_amount,
                    balance_delta_amount=latest.balance_delta_amount,
                    balance_delta_percent=latest.balance_delta_percent,
                    month_income=latest.month_income,
                    month_expense=latest.month_expense,
                    month_net_flow=latest.month_net_flow,
                    trend_metric=latest.trend_metric,
                    trend_period=latest.trend_period,
                    trend_total=latest.trend_total,
                )
            )
        for revision in range(1, 6):
            snapshot_id = uuid4()
            old_snapshot_ids.append(snapshot_id)
            generated_at = old_generated_at + timedelta(seconds=revision)
            database.add(
                HomeProjectionSnapshotRow(
                    id=snapshot_id,
                    user_id=identity.user_id,
                    account_id=latest.account_id,
                    timezone_name=latest.timezone_name,
                    period_start=date(2025, 1, 1),
                    period_end=date(2025, 1, 31),
                    revision=revision,
                    projection_schema_version=2,
                    generated_at=generated_at,
                    data_as_of=generated_at,
                    base_currency=latest.base_currency,
                    balance_amount=latest.balance_amount,
                    balance_delta_amount=latest.balance_delta_amount,
                    balance_delta_percent=latest.balance_delta_percent,
                    month_income=latest.month_income,
                    month_expense=latest.month_expense,
                    month_net_flow=latest.month_net_flow,
                    trend_metric=latest.trend_metric,
                    trend_period=latest.trend_period,
                    trend_total=latest.trend_total,
                )
            )
        await database.flush()
        database.add(
            HomeProjectionActionRow(
                snapshot_id=old_snapshot_ids[0],
                position=0,
                action="synthetic_retention_marker",
            )
        )

    first_pruned = await prune_home_revisions(
        session_factory=session_factory,
        clock=clock,
        policy=RevisionRetentionPolicy(
            minimum_per_series=2,
            grace_days=30,
            maximum_per_cycle=1,
        ),
    )
    # The lexicographically first user has old snapshots but nothing eligible
    # beyond the mandatory two. It must not consume the bounded cleanup slot.
    assert first_pruned == 1
    second_pruned = await prune_home_revisions(
        session_factory=session_factory,
        clock=clock,
        policy=RevisionRetentionPolicy(
            minimum_per_series=2,
            grace_days=30,
            maximum_per_cycle=100,
        ),
    )
    assert second_pruned == 2

    async with session_factory() as database:
        survivors = tuple(
            (
                await database.scalars(
                    select(HomeProjectionSnapshotRow.revision)
                    .where(
                        HomeProjectionSnapshotRow.user_id == identity.user_id,
                        HomeProjectionSnapshotRow.period_start == date(2025, 1, 1),
                    )
                    .order_by(HomeProjectionSnapshotRow.revision.asc())
                )
            ).all()
        )
        deleted_marker = await database.scalar(
            select(HomeProjectionActionRow).where(
                HomeProjectionActionRow.snapshot_id == old_snapshot_ids[0]
            )
        )
        non_deletable_survivors = await database.scalar(
            select(func.count())
            .select_from(HomeProjectionSnapshotRow)
            .where(HomeProjectionSnapshotRow.user_id == non_deletable_user_id)
        )
    assert survivors == (4, 5)
    assert deleted_marker is None
    assert non_deletable_survivors == 2


async def _exercise() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    clock = _MutableClock(datetime.now(UTC).replace(microsecond=0))
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-home-projector-test",
        audience="mfa-home-projector-test-mobile",
    )
    app = _application(
        session_factory=session_factory,
        tokens=tokens,
        clock=clock,
    )
    projector = PostgresHomeProjector(
        session_factory=session_factory,
        clock=clock,
    )

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            identity = await _register(client)
            empty = await _home(client, identity)
            assert empty.status_code == 200, empty.text
            assert empty.json()["homeState"] == "first_use_empty"

            local_date = clock().astimezone(TIMEZONE).date()
            opening_on = local_date.replace(day=1)
            account_id = await _open_account(
                client,
                identity=identity,
                opening_on=opening_on,
                clock=clock,
            )
            await _assert_opening_projection(
                client=client,
                identity=identity,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )

            _, _, occurred_on = await _assert_operation_projection(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                clock=clock,
            )
            await _assert_tampered_event_retry(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
                occurred_on=occurred_on,
            )
            await _assert_writer_and_projector_share_user_account_lock_boundary(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )
            await _assert_child_failure_rolls_back_revision_and_acknowledgement(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )
            (
                healthy_identity,
                healthy_account_id,
            ) = await _assert_poison_dlq_is_exact_and_other_user_progresses(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                clock=clock,
            )
            await _assert_generic_failure_is_cycle_local(
                client=client,
                blocked=identity,
                blocked_account_id=account_id,
                healthy=healthy_identity,
                healthy_account_id=healthy_account_id,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )
            await _assert_home_calendar_is_sampled_after_shared_locks(
                client=client,
                identity=identity,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )
            await _assert_daily_reconciliation(
                client=client,
                identity=identity,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )
            await _assert_watermark_and_newer_schema_guards(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                projector=projector,
                clock=clock,
            )
            await _assert_transfer_projection(
                client=client,
                identity=identity,
                account_id=account_id,
                session_factory=session_factory,
                clock=clock,
            )
            await _assert_leadership_health_and_takeover(
                engine=engine,
                session_factory=session_factory,
                clock=clock,
            )
            await _assert_revision_retention_is_bounded_and_keeps_two(
                identity=identity,
                session_factory=session_factory,
                clock=clock,
            )
    finally:
        await engine.dispose()


def main() -> None:
    _populated_migration_round_trip()
    asyncio.run(_exercise())
    _assert_retry_metadata_blocks_lossy_downgrade()
    _assert_projected_revision_blocks_lossy_downgrade()
    print("Home projector PostgreSQL E2E: pass")


if __name__ == "__main__":
    main()
