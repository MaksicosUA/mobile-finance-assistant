"""Transactional PostgreSQL adapter for authoritative finance operations."""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceOperationAuditRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    UserRow,
)
from .finance_core import (
    OperationAccountUnavailable,
    OperationBeforeAccountBaseline,
    OperationCommandConflict,
    OperationWriteResult,
)
from .operation_contracts import CommittedOperation, OperationDraft


class PostgresFinanceOperationRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

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
                        ),
                    ]
                )
            return OperationWriteResult(
                operation=_to_contract(row),
                idempotent_replay=False,
            )


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
