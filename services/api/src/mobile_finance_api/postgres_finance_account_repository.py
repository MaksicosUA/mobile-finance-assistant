"""Transactional PostgreSQL adapter for authoritative Finance accounts."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from datetime import UTC, datetime
from typing import Literal
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .account_contracts import AccountDraft, CommittedFinanceAccount
from .account_core import (
    AccountAlreadyInitialized,
    AccountCommandConflict,
    AccountListSnapshot,
    AccountPersistenceUnavailable,
    AccountSetupSnapshot,
    AccountWriteResult,
    FinanceAccountSnapshot,
)
from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountAuditRow,
    FinanceAccountOutboxEventRow,
    FinanceAccountRow,
    UserRow,
)


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
                select(FinanceAccountRow).where(
                    FinanceAccountRow.user_id == user_id,
                    FinanceAccountRow.command_id == command_id,
                )
            )
        if existing is None:
            return None
        if existing.command_payload_hash != payload_hash:
            raise AccountCommandConflict
        return _write_result(
            user=user,
            account=existing,
            idempotent_replay=True,
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
                    select(FinanceAccountRow).where(
                        FinanceAccountRow.user_id == user_id,
                        FinanceAccountRow.command_id == draft.command_id,
                    )
                )
                if existing is not None:
                    if existing.command_payload_hash != payload_hash:
                        raise AccountCommandConflict
                    return _write_result(
                        user=user,
                        account=existing,
                        idempotent_replay=True,
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
            return _write_result(
                user=user,
                account=account,
                idempotent_replay=False,
            )


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
) -> AccountWriteResult:
    _require_consistent_profile(user=user, accounts=(account,))
    timezone = user.canonical_timezone
    if timezone is None:  # pragma: no cover - guarded above
        raise AccountPersistenceUnavailable
    return AccountWriteResult(
        account=_to_contract(account),
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


def _to_contract(account: FinanceAccountRow) -> CommittedFinanceAccount:
    return CommittedFinanceAccount(
        account_id=account.id,
        user_id=account.user_id,
        command_id=account.command_id,
        name=account.name,
        currency=account.currency,
        opening_balance=account.opening_balance,
        opening_balance_on=account.opening_balance_on,
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
