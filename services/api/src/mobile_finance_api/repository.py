"""Home repository port and deterministic synthetic adapter."""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from enum import StrEnum
from typing import Literal, Protocol
from zoneinfo import ZoneInfo

from .auth import AuthenticatedUser
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


@dataclass(frozen=True, slots=True)
class HomeQuery:
    period: Literal["current_month"]
    timezone: ZoneInfo


class HomeRepository(Protocol):
    async def get_home(
        self,
        *,
        user: AuthenticatedUser,
        query: HomeQuery,
    ) -> HomeResponse:
        """Return a validated aggregate for one authenticated account."""


class HomeCanonicalTimezoneMismatch(Exception):
    """The requested projection timezone differs from the financial profile."""


class UnavailableHomeRepository:
    """Fail-closed default until a deployment configures a data adapter."""

    async def get_home(
        self,
        *,
        user: AuthenticatedUser,
        query: HomeQuery,
    ) -> HomeResponse:
        del user, query
        raise RuntimeError("Home repository is not configured")


class SyntheticHomeVariant(StrEnum):
    READY = "ready"
    EMPTY = "empty"
    PARTIAL = "partial"


class SyntheticHomeRepository:
    """Deterministic, read-only adapter for the first contract E2E slice.

    The adapter contains synthetic values only. State selection is constructor
    injection, never a public request switch. A real persistence adapter can
    replace this class without changing HTTP or authentication code.
    """

    _GENERATED_AT = datetime(2026, 7, 11, 1, 20, tzinfo=UTC)
    _DATA_AS_OF = datetime(2026, 7, 11, 1, 19, 58, tzinfo=UTC)

    def __init__(
        self,
        *,
        variant: SyntheticHomeVariant = SyntheticHomeVariant.READY,
    ) -> None:
        self._variant = variant

    async def get_home(
        self,
        *,
        user: AuthenticatedUser,
        query: HomeQuery,
    ) -> HomeResponse:
        if query.period != "current_month":
            raise ValueError("unsupported Home period")

        local_date = self._DATA_AS_OF.astimezone(query.timezone).date()
        month_start = local_date.replace(day=1)
        month_end = local_date.replace(
            day=calendar.monthrange(local_date.year, local_date.month)[1]
        )

        if self._variant is SyntheticHomeVariant.EMPTY:
            return self._empty(user, month_start, month_end)
        return self._populated(
            user,
            month_start,
            month_end,
            partial=self._variant is SyntheticHomeVariant.PARTIAL,
        )

    def _empty(
        self,
        user: AuthenticatedUser,
        month_start: date,
        month_end: date,
    ) -> HomeResponse:
        zero = Decimal("0.00")
        return HomeResponse(
            generated_at=self._GENERATED_AT,
            data_as_of=self._DATA_AS_OF,
            base_currency="EUR",
            home_state=HomeState.FIRST_USE_EMPTY,
            user=HomeUser(display_name=user.display_name),
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

    def _populated(
        self,
        user: AuthenticatedUser,
        month_start: date,
        month_end: date,
        *,
        partial: bool,
    ) -> HomeResponse:
        recent_dates = tuple(date(2026, 7, day) for day in (5, 6, 7, 8, 9, 10, 11))
        trend_amounts = tuple(
            Decimal(value)
            for value in (
                "18.00",
                "21.00",
                "15.00",
                "24.00",
                "17.00",
                "20.00",
                "25.20",
            )
        )
        warnings = (
            (
                HomeWarning(
                    code="primary_goal_unavailable",
                    block="primaryGoal",
                ),
            )
            if partial
            else ()
        )

        return HomeResponse(
            generated_at=self._GENERATED_AT,
            data_as_of=self._DATA_AS_OF,
            base_currency="EUR",
            home_state=HomeState.READY,
            user=HomeUser(display_name=user.display_name),
            balance=HomeBalance(
                amount=Decimal("3240.50"),
                delta_amount=Decimal("182.40"),
                delta_percent=Decimal("5.96"),
            ),
            month_summary=HomeMonthSummary(
                from_=month_start,
                to=month_end,
                income=Decimal("1930.00"),
                expense=Decimal("847.20"),
                net_flow=Decimal("1082.80"),
            ),
            trend=HomeTrend(
                metric="expense",
                period="7d",
                total=Decimal("140.20"),
                points=tuple(
                    HomeTrendPoint(date=point_date, amount=amount)
                    for point_date, amount in zip(
                        recent_dates,
                        trend_amounts,
                        strict=True,
                    )
                ),
            ),
            primary_goal=(
                None
                if partial
                else HomeGoal(
                    id="goal_synthetic_1",
                    title="Финансовый резерв",
                    current=Decimal("3200.00"),
                    target=Decimal("10000.00"),
                    currency="EUR",
                    due_date=date(2026, 12, 31),
                    progress_percent=Decimal("32"),
                    monthly_contribution=Decimal("1360.00"),
                )
            ),
            upcoming_payments=(
                HomePayment(
                    id="payment_synthetic_1",
                    title="Аренда",
                    due_on=date(2026, 7, 16),
                    due_at=datetime(2026, 7, 16, 7, tzinfo=UTC),
                    amount=Decimal("530.00"),
                    currency="EUR",
                    status="scheduled",
                ),
                HomePayment(
                    id="payment_synthetic_2",
                    title="Интернет",
                    due_on=date(2026, 7, 20),
                    due_at=datetime(2026, 7, 20, 7, tzinfo=UTC),
                    amount=Decimal("39.99"),
                    currency="EUR",
                    status="scheduled",
                ),
                HomePayment(
                    id="payment_synthetic_3",
                    title="Страховка",
                    due_on=date(2026, 7, 23),
                    due_at=datetime(2026, 7, 23, 7, tzinfo=UTC),
                    amount=Decimal("74.00"),
                    currency="EUR",
                    status="scheduled",
                ),
            ),
            recent_transactions=(
                HomeTransaction(
                    id="transaction_synthetic_1",
                    title="Продуктовый магазин",
                    category="Продукты",
                    occurred_on=date(2026, 7, 10),
                    occurred_at=datetime(
                        2026,
                        7,
                        10,
                        17,
                        45,
                        tzinfo=UTC,
                    ),
                    amount=Decimal("-38.00"),
                    currency="EUR",
                    direction="expense",
                    status="confirmed",
                ),
                HomeTransaction(
                    id="transaction_synthetic_2",
                    title="Зарплата",
                    category="Доход",
                    occurred_on=date(2026, 7, 5),
                    occurred_at=datetime(2026, 7, 5, 8, tzinfo=UTC),
                    amount=Decimal("1930.00"),
                    currency="EUR",
                    direction="income",
                    status="confirmed",
                ),
                HomeTransaction(
                    id="transaction_synthetic_3",
                    title="Дивиденды ETF",
                    category="Инвестиционный доход",
                    occurred_on=date(2026, 7, 3),
                    occurred_at=datetime(2026, 7, 3, 14, 20, tzinfo=UTC),
                    amount=Decimal("55.00"),
                    currency="USD",
                    direction="income",
                    status="confirmed",
                ),
            ),
            available_actions=("voice_entry", "analytics", "goals"),
            warnings=warnings,
        )
