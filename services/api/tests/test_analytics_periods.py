"""Selectable windows, their comparison, and a chart that fits a screen.

The month case must stay byte-for-byte what it was, because the installed
client parses the analytics response with a closed set of keys.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient

from mobile_finance_api.analytics import (
    AnalyticsOperation,
    build_analytics,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.home_projection import (
    HomeProjectionInvariantError,
    ProjectionAccount,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.postgres_analytics_repository import _to_v2_contract

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_GROCERIES = UUID("33333333-3333-4333-8333-333333333333")
_CAR = UUID("44444444-4444-4444-8444-444444444444")
_NOW = datetime(2026, 8, 22, 12, tzinfo=UTC)


def _account() -> ProjectionAccount:
    return ProjectionAccount(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency="EUR",
        opening_balance=Decimal("1000.00"),
        opening_balance_on=date(2025, 1, 1),
        opening_timezone="Europe/Berlin",
        status="active",
        is_default=True,
        created_at=datetime(2025, 1, 1, 8, tzinfo=UTC),
    )


def _operation(
    number: int,
    *,
    amount: str,
    occurred_on: date,
    direction: str = "expense",
    category_id: UUID | None = _GROCERIES,
    category_name: str | None = "Продукты",
) -> AnalyticsOperation:
    return AnalyticsOperation(
        operation_id=UUID(f"00000000-0000-4000-8000-{number:012d}"),
        account_id=_ACCOUNT_ID,
        operation_type=direction,
        amount=Decimal(amount),
        occurred_on=occurred_on,
        created_at=datetime(2025, 1, 1, 9, tzinfo=UTC),
        category_id=category_id,
        category_name=category_name,
    )


def _view(kind: str, operations: tuple[AnalyticsOperation, ...], **bounds: date):
    return build_analytics(
        account=_account(),
        operations=operations,
        generated_at=_NOW,
        kind=kind,  # type: ignore[arg-type]
        **bounds,
    )


# --- the window decides the totals -------------------------------------------


def test_a_wider_window_sees_operations_the_month_hides() -> None:
    """The reason this exists: July was invisible while only the month showed."""

    operations = (
        _operation(1, amount="40.00", occurred_on=date(2026, 7, 10)),
        _operation(2, amount="10.00", occurred_on=date(2026, 8, 5)),
    )

    assert _view("month", operations).expense == Decimal("10.00")
    assert _view("quarter", operations).expense == Decimal("50.00")
    assert _view("year", operations).expense == Decimal("50.00")


def test_the_default_window_is_still_the_month() -> None:
    operations = (_operation(1, amount="40.00", occurred_on=date(2026, 7, 10)),)

    assert build_analytics(
        account=_account(), operations=operations, generated_at=_NOW
    ).expense == Decimal(0)


def test_the_last_seven_days_trend_is_unchanged_by_the_window() -> None:
    """v1 clients read this field and assert exactly seven points."""

    operations = (_operation(1, amount="5.00", occurred_on=date(2026, 8, 20)),)

    for kind in ("month", "quarter", "year"):
        view = _view(kind, operations)
        assert len(view.trend_points) == 7
        assert view.trend_total == Decimal("5.00")


# --- comparison ---------------------------------------------------------------


def test_the_previous_window_is_reported_beside_this_one() -> None:
    operations = (
        _operation(1, amount="100.00", occurred_on=date(2026, 7, 10)),
        _operation(2, amount="30.00", occurred_on=date(2026, 8, 5)),
    )

    view = _view("month", operations)

    assert view.expense == Decimal("30.00")
    assert view.previous_expense == Decimal("100.00")
    assert view.previous_net_flow == Decimal("-100.00")


def test_a_category_that_stopped_is_still_listed() -> None:
    """Otherwise a spend that dropped to zero simply vanishes from the table."""

    operations = (
        _operation(
            1,
            amount="80.00",
            occurred_on=date(2026, 7, 4),
            category_id=_CAR,
            category_name="Автомобиль",
        ),
        _operation(2, amount="30.00", occurred_on=date(2026, 8, 5)),
    )

    changes = {row.name: row for row in _view("month", operations).expense_changes}

    assert changes["Продукты"].amount == Decimal("30.00")
    assert changes["Продукты"].previous_amount == Decimal(0)
    assert changes["Автомобиль"].amount == Decimal(0)
    assert changes["Автомобиль"].previous_amount == Decimal("80.00")


def test_the_comparison_never_reaches_before_the_baseline() -> None:
    view = build_analytics(
        account=_account(),
        operations=(_operation(1, amount="10.00", occurred_on=date(2024, 12, 5)),),
        generated_at=_NOW,
        kind="year",
    )

    # The account did not exist in 2024; its spending is not this user's.
    assert view.previous_expense == Decimal(0)


# --- the chart is a balance line ----------------------------------------------


def test_the_line_runs_from_the_opening_control_point_to_the_closing_one() -> None:
    """The question a chart should answer: did this get better, and by how much.

    Where the money went is the table's job, and it already says it.
    """

    operations = (
        _operation(
            1, amount="5000.00", occurred_on=date(2026, 8, 3), direction="income"
        ),
        _operation(2, amount="1800.00", occurred_on=date(2026, 8, 7)),
        _operation(3, amount="1000.00", occurred_on=date(2026, 8, 15)),
    )

    view = _view("month", operations)

    assert view.balance_opening == Decimal("1000.00")
    assert view.balance_closing == Decimal("3200.00")
    assert view.balance_change == Decimal("2200.00")


def test_the_last_point_is_the_balance_home_projects() -> None:
    """Two screens showing different balances is the failure to prevent."""

    operations = (
        _operation(
            1, amount="500.00", occurred_on=date(2026, 7, 4), direction="income"
        ),
        _operation(2, amount="120.00", occurred_on=date(2026, 8, 6)),
    )
    account = _account()
    projected = account.opening_balance + Decimal("500.00") - Decimal("120.00")

    for kind in ("month", "quarter", "year", "last_7_days"):
        view = _view(kind, operations)
        assert view.balance_closing == projected, kind
        assert view.balance_points[-1].amount == projected, kind


def test_the_line_moves_only_on_committed_money() -> None:
    """A balance that drifts on anything else stops being the balance."""

    operations = (
        _operation(
            1, amount="200.00", occurred_on=date(2026, 8, 4), direction="income"
        ),
        _operation(2, amount="50.00", occurred_on=date(2026, 8, 4)),
    )

    view = _view("month", operations)

    assert view.balance_change == Decimal("150.00")
    assert view.balance_closing == view.balance_opening + view.balance_change


def test_the_opening_point_is_what_the_account_was_worth_before_the_window() -> None:
    operations = (
        _operation(
            1, amount="300.00", occurred_on=date(2026, 7, 20), direction="income"
        ),
    )

    august = _view("month", operations)

    # July's income is not August's change, but it is August's starting point.
    assert august.balance_opening == _account().opening_balance + Decimal("300.00")
    assert august.balance_change == Decimal(0)


def test_a_window_entirely_before_the_account_is_refused() -> None:
    """Reporting a balance for months the account did not exist would be a
    fabrication, and zero would read as "you had nothing" rather than "there
    was no account". The boundary refuses the range instead."""

    with pytest.raises(HomeProjectionInvariantError):
        _view("custom", (), from_date=date(2024, 6, 1), to_date=date(2024, 6, 30))


