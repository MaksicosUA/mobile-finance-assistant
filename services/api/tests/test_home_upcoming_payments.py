from __future__ import annotations

from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

import pytest
from pydantic import ValidationError

from mobile_finance_api.home_projection import (
    HomeProjectionInvariantError,
    ProjectionAccount,
    ProjectionOperation,
    ProjectionPlannedCost,
    build_current_home_revision,
)
from mobile_finance_api.models import (
    HomeBalance,
    HomeMonthSummary,
    HomePayment,
    HomeResponse,
    HomeTrend,
    HomeUser,
    HomeV1Response,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_OTHER_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_OTHER_ACCOUNT_ID = UUID("44444444-4444-4444-8444-444444444444")
# 2026-07-15 12:00 UTC is 14:00 in Europe/Berlin, so the local cutoff date is
# 2026-07-15 and the month period is July.
_GENERATED_AT = datetime(2026, 7, 15, 12, tzinfo=UTC)


def _account() -> ProjectionAccount:
    return ProjectionAccount(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency="EUR",
        opening_balance=Decimal("100.00"),
        opening_balance_on=date(2026, 6, 1),
        opening_timezone="Europe/Berlin",
        status="active",
        is_default=True,
        created_at=datetime(2026, 6, 1, 8, tzinfo=UTC),
    )


def _plan(
    plan_number: int,
    *,
    title: str = "Аренда",
    amount: str = "800.00",
    planned_on: date = date(2026, 8, 1),
    status: str = "planned",
    account_id: UUID = _ACCOUNT_ID,
    user_id: UUID = _USER_ID,
    currency: str = "EUR",
    created_at: datetime = datetime(2026, 7, 1, 9, tzinfo=UTC),
) -> ProjectionPlannedCost:
    return ProjectionPlannedCost(
        planned_cost_id=UUID(int=plan_number),
        user_id=user_id,
        account_id=account_id,
        title=title,
        amount=Decimal(amount),
        currency=currency,
        planned_on=planned_on,
        status=status,
        created_at=created_at,
    )


def _build(*plans: ProjectionPlannedCost, operations: tuple[object, ...] = ()):
    return build_current_home_revision(
        account=_account(),
        operations=operations,  # type: ignore[arg-type]
        generated_at=_GENERATED_AT,
        planned_costs=plans,
    )


def test_a_planned_cost_becomes_an_upcoming_payment() -> None:
    revision = _build(_plan(1, planned_on=date(2026, 8, 1)))
    assert len(revision.upcoming_payments) == 1
    payment = revision.upcoming_payments[0]
    assert payment.payment_id == str(UUID(int=1))
    assert payment.title == "Аренда"
    assert payment.due_on == date(2026, 8, 1)
    # A planned cost has a calendar date and no time of day (ADR 0007/0018).
    assert payment.due_at is None
    assert payment.amount == Decimal("800.00")
    assert payment.status == "scheduled"


def test_a_planned_amount_never_reaches_an_authoritative_total() -> None:
    """The decisive ADR 0018 invariant, asserted at the projection boundary."""

    without = _build()
    with_plan = _build(_plan(1, amount="9999.00"))
    assert with_plan.balance_amount == without.balance_amount
    assert with_plan.month_income == without.month_income
    assert with_plan.month_expense == without.month_expense
    assert with_plan.month_net_flow == without.month_net_flow
    assert with_plan.trend_total == without.trend_total
    assert with_plan.trend_points == without.trend_points
    assert with_plan.recent_transactions == without.recent_transactions


def test_an_outstanding_plan_whose_date_passed_reads_as_overdue() -> None:
    revision = _build(
        _plan(1, planned_on=date(2026, 7, 14)),
        _plan(2, planned_on=date(2026, 7, 15)),
        _plan(3, planned_on=date(2026, 7, 16)),
    )
    statuses = {
        payment.due_on: payment.status for payment in revision.upcoming_payments
    }
    assert statuses[date(2026, 7, 14)] == "overdue"
    # Due today is not yet overdue.
    assert statuses[date(2026, 7, 15)] == "scheduled"
    assert statuses[date(2026, 7, 16)] == "scheduled"


@pytest.mark.parametrize("settled", ["confirmed", "skipped", "cancelled"])
def test_a_settled_plan_is_not_an_obligation(settled: str) -> None:
    revision = _build(_plan(1, status=settled))
    assert revision.upcoming_payments == ()


def test_block_is_ordered_by_date_then_identifier_and_capped_at_three() -> None:
    revision = _build(
        _plan(4, planned_on=date(2026, 9, 1)),
        _plan(2, planned_on=date(2026, 8, 1)),
        _plan(1, planned_on=date(2026, 8, 1)),
        _plan(3, planned_on=date(2026, 8, 15)),
    )
    assert [payment.payment_id for payment in revision.upcoming_payments] == [
        str(UUID(int=1)),
        str(UUID(int=2)),
        str(UUID(int=3)),
    ]


def test_plans_outside_the_projected_account_are_excluded() -> None:
    revision = _build(_plan(1, account_id=_OTHER_ACCOUNT_ID))
    assert revision.upcoming_payments == ()


def test_a_plan_created_after_the_cutoff_is_not_yet_visible() -> None:
    revision = _build(
        _plan(1, created_at=datetime(2026, 7, 15, 12, 0, 1, tzinfo=UTC)),
    )
    assert revision.upcoming_payments == ()


@pytest.mark.parametrize(
    "invalid",
    [
        {"user_id": _OTHER_USER_ID},
        {"currency": "USD"},
        {"amount": "0.00"},
        {"title": "   "},
    ],
)
def test_inconsistent_planned_facts_fail_closed(invalid: dict[str, object]) -> None:
    with pytest.raises(HomeProjectionInvariantError):
        _build(_plan(1, **invalid))  # type: ignore[arg-type]


def test_an_operation_and_a_plan_coexist_without_mixing() -> None:
    operations = (
        ProjectionOperation(
            operation_id=UUID(int=90),
            user_id=_USER_ID,
            account_id=_ACCOUNT_ID,
            operation_type="expense",
            amount=Decimal("10.00"),
            currency="EUR",
            category="Продукты",
            merchant="Магазин",
            occurred_on=date(2026, 7, 2),
            occurred_at=None,
            captured_timezone="Europe/Berlin",
            status="confirmed",
            created_at=datetime(2026, 7, 2, 12, tzinfo=UTC),
        ),
    )
    revision = _build(_plan(1), operations=operations)
    assert revision.month_expense == Decimal("10.00")
    assert len(revision.recent_transactions) == 1
    assert len(revision.upcoming_payments) == 1


# --- wire contract ---------------------------------------------------------


def _home(payment: HomePayment) -> HomeResponse:
    return HomeResponse(
        generated_at=_GENERATED_AT,
        data_as_of=_GENERATED_AT,
        base_currency="EUR",
        user=HomeUser(displayName="Тест"),
        balance=HomeBalance(
            amount=Decimal("100.00"),
            deltaAmount=Decimal("0"),
            deltaPercent=Decimal("0"),
        ),
        monthSummary=HomeMonthSummary.model_validate(
            {
                "from": date(2026, 7, 1),
                "to": date(2026, 7, 31),
                "income": Decimal("0"),
                "expense": Decimal("0"),
                "netFlow": Decimal("0"),
            }
        ),
        trend=HomeTrend(metric="expense", period="7d", total=Decimal("0"), points=()),
        primaryGoal=None,
        upcomingPayments=(payment,),
        recentTransactions=(),
        availableActions=("voice_entry",),
    )


def _payment(**changes: object) -> HomePayment:
    payload: dict[str, object] = {
        "id": "payment-1",
        "title": "Аренда",
        "dueOn": date(2026, 8, 1),
        "dueAt": None,
        "amount": Decimal("800.00"),
        "currency": "EUR",
        "status": "scheduled",
    }
    payload.update(changes)
    return HomePayment.model_validate(payload)


def test_payment_requires_an_authoritative_due_date() -> None:
    assert _payment().due_on == date(2026, 8, 1)
    with pytest.raises(ValidationError):
        HomePayment.model_validate(
            {
                "id": "payment-1",
                "title": "Аренда",
                "dueAt": datetime(2026, 8, 1, tzinfo=UTC),
                "amount": Decimal("800.00"),
                "currency": "EUR",
                "status": "scheduled",
            }
        )


def test_v1_fails_closed_on_a_date_only_payment() -> None:
    # v1 cannot express an obligation without an instant, and synthesizing local
    # midnight would reintroduce exactly the fabricated time this split removes.
    with pytest.raises(ValueError, match="cannot be represented by v1"):
        HomeV1Response.from_v2(_home(_payment()))


def test_v1_still_converts_a_payment_that_carries_a_matching_instant() -> None:
    payment = _payment(dueAt=datetime(2026, 8, 1, 9, tzinfo=UTC))
    converted = HomeV1Response.from_v2(_home(payment))
    assert converted.upcoming_payments[0].due_at == datetime(2026, 8, 1, 9, tzinfo=UTC)


def test_v1_refuses_an_instant_that_disagrees_with_the_due_date() -> None:
    payment = _payment(dueAt=datetime(2026, 8, 2, 9, tzinfo=UTC))
    with pytest.raises(ValueError, match="cannot be represented by v1"):
        HomeV1Response.from_v2(_home(payment))
