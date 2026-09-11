"""Pure deterministic construction of one current-month Home revision.

The transactional outbox is an invalidation signal only.  This module accepts
authoritative account and operation facts and never applies event deltas.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_HALF_EVEN, Decimal, InvalidOperation
from typing import Literal, Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .decimal_math import wide_decimal_context

# Reused rather than reimplemented: the projection must present exactly the
# figures the goal API already derives, or the two surfaces would disagree.
from .goal_contracts import apply_contribution, derive_progress_percent
from .timezones import validated_iana_timezone_key

_PERCENT_SCALE = Decimal("0.01")
_NUMERIC_38_18_MAX = Decimal("99999999999999999999.999999999999999999")


class HomeProjectionInvariantError(RuntimeError):
    """Authoritative facts cannot safely produce a Home revision."""


@dataclass(frozen=True, slots=True)
class ProjectionAccount:
    account_id: UUID
    user_id: UUID
    currency: str
    opening_balance: Decimal
    opening_balance_on: date
    opening_timezone: str
    status: str
    is_default: bool
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ReportingPeriod:
    """The local month a report covers, and the day it is read on."""

    timezone_name: str
    cutoff_local_date: date
    period_start: date
    period_end: date


def reporting_period(
    *,
    timezone_name: str,
    generated_at: datetime,
) -> ReportingPeriod:
    """Resolve the local month from an instant and a canonical timezone.

    Shared with the analytics read so the two can never disagree about which
    month a user is looking at. A month boundary is a local fact (ADR 0007);
    computing it twice is how two screens start showing different totals.
    """

    cutoff_local_date = (
        _aware_utc(generated_at).astimezone(ZoneInfo(timezone_name)).date()
    )
    return ReportingPeriod(
        timezone_name=timezone_name,
        cutoff_local_date=cutoff_local_date,
        period_start=cutoff_local_date.replace(day=1),
        period_end=cutoff_local_date.replace(
            day=calendar.monthrange(cutoff_local_date.year, cutoff_local_date.month)[1]
        ),
    )


#: The windows analytics can report. "month" is what Home projects, and it
#: stays the default so a caller that asks for nothing gets exactly what it
#: got before.
ReportingPeriodKind = Literal["last_7_days", "month", "quarter", "year", "custom"]


def resolved_period(
    *,
    kind: ReportingPeriodKind,
    timezone_name: str,
    generated_at: datetime,
    from_date: date | None = None,
    to_date: date | None = None,
) -> ReportingPeriod:
    """Resolve any reported window in the account's canonical timezone.

    Built on the same local-today that `reporting_period` uses, so every screen
    keeps agreeing about which day it is. A window never extends past today:
    the future holds no committed operations, and showing it as zero would read
    as a fact rather than an absence.
    """

    today = _aware_utc(generated_at).astimezone(ZoneInfo(timezone_name)).date()
    if kind == "month":
        return reporting_period(timezone_name=timezone_name, generated_at=generated_at)
    if kind == "last_7_days":
        start, end = today - timedelta(days=6), today
    elif kind == "quarter":
        first_month = 3 * ((today.month - 1) // 3) + 1
        start = date(today.year, first_month, 1)
        end = _end_of_month(date(today.year, first_month + 2, 1))
    elif kind == "year":
        start, end = date(today.year, 1, 1), date(today.year, 12, 31)
    else:
        if from_date is None or to_date is None or from_date > to_date:
            raise ValueError("a custom period needs a from date and a to date")
        start, end = from_date, to_date
    return ReportingPeriod(
        timezone_name=timezone_name,
        # Never report beyond today, whatever was asked for.
        cutoff_local_date=min(end, today),
        period_start=start,
        period_end=end,
    )


def preceding_period(
    period: ReportingPeriod, *, kind: ReportingPeriodKind
) -> ReportingPeriod:
    """The comparable window immediately before this one.

    Comparison is the reason periods exist — "did I spend more than last
    month" — and it is only honest against a window of the same shape.

    Calendar windows are stepped calendrically, never by subtracting days:
    March has 31 and February 28, so "the same number of days earlier" would
    put the previous month's start in January. A rolling window has no
    calendar to follow, so there the day arithmetic is the right answer.

    A past window has no future to trim, so its cutoff is its own end.
    """

    end = period.period_start - timedelta(days=1)
    if kind == "month":
        start = end.replace(day=1)
    elif kind == "quarter":
        start = date(end.year, 3 * ((end.month - 1) // 3) + 1, 1)
    elif kind == "year":
        start = date(end.year, 1, 1)
    else:
        start = end - (period.period_end - period.period_start)
    return ReportingPeriod(
        timezone_name=period.timezone_name,
        cutoff_local_date=end,
        period_start=start,
        period_end=end,
    )


def _end_of_month(day: date) -> date:
    return day.replace(day=calendar.monthrange(day.year, day.month)[1])


def effective_operations[T: ProjectionOperationLike](
    allocated: tuple[T, ...],
    *,
    opening_balance_on: date,
    cutoff_local_date: date,
) -> tuple[T, ...]:
    """Operations that count: on or after the baseline, not in the future."""

    return tuple(
        operation
        for operation in allocated
        if opening_balance_on <= operation.occurred_on <= cutoff_local_date
    )


def period_operations[T: ProjectionOperationLike](
    effective: tuple[T, ...],
    *,
    period_start: date,
    opening_balance_on: date,
    cutoff_local_date: date,
) -> tuple[T, ...]:
    """Operations inside the reported month.

    The month starts at the later of its first day and the account baseline: a
    month the account did not exist for is partial, not zero.
    """

    return tuple(
        operation
        for operation in effective
        if max(period_start, opening_balance_on)
        <= operation.occurred_on
        <= cutoff_local_date
    )


class ProjectionOperationLike(Protocol):
    """The subset of an operation the shared period filters read."""

    @property
    def occurred_on(self) -> date: ...


@dataclass(frozen=True, slots=True)
class ProjectionOperation:
    operation_id: UUID
    user_id: UUID
    account_id: UUID | None
    operation_type: str
    amount: Decimal
    currency: str
    category: str | None
    merchant: str | None
    occurred_on: date
    occurred_at: datetime | None
    captured_timezone: str
    status: str
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ProjectionPlannedCost:
    """Forecast source fact. Never contributes to an authoritative total."""

    planned_cost_id: UUID
    user_id: UUID
    account_id: UUID
    title: str
    amount: Decimal
    currency: str
    planned_on: date
    status: str
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ProjectionGoal:
    """Declared savings target. Never contributes to an authoritative total."""

    goal_id: UUID
    user_id: UUID
    account_id: UUID
    title: str
    target_amount: Decimal
    monthly_contribution: Decimal
    currency: str
    target_on: date
    status: str
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ProjectionTransfer:
    """One movement between two of the user's wallets (ADR 0029).

    Carries both amounts because nothing is converted; which one applies
    depends on which side of it the wallet being projected is on. It satisfies
    the same shape operations do — an `occurred_on` and a `created_at` — so the
    one eligibility window covers both.
    """

    transfer_id: UUID
    user_id: UUID
    from_account_id: UUID
    from_amount: Decimal
    to_account_id: UUID
    to_amount: Decimal
    occurred_on: date
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ProjectionGoalContribution:
    """One immutable ledger entry earmarking money for a goal (ADR 0019)."""

    contribution_id: UUID
    goal_id: UUID
    user_id: UUID
    direction: str
    amount: Decimal
    created_at: datetime


@dataclass(frozen=True, slots=True)
class ProjectedPrimaryGoal:
    goal_id: str
    title: str
    current_amount: Decimal
    target_amount: Decimal
    monthly_contribution: Decimal
    currency: str
    due_date: date
    progress_percent: Decimal


@dataclass(frozen=True, slots=True)
class ProjectedUpcomingPayment:
    payment_id: str
    title: str
    due_on: date
    # Optional by design: a planned cost has a calendar date and no time of
    # day, and inventing one would contradict ADR 0007.
    due_at: datetime | None
    amount: Decimal
    currency: str
    status: Literal["scheduled", "overdue"]


@dataclass(frozen=True, slots=True)
class ProjectedTrendPoint:
    point_date: date
    amount: Decimal


@dataclass(frozen=True, slots=True)
class ProjectedTransaction:
    transaction_id: str
    title: str | None
    category: str | None
    occurred_on: date
    occurred_at: datetime | None
    amount: Decimal
    currency: str
    direction: Literal["income", "expense"]


@dataclass(frozen=True, slots=True)
class ProjectedWarning:
    code: str
    block: str


@dataclass(frozen=True, slots=True)
class ProjectedHomeRevision:
    timezone_name: str
    period_start: date
    period_end: date
    generated_at: datetime
    data_as_of: datetime
    base_currency: str
    balance_amount: Decimal
    balance_delta_amount: Decimal
    balance_delta_percent: Decimal | None
    month_income: Decimal
    month_expense: Decimal
    month_net_flow: Decimal
    trend_metric: Literal["expense"]
    trend_period: Literal["7d"]
    trend_total: Decimal
    trend_points: tuple[ProjectedTrendPoint, ...]
    recent_transactions: tuple[ProjectedTransaction, ...]
    upcoming_payments: tuple[ProjectedUpcomingPayment, ...]
    primary_goal: ProjectedPrimaryGoal | None
    available_actions: tuple[str, ...]
    warnings: tuple[ProjectedWarning, ...]


def build_current_home_revision(
    *,
    account: ProjectionAccount,
    operations: tuple[ProjectionOperation, ...],
    generated_at: datetime,
    wallets: tuple[ProjectionAccount, ...] = (),
    planned_costs: tuple[ProjectionPlannedCost, ...] = (),
    goals: tuple[ProjectionGoal, ...] = (),
    goal_contributions: tuple[ProjectionGoalContribution, ...] = (),
    transfers: tuple[ProjectionTransfer, ...] = (),
) -> ProjectedHomeRevision:
    """Build one schema-v2 projection from authoritative source facts."""

    # PostgreSQL accepts up to 38 significant integer/fraction digits while
    # Python's default Decimal context has precision 28. Use a wider local
    # context so a valid ledger sum is never silently rounded.
    with wide_decimal_context():
        return _build_current_home_revision(
            account=account,
            operations=operations,
            generated_at=generated_at,
            wallets=wallets,
            planned_costs=planned_costs,
            goals=goals,
            goal_contributions=goal_contributions,
            transfers=transfers,
        )


def _build_current_home_revision(
    *,
    account: ProjectionAccount,
    operations: tuple[ProjectionOperation, ...],
    generated_at: datetime,
    wallets: tuple[ProjectionAccount, ...],
    planned_costs: tuple[ProjectionPlannedCost, ...],
    goals: tuple[ProjectionGoal, ...],
    goal_contributions: tuple[ProjectionGoalContribution, ...],
    transfers: tuple[ProjectionTransfer, ...],
) -> ProjectedHomeRevision:

    generated_at = _aware_utc(generated_at)
    account_created_at = _aware_utc(account.created_at)
    timezone_name = _validated_account(account)
    timezone = ZoneInfo(timezone_name)
    # Only what this wallet holds. A user's other wallets carry operations in
    # their own currencies (ADR 0029), and they are not this projection's to
    # validate — allocation used to happen after validation, when there could
    # only ever be one wallet.
    checked_operations = tuple(
        _validated_operation(operation, account=account)
        for operation in operations
        if operation.account_id is None or operation.account_id == account.account_id
    )
    newest_fact_at = max(
        (
            account_created_at,
            *(_aware_utc(row.created_at) for row in checked_operations),
        )
    )
    if newest_fact_at > generated_at:
        raise HomeProjectionInvariantError(
            "projection clock precedes an authoritative fact"
        )
    data_as_of = generated_at

    cutoff_local_date = generated_at.astimezone(timezone).date()
    if account.opening_balance_on > cutoff_local_date:
        raise HomeProjectionInvariantError(
            "opening baseline is later than the projection date"
        )
    period = reporting_period(timezone_name=timezone_name, generated_at=generated_at)
    period_start = period.period_start
    period_end = period.period_end

    allocated = tuple(
        operation
        for operation in checked_operations
        if operation.account_id == account.account_id
        and operation.created_at <= data_as_of
    )
    effective = effective_operations(
        allocated,
        opening_balance_on=account.opening_balance_on,
        cutoff_local_date=cutoff_local_date,
    )

    # A transfer moves money without being income or expense (ADR 0029), so it
    # reaches the balance and nothing else: not the month totals, not the net
    # flow, not the trend, not a category breakdown.
    allocated_transfers = tuple(
        transfer
        for transfer in transfers
        if account.account_id in (transfer.from_account_id, transfer.to_account_id)
        and _aware_utc(transfer.created_at) <= data_as_of
    )
    effective_transfers = effective_operations(
        allocated_transfers,
        opening_balance_on=account.opening_balance_on,
        cutoff_local_date=cutoff_local_date,
    )
    transferred = sum(
        (
            _transfer_delta(transfer, account_id=account.account_id)
            for transfer in effective_transfers
        ),
        start=Decimal(0),
    )

    balance_amount = (
        account.opening_balance
        + sum(
            (_signed_amount(operation) for operation in effective),
            start=Decimal(0),
        )
        + transferred
    )
    month_operations = period_operations(
        effective,
        period_start=period_start,
        opening_balance_on=account.opening_balance_on,
        cutoff_local_date=cutoff_local_date,
    )
    month_income = sum(
        (
            operation.amount
            for operation in month_operations
            if operation.operation_type == "income"
        ),
        start=Decimal(0),
    )
    month_expense = sum(
        (
            operation.amount
            for operation in month_operations
            if operation.operation_type == "expense"
        ),
        start=Decimal(0),
    )
    month_net_flow = month_income - month_expense
    # What the balance actually did this month. It is the net flow plus what was
    # transferred in or out: showing "+240" beside a balance that fell by 500
    # because money moved to another wallet would be two answers to one
    # question on one card.
    month_transferred = sum(
        (
            _transfer_delta(transfer, account_id=account.account_id)
            for transfer in effective_transfers
            if transfer.occurred_on >= period_start
        ),
        start=Decimal(0),
    )
    balance_month_change = month_net_flow + month_transferred

    warnings: list[ProjectedWarning] = []
    balance_delta_percent: Decimal | None
    if account.opening_balance_on > period_start:
        balance_delta_percent = None
        warnings.append(
            ProjectedWarning(
                code="balance_delta_percent_unavailable_partial_period",
                block="balanceDelta",
            )
        )
        warnings.append(
            ProjectedWarning(
                code="month_summary_partial_after_opening_balance",
                block="monthSummary",
            )
        )
    else:
        balance_at_month_start = (
            account.opening_balance
            + sum(
                (
                    _signed_amount(operation)
                    for operation in effective
                    if operation.occurred_on < period_start
                ),
                start=Decimal(0),
            )
            + sum(
                (
                    _transfer_delta(transfer, account_id=account.account_id)
                    for transfer in effective_transfers
                    if transfer.occurred_on < period_start
                ),
                start=Decimal(0),
            )
        )
        if balance_at_month_start == 0:
            balance_delta_percent = None
            warnings.append(
                ProjectedWarning(
                    code="balance_delta_percent_unavailable_zero_base",
                    block="balanceDeltaPercent",
                )
            )
        else:
            try:
                balance_delta_percent = (
                    balance_month_change / abs(balance_at_month_start) * Decimal(100)
                ).quantize(_PERCENT_SCALE, rounding=ROUND_HALF_EVEN)
            except InvalidOperation as error:
                raise HomeProjectionInvariantError(
                    "balance delta percent exceeds supported precision"
                ) from error

    trend_start = cutoff_local_date - timedelta(days=6)
    trend_points = tuple(
        ProjectedTrendPoint(
            point_date=point_date,
            amount=sum(
                (
                    operation.amount
                    for operation in effective
                    if operation.operation_type == "expense"
                    and operation.occurred_on == point_date
                ),
                start=Decimal(0),
            ),
        )
        for point_date in (trend_start + timedelta(days=offset) for offset in range(7))
    )
    if trend_start < account.opening_balance_on:
        warnings.append(
            ProjectedWarning(
                code="trend_partial_before_opening_balance",
                block="trend",
            )
        )

    recent_operations = sorted(
        effective,
        key=_recent_sort_key,
        reverse=True,
    )[:3]
    recent_transactions = tuple(
        ProjectedTransaction(
            transaction_id=str(operation.operation_id),
            title=operation.merchant,
            category=operation.category,
            occurred_on=operation.occurred_on,
            occurred_at=operation.occurred_at,
            amount=_signed_amount(operation),
            currency=operation.currency,
            direction=operation.operation_type,  # type: ignore[arg-type]
        )
        for operation in recent_operations
    )

    # Outstanding obligations only. confirmed/skipped/cancelled are terminal and
    # are no longer something the user owes. An already-due plan stays in the
    # block on purpose: it is the one a user most needs to see.
    # An obligation belongs to the profile, not to one wallet: a hryvnia bill
    # is due whichever wallet Home happens to draw large, so every revision
    # carries the same list and a reader cannot miss a payment by looking at
    # the wrong one. Each line keeps its own currency and nothing is summed —
    # the same reason balances sit side by side instead of being added
    # (ADR 0029). Each plan is validated against the wallet that owns it, not
    # against the wallet being projected.
    for wallet in wallets:
        if wallet.user_id != account.user_id:
            raise HomeProjectionInvariantError("wallet belongs to another user")
    wallets_by_id = {wallet.account_id: wallet for wallet in (account, *wallets)}
    upcoming_payments = tuple(
        ProjectedUpcomingPayment(
            payment_id=str(plan.planned_cost_id),
            title=plan.title,
            due_on=plan.planned_on,
            due_at=None,
            amount=_finite(plan.amount),
            currency=plan.currency,
            status="overdue" if plan.planned_on < cutoff_local_date else "scheduled",
        )
        for plan in sorted(
            (
                _validated_planned_cost(plan, account=wallets_by_id[plan.account_id])
                for plan in planned_costs
                if plan.status == "planned"
                and plan.account_id in wallets_by_id
                and _aware_utc(plan.created_at) <= data_as_of
            ),
            key=lambda plan: (plan.planned_on, str(plan.planned_cost_id)),
        )[:3]
    )

    primary_goal = _derive_primary_goal(
        goals=goals,
        contributions=goal_contributions,
        account=account,
        data_as_of=data_as_of,
    )

    relevant_legacy = tuple(
        operation
        for operation in checked_operations
        if operation.account_id is None
        and operation.created_at <= data_as_of
        and account.opening_balance_on <= operation.occurred_on <= cutoff_local_date
    )
    if relevant_legacy:
        affected_blocks = ["balance"]
        if any(operation.occurred_on >= period_start for operation in relevant_legacy):
            affected_blocks.append("monthSummary")
        if any(operation.occurred_on >= trend_start for operation in relevant_legacy):
            affected_blocks.append("trend")
        if any(
            operation.account_id is None
            for operation in sorted(
                (*effective, *relevant_legacy),
                key=_recent_sort_key,
                reverse=True,
            )[:3]
        ):
            affected_blocks.append("recentTransactions")
        warnings.extend(
            ProjectedWarning(
                code="legacy_unallocated_operations_excluded",
                block=block,
            )
            for block in affected_blocks
        )

    return ProjectedHomeRevision(
        timezone_name=timezone_name,
        period_start=period_start,
        period_end=period_end,
        generated_at=generated_at,
        data_as_of=data_as_of,
        base_currency=account.currency,
        balance_amount=_finite(balance_amount),
        balance_delta_amount=_finite(balance_month_change),
        balance_delta_percent=(
            None if balance_delta_percent is None else _finite(balance_delta_percent)
        ),
        month_income=_finite(month_income),
        month_expense=_finite(month_expense),
        month_net_flow=_finite(month_net_flow),
        trend_metric="expense",
        trend_period="7d",
        trend_total=_finite(
            sum((point.amount for point in trend_points), start=Decimal(0))
        ),
        trend_points=trend_points,
        recent_transactions=recent_transactions,
        upcoming_payments=upcoming_payments,
        primary_goal=primary_goal,
        available_actions=("voice_entry",),
        warnings=tuple(warnings),
    )


def _derive_primary_goal(
    *,
    goals: tuple[ProjectionGoal, ...],
    contributions: tuple[ProjectionGoalContribution, ...],
    account: ProjectionAccount,
    data_as_of: datetime,
) -> ProjectedPrimaryGoal | None:
    """Pick the goal that needs attention and sum its ledger (ADR 0019).

    The primary goal is derived rather than pinned: the active goal with the
    nearest deadline, ties broken by creation and then id so the ordering is
    total. Nothing here reaches an authoritative money total.
    """

    candidates = sorted(
        (
            _validated_goal(goal, account=account)
            for goal in goals
            if goal.status == "active"
            and goal.account_id == account.account_id
            and _aware_utc(goal.created_at) <= data_as_of
        ),
        key=lambda goal: (
            goal.target_on,
            _aware_utc(goal.created_at),
            str(goal.goal_id),
        ),
    )
    if not candidates:
        return None
    goal = candidates[0]

    current = Decimal(0)
    for entry in contributions:
        if entry.goal_id != goal.goal_id or _aware_utc(entry.created_at) > data_as_of:
            continue
        current = apply_contribution(
            current=current,
            direction=_validated_contribution(entry, goal=goal).direction,
            amount=entry.amount,
        )
    if current < 0:
        # The write path enforces this under a row lock, so a negative sum here
        # means the ledger itself is corrupt. Fail closed rather than publish a
        # figure the projection bounds would reject anyway.
        raise HomeProjectionInvariantError("goal ledger sums below zero")

    return ProjectedPrimaryGoal(
        goal_id=str(goal.goal_id),
        title=goal.title,
        current_amount=_finite(current),
        target_amount=_finite(goal.target_amount),
        monthly_contribution=_finite(goal.monthly_contribution),
        currency=goal.currency,
        due_date=goal.target_on,
        progress_percent=_finite(
            derive_progress_percent(current=current, target=goal.target_amount)
        ),
    )


def _validated_goal(
    goal: ProjectionGoal,
    *,
    account: ProjectionAccount,
) -> ProjectionGoal:
    _aware_utc(goal.created_at)
    if goal.user_id != account.user_id:
        raise HomeProjectionInvariantError("goal belongs to another user")
    if goal.currency != account.currency:
        raise HomeProjectionInvariantError("goal currency does not match account")
    if goal.target_amount <= 0:
        raise HomeProjectionInvariantError("goal target must be positive")
    if goal.monthly_contribution < 0:
        raise HomeProjectionInvariantError(
            "declared monthly contribution must not be negative"
        )
    _finite(goal.target_amount)
    _finite(goal.monthly_contribution)
    if not goal.title.strip():
        raise HomeProjectionInvariantError("goal title must not be blank")
    return goal


def _validated_contribution(
    entry: ProjectionGoalContribution,
    *,
    goal: ProjectionGoal,
) -> ProjectionGoalContribution:
    if entry.user_id != goal.user_id:
        raise HomeProjectionInvariantError("goal contribution belongs to another user")
    if entry.direction not in {"deposit", "withdrawal"}:
        raise HomeProjectionInvariantError("unknown goal contribution direction")
    if entry.amount <= 0:
        raise HomeProjectionInvariantError("goal contribution must be positive")
    _finite(entry.amount)
    return entry


def _validated_account(account: ProjectionAccount) -> str:
    # Neither the currency nor being the default is checked here any more: a
    # wallet holds one currency of its own and only one wallet is the default,
    # while every one of them gets a revision (ADR 0029). The currency an
    # operation carries is still checked against this account's below.
    if account.status != "active":
        raise HomeProjectionInvariantError("unsupported authoritative account state")
    _finite(account.opening_balance)
    try:
        timezone_name = validated_iana_timezone_key(account.opening_timezone)
    except ValueError as error:
        raise HomeProjectionInvariantError("invalid authoritative timezone") from error
    return timezone_name


def _validated_planned_cost(
    plan: ProjectionPlannedCost,
    *,
    account: ProjectionAccount,
) -> ProjectionPlannedCost:
    _aware_utc(plan.created_at)
    if plan.user_id != account.user_id:
        raise HomeProjectionInvariantError("planned cost belongs to another user")
    if plan.currency != account.currency:
        raise HomeProjectionInvariantError(
            "planned cost currency does not match account"
        )
    if plan.amount <= 0:
        raise HomeProjectionInvariantError("planned cost amount must be positive")
    _finite(plan.amount)
    if not plan.title.strip():
        raise HomeProjectionInvariantError("planned cost title must not be blank")
    return plan


def _validated_operation(
    operation: ProjectionOperation,
    *,
    account: ProjectionAccount,
) -> ProjectionOperation:
    created_at = _aware_utc(operation.created_at)
    occurred_at = (
        None if operation.occurred_at is None else _aware_utc(operation.occurred_at)
    )
    if operation.user_id != account.user_id:
        raise HomeProjectionInvariantError("operation belongs to another user")
    if operation.status != "confirmed":
        raise HomeProjectionInvariantError("unsupported operation status")
    if operation.operation_type not in {"income", "expense"}:
        raise HomeProjectionInvariantError("unsupported operation type")
    if operation.currency != account.currency:
        raise HomeProjectionInvariantError("operation currency does not match account")
    if operation.amount <= 0:
        raise HomeProjectionInvariantError("operation amount must be positive")
    _finite(operation.amount)
    try:
        captured_timezone = validated_iana_timezone_key(operation.captured_timezone)
    except ValueError as error:
        raise HomeProjectionInvariantError(
            "invalid operation captured timezone"
        ) from error
    if (
        occurred_at is not None
        and occurred_at.astimezone(ZoneInfo(captured_timezone)).date()
        != operation.occurred_on
    ):
        raise HomeProjectionInvariantError(
            "operation exact time conflicts with its local date"
        )
    if operation.account_id is not None:
        if operation.account_id != account.account_id:
            raise HomeProjectionInvariantError("operation belongs to another account")
        if operation.occurred_on < account.opening_balance_on:
            raise HomeProjectionInvariantError("operation precedes opening baseline")
    return ProjectionOperation(
        operation_id=operation.operation_id,
        user_id=operation.user_id,
        account_id=operation.account_id,
        operation_type=operation.operation_type,
        amount=operation.amount,
        currency=operation.currency,
        category=operation.category,
        merchant=operation.merchant,
        occurred_on=operation.occurred_on,
        occurred_at=occurred_at,
        captured_timezone=captured_timezone,
        status=operation.status,
        created_at=created_at,
    )


def _transfer_delta(transfer: ProjectionTransfer, *, account_id: UUID) -> Decimal:
    """What one transfer did to this wallet: what arrived, or what left."""

    if transfer.to_account_id == account_id:
        return transfer.to_amount
    if transfer.from_account_id == account_id:
        return -transfer.from_amount
    return Decimal(0)  # pragma: no cover - allocation filters these out


def _signed_amount(operation: ProjectionOperation) -> Decimal:
    return (
        operation.amount if operation.operation_type == "income" else -operation.amount
    )


def _recent_sort_key(
    operation: ProjectionOperation,
) -> tuple[date, datetime, datetime, int]:
    return (
        operation.occurred_on,
        operation.occurred_at or datetime.min.replace(tzinfo=UTC),
        operation.created_at,
        operation.operation_id.int,
    )


def _finite(value: Decimal) -> Decimal:
    if not value.is_finite():
        raise HomeProjectionInvariantError("projection decimal is not finite")
    if abs(value) > _NUMERIC_38_18_MAX:
        raise HomeProjectionInvariantError(
            "projection decimal exceeds authoritative storage bounds"
        )
    return value


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise HomeProjectionInvariantError(
            "projection timestamp must be timezone-aware"
        )
    return value.astimezone(UTC)