# --- the chart fits the screen -------------------------------------------------


@pytest.mark.parametrize(
    ("kind", "bucket", "points"),
    [
        ("last_7_days", "day", 7),
        # August up to the 22nd.
        ("month", "day", 22),
        # July to September, cut at today: 8 weeks started.
        ("quarter", "week", 8),
        # January to August: 8 months started.
        ("year", "month", 8),
    ],
)
def test_the_series_bucket_follows_the_window_length(
    kind: str, bucket: str, points: int
) -> None:
    """365 daily points on a 360 dp screen is not a chart."""

    view = _view(kind, ())

    assert view.series_bucket == bucket
    assert len(view.balance_points) == points


def test_the_series_stops_at_today_not_at_the_window_end() -> None:
    """An unfinished month must not be drawn as a collapse to zero."""

    view = _view("month", ())

    assert view.balance_points[-1].point_date == date(2026, 8, 22)


def test_a_coarser_bucket_still_ends_on_the_same_balance() -> None:
    """Bucketing changes how many points are drawn, never where the line ends."""

    operations = tuple(
        _operation(day, amount="1.00", occurred_on=date(2026, 8, day))
        for day in range(1, 23)
    )

    monthly = _view("year", operations)
    daily = _view("month", operations)

    assert monthly.balance_points[-1].amount == daily.balance_points[-1].amount


