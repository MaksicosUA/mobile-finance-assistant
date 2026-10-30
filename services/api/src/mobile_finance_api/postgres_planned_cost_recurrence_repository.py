"""Transactional PostgreSQL adapter for recurring planned costs (ADR 0025).

Materialisation is the interesting part. It writes ordinary ``planned_costs``
rows and relies on a partial unique index — one live instance per rule per date
— rather than on its own bookkeeping, so running it twice, concurrently, or
again after a crash writes nothing the second time.
"""

from __future__ import annotations

import hashlib
from collections.abc import Callable, Sequence
from datetime import UTC, date, datetime
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceCategoryRow,
    PlannedCostAuditRow,
    PlannedCostOutboxEventRow,
    PlannedCostRecurrenceAuditRow,
    PlannedCostRecurrenceRow,
    PlannedCostRow,
    UserRow,
)
from .planned_cost_recurrence import (
    earliest_occurrence,
    horizon_end,
    monthly_occurrences,
)
from .planned_cost_recurrence_contracts import (
    CreatePlannedCostRecurrenceCommand,
    EndPlannedCostRecurrenceCommand,
)
from .planned_cost_recurrence_core import (
    RecurrenceAccountContext,
    RecurrenceAccountUnavailable,
    RecurrenceAlreadyEnded,
    RecurrenceBeforeAccountBaseline,
    RecurrenceCommandConflict,
    RecurrenceEndResult,
    RecurrenceListing,
    RecurrenceNotFound,
    RecurrenceWriteResult,
    StoredRecurrence,
    StoredRecurrenceInstance,
)

#: The index materialisation leans on. Naming it here keeps the ON CONFLICT
#: clause and the migration that created it readable side by side.
_OCCURRENCE_CONFLICT_WHERE = text("recurrence_id IS NOT NULL AND status <> 'cancelled'")


class PostgresPlannedCostRecurrenceRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    # --- reads ----------------------------------------------------------------

    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> RecurrenceAccountContext | None:
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
        return RecurrenceAccountContext(
            account_id=account.id,
            user_id=account.user_id,
            currency=account.currency,
            opening_balance_on=account.opening_balance_on,
            canonical_timezone=account.opening_timezone,
        )

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        async with self._session_factory() as database:
            category = await database.scalar(
                select(FinanceCategoryRow).where(
                    FinanceCategoryRow.id == category_id,
                    FinanceCategoryRow.user_id == user_id,
                    # Archived, not deleted (ADR 0020): a hidden category keeps
                    # its history but must not label anything new.
                    FinanceCategoryRow.archived_at.is_(None),
                )
            )
        return None if category is None else category.direction

    async def list_recurrences(
        self,
        *,
        user_id: UUID,
    ) -> tuple[RecurrenceListing, ...]:
        async with self._session_factory() as database:
            rows = (
                await database.scalars(
                    select(PlannedCostRecurrenceRow)
                    .where(PlannedCostRecurrenceRow.user_id == user_id)
                    .order_by(
                        PlannedCostRecurrenceRow.created_at.asc(),
                        PlannedCostRecurrenceRow.id.asc(),
                    )
                )
            ).all()
            # Outstanding only. A settled instance is no longer an obligation,
            # and the list exists so the interface can offer to skip one.
            instances = (
                await database.execute(
                    select(
                        PlannedCostRow.recurrence_id,
                        PlannedCostRow.id,
                        PlannedCostRow.planned_on,
                    )
                    .where(
                        PlannedCostRow.user_id == user_id,
                        PlannedCostRow.recurrence_id.is_not(None),
                        PlannedCostRow.status == "planned",
                    )
                    .order_by(PlannedCostRow.planned_on.asc())
                )
            ).all()
        owned: dict[UUID, list[StoredRecurrenceInstance]] = {}
        for recurrence_id, planned_cost_id, planned_on in instances:
            owned.setdefault(recurrence_id, []).append(
                StoredRecurrenceInstance(
                    planned_cost_id=planned_cost_id,
                    planned_on=planned_on,
                )
            )
        return tuple(
            RecurrenceListing(
                recurrence=_to_stored(row),
                upcoming=tuple(owned.get(row.id, ())),
            )
            for row in rows
        )

    # --- creation -------------------------------------------------------------

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceWriteResult | None:
        async with self._session_factory() as database:
            rule = await database.scalar(
                select(PlannedCostRecurrenceRow).where(
                    PlannedCostRecurrenceRow.user_id == user_id,
                    PlannedCostRecurrenceRow.command_id == command_id,
                )
            )
            if rule is None:
                return None
            if rule.command_payload_hash != payload_hash:
                raise RecurrenceCommandConflict
            occurrences = await _live_occurrences(database, recurrence_id=rule.id)
        return RecurrenceWriteResult(
            recurrence=_to_stored(rule),
            occurrences=occurrences,
            idempotent_replay=True,
        )

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostRecurrenceCommand,
        payload_hash: bytes,
        through: date,
    ) -> RecurrenceWriteResult:
        recurrence_id = uuid4()
        async with self._session_factory() as database:
            async with database.begin():
                active_user = await database.scalar(
                    select(UserRow)
                    .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
                    .with_for_update()
                )
                if active_user is None:
                    raise RecurrenceAccountUnavailable
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
                    raise RecurrenceAccountUnavailable
                # Re-checked under the lock. A baseline only ever moves earlier
                # (ADR 0016), so this cannot regress; it is stated explicitly so
                # the rule survives any future relaxation.
                if command.starts_on < account.opening_balance_on:
                    raise RecurrenceBeforeAccountBaseline

                created_at = _aware_utc(self._clock())
                inserted_id = await database.scalar(
                    insert(PlannedCostRecurrenceRow)
                    .values(
                        id=recurrence_id,
                        user_id=user_id,
                        account_id=command.account_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        schema_version=command.schema_version,
                        amount=command.amount,
                        currency=command.currency,
                        title=command.title,
                        category=command.category,
                        category_id=command.category_id,
                        frequency=command.frequency,
                        day_of_month=command.day_of_month,
                        starts_on=command.starts_on,
                        ends_on=command.ends_on,
                        status="active",
                        created_at=created_at,
                        updated_at=created_at,
                    )
                    .on_conflict_do_nothing(index_elements=["user_id", "command_id"])
                    .returning(PlannedCostRecurrenceRow.id)
                )
                if inserted_id is None:
                    existing = await database.scalar(
                        select(PlannedCostRecurrenceRow).where(
                            PlannedCostRecurrenceRow.user_id == user_id,
                            PlannedCostRecurrenceRow.command_id == command.command_id,
                        )
                    )
                    if existing is None:  # pragma: no cover - defensive
                        raise RuntimeError("conflicting recurrence disappeared")
                    if existing.command_payload_hash != payload_hash:
                        raise RecurrenceCommandConflict
                    return RecurrenceWriteResult(
                        recurrence=_to_stored(existing),
                        occurrences=await _live_occurrences(
                            database,
                            recurrence_id=existing.id,
                        ),
                        idempotent_replay=True,
                    )

                database.add(
                    PlannedCostRecurrenceAuditRow(
                        id=uuid4(),
                        recurrence_id=recurrence_id,
                        user_id=user_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        event_type="recurrence_created",
                        previous_status=None,
                        new_status="active",
                        created_at=created_at,
                    )
                )
                occurrences = await _materialise(
                    database,
                    recurrence_id=recurrence_id,
                    user_id=user_id,
                    account_id=command.account_id,
                    amount=command.amount,
                    currency=command.currency,
                    title=command.title,
                    category=command.category,
                    category_id=command.category_id,
                    day_of_month=command.day_of_month,
                    starts_on=max(command.starts_on, account.opening_balance_on),
                    ends_on=command.ends_on,
                    through=through,
                    now=created_at,
                )
                recurrence = StoredRecurrence(
                    recurrence_id=recurrence_id,
                    user_id=user_id,
                    account_id=command.account_id,
                    command_id=command.command_id,
                    amount=command.amount,
                    currency=command.currency,
                    title=command.title,
                    category=command.category,
                    category_id=command.category_id,
                    frequency=command.frequency,
                    day_of_month=command.day_of_month,
                    starts_on=command.starts_on,
                    ends_on=command.ends_on,
                    status="active",
                    created_at=created_at,
                    updated_at=created_at,
                )
        return RecurrenceWriteResult(
            recurrence=recurrence,
            occurrences=occurrences,
            idempotent_replay=False,
        )

    # --- ending ---------------------------------------------------------------

    async def replay_existing_end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceEndResult | None:
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(PlannedCostRecurrenceAuditRow).where(
                    PlannedCostRecurrenceAuditRow.recurrence_id == recurrence_id,
                    PlannedCostRecurrenceAuditRow.user_id == user_id,
                    PlannedCostRecurrenceAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            # A creation command replayed as an ending, or an ending command
            # reused with different content, are both conflicts.
            if audit.command_payload_hash != payload_hash:
                raise RecurrenceCommandConflict
            rule = await database.scalar(
                select(PlannedCostRecurrenceRow).where(
                    PlannedCostRecurrenceRow.id == recurrence_id,
                    PlannedCostRecurrenceRow.user_id == user_id,
                )
            )
            if rule is None:  # pragma: no cover - the audit FK forbids this
                raise RecurrenceNotFound
            cancelled = await database.scalar(
                select(text("count(*)"))
                .select_from(PlannedCostRow)
                .where(
                    PlannedCostRow.recurrence_id == recurrence_id,
                    PlannedCostRow.user_id == user_id,
                    PlannedCostRow.status == "cancelled",
                )
            )
        return RecurrenceEndResult(
            recurrence=_to_stored(rule),
            cancelled_occurrences=int(cancelled or 0),
            idempotent_replay=True,
        )

    async def end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command: EndPlannedCostRecurrenceCommand,
        payload_hash: bytes,
    ) -> RecurrenceEndResult:
        async with self._session_factory() as database:
            async with database.begin():
                rule = await database.scalar(
                    select(PlannedCostRecurrenceRow)
                    .where(
                        PlannedCostRecurrenceRow.id == recurrence_id,
                        PlannedCostRecurrenceRow.user_id == user_id,
                    )
                    .with_for_update()
                )
                if rule is None:
                    raise RecurrenceNotFound
                if rule.status != "active":
                    raise RecurrenceAlreadyEnded
                account = await database.scalar(
                    select(FinanceAccountRow).where(
                        FinanceAccountRow.id == rule.account_id,
                        FinanceAccountRow.user_id == user_id,
                    )
                )
                if account is None:  # pragma: no cover - the FK forbids this
                    raise RecurrenceAccountUnavailable

                now = _aware_utc(self._clock())
                today = now.astimezone(ZoneInfo(account.opening_timezone)).date()
                rule.status = "ended"
                rule.updated_at = now
                database.add(
                    PlannedCostRecurrenceAuditRow(
                        id=uuid4(),
                        recurrence_id=recurrence_id,
                        user_id=user_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        event_type="recurrence_ended",
                        previous_status="active",
                        new_status="ended",
                        created_at=now,
                    )
                )
                # Strictly after today. An instance that is already due is an
                # obligation that has arrived: the user settles or skips it
                # deliberately rather than having it vanish with the rule.
                doomed = (
                    await database.scalars(
                        select(PlannedCostRow)
                        .where(
                            PlannedCostRow.recurrence_id == recurrence_id,
                            PlannedCostRow.user_id == user_id,
                            PlannedCostRow.status == "planned",
                            PlannedCostRow.planned_on > today,
                        )
                        .with_for_update()
                        .order_by(PlannedCostRow.planned_on.asc())
                    )
                ).all()
                for plan in doomed:
                    plan.status = "cancelled"
                    plan.updated_at = now
                    database.add_all(
                        _instance_transition_rows(
                            plan_id=plan.id,
                            user_id=user_id,
                            command_id=command.command_id,
                            payload_hash=payload_hash,
                            now=now,
                        )
                    )
                recurrence = _to_stored(rule)
                cancelled_occurrences = len(doomed)
        return RecurrenceEndResult(
            recurrence=recurrence,
            cancelled_occurrences=cancelled_occurrences,
            idempotent_replay=False,
        )

    # --- the projector's periodic job ----------------------------------------

    async def materialise_active_rules(self, *, limit: int = 200) -> int:
        """Extend every active rule up to its horizon. Returns rows written.

        Safe to call at any interval and from a restart: the partial unique
        index refuses anything already there, so a second run does nothing.
        """

        written = 0
        async with self._session_factory() as database:
            async with database.begin():
                pairs = (
                    await database.execute(
                        select(PlannedCostRecurrenceRow, FinanceAccountRow)
                        .join(
                            FinanceAccountRow,
                            (
                                FinanceAccountRow.id
                                == PlannedCostRecurrenceRow.account_id
                            )
                            & (
                                FinanceAccountRow.user_id
                                == PlannedCostRecurrenceRow.user_id
                            ),
                        )
                        .where(
                            PlannedCostRecurrenceRow.status == "active",
                            FinanceAccountRow.status == "active",
                        )
                        .order_by(PlannedCostRecurrenceRow.created_at.asc())
                        .limit(limit)
                    )
                ).all()
                now = _aware_utc(self._clock())
                for rule, account in pairs:
                    # Each account carries its own canonical timezone, so "three
                    # months from today" is asked separately for each rule.
                    today = now.astimezone(ZoneInfo(account.opening_timezone)).date()
                    occurrences = await _materialise(
                        database,
                        recurrence_id=rule.id,
                        user_id=rule.user_id,
                        account_id=rule.account_id,
                        amount=rule.amount,
                        currency=rule.currency,
                        title=rule.title,
                        category=rule.category,
                        category_id=rule.category_id,
                        day_of_month=rule.day_of_month,
                        starts_on=max(rule.starts_on, account.opening_balance_on),
                        ends_on=rule.ends_on,
                        through=horizon_end(today=today),
                        now=now,
                        only_new=True,
                    )
                    written += len(occurrences)
        return written


