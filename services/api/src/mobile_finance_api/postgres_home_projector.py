"""PostgreSQL outbox consumer for immutable Home projection revisions."""

from __future__ import annotations

import logging
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Literal
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from sqlalchemy import select, union
from sqlalchemy.ext.asyncio import AsyncSession

from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountOutboxEventRow,
    FinanceAccountRow,
    FinanceCategoryOutboxEventRow,
    FinanceCategoryRow,
    FinanceGoalContributionRow,
    FinanceGoalOutboxEventRow,
    FinanceGoalRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    HomeProjectionActionRow,
    HomeProjectionGoalRow,
    HomeProjectionPaymentRow,
    HomeProjectionSnapshotRow,
    HomeProjectionTransactionRow,
    HomeProjectionTrendPointRow,
    HomeProjectionWarningRow,
    PlannedCostOutboxEventRow,
    PlannedCostRow,
    UserRow,
    operation_counts,
)
from .home_projection import (
    HomeProjectionInvariantError,
    ProjectedHomeRevision,
    ProjectionAccount,
    ProjectionGoal,
    ProjectionGoalContribution,
    ProjectionOperation,
    ProjectionPlannedCost,
    build_current_home_revision,
)
from .projector_supervision import (
    EventRetryDecision,
    EventRetryPolicy,
    ProjectorFailureCode,
    event_retry_decision,
)
from .timezones import validated_iana_timezone_key

type _EventKind = Literal["account", "operation", "planned_cost", "goal", "category"]

_LOGGER = logging.getLogger("mobile_finance_api.home_projector")
_PROJECTION_SCHEMA_VERSION = 2


@dataclass(frozen=True, slots=True)
class _OutboxCandidate:
    kind: _EventKind
    event_id: UUID
    user_id: UUID
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ProjectionCycleResult:
    published: int
    inspected: int
    failures_present: bool


class _ProjectionStreamBlocked(Exception):
    """A user's stream has a delayed retry or an unresolved dead letter."""


class _OutboxContractError(Exception):
    """A specific identifier-only outbox event failed strict validation."""

    def __init__(
        self,
        *,
        kind: _EventKind,
        event_id: UUID,
        failure_code: ProjectorFailureCode = "invalid_outbox_contract",
    ) -> None:
        super().__init__("outbox event contract is invalid")
        self.kind = kind
        self.event_id = event_id
        self.failure_code = failure_code


