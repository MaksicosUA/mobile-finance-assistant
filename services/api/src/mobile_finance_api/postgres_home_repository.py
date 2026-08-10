"""Account-scoped PostgreSQL adapter for the versioned Home read model."""

from __future__ import annotations

import calendar
from collections.abc import Callable, Sequence
from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from .auth import AuthenticatedUser
from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountOutboxEventRow,
    FinanceAccountRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    HomeProjectionActionRow,
    HomeProjectionGoalRow,
    HomeProjectionPaymentRow,
    HomeProjectionSnapshotRow,
    HomeProjectionTransactionRow,
    HomeProjectionTrendPointRow,
    HomeProjectionWarningRow,
    UserRow,
)
from .decimal_math import wide_decimal_context
from .models import (
    HomeBalance,
    HomeGoal,
    HomeMonthSummary,
    HomePayment,
    HomeResponse,
    HomeState,
    HomeTransaction,
    HomeTrend,
    HomeTrendPoint,
    HomeUser,
    HomeWarning,
)
from .repository import HomeCanonicalTimezoneMismatch, HomeQuery
from .timezones import validated_iana_timezone_key

_PROJECTION_SCHEMA_VERSION = 2


class PostgresHomeRepository:
    """Read the newest immutable projection for the requested local month.

    A user with no lifetime projection is a first-use account. Once any
    projection exists, a missing current month is treated as projection lag or
    data loss and fails closed instead of presenting a misleading empty Home.
    """

    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def get_home(
        self,
        *,
        user: AuthenticatedUser,
        query: HomeQuery,
    ) -> HomeResponse:
        if query.period != "current_month":
            raise ValueError("unsupported Home period")
        try:
            user_id = UUID(user.subject)
        except ValueError as error:
            raise RuntimeError("Invalid authenticated account subject") from error

        timezone_name = query.timezone.key

        async with self._session_factory() as database:
            profile = await database.scalar(
                select(UserRow)
                .where(
                    UserRow.id == user_id,
                    UserRow.disabled_at.is_(None),
                )
                .with_for_update(read=True)
            )
            if profile is None:
                raise RuntimeError("Authenticated account is unavailable")
            accounts = tuple(
                (
                    await database.scalars(
                        select(FinanceAccountRow)
                        .where(FinanceAccountRow.user_id == user_id)
                        .order_by(
                            FinanceAccountRow.created_at.asc(),
                            FinanceAccountRow.id.asc(),
                        )
                        .with_for_update(read=True)
                    )
                ).all()
            )
            # The request's calendar boundary belongs after the shared
            # user -> account locks. A request that waited through canonical
            # midnight must not select yesterday's (or last month's) revision.
            now = _aware_utc(self._clock())
            local_date = now.astimezone(query.timezone).date()
            month_start = local_date.replace(day=1)
            month_end = local_date.replace(
                day=calendar.monthrange(local_date.year, local_date.month)[1]
            )
            if accounts and (
                len(accounts) != 1
                or accounts[0].status != "active"
                or not accounts[0].is_default
            ):
                raise RuntimeError("Authoritative account state is inconsistent")
            canonical_timezone: str | None = None
            if profile.canonical_timezone is not None:
                canonical_timezone = _validated_timezone(profile.canonical_timezone)
                if canonical_timezone != timezone_name:
                    raise HomeCanonicalTimezoneMismatch
            if accounts:
                account = accounts[0]
                if (
                    profile.timezone_revision != 1
                    or canonical_timezone is None
                    or _validated_timezone(account.opening_timezone)
                    != canonical_timezone
                    or account.currency != profile.base_currency
                ):
                    raise RuntimeError("Authoritative account profile is inconsistent")
            elif profile.timezone_revision != 0 or canonical_timezone is not None:
                raise RuntimeError("Empty financial profile is inconsistent")

            snapshot = await database.scalar(
                select(HomeProjectionSnapshotRow)
                .where(
                    HomeProjectionSnapshotRow.user_id == user_id,
                    HomeProjectionSnapshotRow.timezone_name == timezone_name,
                    HomeProjectionSnapshotRow.period_start == month_start,
                )
                .order_by(HomeProjectionSnapshotRow.revision.desc())
                .limit(1)
            )
            if snapshot is None:
                if await _has_projection_history(
                    database,
                    user_id,
                ) or await _has_authoritative_financial_state(database, user_id):
                    raise RuntimeError("Current Home projection is unavailable")
                return _empty_home(
                    display_name=profile.display_name,
                    base_currency=profile.base_currency,
                    generated_at=_empty_snapshot_time(
                        profile_updated_at=profile.updated_at,
                        month_start=month_start,
                        timezone=query.timezone,
                    ),
                    month_start=month_start,
                    month_end=month_end,
                )
            if snapshot.projection_schema_version != _PROJECTION_SCHEMA_VERSION:
                raise RuntimeError("Current Home projection schema is unavailable")

            if await _has_financial_state_after(
                database,
                user_id=user_id,
                data_as_of=snapshot.data_as_of,
            ):
                raise RuntimeError("Current Home projection is behind financial state")
            if snapshot.generated_at.astimezone(query.timezone).date() != local_date:
                raise RuntimeError("Current Home projection is not current for today")
            if await _has_unpublished_projection_event(
                database,
                user_id=user_id,
            ):
                raise RuntimeError("Current Home projection has pending source events")

            if (
                snapshot.period_end != month_end
                or snapshot.base_currency != profile.base_currency
                or _validated_timezone(snapshot.timezone_name) != timezone_name
            ):
                raise RuntimeError("Home projection metadata is inconsistent")

            newest_trend_points = tuple(
                (
                    await database.scalars(
                        select(HomeProjectionTrendPointRow)
                        .where(HomeProjectionTrendPointRow.snapshot_id == snapshot.id)
                        .order_by(HomeProjectionTrendPointRow.point_date.desc())
                        .limit(31)
                    )
                ).all()
            )
            trend_points = tuple(reversed(newest_trend_points))
            goal = await database.scalar(
                select(HomeProjectionGoalRow).where(
                    HomeProjectionGoalRow.snapshot_id == snapshot.id
                )
            )
            payments = tuple(
                (
                    await database.scalars(
                        select(HomeProjectionPaymentRow)
                        .where(HomeProjectionPaymentRow.snapshot_id == snapshot.id)
                        .order_by(
                            HomeProjectionPaymentRow.due_on.asc(),
                            HomeProjectionPaymentRow.payment_id.asc(),
                        )
                        .limit(4)
                    )
                ).all()
            )
            transactions = tuple(
                (
                    await database.scalars(
                        select(HomeProjectionTransactionRow)
                        .where(
                            HomeProjectionTransactionRow.snapshot_id == snapshot.id,
                            HomeProjectionTransactionRow.status == "confirmed",
                        )
                        .order_by(
                            HomeProjectionTransactionRow.position.asc().nullslast(),
                            HomeProjectionTransactionRow.transaction_id.asc(),
                        )
                        .limit(4)
                    )
                ).all()
            )
            actions = tuple(
                (
                    await database.scalars(
                        select(HomeProjectionActionRow)
                        .where(HomeProjectionActionRow.snapshot_id == snapshot.id)
                        .order_by(HomeProjectionActionRow.position.asc())
                        .limit(16)
                    )
                ).all()
            )
            warnings = tuple(
                (
                    await database.scalars(
                        select(HomeProjectionWarningRow)
                        .where(HomeProjectionWarningRow.snapshot_id == snapshot.id)
                        .order_by(HomeProjectionWarningRow.position.asc())
                        .limit(16)
                    )
                ).all()
            )

            _validate_temporal_projection(
                snapshot=snapshot,
                timezone=query.timezone,
                trend_points=trend_points,
                transactions=transactions,
            )
            if len(payments) > 3:
                raise RuntimeError("Home projection payment limit is invalid")

        return _projected_home(
            snapshot=snapshot,
            display_name=profile.display_name,
            trend_points=trend_points,
            goal=goal,
            payments=payments,
            transactions=transactions,
            actions=actions,
            warnings=warnings,
        )