async def _materialise(
    database: AsyncSession,
    *,
    recurrence_id: UUID,
    user_id: UUID,
    account_id: UUID,
    amount: object,
    currency: str,
    title: str,
    category: str | None,
    category_id: UUID | None,
    day_of_month: int,
    starts_on: date,
    ends_on: date | None,
    through: date,
    now: datetime,
    only_new: bool = False,
) -> tuple[date, ...]:
    """Write the instances a rule implies, skipping any that already exist."""

    occurrences = monthly_occurrences(
        day_of_month=day_of_month,
        starts_on=starts_on,
        ends_on=ends_on,
        through=through,
        earliest=earliest_occurrence(through=through),
    )
    # The unique index ignores cancelled rows, so it would let a date someone
    # cancelled come straight back on the next run.
    cancelled = set(
        await database.scalars(
            select(PlannedCostRow.planned_on).where(
                PlannedCostRow.recurrence_id == recurrence_id,
                PlannedCostRow.status == "cancelled",
            )
        )
    )
    written: list[date] = []
    for occurrence in occurrences:
        if occurrence in cancelled:
            continue
        planned_cost_id = uuid4()
        command_id = uuid4()
        inserted = await database.scalar(
            insert(PlannedCostRow)
            .values(
                id=planned_cost_id,
                user_id=user_id,
                account_id=account_id,
                command_id=command_id,
                # A generated instance has no client command behind it. The hash
                # binds the row to what produced it instead, which is the only
                # honest answer to "what content is this command_id bound to".
                command_payload_hash=_instance_payload_hash(
                    recurrence_id=recurrence_id,
                    occurrence=occurrence,
                ),
                schema_version="1",
                amount=amount,
                currency=currency,
                title=title,
                category=category,
                category_id=category_id,
                recurrence_id=recurrence_id,
                planned_on=occurrence,
                status="planned",
                confirmed_operation_id=None,
                confirmed_operation_command_id=None,
                created_at=now,
                updated_at=now,
            )
            .on_conflict_do_nothing(
                index_elements=["recurrence_id", "planned_on"],
                index_where=_OCCURRENCE_CONFLICT_WHERE,
            )
            .returning(PlannedCostRow.id)
        )
        if inserted is None:
            # Already live for this date: a previous run, a concurrent leader,
            # or an instance the user has already acted on.
            if not only_new:
                written.append(occurrence)
            continue
        database.add_all(
            [
                PlannedCostAuditRow(
                    id=uuid4(),
                    planned_cost_id=planned_cost_id,
                    user_id=user_id,
                    command_id=command_id,
                    event_type="planned_cost_created",
                    actor_type="recurrence",
                    payload_hash=_instance_payload_hash(
                        recurrence_id=recurrence_id,
                        occurrence=occurrence,
                    ),
                    previous_status=None,
                    new_status="planned",
                    created_at=now,
                ),
                PlannedCostOutboxEventRow(
                    id=uuid4(),
                    aggregate_type="planned_cost",
                    aggregate_id=planned_cost_id,
                    user_id=user_id,
                    command_id=command_id,
                    event_type="finance.planned_cost.created.v1",
                    payload=_outbox_payload(
                        planned_cost_id=planned_cost_id,
                        user_id=user_id,
                        command_id=command_id,
                    ),
                    created_at=now,
                    published_at=None,
                    attempt_count=0,
                    validation_failure_count=0,
                    next_attempt_at=now,
                    last_failed_at=None,
                    failure_code=None,
                    dead_lettered_at=None,
                ),
            ]
        )
        written.append(occurrence)
    return tuple(written)


