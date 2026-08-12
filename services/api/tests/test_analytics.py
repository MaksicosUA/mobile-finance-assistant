"""Category analytics for one local month (ADR 0020, step 5).

The figures here and on Home must never disagree, so both derive the period
and the eligible operations from the same shared functions, and
`test_totals_match_the_home_projection` pins that agreement.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.analytics import AnalyticsOperation, build_analytics
from mobile_finance_api.analytics_contracts import AnalyticsResponse
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.home_projection import (
    ProjectionAccount,
    ProjectionOperation,
    build_current_home_revision,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.postgres_analytics_repository import (
    AnalyticsUnavailable,
    _to_contract,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_GROCERIES = UUID("33333333-3333-4333-8333-333333333333")
_TRANSPORT = UUID("44444444-4444-4444-8444-444444444444")
_SALARY = UUID("55555555-5555-4555-8555-555555555555")
_GENERATED_AT = datetime(2026, 8, 12, 12, tzinfo=UTC)
_AUTH = {"Authorization": "Bearer synthetic-token"}


def _account(**changes: object) -> ProjectionAccount:
    values: dict[str, object] = {
        "account_id": _ACCOUNT_ID,
        "user_id": _USER_ID,
        "currency": "EUR",
        "opening_balance": Decimal("1000.00"),
        "opening_balance_on": date(2026, 6, 1),
        "opening_timezone": "Europe/Berlin",
        "status": "active",
        "is_default": True,
        "created_at": datetime(2026, 6, 1, 8, tzinfo=UTC),
    }
    values.update(changes)
    return ProjectionAccount(**values)  # type: ignore[arg-type]


def _operation(
    number: int,
    *,
    amount: str,
    direction: str = "expense",
    occurred_on: date = date(2026, 8, 10),
    category_id: UUID | None = _GROCERIES,
    category_name: str | None = "Продукты",
    account_id: UUID | None = _ACCOUNT_ID,
) -> AnalyticsOperation:
    return AnalyticsOperation(
        operation_id=UUID(f"00000000-0000-4000-8000-{number:012d}"),
        account_id=account_id,
        operation_type=direction,
        amount=Decimal(amount),
        occurred_on=occurred_on,
        created_at=datetime(2026, 8, 10, 9, tzinfo=UTC),
        category_id=category_id,
        category_name=category_name,
    )


def _mirrored(operation: AnalyticsOperation) -> ProjectionOperation:
    """The same fact as the Home projection sees it."""

    return ProjectionOperation(
        operation_id=operation.operation_id,
        user_id=_USER_ID,
        account_id=operation.account_id,
        operation_type=operation.operation_type,
        amount=operation.amount,
        currency="EUR",
        category=operation.category_name,
        merchant=None,
        occurred_on=operation.occurred_on,
        occurred_at=None,
        captured_timezone="Europe/Berlin",
        status="confirmed",
        created_at=operation.created_at,
    )


# --- agreement with Home ----------------------------------------------------


def test_totals_match_the_home_projection() -> None:
    """Two screens, one month, one answer.

    Both read the period and eligibility rules from the same functions. This
    asserts the result, so a change to either side that breaks the agreement
    fails here instead of on a user's phone.
    """

    operations = (
        _operation(1, amount="42.00"),
        _operation(
            2, amount="13.50", category_id=_TRANSPORT, category_name="Транспорт"
        ),
        _operation(
            3,
            amount="1500.00",
            direction="income",
            category_id=_SALARY,
            category_name="Зарплата",
        ),
        # Last month: outside the period for both.
        _operation(4, amount="900.00", occurred_on=date(2026, 7, 30)),
    )
    analytics = build_analytics(
        account=_account(),
        operations=operations,
        generated_at=_GENERATED_AT,
    )
    home = build_current_home_revision(
        account=_account(),
        operations=tuple(_mirrored(item) for item in operations),
        generated_at=_GENERATED_AT,
    )

    assert analytics.income == home.month_income
    assert analytics.expense == home.month_expense
    assert analytics.net_flow == home.month_net_flow
    assert analytics.period_start == home.period_start
    assert analytics.period_end == home.period_end
    # The 7-day expense trend moves to analytics unchanged.
    assert analytics.trend_total == home.trend_total
    assert [point.amount for point in analytics.trend_points] == [
        point.amount for point in home.trend_points
    ]


# --- grouping ---------------------------------------------------------------


def test_only_categories_with_activity_are_reported() -> None:
    """A catalogue of 60 with 47 unused would bury the lines that matter."""

    analytics = build_analytics(
        account=_account(),
        operations=(
            _operation(1, amount="42.00"),
            _operation(
                2,
                amount="100.00",
                category_id=_TRANSPORT,
                category_name="Транспорт",
            ),
        ),
        generated_at=_GENERATED_AT,
    )

    assert [item.name for item in analytics.expense_by_category] == [
        "Транспорт",
        "Продукты",
    ]
    # Largest first, so the biggest line is the first thing read.
    assert [item.amount for item in analytics.expense_by_category] == [
        Decimal("100.00"),
        Decimal("42.00"),
    ]
    assert analytics.income_by_category == ()


def test_uncategorized_spending_is_its_own_line() -> None:
    """Hiding it would make the totals stop adding up on screen."""

    analytics = build_analytics(
        account=_account(),
        operations=(
            _operation(1, amount="42.00"),
            _operation(2, amount="8.00", category_id=None, category_name=None),
        ),
        generated_at=_GENERATED_AT,
    )

    unlinked = [
        item for item in analytics.expense_by_category if item.category_id is None
    ]
    assert len(unlinked) == 1
    assert unlinked[0].amount == Decimal("8.00")
    assert unlinked[0].name is None
    assert sum(item.amount for item in analytics.expense_by_category) == Decimal(
        "50.00"
    )


def test_a_share_is_truncated_rather_than_rounded_up() -> None:
    analytics = build_analytics(
        account=_account(),
        operations=(
            _operation(1, amount="100.00"),
            _operation(
                2,
                amount="200.00",
                category_id=_TRANSPORT,
                category_name="Транспорт",
            ),
        ),
        generated_at=_GENERATED_AT,
    )

    shares = {item.name: item.share_percent for item in analytics.expense_by_category}
    # 100/300 is 33.333…; a share must never read as more than it is.
    assert shares["Продукты"] == Decimal("33.33")
    assert shares["Транспорт"] == Decimal("66.66")


def test_operations_outside_the_account_or_period_are_excluded() -> None:
    analytics = build_analytics(
        account=_account(),
        operations=(
            _operation(1, amount="42.00"),
            # Another account's operation.
            _operation(2, amount="500.00", account_id=uuid4()),
            # Before the account existed.
            _operation(3, amount="700.00", occurred_on=date(2026, 5, 1)),
            # Unallocated legacy row.
            _operation(4, amount="800.00", account_id=None),
        ),
        generated_at=_GENERATED_AT,
    )

    assert analytics.expense == Decimal("42.00")


def test_an_empty_month_reports_zero_rather_than_failing() -> None:
    analytics = build_analytics(
        account=_account(),
        operations=(),
        generated_at=_GENERATED_AT,
    )

    assert analytics.income == Decimal(0)
    assert analytics.expense == Decimal(0)
    assert analytics.net_flow == Decimal(0)
    assert analytics.expense_by_category == ()
    assert len(analytics.trend_points) == 7


# --- contract rules ---------------------------------------------------------


def test_the_contract_refuses_a_breakdown_that_does_not_add_up() -> None:
    """The one thing a spending report must never show."""

    view = build_analytics(
        account=_account(),
        operations=(_operation(1, amount="42.00"),),
        generated_at=_GENERATED_AT,
    )
    payload = _to_contract(view).model_dump(mode="json", by_alias=True)
    payload["expenseByCategory"][0]["amount"] = "41.00"

    with pytest.raises(ValidationError):
        AnalyticsResponse.model_validate(payload)


def test_the_contract_refuses_an_inconsistent_net_flow() -> None:
    view = build_analytics(
        account=_account(),
        operations=(_operation(1, amount="42.00"),),
        generated_at=_GENERATED_AT,
    )
    payload = _to_contract(view).model_dump(mode="json", by_alias=True)
    payload["totals"]["netFlow"] = "0"

    with pytest.raises(ValidationError):
        AnalyticsResponse.model_validate(payload)


def test_money_crosses_as_decimal_strings() -> None:
    view = build_analytics(
        account=_account(),
        operations=(_operation(1, amount="42.00"),),
        generated_at=_GENERATED_AT,
    )
    payload = _to_contract(view).model_dump(mode="json", by_alias=True)

    assert isinstance(payload["totals"]["expense"], str)
    assert isinstance(payload["expenseByCategory"][0]["amount"], str)
    assert isinstance(payload["trend"]["total"], str)


# --- transport --------------------------------------------------------------


def test_reading_analytics_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/analytics")
        assert response.status_code == 401

    asyncio.run(scenario())


def test_an_unwired_analytics_store_fails_closed() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/analytics", headers=_AUTH)
        assert response.status_code == 503, response.text
        assert response.json() == {"detail": {"code": "ANALYTICS_UNAVAILABLE"}}

    asyncio.run(scenario())


def test_an_unexpected_failure_never_carries_amounts_or_names() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            analytics_repository=_ExplodingAnalytics(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/analytics", headers=_AUTH)
        assert response.status_code == 503, response.text
        assert "Продукты" not in response.text
        assert "42.00" not in response.text

    asyncio.run(scenario())


def test_a_month_crosses_the_api_with_both_directions() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            analytics_repository=_FakeAnalytics(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/analytics", headers=_AUTH)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["totals"]["expense"] == "42.00"
        assert body["totals"]["income"] == "1500.00"
        assert body["expenseByCategory"][0]["name"] == "Продукты"
        assert body["incomeByCategory"][0]["name"] == "Зарплата"
        assert len(body["trend"]["points"]) == 7

    asyncio.run(scenario())


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic User")


class _FakeAnalytics:
    async def analyse_current_month(self, *, user_id: UUID) -> AnalyticsResponse:
        del user_id
        return _to_contract(
            build_analytics(
                account=_account(),
                operations=(
                    _operation(1, amount="42.00"),
                    _operation(
                        2,
                        amount="1500.00",
                        direction="income",
                        category_id=_SALARY,
                        category_name="Зарплата",
                    ),
                ),
                generated_at=_GENERATED_AT,
            )
        )


class _ExplodingAnalytics:
    async def analyse_current_month(self, *, user_id: UUID) -> AnalyticsResponse:
        del user_id
        raise AnalyticsUnavailable("Продукты 42.00 leaked through an exception")