async def _has_projection_history(database: AsyncSession, user_id: UUID) -> bool:
    value = await database.scalar(
        select(exists().where(HomeProjectionSnapshotRow.user_id == user_id))
    )
    return bool(value)


async def _has_authoritative_financial_state(
    database: AsyncSession,
    user_id: UUID,
) -> bool:
    account_exists = await database.scalar(
        select(exists().where(FinanceAccountRow.user_id == user_id))
    )
    if account_exists:
        return True
    operation_exists = await database.scalar(
        select(exists().where(FinanceOperationRow.user_id == user_id))
    )
    return bool(operation_exists)


async def _has_financial_state_after(
    database: AsyncSession,
    *,
    user_id: UUID,
    data_as_of: datetime,
) -> bool:
    account_is_newer = await database.scalar(
        select(
            exists().where(
                FinanceAccountRow.user_id == user_id,
                FinanceAccountRow.created_at > data_as_of,
            )
        )
    )
    if account_is_newer:
        return True
    operation_is_newer = await database.scalar(
        select(
            exists().where(
                FinanceOperationRow.user_id == user_id,
                FinanceOperationRow.created_at > data_as_of,
            )
        )
    )
    return bool(operation_is_newer)


async def _has_unpublished_projection_event(
    database: AsyncSession,
    *,
    user_id: UUID,
) -> bool:
    account_event_exists = await database.scalar(
        select(
            exists().where(
                FinanceAccountOutboxEventRow.user_id == user_id,
                FinanceAccountOutboxEventRow.published_at.is_(None),
            )
        )
    )
    if account_event_exists:
        return True
    operation_event_exists = await database.scalar(
        select(
            exists().where(
                FinanceOutboxEventRow.aggregate_id == FinanceOperationRow.id,
                FinanceOutboxEventRow.published_at.is_(None),
                FinanceOperationRow.user_id == user_id,
            )
        )
    )
    return bool(operation_event_exists)


