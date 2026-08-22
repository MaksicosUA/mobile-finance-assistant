"""PostgreSQL read adapter for category analytics.

Computed live from authoritative operations rather than from a stored Home
projection. The two therefore agree by construction on the same facts, and
analytics can be a moment ahead while the projector catches up — which is the
right direction for a read that changes nothing.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, date, datetime
from uuid import UUID

from sqlalchemy import select

from .analytics import (
    AnalyticsOperation,
    AnalyticsView,
    CategoryChange,
    CategoryTotal,
    build_analytics,
)
from .analytics_contracts import (
    AnalyticsBalanceLine,
    AnalyticsCategoryChange,
    AnalyticsCategoryTotal,
    AnalyticsPeriod,
    AnalyticsResponse,
    AnalyticsTotals,
    AnalyticsTrend,
    AnalyticsTrendPoint,
    AnalyticsV2Response,
)
from .database import AsyncSessionFactory
from .db_models import FinanceAccountRow, FinanceCategoryRow, FinanceOperationRow
from .home_projection import (
    ProjectionAccount,
    ReportingPeriod,
    ReportingPeriodKind,
    preceding_period,
)


class AnalyticsUnavailable(Exception):
    """The authoritative store could not safely answer the analysis."""


class PostgresAnalyticsRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def analyse_current_month(self, *, user_id: UUID) -> AnalyticsResponse:
        account, operations = await self._read(user_id=user_id)
        return _to_contract(
            build_analytics(
                account=account,
                operations=operations,
                generated_at=_aware_utc(self._clock()),
            )
        )

    async def analyse_period(
        self,
        *,
        user_id: UUID,
        kind: ReportingPeriodKind,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> AnalyticsV2Response:
        account, operations = await self._read(user_id=user_id)
        return _to_v2_contract(
            build_analytics(
                account=account,
                operations=operations,
                generated_at=_aware_utc(self._clock()),
                kind=kind,
                from_date=from_date,
                to_date=to_date,
            ),
            kind=kind,
        )

    async def _read(
        self, *, user_id: UUID
    ) -> tuple[ProjectionAccount, tuple[AnalyticsOperation, ...]]:
        async with self._session_factory() as database:
            account = await database.scalar(
                select(FinanceAccountRow).where(
                    FinanceAccountRow.user_id == user_id,
                    FinanceAccountRow.status == "active",
                    FinanceAccountRow.is_default.is_(True),
                )
            )
            if account is None:
                raise AnalyticsUnavailable
            rows = (
                await database.execute(
                    # Left join: an operation recorded before the catalogue has
                    # no link and must still be counted, as its own line.
                    select(FinanceOperationRow, FinanceCategoryRow.name)
                    .outerjoin(
                        FinanceCategoryRow,
                        (FinanceCategoryRow.id == FinanceOperationRow.category_id)
                        & (FinanceCategoryRow.user_id == FinanceOperationRow.user_id),
                    )
                    .where(
                        FinanceOperationRow.user_id == user_id,
                        FinanceOperationRow.status == "confirmed",
                    )
                )
            ).all()

        return _projection_account(account), tuple(
            AnalyticsOperation(
                operation_id=row.id,
                account_id=row.account_id,
                operation_type=row.operation_type,
                amount=row.amount,
                occurred_on=row.occurred_on,
                created_at=row.created_at,
                category_id=row.category_id,
                category_name=name,
            )
            for row, name in rows
        )


def _projection_account(row: FinanceAccountRow) -> ProjectionAccount:
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


def _to_contract(view: AnalyticsView) -> AnalyticsResponse:
    return AnalyticsResponse(
        generated_at=view.generated_at,
        base_currency=view.base_currency,
        period=AnalyticsPeriod(start=view.period_start, end=view.period_end),
        totals=AnalyticsTotals(
            income=view.income,
            expense=view.expense,
            net_flow=view.net_flow,
        ),
        expense_by_category=tuple(
            _category_total(item) for item in view.expense_by_category
        ),
        income_by_category=tuple(
            _category_total(item) for item in view.income_by_category
        ),
        trend=AnalyticsTrend(
            total=view.trend_total,
            points=tuple(
                AnalyticsTrendPoint(date=point.point_date, amount=point.amount)
                for point in view.trend_points
            ),
        ),
    )


def _to_v2_contract(
    view: AnalyticsView, *, kind: ReportingPeriodKind
) -> AnalyticsV2Response:
    previous = preceding_period(
        ReportingPeriod(
            timezone_name=view.timezone_name,
            cutoff_local_date=view.period_end,
            period_start=view.period_start,
            period_end=view.period_end,
        ),
        kind=kind,
    )
    return AnalyticsV2Response(
        generated_at=view.generated_at,
        base_currency=view.base_currency,
        kind=kind,
        period=AnalyticsPeriod(start=view.period_start, end=view.period_end),
        previous_period=AnalyticsPeriod(
            start=previous.period_start, end=previous.period_end
        ),
        totals=AnalyticsTotals(
            income=view.income, expense=view.expense, net_flow=view.net_flow
        ),
        previous_totals=AnalyticsTotals(
            income=view.previous_income,
            expense=view.previous_expense,
            net_flow=view.previous_net_flow,
        ),
        expense_by_category=tuple(
            _category_total(item) for item in view.expense_by_category
        ),
        income_by_category=tuple(
            _category_total(item) for item in view.income_by_category
        ),
        expense_changes=tuple(_category_change(row) for row in view.expense_changes),
        income_changes=tuple(_category_change(row) for row in view.income_changes),
        balance=AnalyticsBalanceLine(
            bucket=view.series_bucket,
            opening=view.balance_opening,
            closing=view.balance_closing,
            change=view.balance_change,
            points=tuple(
                AnalyticsTrendPoint(date=point.point_date, amount=point.amount)
                for point in view.balance_points
            ),
        ),
    )


def _category_change(row: CategoryChange) -> AnalyticsCategoryChange:
    return AnalyticsCategoryChange(
        category_id=row.category_id,
        name=row.name,
        amount=row.amount,
        previous_amount=row.previous_amount,
    )


def _category_total(item: CategoryTotal) -> AnalyticsCategoryTotal:
    return AnalyticsCategoryTotal(
        category_id=item.category_id,
        name=item.name,
        amount=item.amount,
        share_percent=item.share_percent,
    )


class UnavailableAnalyticsRepository:
    async def analyse_period(
        self,
        *,
        user_id: UUID,
        kind: ReportingPeriodKind,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> AnalyticsV2Response:
        del user_id, kind, from_date, to_date
        raise AnalyticsUnavailable

    async def analyse_current_month(self, *, user_id: UUID) -> AnalyticsResponse:
        del user_id
        raise AnalyticsUnavailable


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