class PostgresHomeProjector:
    """Consume invalidations and transactionally publish complete revisions."""

    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
        retry_policy: EventRetryPolicy | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now
        self._retry_policy = retry_policy or EventRetryPolicy()

    async def consume_next(self) -> bool:
        """Consume one user's pending source events; return false when idle."""

        excluded_user_ids: set[UUID] = set()
        while True:
            candidate = await self._next_candidate(
                excluded_user_ids=excluded_user_ids,
            )
            if candidate is None:
                return False
            try:
                projected = await self._project_user(
                    candidate.user_id,
                    require_pending=True,
                )
            except _ProjectionStreamBlocked:
                excluded_user_ids.add(candidate.user_id)
                continue
            except _OutboxContractError as error:
                await self._record_failed_attempt(error)
                raise HomeProjectionInvariantError(
                    "outbox event contract is invalid"
                ) from None
            if projected:
                return True
            # Another worker acknowledged this candidate after selection.
            # Re-scan before reporting global idle so pending users are not
            # delayed until the next polling cycle.

    async def drain_pending(self, *, max_cycles: int | None = None) -> int:
        """Drain bounded pending work without hiding the first projection error."""

        if max_cycles is not None and max_cycles <= 0:
            raise ValueError("max_cycles must be positive")
        completed = 0
        while max_cycles is None or completed < max_cycles:
            if not await self.consume_next():
                break
            completed += 1
        return completed

    async def drain_available(self, *, max_candidates: int) -> ProjectionCycleResult:
        """Drain ready users while isolating failures for one bounded cycle."""

        if max_candidates <= 0:
            raise ValueError("max_candidates must be positive")
        excluded_user_ids: set[UUID] = set()
        published = 0
        inspected = 0
        failures_present = False
        while inspected < max_candidates:
            candidate = await self._next_candidate(
                excluded_user_ids=excluded_user_ids,
            )
            if candidate is None:
                break
            inspected += 1
            try:
                projected = await self._project_user(
                    candidate.user_id,
                    require_pending=True,
                )
            except _ProjectionStreamBlocked:
                excluded_user_ids.add(candidate.user_id)
                continue
            except _OutboxContractError as error:
                await self._record_failed_attempt(error)
                excluded_user_ids.add(candidate.user_id)
                failures_present = True
                _LOGGER.error(
                    "Home projection stream retry scheduled error_type=%s",
                    type(error).__name__,
                )
                continue
            except Exception as error:
                # Do not attribute a ledger/runtime failure to an arbitrary
                # event. Exclude only this stream for the bounded cycle so
                # other users continue, then let the runtime back off.
                excluded_user_ids.add(candidate.user_id)
                failures_present = True
                _LOGGER.error(
                    "Home projection stream skipped error_type=%s",
                    type(error).__name__,
                )
                continue
            if projected:
                published += 1
        return ProjectionCycleResult(
            published=published,
            inspected=inspected,
            failures_present=failures_present,
        )

    async def reconcile_all(self) -> ProjectionCycleResult:
        """Publish revisions due to a local-day/month boundary without events."""

        async with self._session_factory() as database:
            user_ids = tuple(
                (
                    await database.scalars(
                        select(FinanceAccountRow.user_id)
                        .join(UserRow, UserRow.id == FinanceAccountRow.user_id)
                        .where(
                            FinanceAccountRow.status == "active",
                            FinanceAccountRow.is_default.is_(True),
                            UserRow.disabled_at.is_(None),
                        )
                        .distinct()
                        .order_by(FinanceAccountRow.user_id.asc())
                    )
                ).all()
            )
        published = 0
        failures_present = False
        for user_id in user_ids:
            try:
                if await self._project_user(user_id, require_pending=False):
                    published += 1
            except Exception as error:
                # Isolate malformed ledgers and never log identifiers or
                # financial values from an exception.
                _LOGGER.error(
                    "Home reconciliation skipped one account error_type=%s",
                    type(error).__name__,
                )
                failures_present = True
        return ProjectionCycleResult(
            published=published,
            inspected=len(user_ids),
            failures_present=failures_present,
        )

    async def _next_candidate(
        self,
        *,
        excluded_user_ids: set[UUID],
    ) -> _OutboxCandidate | None:
        now = _aware_utc(self._clock())
        async with self._session_factory() as database:
            blocked_users = union(
                select(FinanceAccountOutboxEventRow.user_id.label("user_id")).where(
                    FinanceAccountOutboxEventRow.published_at.is_(None),
                    (
                        FinanceAccountOutboxEventRow.dead_lettered_at.is_not(None)
                        | (FinanceAccountOutboxEventRow.next_attempt_at > now)
                    ),
                ),
                select(FinanceOperationRow.user_id.label("user_id"))
                .join(
                    FinanceOutboxEventRow,
                    FinanceOutboxEventRow.aggregate_id == FinanceOperationRow.id,
                )
                .where(
                    FinanceOutboxEventRow.published_at.is_(None),
                    (
                        FinanceOutboxEventRow.dead_lettered_at.is_not(None)
                        | (FinanceOutboxEventRow.next_attempt_at > now)
                    ),
                ),
                select(PlannedCostOutboxEventRow.user_id.label("user_id")).where(
                    PlannedCostOutboxEventRow.published_at.is_(None),
                    (
                        PlannedCostOutboxEventRow.dead_lettered_at.is_not(None)
                        | (PlannedCostOutboxEventRow.next_attempt_at > now)
                    ),
                ),
                select(FinanceGoalOutboxEventRow.user_id.label("user_id")).where(
                    FinanceGoalOutboxEventRow.published_at.is_(None),
                    (
                        FinanceGoalOutboxEventRow.dead_lettered_at.is_not(None)
                        | (FinanceGoalOutboxEventRow.next_attempt_at > now)
                    ),
                ),
                select(FinanceCategoryOutboxEventRow.user_id.label("user_id")).where(
                    FinanceCategoryOutboxEventRow.published_at.is_(None),
                    (
                        FinanceCategoryOutboxEventRow.dead_lettered_at.is_not(None)
                        | (FinanceCategoryOutboxEventRow.next_attempt_at > now)
                    ),
                ),
            ).subquery()
            account_query = (
                select(
                    FinanceAccountOutboxEventRow.id,
                    FinanceAccountOutboxEventRow.user_id,
                    FinanceAccountOutboxEventRow.created_at,
                )
                .join(
                    UserRow,
                    UserRow.id == FinanceAccountOutboxEventRow.user_id,
                )
                .where(
                    FinanceAccountOutboxEventRow.published_at.is_(None),
                    FinanceAccountOutboxEventRow.dead_lettered_at.is_(None),
                    FinanceAccountOutboxEventRow.next_attempt_at.is_not(None),
                    FinanceAccountOutboxEventRow.next_attempt_at <= now,
                    UserRow.disabled_at.is_(None),
                    FinanceAccountOutboxEventRow.user_id.not_in(
                        select(blocked_users.c.user_id)
                    ),
                )
                .order_by(
                    FinanceAccountOutboxEventRow.created_at.asc(),
                    FinanceAccountOutboxEventRow.id.asc(),
                )
                .limit(1)
            )
            if excluded_user_ids:
                account_query = account_query.where(
                    FinanceAccountOutboxEventRow.user_id.not_in(excluded_user_ids)
                )
            account_row = (await database.execute(account_query)).one_or_none()
            operation_query = (
                select(
                    FinanceOutboxEventRow.id,
                    FinanceOperationRow.user_id,
                    FinanceOutboxEventRow.created_at,
                )
                .join(
                    FinanceOperationRow,
                    FinanceOperationRow.id == FinanceOutboxEventRow.aggregate_id,
                )
                .join(UserRow, UserRow.id == FinanceOperationRow.user_id)
                .join(
                    FinanceAccountRow,
                    FinanceAccountRow.user_id == FinanceOperationRow.user_id,
                )
                .where(
                    FinanceOutboxEventRow.published_at.is_(None),
                    FinanceOutboxEventRow.dead_lettered_at.is_(None),
                    FinanceOutboxEventRow.next_attempt_at.is_not(None),
                    FinanceOutboxEventRow.next_attempt_at <= now,
                    UserRow.disabled_at.is_(None),
                    FinanceAccountRow.status == "active",
                    FinanceAccountRow.is_default.is_(True),
                    FinanceOperationRow.user_id.not_in(select(blocked_users.c.user_id)),
                )
                .order_by(
                    FinanceOutboxEventRow.created_at.asc(),
                    FinanceOutboxEventRow.id.asc(),
                )
                .limit(1)
            )
            if excluded_user_ids:
                operation_query = operation_query.where(
                    FinanceOperationRow.user_id.not_in(excluded_user_ids)
                )
            operation_row = (await database.execute(operation_query)).one_or_none()
            planned_cost_query = (
                select(
                    PlannedCostOutboxEventRow.id,
                    PlannedCostOutboxEventRow.user_id,
                    PlannedCostOutboxEventRow.created_at,
                )
                .join(UserRow, UserRow.id == PlannedCostOutboxEventRow.user_id)
                .join(
                    FinanceAccountRow,
                    FinanceAccountRow.user_id == PlannedCostOutboxEventRow.user_id,
                )
                .where(
                    PlannedCostOutboxEventRow.published_at.is_(None),
                    PlannedCostOutboxEventRow.dead_lettered_at.is_(None),
                    PlannedCostOutboxEventRow.next_attempt_at.is_not(None),
                    PlannedCostOutboxEventRow.next_attempt_at <= now,
                    UserRow.disabled_at.is_(None),
                    FinanceAccountRow.status == "active",
                    FinanceAccountRow.is_default.is_(True),
                    PlannedCostOutboxEventRow.user_id.not_in(
                        select(blocked_users.c.user_id)
                    ),
                )
                .order_by(
                    PlannedCostOutboxEventRow.created_at.asc(),
                    PlannedCostOutboxEventRow.id.asc(),
                )
                .limit(1)
            )
            if excluded_user_ids:
                planned_cost_query = planned_cost_query.where(
                    PlannedCostOutboxEventRow.user_id.not_in(excluded_user_ids)
                )
            planned_cost_row = (
                await database.execute(planned_cost_query)
            ).one_or_none()
            goal_query = (
                select(
                    FinanceGoalOutboxEventRow.id,
                    FinanceGoalOutboxEventRow.user_id,
                    FinanceGoalOutboxEventRow.created_at,
                )
                .join(UserRow, UserRow.id == FinanceGoalOutboxEventRow.user_id)
                .join(
                    FinanceAccountRow,
                    FinanceAccountRow.user_id == FinanceGoalOutboxEventRow.user_id,
                )
                .where(
                    FinanceGoalOutboxEventRow.published_at.is_(None),
                    FinanceGoalOutboxEventRow.dead_lettered_at.is_(None),
                    FinanceGoalOutboxEventRow.next_attempt_at.is_not(None),
                    FinanceGoalOutboxEventRow.next_attempt_at <= now,
                    UserRow.disabled_at.is_(None),
                    FinanceAccountRow.status == "active",
                    FinanceAccountRow.is_default.is_(True),
                    FinanceGoalOutboxEventRow.user_id.not_in(
                        select(blocked_users.c.user_id)
                    ),
                )
                .order_by(
                    FinanceGoalOutboxEventRow.created_at.asc(),
                    FinanceGoalOutboxEventRow.id.asc(),
                )
                .limit(1)
            )
            if excluded_user_ids:
                goal_query = goal_query.where(
                    FinanceGoalOutboxEventRow.user_id.not_in(excluded_user_ids)
                )
            goal_row = (await database.execute(goal_query)).one_or_none()
            category_query = (
                select(
                    FinanceCategoryOutboxEventRow.id,
                    FinanceCategoryOutboxEventRow.user_id,
                    FinanceCategoryOutboxEventRow.created_at,
                )
                .join(UserRow, UserRow.id == FinanceCategoryOutboxEventRow.user_id)
                .join(
                    FinanceAccountRow,
                    FinanceAccountRow.user_id == FinanceCategoryOutboxEventRow.user_id,
                )
                .where(
                    FinanceCategoryOutboxEventRow.published_at.is_(None),
                    FinanceCategoryOutboxEventRow.dead_lettered_at.is_(None),
                    FinanceCategoryOutboxEventRow.next_attempt_at.is_not(None),
                    FinanceCategoryOutboxEventRow.next_attempt_at <= now,
                    UserRow.disabled_at.is_(None),
                    FinanceAccountRow.status == "active",
                    FinanceAccountRow.is_default.is_(True),
                    FinanceCategoryOutboxEventRow.user_id.not_in(
                        select(blocked_users.c.user_id)
                    ),
                )
                .order_by(
                    FinanceCategoryOutboxEventRow.created_at.asc(),
                    FinanceCategoryOutboxEventRow.id.asc(),
                )
                .limit(1)
            )
            if excluded_user_ids:
                category_query = category_query.where(
                    FinanceCategoryOutboxEventRow.user_id.not_in(excluded_user_ids)
                )
            category_row = (await database.execute(category_query)).one_or_none()

        candidates = tuple(
            candidate
            for candidate in (
                None
                if account_row is None
                else _OutboxCandidate(
                    kind="account",
                    event_id=account_row.id,
                    user_id=account_row.user_id,
                    created_at=_aware_utc(account_row.created_at),
                ),
                None
                if operation_row is None
                else _OutboxCandidate(
                    kind="operation",
                    event_id=operation_row.id,
                    user_id=operation_row.user_id,
                    created_at=_aware_utc(operation_row.created_at),
                ),
                None
                if planned_cost_row is None
                else _OutboxCandidate(
                    kind="planned_cost",
                    event_id=planned_cost_row.id,
                    user_id=planned_cost_row.user_id,
                    created_at=_aware_utc(planned_cost_row.created_at),
                ),
                None
                if goal_row is None
                else _OutboxCandidate(
                    kind="goal",
                    event_id=goal_row.id,
                    user_id=goal_row.user_id,
                    created_at=_aware_utc(goal_row.created_at),
                ),
                None
                if category_row is None
                else _OutboxCandidate(
                    kind="category",
                    event_id=category_row.id,
                    user_id=category_row.user_id,
                    created_at=_aware_utc(category_row.created_at),
                ),
            )
            if candidate is not None
        )
        if not candidates:
            return None
        return min(
            candidates,
            key=lambda item: (
                item.created_at,
                item.event_id.int,
            ),
        )

    async def _project_user(
        self,
        user_id: UUID,
        *,
        require_pending: bool,
    ) -> bool:
        async with self._session_factory() as database, database.begin():
            user = await database.scalar(
                select(UserRow)
                .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
                .with_for_update()
            )
            if user is None:
                raise HomeProjectionInvariantError("projection user is unavailable")

            accounts = tuple(
                (
                    await database.scalars(
                        select(FinanceAccountRow)
                        .where(FinanceAccountRow.user_id == user_id)
                        .order_by(
                            FinanceAccountRow.created_at.asc(),
                            FinanceAccountRow.id.asc(),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            if len(accounts) != 1:
                raise HomeProjectionInvariantError(
                    "projection requires exactly one account"
                )
            account = accounts[0]

            operations = tuple(
                (
                    await database.scalars(
                        select(FinanceOperationRow)
                        # Reversed operations are excluded from the rebuild,
                        # never from the event resolution above: an
                        # invalidation must still find its user, or the very
                        # correction that withdrew the money would never be
                        # projected (ADR 0023).
                        .where(
                            FinanceOperationRow.user_id == user_id, operation_counts()
                        )
                        .order_by(
                            FinanceOperationRow.created_at.asc(),
                            FinanceOperationRow.id.asc(),
                        )
                    )
                ).all()
            )
            account_events = tuple(
                (
                    await database.scalars(
                        select(FinanceAccountOutboxEventRow)
                        .where(
                            FinanceAccountOutboxEventRow.user_id == user_id,
                            FinanceAccountOutboxEventRow.published_at.is_(None),
                        )
                        .order_by(
                            FinanceAccountOutboxEventRow.created_at.asc(),
                            FinanceAccountOutboxEventRow.id.asc(),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            operation_events = tuple(
                (
                    await database.scalars(
                        select(FinanceOutboxEventRow)
                        .join(
                            FinanceOperationRow,
                            FinanceOperationRow.id
                            == FinanceOutboxEventRow.aggregate_id,
                        )
                        .where(
                            FinanceOperationRow.user_id == user_id,
                            FinanceOutboxEventRow.published_at.is_(None),
                        )
                        .order_by(
                            FinanceOutboxEventRow.created_at.asc(),
                            FinanceOutboxEventRow.id.asc(),
                        )
                        .with_for_update(of=FinanceOutboxEventRow)
                    )
                ).all()
            )
            planned_costs = tuple(
                (
                    await database.scalars(
                        select(PlannedCostRow)
                        .where(PlannedCostRow.user_id == user_id)
                        .order_by(
                            PlannedCostRow.created_at.asc(),
                            PlannedCostRow.id.asc(),
                        )
                    )
                ).all()
            )
            planned_cost_events = tuple(
                (
                    await database.scalars(
                        select(PlannedCostOutboxEventRow)
                        .where(
                            PlannedCostOutboxEventRow.user_id == user_id,
                            PlannedCostOutboxEventRow.published_at.is_(None),
                        )
                        .order_by(
                            PlannedCostOutboxEventRow.created_at.asc(),
                            PlannedCostOutboxEventRow.id.asc(),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            goals = tuple(
                (
                    await database.scalars(
                        select(FinanceGoalRow)
                        .where(FinanceGoalRow.user_id == user_id)
                        .order_by(
                            FinanceGoalRow.created_at.asc(),
                            FinanceGoalRow.id.asc(),
                        )
                    )
                ).all()
            )
            goal_contributions = tuple(
                (
                    await database.scalars(
                        select(FinanceGoalContributionRow)
                        .where(FinanceGoalContributionRow.user_id == user_id)
                        .order_by(
                            FinanceGoalContributionRow.created_at.asc(),
                            FinanceGoalContributionRow.id.asc(),
                        )
                    )
                ).all()
            )
            goal_events = tuple(
                (
                    await database.scalars(
                        select(FinanceGoalOutboxEventRow)
                        .where(
                            FinanceGoalOutboxEventRow.user_id == user_id,
                            FinanceGoalOutboxEventRow.published_at.is_(None),
                        )
                        .order_by(
                            FinanceGoalOutboxEventRow.created_at.asc(),
                            FinanceGoalOutboxEventRow.id.asc(),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            # Archived rows included: an operation keeps pointing at the
            # category it was recorded against, and hiding it must not blank
            # the label on a transaction that already happened.
            categories = tuple(
                (
                    await database.scalars(
                        select(FinanceCategoryRow).where(
                            FinanceCategoryRow.user_id == user_id
                        )
                    )
                ).all()
            )
            category_events = tuple(
                (
                    await database.scalars(
                        select(FinanceCategoryOutboxEventRow)
                        .where(
                            FinanceCategoryOutboxEventRow.user_id == user_id,
                            FinanceCategoryOutboxEventRow.published_at.is_(None),
                        )
                        .order_by(
                            FinanceCategoryOutboxEventRow.created_at.asc(),
                            FinanceCategoryOutboxEventRow.id.asc(),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            eligibility_at = _aware_utc(self._clock())
            if _stream_is_blocked(
                account_events=account_events,
                operation_events=operation_events,
                planned_cost_events=planned_cost_events,
                goal_events=goal_events,
                category_events=category_events,
                eligibility_at=eligibility_at,
            ):
                raise _ProjectionStreamBlocked
            pending_events = bool(
                account_events
                or operation_events
                or planned_cost_events
                or goal_events
                or category_events
            )
            if require_pending and not pending_events:
                return False
            if not require_pending and pending_events:
                # Event validation/acknowledgement belongs to consume_next.
                # A poison event must not make the calendar reconciliation
                # publish a revision or block unrelated users.
                return False

            _validate_profile(user=user, account=account)
            # Read separately from the operations above, and deliberately
            # unfiltered: an event about a withdrawn operation still has to
            # validate, or the very correction that withdrew it could never be
            # projected (ADR 0023). The rebuild reads what counts; this reads
            # what the events are about.
            operations_by_id = await _operations_named_by(
                database,
                user_id=user_id,
                events=operation_events,
            )
            _validate_account_events(account_events, account=account)
            _validate_operation_events(
                operation_events,
                operations_by_id=operations_by_id,
            )
            _validate_planned_cost_events(
                planned_cost_events,
                planned_costs_by_id={plan.id: plan for plan in planned_costs},
            )
            _validate_goal_events(
                goal_events,
                goals_by_id={goal.id: goal for goal in goals},
                contributions_by_command={
                    (entry.user_id, entry.command_id): entry
                    for entry in goal_contributions
                },
            )
            _validate_category_events(
                category_events,
                categories_by_id={category.id: category for category in categories},
            )

            generated_at = _aware_utc(self._clock())
            latest_watermark = await database.scalar(
                select(HomeProjectionSnapshotRow)
                .where(
                    HomeProjectionSnapshotRow.user_id == user_id,
                    HomeProjectionSnapshotRow.timezone_name == account.opening_timezone,
                )
                .order_by(
                    HomeProjectionSnapshotRow.data_as_of.desc(),
                    HomeProjectionSnapshotRow.revision.desc(),
                )
                .limit(1)
            )
            if latest_watermark is not None and generated_at < _aware_utc(
                latest_watermark.data_as_of
            ):
                raise HomeProjectionInvariantError(
                    "projection watermark cannot move backwards"
                )
            if (
                latest_watermark is not None
                and latest_watermark.projection_schema_version
                > _PROJECTION_SCHEMA_VERSION
            ):
                raise HomeProjectionInvariantError(
                    "newer Home projection schema is already authoritative"
                )
            # ADR 0020: a report reads the link, never the stored text. The
            # text stays on the operation as evidence of what the user wrote,
            # and is the fallback for anything recorded before the catalogue.
            category_names = {category.id: category.name for category in categories}
            projection = build_current_home_revision(
                account=_account_fact(account),
                operations=tuple(
                    _operation_fact(row, category_names=category_names)
                    for row in operations
                ),
                generated_at=generated_at,
                planned_costs=tuple(_planned_cost_fact(row) for row in planned_costs),
                goals=tuple(_goal_fact(row) for row in goals),
                goal_contributions=tuple(
                    _goal_contribution_fact(row) for row in goal_contributions
                ),
            )
            latest = await database.scalar(
                select(HomeProjectionSnapshotRow)
                .where(
                    HomeProjectionSnapshotRow.user_id == user_id,
                    HomeProjectionSnapshotRow.timezone_name == projection.timezone_name,
                    HomeProjectionSnapshotRow.period_start == projection.period_start,
                )
                .order_by(HomeProjectionSnapshotRow.revision.desc())
                .limit(1)
            )
            if (
                latest is not None
                and latest.projection_schema_version > _PROJECTION_SCHEMA_VERSION
            ):
                raise HomeProjectionInvariantError(
                    "newer Home projection schema is already authoritative"
                )
            has_pending = pending_events
            if not has_pending and not _reconciliation_due(
                latest=latest,
                projection=projection,
            ):
                return False

            snapshot_id = uuid4()
            revision = 1 if latest is None else latest.revision + 1
            database.add(
                HomeProjectionSnapshotRow(
                    id=snapshot_id,
                    user_id=user_id,
                    timezone_name=projection.timezone_name,
                    period_start=projection.period_start,
                    period_end=projection.period_end,
                    revision=revision,
                    projection_schema_version=_PROJECTION_SCHEMA_VERSION,
                    generated_at=projection.generated_at,
                    data_as_of=projection.data_as_of,
                    base_currency=projection.base_currency,
                    balance_amount=projection.balance_amount,
                    balance_delta_amount=projection.balance_delta_amount,
                    balance_delta_percent=projection.balance_delta_percent,
                    month_income=projection.month_income,
                    month_expense=projection.month_expense,
                    month_net_flow=projection.month_net_flow,
                    trend_metric=projection.trend_metric,
                    trend_period=projection.trend_period,
                    trend_total=projection.trend_total,
                )
            )
            await database.flush()
            database.add_all(_projection_children(snapshot_id, projection))

            for account_event in account_events:
                account_event.published_at = projection.generated_at
                account_event.attempt_count = min(
                    account_event.attempt_count + 1,
                    32767,
                )
                account_event.next_attempt_at = None
                account_event.last_failed_at = None
                account_event.failure_code = None
                account_event.dead_lettered_at = None
            for operation_event in operation_events:
                operation_event.published_at = projection.generated_at
                operation_event.attempt_count = min(
                    operation_event.attempt_count + 1,
                    32767,
                )
                operation_event.next_attempt_at = None
                operation_event.last_failed_at = None
                operation_event.failure_code = None
                operation_event.dead_lettered_at = None
            for planned_cost_event in planned_cost_events:
                planned_cost_event.published_at = projection.generated_at
                planned_cost_event.attempt_count = min(
                    planned_cost_event.attempt_count + 1,
                    32767,
                )
                planned_cost_event.next_attempt_at = None
                planned_cost_event.last_failed_at = None
                planned_cost_event.failure_code = None
                planned_cost_event.dead_lettered_at = None
            for goal_event in goal_events:
                goal_event.published_at = projection.generated_at
                goal_event.attempt_count = min(goal_event.attempt_count + 1, 32767)
                goal_event.next_attempt_at = None
                goal_event.last_failed_at = None
                goal_event.failure_code = None
                goal_event.dead_lettered_at = None
            for category_event in category_events:
                category_event.published_at = projection.generated_at
                category_event.attempt_count = min(
                    category_event.attempt_count + 1,
                    32767,
                )
                category_event.next_attempt_at = None
                category_event.last_failed_at = None
                category_event.failure_code = None
                category_event.dead_lettered_at = None
        return True

    async def _record_failed_attempt(self, error: _OutboxContractError) -> None:
        failed_at = _aware_utc(self._clock())
        async with self._session_factory() as database, database.begin():
            if error.kind == "account":
                account_event = await database.scalar(
                    select(FinanceAccountOutboxEventRow)
                    .where(
                        FinanceAccountOutboxEventRow.id == error.event_id,
                        FinanceAccountOutboxEventRow.published_at.is_(None),
                        FinanceAccountOutboxEventRow.dead_lettered_at.is_(None),
                    )
                    .with_for_update()
                )
                if account_event is not None:
                    decision = event_retry_decision(
                        previous_validation_failure_count=(
                            account_event.validation_failure_count
                        ),
                        failed_at=failed_at,
                        failure_code=error.failure_code,
                        policy=self._retry_policy,
                    )
                    _apply_retry_decision(account_event, decision=decision)
                return
            if error.kind == "goal":
                goal_event = await database.scalar(
                    select(FinanceGoalOutboxEventRow)
                    .where(
                        FinanceGoalOutboxEventRow.id == error.event_id,
                        FinanceGoalOutboxEventRow.published_at.is_(None),
                        FinanceGoalOutboxEventRow.dead_lettered_at.is_(None),
                    )
                    .with_for_update()
                )
                if goal_event is not None:
                    decision = event_retry_decision(
                        previous_validation_failure_count=(
                            goal_event.validation_failure_count
                        ),
                        failed_at=failed_at,
                        failure_code=error.failure_code,
                        policy=self._retry_policy,
                    )
                    _apply_retry_decision(goal_event, decision=decision)
                return
            if error.kind == "category":
                category_event = await database.scalar(
                    select(FinanceCategoryOutboxEventRow)
                    .where(
                        FinanceCategoryOutboxEventRow.id == error.event_id,
                        FinanceCategoryOutboxEventRow.published_at.is_(None),
                        FinanceCategoryOutboxEventRow.dead_lettered_at.is_(None),
                    )
                    .with_for_update()
                )
                if category_event is not None:
                    decision = event_retry_decision(
                        previous_validation_failure_count=(
                            category_event.validation_failure_count
                        ),
                        failed_at=failed_at,
                        failure_code=error.failure_code,
                        policy=self._retry_policy,
                    )
                    _apply_retry_decision(category_event, decision=decision)
                return
            if error.kind == "planned_cost":
                planned_cost_event = await database.scalar(
                    select(PlannedCostOutboxEventRow)
                    .where(
                        PlannedCostOutboxEventRow.id == error.event_id,
                        PlannedCostOutboxEventRow.published_at.is_(None),
                        PlannedCostOutboxEventRow.dead_lettered_at.is_(None),
                    )
                    .with_for_update()
                )
                if planned_cost_event is not None:
                    decision = event_retry_decision(
                        previous_validation_failure_count=(
                            planned_cost_event.validation_failure_count
                        ),
                        failed_at=failed_at,
                        failure_code=error.failure_code,
                        policy=self._retry_policy,
                    )
                    _apply_retry_decision(planned_cost_event, decision=decision)
                return
            operation_event = await database.scalar(
                select(FinanceOutboxEventRow)
                .where(
                    FinanceOutboxEventRow.id == error.event_id,
                    FinanceOutboxEventRow.published_at.is_(None),
                    FinanceOutboxEventRow.dead_lettered_at.is_(None),
                )
                .with_for_update()
            )
            if operation_event is not None:
                decision = event_retry_decision(
                    previous_validation_failure_count=(
                        operation_event.validation_failure_count
                    ),
                    failed_at=failed_at,
                    failure_code=error.failure_code,
                    policy=self._retry_policy,
                )
                _apply_retry_decision(operation_event, decision=decision)


def _validate_profile(*, user: UserRow, account: FinanceAccountRow) -> None:
    try:
        canonical_timezone = (
            None
            if user.canonical_timezone is None
            else validated_iana_timezone_key(user.canonical_timezone)
        )
        opening_timezone = validated_iana_timezone_key(account.opening_timezone)
    except ValueError as error:
        raise HomeProjectionInvariantError("projection timezone is invalid") from error
    if (
        user.timezone_revision != 1
        or canonical_timezone is None
        or canonical_timezone != opening_timezone
        or user.base_currency != account.currency
        or account.user_id != user.id
    ):
        raise HomeProjectionInvariantError(
            "profile and account projection metadata are inconsistent"
        )


def _validate_account_events(
    events: Sequence[FinanceAccountOutboxEventRow],
    *,
    account: FinanceAccountRow,
) -> None:
    expected_payload = {
        "schemaVersion": "1",
        "accountId": str(account.id),
        "userId": str(account.user_id),
        "commandId": str(account.command_id),
    }
    for event in events:
        if (
            event.aggregate_type != "finance_account"
            or event.aggregate_id != account.id
            or event.user_id != account.user_id
        ):
            raise _OutboxContractError(kind="account", event_id=event.id)
        if event.event_type == "finance.account.opened.v1":
            # The opening event is bound to the account's own opening command.
            if (
                event.command_id != account.command_id
                or event.payload != expected_payload
            ):
                raise _OutboxContractError(kind="account", event_id=event.id)
        elif event.event_type in {
            "finance.account.baseline_corrected.v1",
            "finance.account.timezone_corrected.v1",
        }:
            # A correction carries its own command identity (ADR 0016, ADR
            # 0028), so the payload is checked against that instead of the
            # opening command.
            if event.payload != {
                "schemaVersion": "1",
                "accountId": str(account.id),
                "userId": str(account.user_id),
                "commandId": str(event.command_id),
            }:
                raise _OutboxContractError(kind="account", event_id=event.id)
        else:
            raise _OutboxContractError(kind="account", event_id=event.id)


async def _operations_named_by(
    database: AsyncSession,
    *,
    user_id: UUID,
    events: Sequence[FinanceOutboxEventRow],
) -> dict[UUID, FinanceOperationRow]:
    aggregate_ids = {event.aggregate_id for event in events}
    if not aggregate_ids:
        return {}
    rows = (
        await database.scalars(
            select(FinanceOperationRow).where(
                FinanceOperationRow.user_id == user_id,
                FinanceOperationRow.id.in_(aggregate_ids),
            )
        )
    ).all()
    return {row.id: row for row in rows}


def _validate_operation_events(
    events: Sequence[FinanceOutboxEventRow],
    *,
    operations_by_id: dict[UUID, FinanceOperationRow],
) -> None:
    for event in events:
        operation = operations_by_id.get(event.aggregate_id)
        if operation is None:
            raise _OutboxContractError(kind="operation", event_id=event.id)
        expected_payload = {
            "schemaVersion": "1",
            "operationId": str(operation.id),
            "userId": str(operation.user_id),
            "commandId": str(operation.command_id),
        }
        if (
            event.aggregate_type != "finance_operation"
            or event.event_type
            not in {
                "finance.operation.accepted.v1",
                # An operation withdrawn from the ledger invalidates exactly
                # the same projection its acceptance did (ADR 0023).
                "finance.operation.reversed.v1",
            }
            or event.payload != expected_payload
        ):
            raise _OutboxContractError(kind="operation", event_id=event.id)


def _validate_planned_cost_events(
    events: Sequence[PlannedCostOutboxEventRow],
    *,
    planned_costs_by_id: dict[UUID, PlannedCostRow],
) -> None:
    for event in events:
        plan = planned_costs_by_id.get(event.aggregate_id)
        if plan is None or plan.user_id != event.user_id:
            raise _OutboxContractError(kind="planned_cost", event_id=event.id)
        if event.aggregate_type != "planned_cost" or event.event_type not in {
            "finance.planned_cost.created.v1",
            "finance.planned_cost.transitioned.v1",
        }:
            raise _OutboxContractError(kind="planned_cost", event_id=event.id)
        # Identifier-only, and bound to the command that produced the event:
        # creation carries the plan's own command, a transition carries its own.
        if event.payload != {
            "schemaVersion": "1",
            "plannedCostId": str(plan.id),
            "userId": str(plan.user_id),
            "commandId": str(event.command_id),
        }:
            raise _OutboxContractError(kind="planned_cost", event_id=event.id)
        if (
            event.event_type == "finance.planned_cost.created.v1"
            and event.command_id != plan.command_id
        ):
            raise _OutboxContractError(kind="planned_cost", event_id=event.id)


def _validate_goal_events(
    events: Sequence[FinanceGoalOutboxEventRow],
    *,
    goals_by_id: dict[UUID, FinanceGoalRow],
    contributions_by_command: dict[tuple[UUID, UUID], FinanceGoalContributionRow],
) -> None:
    for event in events:
        goal = goals_by_id.get(event.aggregate_id)
        if goal is None or goal.user_id != event.user_id:
            raise _OutboxContractError(kind="goal", event_id=event.id)
        if event.aggregate_type != "finance_goal" or event.event_type not in {
            "finance.goal.created.v1",
            "finance.goal.cancelled.v1",
            "finance.goal.contributed.v1",
        }:
            raise _OutboxContractError(kind="goal", event_id=event.id)
        # Identifier-only, and bound to the command that produced the event.
        if event.payload != {
            "schemaVersion": "1",
            "goalId": str(goal.id),
            "userId": str(goal.user_id),
            "commandId": str(event.command_id),
        }:
            raise _OutboxContractError(kind="goal", event_id=event.id)
        if (
            event.event_type == "finance.goal.created.v1"
            and event.command_id != goal.command_id
        ):
            raise _OutboxContractError(kind="goal", event_id=event.id)
        # A contribution event must have its ledger entry, or the projection
        # would publish a balance that no row explains.
        if event.event_type == "finance.goal.contributed.v1":
            entry = contributions_by_command.get((event.user_id, event.command_id))
            if entry is None or entry.goal_id != goal.id:
                raise _OutboxContractError(kind="goal", event_id=event.id)


def _validate_category_events(
    events: Sequence[FinanceCategoryOutboxEventRow],
    *,
    categories_by_id: dict[UUID, FinanceCategoryRow],
) -> None:
    for event in events:
        category = categories_by_id.get(event.aggregate_id)
        if category is None or category.user_id != event.user_id:
            raise _OutboxContractError(kind="category", event_id=event.id)
        if (
            event.aggregate_type != "finance_category"
            or event.event_type != "finance.category.renamed.v1"
        ):
            raise _OutboxContractError(kind="category", event_id=event.id)
        # Identifier-only. The new name is deliberately absent: the projector
        # reads it from the category row, so no event can replay a stale label.
        if event.payload != {
            "schemaVersion": "1",
            "categoryId": str(category.id),
            "userId": str(category.user_id),
            "commandId": str(event.command_id),
        }:
            raise _OutboxContractError(kind="category", event_id=event.id)


def _stream_is_blocked(
    *,
    account_events: Sequence[FinanceAccountOutboxEventRow],
    operation_events: Sequence[FinanceOutboxEventRow],
    planned_cost_events: Sequence[PlannedCostOutboxEventRow],
    goal_events: Sequence[FinanceGoalOutboxEventRow],
    category_events: Sequence[FinanceCategoryOutboxEventRow],
    eligibility_at: datetime,
) -> bool:
    return (
        any(
            _event_is_blocked(event, eligibility_at=eligibility_at)
            for event in account_events
        )
        or any(
            _event_is_blocked(event, eligibility_at=eligibility_at)
            for event in operation_events
        )
        or any(
            _event_is_blocked(event, eligibility_at=eligibility_at)
            for event in planned_cost_events
        )
        or any(
            _event_is_blocked(event, eligibility_at=eligibility_at)
            for event in goal_events
        )
        or any(
            _event_is_blocked(event, eligibility_at=eligibility_at)
            for event in category_events
        )
    )


def _event_is_blocked(
    event: FinanceAccountOutboxEventRow
    | FinanceOutboxEventRow
    | PlannedCostOutboxEventRow
    | FinanceGoalOutboxEventRow
    | FinanceCategoryOutboxEventRow,
    *,
    eligibility_at: datetime,
) -> bool:
    if event.dead_lettered_at is not None:
        return True
    if event.next_attempt_at is None:
        raise HomeProjectionInvariantError("pending outbox event has no retry schedule")
    return _aware_utc(event.next_attempt_at) > eligibility_at


def _apply_retry_decision(
    event: FinanceAccountOutboxEventRow
    | FinanceOutboxEventRow
    | PlannedCostOutboxEventRow
    | FinanceGoalOutboxEventRow
    | FinanceCategoryOutboxEventRow,
    *,
    decision: EventRetryDecision,
) -> None:
    event.attempt_count = min(event.attempt_count + 1, 32767)
    event.validation_failure_count = decision.validation_failure_count
    event.next_attempt_at = decision.next_attempt_at
    event.last_failed_at = decision.last_failed_at
    event.failure_code = decision.failure_code
    event.dead_lettered_at = decision.dead_lettered_at


def _account_fact(row: FinanceAccountRow) -> ProjectionAccount:
    return ProjectionAccount(
        account_id=row.id,
        user_id=row.user_id,
        currency=row.currency,
        opening_balance=row.opening_balance,
        opening_balance_on=row.opening_balance_on,
        opening_timezone=row.opening_timezone,
        status=row.status,
        is_default=row.is_default,
        created_at=row.created_at,
    )


def _category_label(
    row: FinanceOperationRow,
    *,
    category_names: Mapping[UUID, str],
) -> str | None:
    if row.category_id is None:
        return row.category
    name = category_names.get(row.category_id)
    if name is None:
        # The composite foreign key makes this unreachable while the row
        # exists, and categories are archived rather than deleted. Falling back
        # rather than raising keeps one impossible row from blanking a label.
        return row.category
    return name


def _operation_fact(
    row: FinanceOperationRow,
    *,
    category_names: Mapping[UUID, str],
) -> ProjectionOperation:
    return ProjectionOperation(
        operation_id=row.id,
        user_id=row.user_id,
        account_id=row.account_id,
        operation_type=row.operation_type,
        amount=row.amount,
        currency=row.currency,
        # The linked category's current name wins, so renaming one renames it
        # everywhere it is reported. The stored text remains for operations
        # recorded before the catalogue, which have no link to follow.
        category=_category_label(row, category_names=category_names),
        merchant=row.merchant,
        occurred_on=row.occurred_on,
        occurred_at=row.occurred_at,
        captured_timezone=row.captured_timezone,
        status=row.status,
        created_at=row.created_at,
    )


def _planned_cost_fact(row: PlannedCostRow) -> ProjectionPlannedCost:
    return ProjectionPlannedCost(
        planned_cost_id=row.id,
        user_id=row.user_id,
        account_id=row.account_id,
        title=row.title,
        amount=row.amount,
        currency=row.currency,
        planned_on=row.planned_on,
        status=row.status,
        created_at=row.created_at,
    )


def _goal_fact(row: FinanceGoalRow) -> ProjectionGoal:
    return ProjectionGoal(
        goal_id=row.id,
        user_id=row.user_id,
        account_id=row.account_id,
        title=row.title,
        target_amount=row.target_amount,
        monthly_contribution=row.monthly_contribution,
        currency=row.currency,
        target_on=row.target_on,
        status=row.status,
        created_at=row.created_at,
    )


def _goal_contribution_fact(
    row: FinanceGoalContributionRow,
) -> ProjectionGoalContribution:
    return ProjectionGoalContribution(
        contribution_id=row.id,
        goal_id=row.goal_id,
        user_id=row.user_id,
        direction=row.direction,
        amount=row.amount,
        created_at=row.created_at,
    )


def _reconciliation_due(
    *,
    latest: HomeProjectionSnapshotRow | None,
    projection: ProjectedHomeRevision,
) -> bool:
    if latest is None:
        return True
    if latest.projection_schema_version < _PROJECTION_SCHEMA_VERSION:
        return True
    timezone = ZoneInfo(projection.timezone_name)
    return latest.data_as_of.astimezone(timezone).date() < (
        projection.data_as_of.astimezone(timezone).date()
    )


def _projection_children(
    snapshot_id: UUID,
    projection: ProjectedHomeRevision,
) -> list[object]:
    children: list[object] = [
        HomeProjectionTrendPointRow(
            snapshot_id=snapshot_id,
            point_date=point.point_date,
            amount=point.amount,
        )
        for point in projection.trend_points
    ]
    children.extend(
        HomeProjectionTransactionRow(
            snapshot_id=snapshot_id,
            position=position,
            transaction_id=transaction.transaction_id,
            title=transaction.title,
            category=transaction.category,
            occurred_on=transaction.occurred_on,
            occurred_at=transaction.occurred_at,
            amount=transaction.amount,
            base_amount=transaction.amount,
            currency=transaction.currency,
            direction=transaction.direction,
            status="confirmed",
        )
        for position, transaction in enumerate(projection.recent_transactions)
    )
    children.extend(
        HomeProjectionPaymentRow(
            snapshot_id=snapshot_id,
            payment_id=payment.payment_id,
            title=payment.title,
            due_on=payment.due_on,
            due_at=payment.due_at,
            amount=payment.amount,
            base_amount=payment.amount,
            currency=payment.currency,
            status=payment.status,
        )
        for payment in projection.upcoming_payments
    )
    if projection.primary_goal is not None:
        goal = projection.primary_goal
        children.append(
            HomeProjectionGoalRow(
                snapshot_id=snapshot_id,
                goal_id=goal.goal_id,
                title=goal.title,
                current_amount=goal.current_amount,
                target_amount=goal.target_amount,
                monthly_contribution=goal.monthly_contribution,
                current_base_amount=goal.current_amount,
                target_base_amount=goal.target_amount,
                monthly_contribution_base_amount=goal.monthly_contribution,
                currency=goal.currency,
                due_date=goal.due_date,
                progress_percent=goal.progress_percent,
            )
        )
    children.extend(
        HomeProjectionActionRow(
            snapshot_id=snapshot_id,
            position=position,
            action=action,
        )
        for position, action in enumerate(projection.available_actions)
    )
    children.extend(
        HomeProjectionWarningRow(
            snapshot_id=snapshot_id,
            position=position,
            code=warning.code,
            block=warning.block,
        )
        for position, warning in enumerate(projection.warnings)
    )
    return children


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise HomeProjectionInvariantError("projector clock must be timezone-aware")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
