"""Transactional PostgreSQL adapter for authoritative Finance accounts."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from datetime import UTC, date, datetime
from typing import Literal
from uuid import UUID, uuid4

from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .account_contracts import (
    AccountDraft,
    CommittedFinanceAccount,
    CorrectBaselineDraft,
)
from .account_core import (
    AccountAlreadyInitialized,
    AccountCommandConflict,
    AccountListSnapshot,
    AccountPersistenceUnavailable,
    AccountSetupSnapshot,
    AccountWriteResult,
    BaselineCorrectionSnapshot,
    BaselineWriteResult,
    FinanceAccountSnapshot,
)
from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountAuditRow,
    FinanceAccountOutboxEventRow,
    FinanceAccountRow,
    FinanceOperationRow,
    UserRow,
)
from .postgres_category_repository import seeded_category_rows


class PostgresFinanceAccountRepository:
    """Persist the single v1 account, timezone bootstrap, audit, and outbox."""

    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        async with self._session_factory() as database:
            account = await database.scalar(
                select(FinanceAccountRow).where(
                    FinanceAccountRow.id == account_id,
                    FinanceAccountRow.user_id == user_id,
                    FinanceAccountRow.status == "active",
                )
            )
        if account is None:
            return None
        return _to_directory_snapshot(account)

    async def get_setup_snapshot(self, *, user_id: UUID) -> AccountSetupSnapshot:
        async with self._session_factory() as database:
            user = await _active_user(database=database, user_id=user_id)
            accounts = await _accounts(database=database, user_id=user_id)
        _require_single_account(accounts)
        _require_consistent_profile(user=user, accounts=accounts)
        snapshot = AccountSetupSnapshot(
            account_id=accounts[0].id if accounts else None,
            canonical_timezone=user.canonical_timezone,
            timezone_revision=user.timezone_revision,
        )
        if not snapshot.is_consistent:
            raise AccountPersistenceUnavailable
        return snapshot

    async def list_accounts(self, *, user_id: UUID) -> AccountListSnapshot:
        async with self._session_factory() as database:
            user = await _active_user(database=database, user_id=user_id)
            accounts = await _accounts(database=database, user_id=user_id)
        _require_single_account(accounts)
        _require_consistent_profile(user=user, accounts=accounts)
        timezone_revision: Literal[0, 1] = 1 if accounts else 0
        return AccountListSnapshot(
            canonical_timezone=user.canonical_timezone,
            timezone_revision=timezone_revision,
            accounts=tuple(_to_contract(account) for account in accounts),
        )

    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> AccountWriteResult | None:
        if len(payload_hash) != 32:
            raise AccountPersistenceUnavailable
        async with self._session_factory() as database:
            user = await _active_user(database=database, user_id=user_id)
            existing = await database.scalar(
                _opening_replay_account_query(
                    user_id=user_id,
                    command_id=command_id,
                )
            )
            baseline_corrections: tuple[FinanceAccountAuditRow, ...] = ()
            if existing is not None:
                baseline_corrections = await _baseline_corrections(
                    database=database,
                    user_id=user_id,
                    account_id=existing.id,
                )
        if existing is None:
            return None
        if existing.command_payload_hash != payload_hash:
            raise AccountCommandConflict
        return _write_result(
            user=user,
            account=existing,
            idempotent_replay=True,
            opening_balance_on=_original_opening_balance_on(
                account=existing,
                corrections=baseline_corrections,
            ),
        )

    async def commit_account(
        self,
        *,
        user_id: UUID,
        draft: AccountDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> AccountWriteResult:
        if len(payload_hash) != 32:
            raise AccountPersistenceUnavailable
        confirmed_at = _aware_utc(confirmed_at)
        created_at = _aware_utc(self._clock())
        account_id = uuid4()

        async with self._session_factory() as database:
            async with database.begin():
                user = await database.scalar(
                    select(UserRow)
                    .where(
                        UserRow.id == user_id,
                        UserRow.disabled_at.is_(None),
                    )
                    .with_for_update()
                )
                if user is None:
                    raise AccountPersistenceUnavailable

                existing = await database.scalar(
                    _opening_replay_account_query(
                        user_id=user_id,
                        command_id=draft.command_id,
                    )
                )
                if existing is not None:
                    if existing.command_payload_hash != payload_hash:
                        raise AccountCommandConflict
                    baseline_corrections = await _baseline_corrections(
                        database=database,
                        user_id=user_id,
                        account_id=existing.id,
                    )
                    return _write_result(
                        user=user,
                        account=existing,
                        idempotent_replay=True,
                        opening_balance_on=_original_opening_balance_on(
                            account=existing,
                            corrections=baseline_corrections,
                        ),
                    )

                account_exists = await database.scalar(
                    select(FinanceAccountRow.id)
                    .where(FinanceAccountRow.user_id == user_id)
                    .limit(1)
                )
                if account_exists is not None:
                    raise AccountAlreadyInitialized
                if (
                    user.canonical_timezone is not None
                    or user.timezone_revision != 0
                    or user.base_currency != draft.currency
                ):
                    raise AccountPersistenceUnavailable

                account = FinanceAccountRow(
                    id=account_id,
                    user_id=user_id,
                    command_id=draft.command_id,
                    command_payload_hash=payload_hash,
                    schema_version=draft.schema_version,
                    name=draft.name,
                    currency=draft.currency,
                    opening_balance=draft.opening_balance,
                    opening_balance_on=draft.opening_balance_on,
                    opening_timezone=draft.canonical_timezone,
                    status="active",
                    is_default=True,
                    confirmed_at=confirmed_at,
                    created_at=created_at,
                )
                user.canonical_timezone = draft.canonical_timezone
                user.timezone_revision = 1
                user.updated_at = created_at
                database.add(account)
                # The mappings deliberately expose no ORM relationships. Flush
                # the account and profile before inserting strongly-FK children.
                await database.flush()
                database.add_all(
                    [
                        FinanceAccountAuditRow(
                            id=uuid4(),
                            account_id=account_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="account_opened",
                            actor_type="user",
                            payload_hash=payload_hash,
                            created_at=created_at,
                        ),
                        FinanceAccountOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="finance_account",
                            aggregate_id=account_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="finance.account.opened.v1",
                            payload=_outbox_payload(
                                account_id=account_id,
                                user_id=user_id,
                                command_id=draft.command_id,
                            ),
                            created_at=created_at,
                            published_at=None,
                            attempt_count=0,
                            validation_failure_count=0,
                            next_attempt_at=created_at,
                            last_failed_at=None,
                            failure_code=None,
                            dead_lettered_at=None,
                        ),
                    ]
                )
                # Seeded in the same transaction as the account, so a user never
                # faces an empty picker and a failure leaves neither (ADR 0020).
                database.add_all(
                    seeded_category_rows(user_id=user_id, created_at=created_at)
                )
            return _write_result(
                user=user,
                account=account,
                idempotent_replay=False,
            )

    async def get_baseline_snapshot(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> BaselineCorrectionSnapshot | None:
        async with self._session_factory() as database:
            account = await database.scalar(
                select(FinanceAccountRow).where(
                    FinanceAccountRow.id == account_id,
                    FinanceAccountRow.user_id == user_id,
                    FinanceAccountRow.status == "active",
                )
            )
            if account is None:
                return None
            earliest = await _earliest_operation_on(
                database=database,
                user_id=user_id,
                account_id=account_id,
            )
        return BaselineCorrectionSnapshot(
            account_id=account.id,
            user_id=account.user_id,
            opening_balance_on=account.opening_balance_on,
            canonical_timezone=account.opening_timezone,
            earliest_operation_on=earliest,
        )

    async def replay_existing_baseline(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BaselineWriteResult | None:
        if len(payload_hash) != 32:
            raise AccountPersistenceUnavailable
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(FinanceAccountAuditRow).where(
                    FinanceAccountAuditRow.account_id == account_id,
                    FinanceAccountAuditRow.user_id == user_id,
                    FinanceAccountAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            if (
                audit.payload_hash != payload_hash
                or audit.event_type != "account_baseline_corrected"
            ):
                raise AccountCommandConflict
            account = await database.scalar(
                select(FinanceAccountRow).where(
                    FinanceAccountRow.id == account_id,
                    FinanceAccountRow.user_id == user_id,
                )
            )
        if account is None:  # pragma: no cover - foreign key guarantees a row
            raise AccountPersistenceUnavailable
        return _baseline_replay_result(account=account, audit=audit)

    async def correct_opening_baseline(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> BaselineWriteResult:
        if len(payload_hash) != 32:
            raise AccountPersistenceUnavailable
        del confirmed_at  # bound into payload_hash; the audit row carries created_at
        created_at = _aware_utc(self._clock())

        async with self._session_factory() as database:
            async with database.begin():
                account = await database.scalar(
                    select(FinanceAccountRow)
                    .where(
                        FinanceAccountRow.id == draft.account_id,
                        FinanceAccountRow.user_id == user_id,
                        FinanceAccountRow.status == "active",
                    )
                    .with_for_update()
                )
                if account is None:
                    raise AccountPersistenceUnavailable

                existing = await database.scalar(
                    select(FinanceAccountAuditRow).where(
                        FinanceAccountAuditRow.account_id == draft.account_id,
                        FinanceAccountAuditRow.user_id == user_id,
                        FinanceAccountAuditRow.command_id == draft.command_id,
                    )
                )
                if existing is not None:
                    if (
                        existing.payload_hash != payload_hash
                        or existing.event_type != "account_baseline_corrected"
                    ):
                        raise AccountCommandConflict
                    return _baseline_replay_result(account=account, audit=existing)

                previous_opening_balance_on = account.opening_balance_on
                # Re-check under the row lock: evaluation and confirmation are
                # separate requests, so the bound may have moved in between.
                if draft.opening_balance_on >= previous_opening_balance_on:
                    raise AccountPersistenceUnavailable
                earliest = await _earliest_operation_on(
                    database=database,
                    user_id=user_id,
                    account_id=draft.account_id,
                )
                if earliest is not None and draft.opening_balance_on > earliest:
                    raise AccountPersistenceUnavailable

                account.opening_balance_on = draft.opening_balance_on
                database.add_all(
                    [
                        FinanceAccountAuditRow(
                            id=uuid4(),
                            account_id=draft.account_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="account_baseline_corrected",
                            actor_type="user",
                            payload_hash=payload_hash,
                            details={
                                "previousOpeningBalanceOn": (
                                    previous_opening_balance_on.isoformat()
                                ),
                                "openingBalanceOn": (
                                    draft.opening_balance_on.isoformat()
                                ),
                            },
                            created_at=created_at,
                        ),
                        FinanceAccountOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="finance_account",
                            aggregate_id=draft.account_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="finance.account.baseline_corrected.v1",
                            payload=_outbox_payload(
                                account_id=draft.account_id,
                                user_id=user_id,
                                command_id=draft.command_id,
                            ),
                            created_at=created_at,
                            published_at=None,
                            attempt_count=0,
                            validation_failure_count=0,
                            next_attempt_at=created_at,
                            last_failed_at=None,
                            failure_code=None,
                            dead_lettered_at=None,
                        ),
                    ]
                )
            return BaselineWriteResult(
                account=_to_contract(account),
                previous_opening_balance_on=previous_opening_balance_on,
                idempotent_replay=False,
            )


async def _earliest_operation_on(
    *,
    database: AsyncSession,
    user_id: UUID,
    account_id: UUID,
) -> date | None:
    earliest: date | None = await database.scalar(
        select(func.min(FinanceOperationRow.occurred_on)).where(
            FinanceOperationRow.account_id == account_id,
            FinanceOperationRow.user_id == user_id,
        )
    )
    return earliest


async def _baseline_corrections(
    *,
    database: AsyncSession,
    user_id: UUID,
    account_id: UUID,
) -> tuple[FinanceAccountAuditRow, ...]:
    result = await database.scalars(
        select(FinanceAccountAuditRow).where(
            FinanceAccountAuditRow.account_id == account_id,
            FinanceAccountAuditRow.user_id == user_id,
            FinanceAccountAuditRow.event_type == "account_baseline_corrected",
        )
    )
    return tuple(result.all())


def _opening_replay_account_query(
    *, user_id: UUID, command_id: UUID
) -> Select[tuple[FinanceAccountRow]]:
    """Lock the live account while reconstructing its original receipt.

    PostgreSQL READ COMMITTED takes a new snapshot for each statement. Without
    this row lock, a concurrent baseline correction can commit after the account
    read but before the audit-chain read, making a valid chain look corrupt.
    """

    return (
        select(FinanceAccountRow)
        .where(
            FinanceAccountRow.user_id == user_id,
            FinanceAccountRow.command_id == command_id,
        )
        .with_for_update()
    )


def _baseline_replay_result(
    *,
    account: FinanceAccountRow,
    audit: FinanceAccountAuditRow,
) -> BaselineWriteResult:
    previous = _audit_baseline_date(audit, "previousOpeningBalanceOn")
    corrected = _audit_baseline_date(audit, "openingBalanceOn")
    # Replay is the original receipt, not a snapshot of later aggregate state.
    # A subsequent correction may have moved the live baseline farther back, so
    # preserve every current immutable account field while restoring the date
    # that this command actually accepted.
    if corrected >= previous or account.opening_balance_on > corrected:
        raise AccountPersistenceUnavailable
    return BaselineWriteResult(
        account=_to_contract(account, opening_balance_on=corrected),
        previous_opening_balance_on=previous,
        idempotent_replay=True,
    )


def _original_opening_balance_on(
    *,
    account: FinanceAccountRow,
    corrections: Sequence[FinanceAccountAuditRow],
) -> date:
    if not corrections:
        return account.opening_balance_on

    transitions: dict[date, date] = {}
    for audit in corrections:
        if audit.event_type != "account_baseline_corrected":
            raise AccountPersistenceUnavailable
        previous = _audit_baseline_date(audit, "previousOpeningBalanceOn")
        corrected = _audit_baseline_date(audit, "openingBalanceOn")
        if corrected >= previous or previous in transitions:
            raise AccountPersistenceUnavailable
        transitions[previous] = corrected

    # Corrections move strictly backwards, so the greatest previous date is the
    # first correction's source and therefore the original onboarding date.
    original = max(transitions)
    cursor = original
    visited = 0
    while cursor in transitions:
        cursor = transitions[cursor]
        visited += 1
    if visited != len(transitions) or cursor != account.opening_balance_on:
        raise AccountPersistenceUnavailable
    return original


def _audit_baseline_date(audit: FinanceAccountAuditRow, key: str) -> date:
    details = audit.details
    if not isinstance(details, dict):  # pragma: no cover - guarded by CHECK
        raise AccountPersistenceUnavailable
    raw = details.get(key)
    if not isinstance(raw, str):  # pragma: no cover - guarded by CHECK
        raise AccountPersistenceUnavailable
    try:
        return date.fromisoformat(raw)
    except ValueError as error:  # pragma: no cover - guarded by CHECK
        raise AccountPersistenceUnavailable from error


async def _active_user(*, database: AsyncSession, user_id: UUID) -> UserRow:
    user = await database.scalar(
        select(UserRow).where(
            UserRow.id == user_id,
            UserRow.disabled_at.is_(None),
        )
    )
    if user is None:
        raise AccountPersistenceUnavailable
    return user


async def _accounts(
    *, database: AsyncSession, user_id: UUID
) -> tuple[FinanceAccountRow, ...]:
    result = await database.scalars(
        select(FinanceAccountRow)
        .where(FinanceAccountRow.user_id == user_id)
        .order_by(FinanceAccountRow.created_at.asc(), FinanceAccountRow.id.asc())
        .limit(2)
    )
    return tuple(result.all())


def _require_single_account(accounts: Sequence[FinanceAccountRow]) -> None:
    if len(accounts) > 1:
        raise AccountPersistenceUnavailable


def _require_consistent_profile(
    *,
    user: UserRow,
    accounts: Sequence[FinanceAccountRow],
) -> None:
    if not accounts:
        if (
            user.base_currency != "EUR"
            or user.canonical_timezone is not None
            or user.timezone_revision != 0
        ):
            raise AccountPersistenceUnavailable
        return
    account = accounts[0]
    if (
        account.user_id != user.id
        or account.status != "active"
        or not account.is_default
        or account.currency != user.base_currency
        or user.canonical_timezone is None
        or user.timezone_revision != 1
        or account.opening_timezone != user.canonical_timezone
    ):
        raise AccountPersistenceUnavailable


def _write_result(
    *,
    user: UserRow,
    account: FinanceAccountRow,
    idempotent_replay: bool,
    opening_balance_on: date | None = None,
) -> AccountWriteResult:
    _require_consistent_profile(user=user, accounts=(account,))
    timezone = user.canonical_timezone
    if timezone is None:  # pragma: no cover - guarded above
        raise AccountPersistenceUnavailable
    return AccountWriteResult(
        account=_to_contract(account, opening_balance_on=opening_balance_on),
        canonical_timezone=timezone,
        timezone_revision=1,
        idempotent_replay=idempotent_replay,
    )


def _to_directory_snapshot(account: FinanceAccountRow) -> FinanceAccountSnapshot:
    return FinanceAccountSnapshot(
        account_id=account.id,
        user_id=account.user_id,
        currency=account.currency,
        opening_balance_on=account.opening_balance_on,
        status=account.status,  # type: ignore[arg-type]
    )


def _to_contract(
    account: FinanceAccountRow,
    *,
    opening_balance_on: date | None = None,
) -> CommittedFinanceAccount:
    return CommittedFinanceAccount(
        account_id=account.id,
        user_id=account.user_id,
        command_id=account.command_id,
        name=account.name,
        currency=account.currency,
        opening_balance=account.opening_balance,
        opening_balance_on=(
            opening_balance_on
            if opening_balance_on is not None
            else account.opening_balance_on
        ),
        opening_timezone=account.opening_timezone,
        status=account.status,  # type: ignore[arg-type]
        is_default=account.is_default,  # type: ignore[arg-type]
        confirmed_at=account.confirmed_at,
        created_at=account.created_at,
    )


def _outbox_payload(
    *,
    account_id: UUID,
    user_id: UUID,
    command_id: UUID,
) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "accountId": str(account_id),
        "userId": str(user_id),
        "commandId": str(command_id),
    }


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
