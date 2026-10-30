"""Transactional PostgreSQL adapter for forecast-only planned costs."""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, date, datetime
from uuid import UUID, uuid4

from sqlalchemy import Select, func, select
from sqlalchemy.dialects.postgresql import insert

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceOperationRow,
    PlannedCostAuditRow,
    PlannedCostOutboxEventRow,
    PlannedCostRow,
    UserRow,
)
from .planned_cost_contracts import (
    CreatePlannedCostCommand,
    PlannedCostStatus,
    TransitionPlannedCostCommand,
)
from .planned_cost_core import (
    PlannedCostAccountContext,
    PlannedCostAccountUnavailable,
    PlannedCostBeforeAccountBaseline,
    PlannedCostCommandConflict,
    PlannedCostConfirmingOperationMissing,
    PlannedCostInvalidTransition,
    PlannedCostListSnapshot,
    PlannedCostNotFound,
    PlannedCostWriteResult,
    StoredPlannedCost,
)
from .quotas import MAX_OPEN_PLANS, require_room

_AUDIT_EVENT_TYPE: dict[str, str] = {
    "confirmed": "planned_cost_confirmed",
    "skipped": "planned_cost_skipped",
    "cancelled": "planned_cost_cancelled",
}


class PostgresPlannedCostRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> PlannedCostAccountContext | None:
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
        return PlannedCostAccountContext(
            account_id=account.id,
            user_id=account.user_id,
            currency=account.currency,
            opening_balance_on=account.opening_balance_on,
            canonical_timezone=account.opening_timezone,
        )

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        async with self._session_factory() as database:
            existing = await database.execute(
                _plan_with_timezone().where(
                    PlannedCostRow.user_id == user_id,
                    PlannedCostRow.command_id == command_id,
                )
            )
            row = existing.first()
        if row is None:
            return None
        plan, timezone = row.tuple()
        if plan.command_payload_hash != payload_hash:
            raise PlannedCostCommandConflict
        return PlannedCostWriteResult(
            plan=_to_stored(plan, canonical_timezone=timezone),
            idempotent_replay=True,
        )

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostCommand,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult:
        planned_cost_id = uuid4()
        async with self._session_factory() as database:
            async with database.begin():
                active_user = await database.scalar(
                    select(UserRow)
                    .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
                    .with_for_update()
                )
                if active_user is None:
                    raise PlannedCostAccountUnavailable
                await require_room(
                    database,
                    select(func.count())
                    .select_from(PlannedCostRow)
                    .where(
                        PlannedCostRow.user_id == user_id,
                        PlannedCostRow.status == "planned",
                    ),
                    limit=MAX_OPEN_PLANS,
                )
                account = await database.scalar(
                    select(FinanceAccountRow)
                    .where(
                        FinanceAccountRow.id == command.account_id,
                        FinanceAccountRow.user_id == user_id,
                        FinanceAccountRow.status == "active",
                    )
                    .with_for_update()
                )
                if account is None or account.currency != command.currency:
                    raise PlannedCostAccountUnavailable
                # Re-checked under the lock. A baseline can only move earlier
                # (ADR 0016), so this cannot regress today; it is validated
                # explicitly so the rule survives any future relaxation.
                if command.planned_on < account.opening_balance_on:
                    raise PlannedCostBeforeAccountBaseline

                created_at = _aware_utc(self._clock())
                inserted_id = await database.scalar(
                    insert(PlannedCostRow)
                    .values(
                        id=planned_cost_id,
                        user_id=user_id,
                        account_id=command.account_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        schema_version=command.schema_version,
                        amount=command.amount,
                        currency=command.currency,
                        title=command.title,
                        category=command.category,
                        planned_on=command.planned_on,
                        status="planned",
                        confirmed_operation_id=None,
                        confirmed_operation_command_id=None,
                        created_at=created_at,
                        updated_at=created_at,
                    )
                    .on_conflict_do_nothing(index_elements=["user_id", "command_id"])
                    .returning(PlannedCostRow.id)
                )
                if inserted_id is None:
                    existing = await database.scalar(
                        select(PlannedCostRow).where(
                            PlannedCostRow.user_id == user_id,
                            PlannedCostRow.command_id == command.command_id,
                        )
                    )
                    if existing is None:
                        raise RuntimeError("conflicting planned cost disappeared")
                    if existing.command_payload_hash != payload_hash:
                        raise PlannedCostCommandConflict
                    return PlannedCostWriteResult(
                        plan=_to_stored(
                            existing,
                            canonical_timezone=account.opening_timezone,
                        ),
                        idempotent_replay=True,
                    )

                database.add_all(
                    [
                        PlannedCostAuditRow(
                            id=uuid4(),
                            planned_cost_id=planned_cost_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type="planned_cost_created",
                            actor_type="user",
                            payload_hash=payload_hash,
                            previous_status=None,
                            new_status="planned",
                            created_at=created_at,
                        ),
                        PlannedCostOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="planned_cost",
                            aggregate_id=planned_cost_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type="finance.planned_cost.created.v1",
                            payload=_outbox_payload(
                                planned_cost_id=planned_cost_id,
                                user_id=user_id,
                                command_id=command.command_id,
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
                plan = StoredPlannedCost(
                    planned_cost_id=planned_cost_id,
                    user_id=user_id,
                    account_id=command.account_id,
                    command_id=command.command_id,
                    amount=command.amount,
                    currency=command.currency,
                    title=command.title,
                    category=command.category,
                    planned_on=command.planned_on,
                    status="planned",
                    confirmed_operation_id=None,
                    created_at=created_at,
                    updated_at=created_at,
                    canonical_timezone=account.opening_timezone,
                )
            return PlannedCostWriteResult(plan=plan, idempotent_replay=False)

    async def replay_existing_transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(PlannedCostAuditRow).where(
                    PlannedCostAuditRow.planned_cost_id == planned_cost_id,
                    PlannedCostAuditRow.user_id == user_id,
                    PlannedCostAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            # A creation command replayed as a transition, or a transition
            # command reused with different content, are both conflicts.
            if audit.payload_hash != payload_hash:
                raise PlannedCostCommandConflict
            found = await database.execute(
                _plan_with_timezone().where(
                    PlannedCostRow.id == planned_cost_id,
                    PlannedCostRow.user_id == user_id,
                )
            )
            row = found.first()
        if row is None:
            raise PlannedCostNotFound
        plan, timezone = row.tuple()
        return PlannedCostWriteResult(
            plan=_to_stored(plan, canonical_timezone=timezone),
            idempotent_replay=True,
        )

    async def transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command: TransitionPlannedCostCommand,
        payload_hash: bytes,
        target_status: PlannedCostStatus,
    ) -> PlannedCostWriteResult:
        async with self._session_factory() as database:
            async with database.begin():
                plan = await database.scalar(
                    select(PlannedCostRow)
                    .where(
                        PlannedCostRow.id == planned_cost_id,
                        PlannedCostRow.user_id == user_id,
                    )
                    .with_for_update()
                )
                if plan is None:
                    raise PlannedCostNotFound
                if plan.status != "planned":
                    raise PlannedCostInvalidTransition

                operation_id: UUID | None = None
                if target_status == "confirmed":
                    operation_command_id = command.operation_command_id
                    if operation_command_id is None:  # pragma: no cover - contract
                        raise PlannedCostConfirmingOperationMissing
                    operation_id = await database.scalar(
                        select(FinanceOperationRow.id).where(
                            FinanceOperationRow.user_id == user_id,
                            FinanceOperationRow.command_id == operation_command_id,
                        )
                    )
                    if operation_id is None:
                        raise PlannedCostConfirmingOperationMissing

                account_timezone = await database.scalar(
                    select(FinanceAccountRow.opening_timezone).where(
                        FinanceAccountRow.id == plan.account_id,
                        FinanceAccountRow.user_id == user_id,
                    )
                )
                if account_timezone is None:
                    raise PlannedCostAccountUnavailable

                updated_at = _aware_utc(self._clock())
                plan.status = target_status
                plan.confirmed_operation_id = operation_id
                plan.confirmed_operation_command_id = (
                    command.operation_command_id if operation_id is not None else None
                )
                plan.updated_at = updated_at
                database.add_all(
                    [
                        PlannedCostAuditRow(
                            id=uuid4(),
                            planned_cost_id=planned_cost_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type=_AUDIT_EVENT_TYPE[target_status],
                            actor_type="user",
                            payload_hash=payload_hash,
                            previous_status="planned",
                            new_status=target_status,
                            created_at=updated_at,
                        ),
                        PlannedCostOutboxEventRow(
                            id=uuid4(),
                            aggregate_type="planned_cost",
                            aggregate_id=planned_cost_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type="finance.planned_cost.transitioned.v1",
                            payload=_outbox_payload(
                                planned_cost_id=planned_cost_id,
                                user_id=user_id,
                                command_id=command.command_id,
                            ),
                            created_at=updated_at,
                            published_at=None,
                            attempt_count=0,
                            validation_failure_count=0,
                            next_attempt_at=updated_at,
                            last_failed_at=None,
                            failure_code=None,
                            dead_lettered_at=None,
                        ),
                    ]
                )
                stored = _to_stored(plan, canonical_timezone=account_timezone)
            return PlannedCostWriteResult(plan=stored, idempotent_replay=False)

    async def list_plans(
        self,
        *,
        user_id: UUID,
        planned_from: date | None,
        planned_to: date | None,
    ) -> PlannedCostListSnapshot:
        async with self._session_factory() as database:
            canonical_timezone = await database.scalar(
                select(UserRow.canonical_timezone).where(UserRow.id == user_id)
            )
            statement = _plan_with_timezone().where(PlannedCostRow.user_id == user_id)
            if planned_from is not None:
                statement = statement.where(PlannedCostRow.planned_on >= planned_from)
            if planned_to is not None:
                statement = statement.where(PlannedCostRow.planned_on <= planned_to)
            found = await database.execute(
                statement.order_by(PlannedCostRow.planned_on, PlannedCostRow.id)
            )
            rows = found.all()
        return PlannedCostListSnapshot(
            canonical_timezone=canonical_timezone,
            plans=tuple(
                _to_stored(plan, canonical_timezone=timezone)
                for plan, timezone in (row.tuple() for row in rows)
            ),
        )


def _plan_with_timezone() -> Select[tuple[PlannedCostRow, str]]:
    """Select a plan together with the canonical timezone of its account."""

    return select(PlannedCostRow, FinanceAccountRow.opening_timezone).join(
        FinanceAccountRow,
        (FinanceAccountRow.id == PlannedCostRow.account_id)
        & (FinanceAccountRow.user_id == PlannedCostRow.user_id),
    )


def _to_stored(row: PlannedCostRow, *, canonical_timezone: str) -> StoredPlannedCost:
    return StoredPlannedCost(
        planned_cost_id=row.id,
        user_id=row.user_id,
        account_id=row.account_id,
        command_id=row.command_id,
        amount=row.amount,
        currency=row.currency,
        title=row.title,
        category=row.category,
        planned_on=row.planned_on,
        status=row.status,
        confirmed_operation_id=row.confirmed_operation_id,
        created_at=row.created_at,
        updated_at=row.updated_at,
        canonical_timezone=canonical_timezone,
    )


def _outbox_payload(
    *,
    planned_cost_id: UUID,
    user_id: UUID,
    command_id: UUID,
) -> dict[str, object]:
    """Identifier-only invalidation: never an amount, a title, or a category."""

    return {
        "schemaVersion": "1",
        "plannedCostId": str(planned_cost_id),
        "userId": str(user_id),
        "commandId": str(command_id),
    }


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