def _instance_transition_rows(
    *,
    plan_id: UUID,
    user_id: UUID,
    command_id: UUID,
    payload_hash: bytes,
    now: datetime,
) -> Sequence[object]:
    """Audit and invalidation for one instance withdrawn with its rule.

    The instance rows reuse the rule's command id: one decision by the user,
    recorded once against every row it moved.
    """

    return [
        PlannedCostAuditRow(
            id=uuid4(),
            planned_cost_id=plan_id,
            user_id=user_id,
            command_id=command_id,
            event_type="planned_cost_cancelled",
            actor_type="user",
            payload_hash=payload_hash,
            previous_status="planned",
            new_status="cancelled",
            created_at=now,
        ),
        PlannedCostOutboxEventRow(
            id=uuid4(),
            aggregate_type="planned_cost",
            aggregate_id=plan_id,
            user_id=user_id,
            command_id=command_id,
            event_type="finance.planned_cost.transitioned.v1",
            payload=_outbox_payload(
                planned_cost_id=plan_id,
                user_id=user_id,
                command_id=command_id,
            ),
            created_at=now,
            published_at=None,
            attempt_count=0,
            validation_failure_count=0,
            next_attempt_at=now,
            last_failed_at=None,
            failure_code=None,
            dead_lettered_at=None,
        ),
    ]