def test_a_custom_window_is_bucketed_by_its_own_length() -> None:
    short = _view("custom", (), from_date=date(2026, 8, 1), to_date=date(2026, 8, 20))
    long = _view("custom", (), from_date=date(2025, 1, 1), to_date=date(2026, 8, 20))

    assert short.series_bucket == "day"
    assert long.series_bucket == "month"


# --- transport ----------------------------------------------------------------


def test_reading_a_window_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.get("/api/v1/analytics/v2")
        assert response.status_code == 401

    asyncio.run(scenario())


def test_the_default_window_is_the_month_home_projects() -> None:
    async def scenario() -> None:
        repository = _FakeAnalytics()
        response = await _get(repository)
        assert response.status_code == 200, response.text
        assert repository.asked == [("month", None, None)]
        assert response.json()["kind"] == "month"

    asyncio.run(scenario())


@pytest.mark.parametrize(
    "query",
    [
        # A custom window without both bounds cannot be resolved.
        "?period=custom",
        "?period=custom&from=2026-08-01",
        "?period=custom&to=2026-08-01",
        "?period=custom&from=2026-08-20&to=2026-08-01",
        # Longer than the cap.
        "?period=custom&from=2000-01-01&to=2026-08-01",
        # Bounds with a named window: honouring them would report a window the
        # caller never asked for.
        "?period=month&from=2026-08-01&to=2026-08-20",
    ],
)
def test_an_unhonourable_window_is_refused_before_the_database(query: str) -> None:
    async def scenario() -> None:
        repository = _FakeAnalytics()
        response = await _get(repository, query)
        assert response.status_code == 422, response.text
        assert response.json()["detail"]["code"] == "MALFORMED_ANALYTICS_QUERY"
        assert repository.asked == []

    asyncio.run(scenario())


def test_a_window_before_the_account_is_a_bad_request_not_a_broken_service() -> None:
    async def scenario() -> None:
        repository = _FakeAnalytics(failure=HomeProjectionInvariantError("before"))
        response = await _get(
            repository, "?period=custom&from=2024-01-01&to=2024-01-31"
        )
        assert response.status_code == 422, response.text

    asyncio.run(scenario())


def test_an_unavailable_store_still_fails_closed() -> None:
    async def scenario() -> None:
        repository = _FakeAnalytics(failure=RuntimeError("no database"))
        response = await _get(repository)
        assert response.status_code == 503, response.text
        assert response.json()["detail"]["code"] == "ANALYTICS_UNAVAILABLE"

    asyncio.run(scenario())


async def _get(repository: _FakeAnalytics, query: str = ""):  # type: ignore[no-untyped-def]
    app = create_app(
        current_user_authenticator=_StaticAuthenticator(),
        analytics_repository=repository,
    )
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        return await client.get(
            f"/api/v1/analytics/v2{query}",
            headers={"Authorization": "Bearer synthetic-token"},
        )


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


class _FakeAnalytics:
    def __init__(self, *, failure: Exception | None = None) -> None:
        self.failure = failure
        self.asked: list[tuple[str, date | None, date | None]] = []

    async def analyse_period(
        self,
        *,
        user_id: UUID,
        kind: str,
        from_date: date | None = None,
        to_date: date | None = None,
    ):  # type: ignore[no-untyped-def]
        del user_id
        if self.failure is not None:
            raise self.failure
        self.asked.append((kind, from_date, to_date))
        return _to_v2_contract(
            build_analytics(
                account=_account(),
                operations=(
                    _operation(1, amount="10.00", occurred_on=date(2026, 8, 5)),
                ),
                generated_at=_NOW,
                kind=kind,  # type: ignore[arg-type]
                from_date=from_date,
                to_date=to_date,
            ),
            kind=kind,  # type: ignore[arg-type]
        )
