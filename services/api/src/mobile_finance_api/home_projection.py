"""Pure deterministic construction of one current-month Home revision.

The transactional outbox is an invalidation signal only.  This module accepts
authoritative account and operation facts and never applies event deltas.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_HALF_EVEN, Decimal, InvalidOperation
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo

from .decimal_math import wide_decimal_context
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
    available_actions: tuple[str, ...]
    warnings: tuple[ProjectedWarning, ...]


def build_current_home_revision(
    *,
    account: ProjectionAccount,
    operations: tuple[ProjectionOperation, ...],
    generated_at: datetime,
    planned_costs: tuple[ProjectionPlannedCost, ...] = (),
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
            planned_costs=planned_costs,
        )


def _build_current_home_revision(
    *,
    account: ProjectionAccount,
    operations: tuple[ProjectionOperation, ...],
    generated_at: datetime,
    planned_costs: tuple[ProjectionPlannedCost, ...],
) -> ProjectedHomeRevision:

    generated_at = _aware_utc(generated_at)
    account_created_at = _aware_utc(account.created_at)
    timezone_name = _validated_account(account)
    timezone = ZoneInfo(timezone_name)
    checked_operations = tuple(
        _validated_operation(operation, account=account) for operation in operations
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
    period_start = cutoff_local_date.replace(day=1)
    period_end = cutoff_local_date.replace(
        day=calendar.monthrange(cutoff_local_date.year, cutoff_local_date.month)[1]
    )

    allocated = tuple(
        operation
        for operation in checked_operations
        if operation.account_id == account.account_id
        and operation.created_at <= data_as_of
    )
    effective = tuple(
        operation
        for operation in allocated
        if account.opening_balance_on <= operation.occurred_on <= cutoff_local_date
    )

    balance_amount = account.opening_balance + sum(
        (_signed_amount(operation) for operation in effective),
        start=Decimal(0),
    )
    month_operations = tuple(
        operation
        for operation in effective
        if max(period_start, account.opening_balance_on)
        <= operation.occurred_on
        <= cutoff_local_date
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
        balance_at_month_start = account.opening_balance + sum(
            (
                _signed_amount(operation)
                for operation in effective
                if operation.occurred_on < period_start
            ),
            start=Decimal(0),
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
                    month_net_flow / abs(balance_at_month_start) * Decimal(100)
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
                _validated_planned_cost(plan, account=account)
                for plan in planned_costs
                if plan.status == "planned"
                and plan.account_id == account.account_id
                and _aware_utc(plan.created_at) <= data_as_of
            ),
            key=lambda plan: (plan.planned_on, str(plan.planned_cost_id)),
        )[:3]
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
        balance_delta_amount=_finite(month_net_flow),
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
        available_actions=("voice_entry",),
        warnings=tuple(warnings),
    )


def _validated_account(account: ProjectionAccount) -> str:
    if (
        account.currency != "EUR"
        or account.status != "active"
        or not account.is_default
    ):
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
