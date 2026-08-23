"""Transactional PostgreSQL adapter for authoritative finance operations."""

from __future__ import annotations

import base64
import binascii
from collections.abc import Callable
from datetime import UTC, date, datetime
from typing import cast
from uuid import UUID, uuid4

from sqlalchemy import Date, DateTime, Uuid, literal, select, tuple_
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceCategoryRow,
    FinanceOperationAuditRow,
    FinanceOperationReversalRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    UserRow,
    operation_counts,
)
from .finance_core import (
    OperationAccountUnavailable,
    OperationAlreadyReversed,
    OperationBeforeAccountBaseline,
    OperationCommandConflict,
    OperationNotFound,
    OperationReversalResult,
    OperationWriteResult,
)
from .operation_contracts import (
    CommittedOperation,
    ListOperationsResponse,
    OperationDraft,
    OperationHistoryItem,
    OperationReversal,
)

MAXIMUM_HISTORY_PAGE = 100


class InvalidOperationCursor(Exception):
    """The paging cursor was not one this server issued."""


class PostgresFinanceOperationRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def list_operations(
        self,
        *,
        user_id: UUID,
        limit: int,
        cursor: str | None = None,
    ) -> ListOperationsResponse:
        """Return one page of the user's confirmed operations, newest first.

        Read-only, and outside Finance Core on purpose: nothing here decides or
        changes financial state.
        """

        if limit < 1 or limit > MAXIMUM_HISTORY_PAGE:
            raise ValueError("limit is out of range")
        after = _decode_cursor(cursor) if cursor is not None else None

        # Left join: an operation recorded before the catalogue has no link, and
        # must still appear rather than vanishing from its own history.
        statement = (
            select(FinanceOperationRow, FinanceCategoryRow.name)
            .outerjoin(
                FinanceCategoryRow,
                (FinanceCategoryRow.id == FinanceOperationRow.category_id)
                & (FinanceCategoryRow.user_id == FinanceOperationRow.user_id),
            )
            # A corrected or removed operation is gone from the ledger the
            # user reads; the row, its audit trail, and the reversal that
            # withdrew it all stay in the database (ADR 0023).
            .where(FinanceOperationRow.user_id == user_id, operation_counts())
            .order_by(
                FinanceOperationRow.occurred_on.desc(),
                FinanceOperationRow.created_at.desc(),
                FinanceOperationRow.id.desc(),
            )
            # One extra row answers "is there another page" without a second
            # count query that could disagree with the page it describes.
            .limit(limit + 1)
        )
        if after is not None:
            occurred_on, created_at, operation_id = after
            statement = statement.where(
                tuple_(
                    FinanceOperationRow.occurred_on,
                    FinanceOperationRow.created_at,
                    FinanceOperationRow.id,
                )
                < tuple_(
                    literal(occurred_on, Date),
                    literal(created_at, DateTime(timezone=True)),
                    literal(operation_id, Uuid(as_uuid=True)),
                )
            )

        async with self._session_factory() as database:
            rows = (await database.execute(statement)).all()

        page = rows[:limit]
        next_cursor = (
            _encode_cursor(page[-1][0]) if len(rows) > limit and page else None
        )
        return ListOperationsResponse(
            operations=tuple(
                _to_history_item(row, category_name=name) for row, name in page
            ),
            next_cursor=next_cursor,
        )

    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationWriteResult | None:
        async with self._session_factory() as database:
            existing = await database.scalar(
                select(FinanceOperationRow).where(
                    FinanceOperationRow.user_id == user_id,
                    FinanceOperationRow.command_id == command_id,
                )
            )
        if existing is None:
            return None
        if existing.command_payload_hash != payload_hash:
            raise OperationCommandConflict
        return OperationWriteResult(
            operation=_to_contract(existing),
            idempotent_replay=True,
        )

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult:
        operation_id = uuid4()
        account_id = draft.account_id
        if account_id is None:
            raise OperationAccountUnavailable

        async with self._session_factory() as database:
            async with database.begin():
                active_user = await database.scalar(
                    select(UserRow)
                    .where(
                        UserRow.id == user_id,
                        UserRow.disabled_at.is_(None),
                    )
                    .with_for_update()
                )
                if active_user is None:
                    raise OperationAccountUnavailable
                account = await database.scalar(
                    select(FinanceAccountRow)
                    .where(
                        FinanceAccountRow.id == account_id,
                        FinanceAccountRow.user_id == user_id,
                        FinanceAccountRow.status == "active",
                    )
                    .with_for_update()
                )
                if account is None or account.currency != draft.currency:
                    raise OperationAccountUnavailable
                if draft.occurred_on < account.opening_balance_on:
                    raise OperationBeforeAccountBaseline
                # Assign the source timestamp only after acquiring the same
                # user -> account locks used by the Home projector. A writer
                # that waited behind a completed projection must therefore be
                # newer than that projection's cutoff instead of carrying a
                # pre-lock time.
                created_at = _aware_utc(self._clock())
                inserted_id = await database.scalar(
                    insert(FinanceOperationRow)
                    .values(
                        id=operation_id,
                        user_id=user_id,
                        command_id=draft.command_id,
                        command_payload_hash=payload_hash,
                        schema_version=draft.schema_version,
                        operation_type=draft.operation_type,
                        amount=draft.amount,
                        currency=draft.currency,
                        account_id=account_id,
                        category=draft.category,
                        category_id=draft.category_id,
                        merchant=draft.merchant,
                        captured_at=draft.captured_at,
                        captured_timezone=draft.captured_timezone,
                        source_expression=draft.source_expression,
                        date_resolver_version=draft.date_resolver_version,
                        occurred_on=draft.occurred_on,
                        occurred_at=draft.occurred_at,
                        source=draft.source,
                        status="confirmed",
                        confirmed_at=confirmed_at,
                        created_at=created_at,
                    )
                    .on_conflict_do_nothing(index_elements=["user_id", "command_id"])
                    .returning(FinanceOperationRow.id)
                )
                if inserted_id is None:
                    existing = await database.scalar(
                        select(FinanceOperationRow).where(
                            FinanceOperationRow.user_id == user_id,
                            FinanceOperationRow.command_id == draft.command_id,
                        )
                    )
                    if existing is None:
                        raise RuntimeError("conflicting operation disappeared")
                    if existing.command_payload_hash != payload_hash:
                        raise OperationCommandConflict
                    return OperationWriteResult(
                        operation=_to_contract(existing),
                        idempotent_replay=True,
                    )

                row = FinanceOperationRow(
                    id=operation_id,
                    user_id=user_id,
                    command_id=draft.command_id,
                    command_payload_hash=payload_hash,
                    schema_version=draft.schema_version,
                    operation_type=draft.operation_type,
                    amount=draft.amount,
                    currency=draft.currency,
                    account_id=account_id,
                    category=draft.category,
                    category_id=draft.category_id,
                    merchant=draft.merchant,
                    captured_at=draft.captured_at,
                    captured_timezone=draft.captured_timezone,
                    source_expression=draft.source_expression,
                    date_resolver_version=draft.date_resolver_version,
                    occurred_on=draft.occurred_on,
                    occurred_at=draft.occurred_at,
                    source=draft.source,
                    status="confirmed",
                    confirmed_at=confirmed_at,
                    created_at=created_at,
                )
                database.add_all(
                    [
                        FinanceOperationAuditRow(
                            id=uuid4(),
                            operation_id=operation_id,
                            user_id=user_id,
                            command_id=draft.command_id,
                            event_type="operation_accepted",
                            actor_type="user",
                            payload_hash=payload_hash,
                            created_at=created_at,
                        ),
                        FinanceOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="finance_operation",
                            aggregate_id=operation_id,
                            event_type="finance.operation.accepted.v1",
                            payload=_outbox_payload(
                                operation_id=operation_id,
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
            return OperationWriteResult(
                operation=_to_contract(row),
                idempotent_replay=False,
            )

    async def replay_reversal(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationReversalResult | None:
        async with self._session_factory() as database:
            existing = await database.scalar(
                select(FinanceOperationReversalRow).where(
                    FinanceOperationReversalRow.user_id == user_id,
                    FinanceOperationReversalRow.command_id == command_id,
                )
            )
            if existing is None:
                return None
            if existing.command_payload_hash != payload_hash:
                raise OperationCommandConflict
            replacement = None
            if existing.replacement_operation_id is not None:
                replacement = await database.scalar(
                    select(FinanceOperationRow).where(
                        FinanceOperationRow.id == existing.replacement_operation_id,
                        FinanceOperationRow.user_id == user_id,
                    )
                )
                if replacement is None:
                    raise RuntimeError("a recorded replacement disappeared")
        return OperationReversalResult(
            reversal=_to_reversal(existing),
            replacement=None if replacement is None else _to_contract(replacement),
            idempotent_replay=True,
        )

    async def reverse(
        self,
        *,
        user_id: UUID,
        target_operation_id: UUID,
        command_id: UUID,
        replacement: OperationDraft | None,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationReversalResult:
        """Withdraw one operation, and write its replacement in the same
        transaction when there is one (ADR 0023).

        One transaction is the whole point: a correction that reversed first
        and failed to write its replacement would delete money the user only
        wanted to change.
        """

        reversal_id = uuid4()
        replacement_id = uuid4() if replacement is not None else None

        async with self._session_factory() as database:
            async with database.begin():
                active_user = await database.scalar(
                    select(UserRow)
                    .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
                    .with_for_update()
                )
                if active_user is None:
                    raise OperationAccountUnavailable
                # Locking the target serialises two reversals of the same
                # operation, so the check below cannot be overtaken.
                target = await database.scalar(
                    select(FinanceOperationRow)
                    .where(
                        FinanceOperationRow.id == target_operation_id,
                        FinanceOperationRow.user_id == user_id,
                    )
                    .with_for_update()
                )
                if target is None:
                    raise OperationNotFound
                already = await database.scalar(
                    select(FinanceOperationReversalRow).where(
                        FinanceOperationReversalRow.operation_id == target.id
                    )
                )
                if already is not None:
                    # A retry of this very command is a replay; anything else
                    # is a second attempt to withdraw the same money.
                    if already.command_payload_hash != payload_hash:
                        raise OperationAlreadyReversed
                    stored_replacement = None
                    if already.replacement_operation_id is not None:
                        stored_replacement = await database.scalar(
                            select(FinanceOperationRow).where(
                                FinanceOperationRow.id
                                == already.replacement_operation_id,
                                FinanceOperationRow.user_id == user_id,
                            )
                        )
                        if stored_replacement is None:
                            raise RuntimeError("a recorded replacement disappeared")
                    return OperationReversalResult(
                        reversal=_to_reversal(already),
                        replacement=(
                            None
                            if stored_replacement is None
                            else _to_contract(stored_replacement)
                        ),
                        idempotent_replay=True,
                    )

                created_at = _aware_utc(self._clock())
                written: FinanceOperationRow | None = None
                if replacement is not None and replacement_id is not None:
                    written = await self._insert_replacement(
                        database,
                        user_id=user_id,
                        draft=replacement,
                        operation_id=replacement_id,
                        payload_hash=payload_hash,
                        confirmed_at=confirmed_at,
                        created_at=created_at,
                    )

                reversal = FinanceOperationReversalRow(
                    id=reversal_id,
                    operation_id=target.id,
                    user_id=user_id,
                    replacement_operation_id=replacement_id,
                    command_id=command_id,
                    command_payload_hash=payload_hash,
                    confirmed_at=confirmed_at,
                    created_at=created_at,
                )
                database.add(reversal)
                database.add_all(
                    [
                        FinanceOperationAuditRow(
                            id=uuid4(),
                            operation_id=target.id,
                            user_id=user_id,
                            command_id=reversal.command_id,
                            event_type="operation_reversed",
                            actor_type="user",
                            payload_hash=payload_hash,
                            created_at=created_at,
                        ),
                        FinanceOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="finance_operation",
                            aggregate_id=target.id,
                            event_type="finance.operation.reversed.v1",
                            # Identifier-only, and it identifies the operation
                            # that stopped counting — so it carries that
                            # operation's own command id, exactly as its
                            # acceptance did. The command that withdrew it is
                            # recorded in the reversal row and its audit event,
                            # which is where a command belongs (ADR 0011).
                            payload=_outbox_payload(
                                operation_id=target.id,
                                user_id=user_id,
                                command_id=target.command_id,
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
            return OperationReversalResult(
                reversal=_to_reversal(reversal),
                replacement=None if written is None else _to_contract(written),
                idempotent_replay=False,
            )

    async def _insert_replacement(
        self,
        database: object,
        *,
        user_id: UUID,
        draft: OperationDraft,
        operation_id: UUID,
        payload_hash: bytes,
        confirmed_at: datetime,
        created_at: datetime,
    ) -> FinanceOperationRow:
        """Write the correction's replacement under the same account rules.

        A correction must not be able to record something the ordinary write
        path would refuse, so the account, currency, and baseline checks are
        the same ones `commit` applies.
        """

        session = cast(AsyncSession, database)
        account_id = draft.account_id
        if account_id is None:
            raise OperationAccountUnavailable
        account = await session.scalar(
            select(FinanceAccountRow)
            .where(
                FinanceAccountRow.id == account_id,
                FinanceAccountRow.user_id == user_id,
                FinanceAccountRow.status == "active",
            )
            .with_for_update()
        )
        if account is None or account.currency != draft.currency:
            raise OperationAccountUnavailable
        if draft.occurred_on < account.opening_balance_on:
            raise OperationBeforeAccountBaseline

        conflicting = await session.scalar(
            select(FinanceOperationRow).where(
                FinanceOperationRow.user_id == user_id,
                FinanceOperationRow.command_id == draft.command_id,
            )
        )
        if conflicting is not None:
            # The command id already wrote an operation, and this correction
            # is not that command replayed — the replay path above would have
            # returned first.
            raise OperationCommandConflict

        row = FinanceOperationRow(
            id=operation_id,
            user_id=user_id,
            command_id=draft.command_id,
            command_payload_hash=payload_hash,
            schema_version=draft.schema_version,
            operation_type=draft.operation_type,
            amount=draft.amount,
            currency=draft.currency,
            account_id=account_id,
            category=draft.category,
            category_id=draft.category_id,
            merchant=draft.merchant,
            captured_at=draft.captured_at,
            captured_timezone=draft.captured_timezone,
            source_expression=draft.source_expression,
            date_resolver_version=draft.date_resolver_version,
            occurred_on=draft.occurred_on,
            occurred_at=draft.occurred_at,
            source=draft.source,
            status="confirmed",
            confirmed_at=confirmed_at,
            created_at=created_at,
        )
        session.add(row)
        # Flushed before the rows that point at it. Nothing relates these
        # mappers, so the unit of work may otherwise insert the audit row
        # first, and its foreign key then refuses an operation that does not
        # exist yet.
        await session.flush()
        session.add_all(
            [
                FinanceOperationAuditRow(
                    id=uuid4(),
                    operation_id=operation_id,
                    user_id=user_id,
                    command_id=draft.command_id,
                    event_type="operation_accepted",
                    actor_type="user",
                    payload_hash=payload_hash,
                    created_at=created_at,
                ),
                FinanceOutboxEventRow(
                    id=uuid4(),
                    aggregate_type="finance_operation",
                    aggregate_id=operation_id,
                    event_type="finance.operation.accepted.v1",
                    payload=_outbox_payload(
                        operation_id=operation_id,
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
        return row


def _to_contract(row: FinanceOperationRow) -> CommittedOperation:
    return CommittedOperation(
        operation_id=row.id,
        user_id=row.user_id,
        command_id=row.command_id,
        operation_type=row.operation_type,  # type: ignore[arg-type]
        amount=row.amount,
        currency=row.currency,
        account_id=row.account_id,
        category=row.category,
        category_id=row.category_id,
        merchant=row.merchant,
        captured_at=row.captured_at,
        captured_timezone=row.captured_timezone,
        source_expression=row.source_expression,
        date_resolver_version=row.date_resolver_version,  # type: ignore[arg-type]
        occurred_on=row.occurred_on,
        occurred_at=row.occurred_at,
        source=row.source,  # type: ignore[arg-type]
        status="confirmed",
        confirmed_at=row.confirmed_at,
        created_at=row.created_at,
    )


def _to_reversal(row: FinanceOperationReversalRow) -> OperationReversal:
    return OperationReversal(
        reversal_id=row.id,
        operation_id=row.operation_id,
        replacement_operation_id=row.replacement_operation_id,
        command_id=row.command_id,
        confirmed_at=row.confirmed_at,
        created_at=row.created_at,
    )


def _to_history_item(
    row: FinanceOperationRow,
    *,
    category_name: str | None,
) -> OperationHistoryItem:
    return OperationHistoryItem(
        operation_id=row.id,
        operation_type=row.operation_type,  # type: ignore[arg-type]
        amount=row.amount,
        currency=row.currency,
        account_id=row.account_id,
        # The link wins. The stored text stays beside it and is the fallback
        # for operations recorded before the catalogue existed (ADR 0020).
        category=category_name if row.category_id is not None else row.category,
        category_id=row.category_id,
        category_text=row.category,
        merchant=row.merchant,
        occurred_on=row.occurred_on,
        occurred_at=row.occurred_at,
        source=row.source,  # type: ignore[arg-type]
        status=row.status,  # type: ignore[arg-type]
        created_at=row.created_at,
    )


def _encode_cursor(row: FinanceOperationRow) -> str:
    parts = (
        row.occurred_on.isoformat(),
        _aware_utc(row.created_at).isoformat(),
        str(row.id),
    )
    raw = "|".join(parts).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode_cursor(cursor: str) -> tuple[date, datetime, UUID]:
    """Decode a cursor this server issued, or refuse it.

    A cursor only positions a read, so a forged one cannot expose another
    user's rows — the query is still scoped to the caller. It is still parsed
    strictly: a silently ignored cursor would page from the top forever.
    """

    try:
        padding = "=" * (-len(cursor) % 4)
        decoded = base64.urlsafe_b64decode(cursor + padding).decode("utf-8")
        occurred_on, created_at, operation_id = decoded.split("|")
        return (
            date.fromisoformat(occurred_on),
            _aware_utc(datetime.fromisoformat(created_at)),
            UUID(operation_id),
        )
    except (ValueError, binascii.Error, UnicodeDecodeError) as error:
        raise InvalidOperationCursor from error


def _outbox_payload(
    *,
    operation_id: UUID,
    user_id: UUID,
    command_id: UUID,
) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "operationId": str(operation_id),
        "userId": str(user_id),
        "commandId": str(command_id),
    }


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
