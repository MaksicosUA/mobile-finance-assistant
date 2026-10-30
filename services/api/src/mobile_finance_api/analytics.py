"""Deterministic spending and income analysis for one local month.

Read-only. Nothing here decides or changes financial state; it groups facts
Finance Core already committed.

The period rules are imported from the Home projection rather than repeated,
because two definitions of "this month" is how two screens start disagreeing
about the same money.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_DOWN, Decimal
from typing import Literal
from uuid import UUID

from .decimal_math import wide_decimal_context
from .home_projection import (
    HomeProjectionInvariantError,
    ProjectionAccount,
    ProjectionTransfer,
    ReportingPeriod,
    ReportingPeriodKind,
    effective_operations,
    period_operations,
    preceding_period,
    resolved_period,
    transfer_delta,
)

_PERCENT_QUANTUM = Decimal("0.01")
_HUNDRED = Decimal(100)
_TREND_DAYS = 7

#: How wide one point of the series is. Chosen from the window's length, not
#: its name, so a custom range gets the same treatment as a named one.
SeriesBucket = Literal["day", "week", "month"]

#: A day per point up to about a month, a week per point up to about half a
#: year, a month per point beyond. 365 daily points on a 360 dp screen is not
#: a chart.
_DAILY_LIMIT = 31
_WEEKLY_LIMIT = 186


@dataclass(frozen=True, slots=True)
class AnalyticsOperation:
    """One committed operation, with the link analysis groups by."""

    operation_id: UUID
    account_id: UUID | None
    operation_type: str
    amount: Decimal
    occurred_on: date
    created_at: datetime
    category_id: UUID | None
    # The category's current name, resolved through the link (ADR 0020). None
    # for an operation recorded before the catalogue and never linked.
    category_name: str | None


@dataclass(frozen=True, slots=True)
class CategoryChange:
    """One category in the reported window, beside the window before it.

    Covers the union of both windows: a category that was spent on last month
    and not this one has to appear, or the drop is invisible.
    """

    category_id: UUID | None
    name: str | None
    amount: Decimal
    previous_amount: Decimal


@dataclass(frozen=True, slots=True)
class CategoryTotal:
    """What one category accounts for in the period."""

    # Null for operations that carry no link. Uncategorized is reported as its
    # own line rather than hidden or guessed at (ADR 0020).
    category_id: UUID | None
    name: str | None
    amount: Decimal
    share_percent: Decimal


@dataclass(frozen=True, slots=True)
class TrendPoint:
    point_date: date
    amount: Decimal


@dataclass(frozen=True, slots=True)
class AnalyticsView:
    timezone_name: str
    period_start: date
    period_end: date
    generated_at: datetime
    base_currency: str
    income: Decimal
    expense: Decimal
    net_flow: Decimal
    expense_by_category: tuple[CategoryTotal, ...]
    income_by_category: tuple[CategoryTotal, ...]
    trend_total: Decimal
    #: The last seven days, whatever the window. Frozen for the v1 contract.
    trend_points: tuple[TrendPoint, ...]
    #: The reported window itself, bucketed to fit a phone screen.
    series_bucket: SeriesBucket = "day"
    #: What the account was worth entering the window — the control point the
    #: line starts from.
    balance_opening: Decimal = Decimal(0)
    #: The balance as at the end of each bucket, so the line answers "did this
    #: get better" rather than "where did it go", which the table already says.
    balance_points: tuple[TrendPoint, ...] = ()
    balance_closing: Decimal = Decimal(0)
    balance_change: Decimal = Decimal(0)
    #: The equally shaped window before this one.
    previous_income: Decimal = Decimal(0)
    previous_expense: Decimal = Decimal(0)
    previous_net_flow: Decimal = Decimal(0)
    expense_changes: tuple[CategoryChange, ...] = ()
    income_changes: tuple[CategoryChange, ...] = ()


def build_analytics(
    *,
    account: ProjectionAccount,
    operations: tuple[AnalyticsOperation, ...],
    generated_at: datetime,
    kind: ReportingPeriodKind = "month",
    from_date: date | None = None,
    to_date: date | None = None,
    transfers: tuple[ProjectionTransfer, ...] = (),
) -> AnalyticsView:
    """Group one account's committed operations for one reported window.

    The window defaults to the current local month, which is what the Home
    projection reports, so asking for nothing gives exactly what it gave
    before.
    """

    generated_at = _aware_utc(generated_at)
    period = resolved_period(
        kind=kind,
        timezone_name=account.opening_timezone,
        generated_at=generated_at,
        from_date=from_date,
        to_date=to_date,
    )
    if account.opening_balance_on > period.cutoff_local_date:
        raise HomeProjectionInvariantError(
            "opening baseline is later than the analysed date"
        )

    allocated = tuple(
        operation
        for operation in operations
        if operation.account_id == account.account_id
        and _aware_utc(operation.created_at) <= generated_at
    )
    effective = effective_operations(
        allocated,
        opening_balance_on=account.opening_balance_on,
        cutoff_local_date=period.cutoff_local_date,
    )
    # A transfer reaches the balance line and nothing else: it is neither income
    # nor expense (ADR 0029). The same window Home applies, for the same reason.
    moved = tuple(
        (transfer.occurred_on, transfer_delta(transfer, account_id=account.account_id))
        for transfer in effective_operations(
            tuple(
                transfer
                for transfer in transfers
                if account.account_id
                in (transfer.from_account_id, transfer.to_account_id)
                and _aware_utc(transfer.created_at) <= generated_at
            ),
            opening_balance_on=account.opening_balance_on,
            cutoff_local_date=period.cutoff_local_date,
        )
    )
    month = period_operations(
        effective,
        period_start=period.period_start,
        opening_balance_on=account.opening_balance_on,
        cutoff_local_date=period.cutoff_local_date,
    )

    income = _total(month, "income")
    expense = _total(month, "expense")

    # The window before this one, over the same effective set. Its own bounds
    # are the cutoff: a past window has no future to trim.
    previous = preceding_period(period, kind=kind)
    earlier = tuple(
        operation
        for operation in allocated
        if max(previous.period_start, account.opening_balance_on)
        <= operation.occurred_on
        <= previous.period_end
    )
    previous_income = _total(earlier, "income")
    previous_expense = _total(earlier, "expense")

    # The line the chart draws: what the account was worth entering the window,
    # every bucket boundary along it, and what it is worth now. Its last point
    # is the same arithmetic Home projects, so the two cannot disagree about
    # the balance a user is looking at.
    balance_opening = _balance_as_at(
        effective,
        moved=moved,
        opening_balance=account.opening_balance,
        as_at=period.period_start - timedelta(days=1),
    )
    balance_points = tuple(
        TrendPoint(
            point_date=boundary,
            amount=_balance_as_at(
                effective,
                moved=moved,
                opening_balance=account.opening_balance,
                as_at=boundary,
            ),
        )
        for boundary in _bucket_boundaries(period)
    )
    balance_closing = _balance_as_at(
        effective,
        moved=moved,
        opening_balance=account.opening_balance,
        as_at=period.cutoff_local_date,
    )

    trend_start = period.cutoff_local_date - timedelta(days=_TREND_DAYS - 1)
    trend_points = tuple(
        TrendPoint(
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
        for point_date in (
            trend_start + timedelta(days=offset) for offset in range(_TREND_DAYS)
        )
    )

    return AnalyticsView(
        timezone_name=period.timezone_name,
        period_start=period.period_start,
        period_end=period.period_end,
        generated_at=generated_at,
        base_currency=account.currency,
        income=income,
        expense=expense,
        net_flow=income - expense,
        expense_by_category=_by_category(month, "expense", total=expense),
        income_by_category=_by_category(month, "income", total=income),
        trend_total=sum((point.amount for point in trend_points), start=Decimal(0)),
        trend_points=trend_points,
        series_bucket=_bucket_for(period),
        balance_opening=balance_opening,
        balance_points=balance_points,
        balance_closing=balance_closing,
        balance_change=balance_closing - balance_opening,
        previous_income=previous_income,
        previous_expense=previous_expense,
        previous_net_flow=previous_income - previous_expense,
        expense_changes=_changes(month, earlier, "expense"),
        income_changes=_changes(month, earlier, "income"),
    )


def _bucket_for(period: ReportingPeriod) -> SeriesBucket:
    span = (period.period_end - period.period_start).days + 1
    if span <= _DAILY_LIMIT:
        return "day"
    if span <= _WEEKLY_LIMIT:
        return "week"
    return "month"


def _bucket_boundaries(period: ReportingPeriod) -> tuple[date, ...]:
    """The last day of each bucket, with the final one cut at today.

    Drawing an unfinished month all the way to its calendar end would show a
    flat line into the future, which reads as a fact rather than an absence.
    """

    bucket = _bucket_for(period)
    starts: list[date] = []
    cursor = period.period_start
    while cursor <= period.cutoff_local_date:
        starts.append(cursor)
        cursor = _next_bucket(cursor, bucket)
    return tuple(
        min(
            (
                starts[index + 1] - timedelta(days=1)
                if index + 1 < len(starts)
                else period.cutoff_local_date
            ),
            period.cutoff_local_date,
        )
        for index in range(len(starts))
    )


def _next_bucket(start: date, bucket: SeriesBucket) -> date:
    if bucket == "day":
        return start + timedelta(days=1)
    if bucket == "week":
        return start + timedelta(days=7)
    year, month = divmod(start.month, 12)
    return date(start.year + year, month + 1, 1)


def _balance_as_at(
    effective: tuple[AnalyticsOperation, ...],
    *,
    moved: tuple[tuple[date, Decimal], ...],
    opening_balance: Decimal,
    as_at: date,
) -> Decimal:
    """The account's worth on `as_at`, by the same rule Home projects.

    Income raises it, expense lowers it, and a transfer moves it by what left
    or arrived; nothing else moves it. A goal contribution earmarks money
    already here (ADR 0019) and a planned cost is a forecast (ADR 0018), so
    neither appears.
    """

    operations = sum(
        (
            operation.amount
            if operation.operation_type == "income"
            else -operation.amount
            for operation in effective
            if operation.occurred_on <= as_at
        ),
        start=Decimal(0),
    )
    transfers = sum(
        (delta for occurred_on, delta in moved if occurred_on <= as_at),
        start=Decimal(0),
    )
    return opening_balance + operations + transfers


def _changes(
    current: tuple[AnalyticsOperation, ...],
    earlier: tuple[AnalyticsOperation, ...],
    direction: str,
) -> tuple[CategoryChange, ...]:
    """Both windows side by side, over the union of their categories."""

    now = _grouped(current, direction)
    before = _grouped(earlier, direction)
    names: dict[UUID | None, str | None] = {}
    for operation in (*earlier, *current):
        if operation.operation_type == direction:
            names[operation.category_id] = operation.category_name
    rows = [
        CategoryChange(
            category_id=key,
            name=names.get(key),
            amount=now.get(key, Decimal(0)),
            previous_amount=before.get(key, Decimal(0)),
        )
        for key in {**before, **now}
    ]
    rows.sort(key=lambda row: (-row.amount, -row.previous_amount))
    return tuple(rows)


def _grouped(
    operations: tuple[AnalyticsOperation, ...], direction: str
) -> dict[UUID | None, Decimal]:
    totals: dict[UUID | None, Decimal] = {}
    for operation in operations:
        if operation.operation_type != direction:
            continue
        totals[operation.category_id] = (
            totals.get(operation.category_id, Decimal(0)) + operation.amount
        )
    return totals


def _total(operations: tuple[AnalyticsOperation, ...], direction: str) -> Decimal:
    return sum(
        (
            operation.amount
            for operation in operations
            if operation.operation_type == direction
        ),
        start=Decimal(0),
    )


def _by_category(
    operations: tuple[AnalyticsOperation, ...],
    direction: str,
    *,
    total: Decimal,
) -> tuple[CategoryTotal, ...]:
    """Sum one direction per category, largest first.

    Only categories with something in the period appear. A catalogue can hold
    dozens of unused categories, and a list of zeroes buries the few lines that
    say anything.
    """

    sums: dict[UUID | None, Decimal] = {}
    names: dict[UUID | None, str | None] = {}
    for operation in operations:
        if operation.operation_type != direction:
            continue
        key = operation.category_id
        sums[key] = sums.get(key, Decimal(0)) + operation.amount
        # An unlinked operation has no name to show; the screen labels it.
        names.setdefault(key, operation.category_name if key is not None else None)

    return tuple(
        sorted(
            (
                CategoryTotal(
                    category_id=key,
                    name=names[key],
                    amount=amount,
                    share_percent=_share(amount, total=total),
                )
                for key, amount in sums.items()
                if amount > 0
            ),
            # Largest first, then by name so equal amounts keep a stable order
            # instead of shuffling between reads.
            key=lambda item: (-item.amount, (item.name or ""), str(item.category_id)),
        )
    )


def _share(amount: Decimal, *, total: Decimal) -> Decimal:
    if total <= 0:
        return Decimal("0.00")
    with wide_decimal_context():
        ratio = (amount / total) * _HUNDRED
    # Truncated rather than rounded, for the same reason goal progress is: a
    # share must never read as more than it is, and the exact ratio rarely
    # fits a fixed scale.
    return ratio.quantize(_PERCENT_QUANTUM, rounding=ROUND_DOWN)


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise HomeProjectionInvariantError("analysis requires aware timestamps")
    return value.astimezone(UTC)