async def _live_occurrences(
    database: AsyncSession,
    *,
    recurrence_id: UUID,
) -> tuple[date, ...]:
    rows = (
        await database.scalars(
            select(PlannedCostRow.planned_on)
            .where(
                PlannedCostRow.recurrence_id == recurrence_id,
                PlannedCostRow.status != "cancelled",
            )
            .order_by(PlannedCostRow.planned_on.asc())
        )
    ).all()
    return tuple(rows)


def _instance_payload_hash(*, recurrence_id: UUID, occurrence: date) -> bytes:
    return hashlib.sha256(f"{recurrence_id}:{occurrence.isoformat()}".encode()).digest()


def _outbox_payload(
    *,
    planned_cost_id: UUID,
    user_id: UUID,
    command_id: UUID,
) -> dict[str, object]:
    """Identifier-only invalidation (ADR 0011): no amount, no title, no date."""

    return {
        "schemaVersion": "1",
        "plannedCostId": str(planned_cost_id),
        "userId": str(user_id),
        "commandId": str(command_id),
    }


def _to_stored(row: PlannedCostRecurrenceRow) -> StoredRecurrence:
    return StoredRecurrence(
        recurrence_id=row.id,
        user_id=row.user_id,
        account_id=row.account_id,
        command_id=row.command_id,
        amount=row.amount,
        currency=row.currency,
        title=row.title,
        category=row.category,
        category_id=row.category_id,
        frequency=row.frequency,
        day_of_month=row.day_of_month,
        starts_on=row.starts_on,
        ends_on=row.ends_on,
        status=row.status,
        created_at=_aware_utc(row.created_at),
        updated_at=_aware_utc(row.updated_at),
    )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
