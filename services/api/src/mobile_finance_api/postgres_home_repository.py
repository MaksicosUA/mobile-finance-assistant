"""Persistent first-use Home adapter for authenticated PostgreSQL accounts."""

from __future__ import annotations

import calendar
from collections.abc import Callable
from datetime import UTC, date, datetime, time
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select

from .auth import AuthenticatedUser
from .database import AsyncSessionFactory
from .db_models import UserRow
from .models import (
    HomeBalance,
    HomeMonthSummary,
    HomeResponse,
    HomeState,
    HomeTrend,
    HomeUser,
)
from .repository import HomeQuery


class PostgresEmptyHomeRepository:
    """Return an authoritative empty Home for a persistent active account.

    This adapter intentionally contains no financial tables or writes. A later
    Finance Core read adapter can replace it without changing the HTTP contract.
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
        try:
            user_id = UUID(user.subject)
        except ValueError as error:
            raise RuntimeError("Invalid authenticated account subject") from error

        async with self._session_factory() as database:
            profile = await database.scalar(
                select(UserRow).where(
                    UserRow.id == user_id,
                    UserRow.disabled_at.is_(None),
                )
            )
        if profile is None:
            raise RuntimeError("Authenticated account is unavailable")

        now = _aware_utc(self._clock())
        local_date = now.astimezone(query.timezone).date()
        month_start = local_date.replace(day=1)
        month_end = local_date.replace(
            day=calendar.monthrange(local_date.year, local_date.month)[1]
        )
        # Home is content-addressed with a strong ETag. Keep the representation
        # stable within a month unless the persistent profile changes.
        period_started_at = datetime.combine(
            month_start,
            time.min,
            tzinfo=query.timezone,
        ).astimezone(UTC)
        snapshot_at = max(_aware_utc(profile.updated_at), period_started_at)
        return _empty_home(
            display_name=profile.display_name,
            base_currency=profile.base_currency,
            generated_at=snapshot_at,
            month_start=month_start,
            month_end=month_end,
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


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("A timezone-aware clock is required")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
