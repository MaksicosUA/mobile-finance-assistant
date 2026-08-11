"""Transactional PostgreSQL adapter for savings goals and their ledger."""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import ColumnElement, Select, case, func, literal, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceGoalAuditRow,
    FinanceGoalContributionRow,
    FinanceGoalOutboxEventRow,
    FinanceGoalRow,
    UserRow,
)
from .goal_contracts import (
    CancelGoalCommand,
    CreateGoalCommand,
    RecordGoalContributionCommand,
    apply_contribution,
)
from .goal_core import (
    ContributionWriteResult,
    GoalAccountContext,
    GoalAccountUnavailable,
    GoalCommandConflict,
    GoalLedgerSnapshot,
    GoalListSnapshot,
    GoalNotActive,
    GoalNotFound,
    GoalTargetBeforeAccountBaseline,
    GoalWithdrawalExceedsBalance,
    GoalWriteResult,
    StoredGoal,
    StoredGoalContribution,
)

_ZERO = Decimal(0)


class PostgresGoalRepository:
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
    ) -> GoalAccountContext | None:
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
        return _to_account_context(account)

    async def get_goal_context(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> tuple[StoredGoal, GoalAccountContext] | None:
        async with self._session_factory() as database:
            found = await database.execute(
                select(FinanceGoalRow, FinanceAccountRow, _balance_expression())
                .join(
                    FinanceAccountRow,
                    (FinanceAccountRow.id == FinanceGoalRow.account_id)
                    & (FinanceAccountRow.user_id == FinanceGoalRow.user_id),
                )
                .where(
                    FinanceGoalRow.id == goal_id,
                    FinanceGoalRow.user_id == user_id,
                )
            )
            row = found.first()
        if row is None:
            return None
        goal, account, balance = row.tuple()
        return (
            _to_stored(
                goal,
                canonical_timezone=account.opening_timezone,
                current_amount=balance,
            ),
            _to_account_context(account),
        )

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        async with self._session_factory() as database:
            found = await database.execute(
                _goal_with_context().where(
                    FinanceGoalRow.user_id == user_id,
                    FinanceGoalRow.command_id == command_id,
                )
            )
            row = found.first()
        if row is None:
            return None
        goal, timezone, balance = row.tuple()
        if goal.command_payload_hash != payload_hash:
            raise GoalCommandConflict
        return GoalWriteResult(
            goal=_to_stored(
                goal,
                canonical_timezone=timezone,
                current_amount=balance,
            ),
            idempotent_replay=True,
        )

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreateGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        goal_id = uuid4()
        async with self._session_factory() as database:
            async with database.begin():
                active_user = await database.scalar(
                    select(UserRow)
                    .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
                    .with_for_update()
                )
                if active_user is None:
                    raise GoalAccountUnavailable
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
                    raise GoalAccountUnavailable
                # Re-checked under the lock. A baseline can only move earlier
                # (ADR 0016), so this cannot regress today; it is validated
                # explicitly so the rule survives any future relaxation.
                if command.target_on < account.opening_balance_on:
                    raise GoalTargetBeforeAccountBaseline

                created_at = _aware_utc(self._clock())
                monthly = (
                    command.monthly_contribution
                    if command.monthly_contribution is not None
                    else _ZERO
                )
                inserted_id = await database.scalar(
                    insert(FinanceGoalRow)
                    .values(
                        id=goal_id,
                        user_id=user_id,
                        account_id=command.account_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        schema_version=command.schema_version,
                        title=command.title,
                        target_amount=command.target_amount,
                        monthly_contribution=monthly,
                        currency=command.currency,
                        target_on=command.target_on,
                        status="active",
                        created_at=created_at,
                        updated_at=created_at,
                    )
                    .on_conflict_do_nothing(index_elements=["user_id", "command_id"])
                    .returning(FinanceGoalRow.id)
                )
                if inserted_id is None:
                    existing = await database.scalar(
                        select(FinanceGoalRow).where(
                            FinanceGoalRow.user_id == user_id,
                            FinanceGoalRow.command_id == command.command_id,
                        )
                    )
                    if existing is None:
                        raise RuntimeError("conflicting goal disappeared")
                    if existing.command_payload_hash != payload_hash:
                        raise GoalCommandConflict
                    balance = await self._balance(database, goal_id=existing.id)
                    return GoalWriteResult(
                        goal=_to_stored(
                            existing,
                            canonical_timezone=account.opening_timezone,
                            current_amount=balance,
                        ),
                        idempotent_replay=True,
                    )

                database.add_all(
                    [
                        FinanceGoalAuditRow(
                            id=uuid4(),
                            goal_id=goal_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            contribution_id=None,
                            event_type="goal_created",
                            actor_type="user",
                            payload_hash=payload_hash,
                            previous_status=None,
                            new_status="active",
                            created_at=created_at,
                        ),
                        _outbox_row(
                            goal_id=goal_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type="finance.goal.created.v1",
                            created_at=created_at,
                        ),
                    ]
                )
                goal = StoredGoal(
                    goal_id=goal_id,
                    user_id=user_id,
                    account_id=command.account_id,
                    command_id=command.command_id,
                    title=command.title,
                    target_amount=command.target_amount,
                    monthly_contribution=monthly,
                    current_amount=_ZERO,
                    currency=command.currency,
                    target_on=command.target_on,
                    status="active",
                    created_at=created_at,
                    updated_at=created_at,
                    canonical_timezone=account.opening_timezone,
                )
            return GoalWriteResult(goal=goal, idempotent_replay=False)

    async def replay_existing_goal_command(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(FinanceGoalAuditRow).where(
                    FinanceGoalAuditRow.goal_id == goal_id,
                    FinanceGoalAuditRow.user_id == user_id,
                    FinanceGoalAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            # A creation or contribution command replayed as a cancellation, or
            # a cancellation reused with different content, are both conflicts.
            if audit.payload_hash != payload_hash:
                raise GoalCommandConflict
            row = (
                await database.execute(
                    _goal_with_context().where(
                        FinanceGoalRow.id == goal_id,
                        FinanceGoalRow.user_id == user_id,
                    )
                )
            ).first()
        if row is None:
            raise GoalNotFound
        goal, timezone, balance = row.tuple()
        return GoalWriteResult(
            goal=_to_stored(
                goal,
                canonical_timezone=timezone,
                current_amount=balance,
            ),
            idempotent_replay=True,
        )

    async def cancel(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: CancelGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        async with self._session_factory() as database:
            async with database.begin():
                goal = await self._locked_goal(
                    database,
                    user_id=user_id,
                    goal_id=goal_id,
                )
                if goal.status != "active":
                    raise GoalNotActive

                timezone = await self._account_timezone(
                    database,
                    user_id=user_id,
                    account_id=goal.account_id,
                )
                updated_at = _aware_utc(self._clock())
                goal.status = "cancelled"
                goal.updated_at = updated_at
                database.add_all(
                    [
                        FinanceGoalAuditRow(
                            id=uuid4(),
                            goal_id=goal_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            contribution_id=None,
                            event_type="goal_cancelled",
                            actor_type="user",
                            payload_hash=payload_hash,
                            previous_status="active",
                            new_status="cancelled",
                            created_at=updated_at,
                        ),
                        _outbox_row(
                            goal_id=goal_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type="finance.goal.cancelled.v1",
                            created_at=updated_at,
                        ),
                    ]
                )
                # The ledger is deliberately kept: the money really was set
                # aside, and deleting the evidence would make the audit lie.
                balance = await self._balance(database, goal_id=goal_id)
                stored = _to_stored(
                    goal,
                    canonical_timezone=timezone,
                    current_amount=balance,
                )
            return GoalWriteResult(goal=stored, idempotent_replay=False)

    async def replay_existing_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> ContributionWriteResult | None:
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(FinanceGoalAuditRow).where(
                    FinanceGoalAuditRow.goal_id == goal_id,
                    FinanceGoalAuditRow.user_id == user_id,
                    FinanceGoalAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            if audit.payload_hash != payload_hash:
                raise GoalCommandConflict
            if audit.contribution_id is None:
                # Same command id, same payload, but it was not a contribution.
                # Treating it as one would return a ledger entry that does not
                # exist, so this fails closed as an identity conflict.
                raise GoalCommandConflict
            entry = await database.scalar(
                select(FinanceGoalContributionRow).where(
                    FinanceGoalContributionRow.id == audit.contribution_id,
                    FinanceGoalContributionRow.user_id == user_id,
                )
            )
            row = (
                await database.execute(
                    _goal_with_context().where(
                        FinanceGoalRow.id == goal_id,
                        FinanceGoalRow.user_id == user_id,
                    )
                )
            ).first()
        if entry is None or row is None:
            raise GoalNotFound
        goal, timezone, balance = row.tuple()
        return ContributionWriteResult(
            contribution=_to_stored_contribution(entry),
            goal=_to_stored(
                goal,
                canonical_timezone=timezone,
                current_amount=balance,
            ),
            idempotent_replay=True,
        )

    async def record_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: RecordGoalContributionCommand,
        occurred_on: date,
        payload_hash: bytes,
    ) -> ContributionWriteResult:
        contribution_id = uuid4()
        async with self._session_factory() as database:
            async with database.begin():
                goal = await self._locked_goal(
                    database,
                    user_id=user_id,
                    goal_id=goal_id,
                )
                if goal.status != "active":
                    raise GoalNotActive

                # Read under the goal's row lock, so two concurrent withdrawals
                # cannot both observe a balance that only covers one of them.
                balance = await self._balance(database, goal_id=goal_id)
                if command.direction == "withdrawal" and command.amount > balance:
                    raise GoalWithdrawalExceedsBalance

                timezone = await self._account_timezone(
                    database,
                    user_id=user_id,
                    account_id=goal.account_id,
                )
                created_at = _aware_utc(self._clock())
                inserted_id = await database.scalar(
                    insert(FinanceGoalContributionRow)
                    .values(
                        id=contribution_id,
                        goal_id=goal_id,
                        user_id=user_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        schema_version=command.schema_version,
                        direction=command.direction,
                        amount=command.amount,
                        currency=goal.currency,
                        occurred_on=occurred_on,
                        created_at=created_at,
                    )
                    .on_conflict_do_nothing(index_elements=["user_id", "command_id"])
                    .returning(FinanceGoalContributionRow.id)
                )
                if inserted_id is None:
                    existing = await database.scalar(
                        select(FinanceGoalContributionRow).where(
                            FinanceGoalContributionRow.user_id == user_id,
                            FinanceGoalContributionRow.command_id == command.command_id,
                        )
                    )
                    if existing is None:
                        raise RuntimeError("conflicting contribution disappeared")
                    if (
                        existing.command_payload_hash != payload_hash
                        or existing.goal_id != goal_id
                    ):
                        raise GoalCommandConflict
                    return ContributionWriteResult(
                        contribution=_to_stored_contribution(existing),
                        goal=_to_stored(
                            goal,
                            canonical_timezone=timezone,
                            current_amount=balance,
                        ),
                        idempotent_replay=True,
                    )

                database.add_all(
                    [
                        FinanceGoalAuditRow(
                            id=uuid4(),
                            goal_id=goal_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            contribution_id=contribution_id,
                            event_type="goal_contribution_recorded",
                            actor_type="user",
                            payload_hash=payload_hash,
                            previous_status="active",
                            new_status="active",
                            created_at=created_at,
                        ),
                        _outbox_row(
                            goal_id=goal_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            event_type="finance.goal.contributed.v1",
                            created_at=created_at,
                        ),
                    ]
                )
                entry = StoredGoalContribution(
                    contribution_id=contribution_id,
                    goal_id=goal_id,
                    user_id=user_id,
                    command_id=command.command_id,
                    direction=command.direction,
                    amount=command.amount,
                    currency=goal.currency,
                    occurred_on=occurred_on,
                    created_at=created_at,
                )
                stored = _to_stored(
                    goal,
                    canonical_timezone=timezone,
                    current_amount=apply_contribution(
                        current=balance,
                        direction=command.direction,
                        amount=command.amount,
                    ),
                )
            return ContributionWriteResult(
                contribution=entry,
                goal=stored,
                idempotent_replay=False,
            )

    async def list_goals(self, *, user_id: UUID) -> GoalListSnapshot:
        async with self._session_factory() as database:
            canonical_timezone = await database.scalar(
                select(UserRow.canonical_timezone).where(UserRow.id == user_id)
            )
            found = await database.execute(
                _goal_with_context()
                .where(FinanceGoalRow.user_id == user_id)
                # Primary-goal order (ADR 0019): nearest deadline first, then
                # oldest, then id, so the ordering is total and stable.
                .order_by(
                    FinanceGoalRow.target_on,
                    FinanceGoalRow.created_at,
                    FinanceGoalRow.id,
                )
            )
            rows = found.all()
        return GoalListSnapshot(
            canonical_timezone=canonical_timezone,
            goals=tuple(
                _to_stored(goal, canonical_timezone=timezone, current_amount=balance)
                for goal, timezone, balance in (row.tuple() for row in rows)
            ),
        )

    async def list_contributions(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> GoalLedgerSnapshot:
        async with self._session_factory() as database:
            row = (
                await database.execute(
                    _goal_with_context().where(
                        FinanceGoalRow.id == goal_id,
                        FinanceGoalRow.user_id == user_id,
                    )
                )
            ).first()
            if row is None:
                raise GoalNotFound
            entries = (
                await database.scalars(
                    select(FinanceGoalContributionRow)
                    .where(
                        FinanceGoalContributionRow.goal_id == goal_id,
                        FinanceGoalContributionRow.user_id == user_id,
                    )
                    .order_by(
                        FinanceGoalContributionRow.occurred_on,
                        FinanceGoalContributionRow.created_at,
                        FinanceGoalContributionRow.id,
                    )
                )
            ).all()
        goal, timezone, balance = row.tuple()
        return GoalLedgerSnapshot(
            goal=_to_stored(
                goal,
                canonical_timezone=timezone,
                current_amount=balance,
            ),
            contributions=tuple(_to_stored_contribution(entry) for entry in entries),
        )

    async def _locked_goal(
        self,
        database: AsyncSession,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> FinanceGoalRow:
        goal = await database.scalar(
            select(FinanceGoalRow)
            .where(
                FinanceGoalRow.id == goal_id,
                FinanceGoalRow.user_id == user_id,
            )
            .with_for_update()
        )
        if goal is None:
            raise GoalNotFound
        return goal

    async def _account_timezone(
        self,
        database: AsyncSession,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> str:
        timezone = await database.scalar(
            select(FinanceAccountRow.opening_timezone).where(
                FinanceAccountRow.id == account_id,
                FinanceAccountRow.user_id == user_id,
            )
        )
        if timezone is None:
            raise GoalAccountUnavailable
        return timezone

    async def _balance(self, database: AsyncSession, *, goal_id: UUID) -> Decimal:
        balance = await database.scalar(
            select(
                func.coalesce(
                    func.sum(_signed_amount()),
                    literal(_ZERO),
                )
            ).where(FinanceGoalContributionRow.goal_id == goal_id)
        )
        return balance if balance is not None else _ZERO


def _signed_amount() -> ColumnElement[Decimal]:
    """Fold the ledger direction into an addable amount for SQL aggregation.

    This is the SQL counterpart of `apply_contribution`; a test asserts the two
    agree over the same entries so the pair cannot drift silently.
    """

    return case(
        (
            FinanceGoalContributionRow.direction == "deposit",
            FinanceGoalContributionRow.amount,
        ),
        else_=-FinanceGoalContributionRow.amount,
    )


def _balance_expression() -> ColumnElement[Decimal]:
    return func.coalesce(
        select(func.sum(_signed_amount()))
        .where(FinanceGoalContributionRow.goal_id == FinanceGoalRow.id)
        .correlate(FinanceGoalRow)
        .scalar_subquery(),
        literal(_ZERO),
    )


def _goal_with_context() -> Select[tuple[FinanceGoalRow, str, Decimal]]:
    """Select a goal with its account timezone and its derived ledger balance."""

    return select(
        FinanceGoalRow,
        FinanceAccountRow.opening_timezone,
        _balance_expression(),
    ).join(
        FinanceAccountRow,
        (FinanceAccountRow.id == FinanceGoalRow.account_id)
        & (FinanceAccountRow.user_id == FinanceGoalRow.user_id),
    )


def _to_account_context(account: FinanceAccountRow) -> GoalAccountContext:
    return GoalAccountContext(
        account_id=account.id,
        user_id=account.user_id,
        currency=account.currency,
        opening_balance_on=account.opening_balance_on,
        canonical_timezone=account.opening_timezone,
    )


def _to_stored(
    row: FinanceGoalRow,
    *,
    canonical_timezone: str,
    current_amount: Decimal,
) -> StoredGoal:
    return StoredGoal(
        goal_id=row.id,
        user_id=row.user_id,
        account_id=row.account_id,
        command_id=row.command_id,
        title=row.title,
        target_amount=row.target_amount,
        monthly_contribution=row.monthly_contribution,
        current_amount=current_amount,
        currency=row.currency,
        target_on=row.target_on,
        status=row.status,
        created_at=row.created_at,
        updated_at=row.updated_at,
        canonical_timezone=canonical_timezone,
    )


def _to_stored_contribution(
    row: FinanceGoalContributionRow,
) -> StoredGoalContribution:
    return StoredGoalContribution(
        contribution_id=row.id,
        goal_id=row.goal_id,
        user_id=row.user_id,
        command_id=row.command_id,
        direction=row.direction,
        amount=row.amount,
        currency=row.currency,
        occurred_on=row.occurred_on,
        created_at=row.created_at,
    )


def _outbox_row(
    *,
    goal_id: UUID,
    user_id: UUID,
    command_id: UUID,
    event_type: str,
    created_at: datetime,
) -> FinanceGoalOutboxEventRow:
    return FinanceGoalOutboxEventRow(
        id=uuid4(),
        aggregate_type="finance_goal",
        aggregate_id=goal_id,
        user_id=user_id,
        command_id=command_id,
        event_type=event_type,
        payload=_outbox_payload(
            goal_id=goal_id,
            user_id=user_id,
            command_id=command_id,
        ),
        created_at=created_at,
        published_at=None,
        attempt_count=0,
        validation_failure_count=0,
        next_attempt_at=created_at,
        last_failed_at=None,
        failure_code=None,
        dead_lettered_at=None,
    )


def _outbox_payload(
    *,
    goal_id: UUID,
    user_id: UUID,
    command_id: UUID,
) -> dict[str, object]:
    """Identifier-only invalidation: never an amount and never a title."""

    return {
        "schemaVersion": "1",
        "goalId": str(goal_id),
        "userId": str(user_id),
        "commandId": str(command_id),
    }


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