def _projected_home(
    *,
    snapshot: HomeProjectionSnapshotRow,
    display_name: str,
    trend_points: Sequence[HomeProjectionTrendPointRow],
    goal: HomeProjectionGoalRow | None,
    payments: Sequence[HomeProjectionPaymentRow],
    transactions: Sequence[HomeProjectionTransactionRow],
    actions: Sequence[HomeProjectionActionRow],
    warnings: Sequence[HomeProjectionWarningRow],
) -> HomeResponse:
    return HomeResponse(
        generated_at=snapshot.generated_at,
        data_as_of=snapshot.data_as_of,
        base_currency=snapshot.base_currency,
        home_state=HomeState.READY,
        user=HomeUser(display_name=display_name),
        balance=HomeBalance(
            amount=snapshot.balance_amount,
            delta_amount=snapshot.balance_delta_amount,
            delta_percent=snapshot.balance_delta_percent,
        ),
        month_summary=HomeMonthSummary(
            from_=snapshot.period_start,
            to=snapshot.period_end,
            income=snapshot.month_income,
            expense=snapshot.month_expense,
            net_flow=snapshot.month_net_flow,
        ),
        trend=HomeTrend(
            metric=snapshot.trend_metric,
            period=snapshot.trend_period,
            total=snapshot.trend_total,
            points=tuple(
                HomeTrendPoint(date=row.point_date, amount=row.amount)
                for row in trend_points
            ),
        ),
        primary_goal=(
            None
            if goal is None
            else HomeGoal(
                id=goal.goal_id,
                title=goal.title,
                current=goal.current_amount,
                target=goal.target_amount,
                currency=goal.currency,
                due_date=goal.due_date,
                progress_percent=goal.progress_percent,
                monthly_contribution=goal.monthly_contribution,
            )
        ),
        upcoming_payments=tuple(
            HomePayment(
                id=row.payment_id,
                title=row.title,
                due_on=row.due_on,
                due_at=row.due_at,
                amount=row.amount,
                currency=row.currency,
                status=row.status,
            )
            for row in payments
        ),
        recent_transactions=tuple(
            HomeTransaction(
                id=row.transaction_id,
                title=row.title,
                category=row.category,
                occurred_on=_required_occurred_on(row),
                occurred_at=row.occurred_at,
                amount=row.amount,
                currency=row.currency,
                direction=row.direction,
                status="confirmed",
            )
            for row in transactions
        ),
        available_actions=tuple(row.action for row in actions),
        warnings=tuple(HomeWarning(code=row.code, block=row.block) for row in warnings),
    )


def _empty_home(
    *,
    display_name: str,
    base_currency: str,
    generated_at: datetime,
    month_start: date,
    month_end: date,
) -> HomeResponse:
    zero = Decimal("0.00")
    return HomeResponse(
        generated_at=generated_at,
        data_as_of=generated_at,
        base_currency=base_currency,
        home_state=HomeState.FIRST_USE_EMPTY,
        user=HomeUser(display_name=display_name),
        balance=HomeBalance(
            amount=zero,
            delta_amount=zero,
            delta_percent=zero,
        ),
        month_summary=HomeMonthSummary(
            from_=month_start,
            to=month_end,
            income=zero,
            expense=zero,
            net_flow=zero,
        ),
        trend=HomeTrend(
            metric="expense",
            period="7d",
            total=zero,
            points=(),
        ),
        primary_goal=None,
        upcoming_payments=(),
        recent_transactions=(),
        available_actions=("voice_entry",),
        warnings=(),
    )


def _empty_snapshot_time(
    *,
    profile_updated_at: datetime,
    month_start: date,
    timezone: ZoneInfo,
) -> datetime:
    period_started_at = datetime.combine(
        month_start,
        time.min,
        tzinfo=timezone,
    ).astimezone(UTC)
    return max(_aware_utc(profile_updated_at), period_started_at)


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("A timezone-aware clock is required")
    return value.astimezone(UTC)


def _validated_timezone(value: str) -> str:
    try:
        return validated_iana_timezone_key(value)
    except ValueError as error:
        raise RuntimeError("Home projection timezone is invalid") from error


def _validate_temporal_projection(
    *,
    snapshot: HomeProjectionSnapshotRow,
    timezone: ZoneInfo,
    trend_points: Sequence[HomeProjectionTrendPointRow],
    transactions: Sequence[HomeProjectionTransactionRow],
) -> None:
    local_projection_date = (
        _aware_utc(snapshot.generated_at).astimezone(timezone).date()
    )
    if [row.position for row in transactions] != list(range(len(transactions))):
        raise RuntimeError("Home projection transaction order is invalid")
    if any(
        row.occurred_on is None or row.occurred_on > local_projection_date
        for row in transactions
    ):
        raise RuntimeError("Home projection transaction date is in the future")
    if snapshot.trend_metric == "expense" and any(
        row.amount < 0 for row in trend_points
    ):
        raise RuntimeError("Home projection expense trend is invalid")
    with wide_decimal_context():
        calculated_trend_total = sum(
            (row.amount for row in trend_points),
            start=Decimal(0),
        )
    if calculated_trend_total != snapshot.trend_total:
        raise RuntimeError("Home projection trend total is inconsistent")
    horizon_days = {"7d": 7, "30d": 30}.get(snapshot.trend_period)
    if horizon_days is None:
        return
    earliest_date = local_projection_date - timedelta(days=horizon_days - 1)
    expected_dates = tuple(
        earliest_date + timedelta(days=offset) for offset in range(horizon_days)
    )
    if tuple(row.point_date for row in trend_points) != expected_dates:
        raise RuntimeError("Home projection trend horizon is invalid")


def _required_occurred_on(row: HomeProjectionTransactionRow) -> date:
    if row.occurred_on is None:
        raise RuntimeError("Home projection transaction date is unavailable")
    return row.occurred_on


def _utc_now() -> datetime:
    return datetime.now(UTC)


# Compatibility for code embedding the previous empty-only adapter. New
# runtime wiring uses PostgresHomeRepository explicitly.
PostgresEmptyHomeRepository = PostgresHomeRepository
