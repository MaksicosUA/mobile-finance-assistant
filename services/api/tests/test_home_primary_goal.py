from __future__ import annotations

from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

import pytest

from mobile_finance_api.home_projection import (
    HomeProjectionInvariantError,
    ProjectionAccount,
    ProjectionGoal,
    ProjectionGoalContribution,
    ProjectionOperation,
    build_current_home_revision,
)
from mobile_finance_api.models import HomeGoal

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


def _goal(
    goal_number: int,
    *,
    title: str = "Отпуск",
    target: str = "3000.00",
    monthly: str = "250.00",
    target_on: date = date(2027, 6, 1),
    status: str = "active",
    account_id: UUID = _ACCOUNT_ID,
    user_id: UUID = _USER_ID,
    currency: str = "EUR",
    created_at: datetime = datetime(2026, 7, 1, 9, tzinfo=UTC),
) -> ProjectionGoal:
    return ProjectionGoal(
        goal_id=UUID(int=goal_number),
        user_id=user_id,
        account_id=account_id,
        title=title,
        target_amount=Decimal(target),
        monthly_contribution=Decimal(monthly),
        currency=currency,
        target_on=target_on,
        status=status,
        created_at=created_at,
    )


def _entry(
    entry_number: int,
    *,
    goal_number: int = 1,
    direction: str = "deposit",
    amount: str = "500.00",
    user_id: UUID = _USER_ID,
    created_at: datetime = datetime(2026, 7, 2, 9, tzinfo=UTC),
) -> ProjectionGoalContribution:
    return ProjectionGoalContribution(
        contribution_id=UUID(int=1000 + entry_number),
        goal_id=UUID(int=goal_number),
        user_id=user_id,
        direction=direction,
        amount=Decimal(amount),
        created_at=created_at,
    )


def _build(
    *,
    goals: tuple[ProjectionGoal, ...] = (),
    contributions: tuple[ProjectionGoalContribution, ...] = (),
    operations: tuple[ProjectionOperation, ...] = (),
):
    return build_current_home_revision(
        account=_account(),
        operations=operations,
        generated_at=_GENERATED_AT,
        goals=goals,
        goal_contributions=contributions,
    )


# --- the slot finally has a producer ---------------------------------------


def test_no_goal_leaves_the_block_empty_rather_than_invented() -> None:
    assert _build().primary_goal is None


def test_a_goal_with_no_ledger_reads_as_empty_progress() -> None:
    projection = _build(goals=(_goal(1),))
    goal = projection.primary_goal
    assert goal is not None
    assert goal.goal_id == str(UUID(int=1))
    assert goal.current_amount == Decimal(0)
    assert goal.progress_percent == Decimal(0)
    assert goal.target_amount == Decimal("3000.00")
    assert goal.monthly_contribution == Decimal("250.00")
    assert goal.due_date == date(2027, 6, 1)


def test_the_ledger_drives_current_and_progress() -> None:
    projection = _build(
        goals=(_goal(1),),
        contributions=(
            _entry(1, amount="1000.00"),
            _entry(2, amount="700.00"),
            _entry(3, direction="withdrawal", amount="200.00"),
        ),
    )
    goal = projection.primary_goal
    assert goal is not None
    assert goal.current_amount == Decimal("1500.00")
    assert goal.progress_percent == Decimal(50)


def test_another_goals_entries_are_never_counted() -> None:
    projection = _build(
        goals=(_goal(1),),
        contributions=(_entry(1, goal_number=2, amount="900.00"),),
    )
    goal = projection.primary_goal
    assert goal is not None
    assert goal.current_amount == Decimal(0)


# --- primary selection ------------------------------------------------------


def test_the_nearest_deadline_wins() -> None:
    projection = _build(
        goals=(
            _goal(1, title="Отпуск", target_on=date(2027, 6, 1)),
            _goal(2, title="Ремонт", target_on=date(2026, 9, 1)),
            _goal(3, title="Машина", target_on=date(2028, 1, 1)),
        )
    )
    goal = projection.primary_goal
    assert goal is not None
    assert goal.title == "Ремонт"


def test_an_equal_deadline_is_broken_by_creation_then_id() -> None:
    """The ordering must be total, or two projections could disagree."""

    same_day = date(2026, 9, 1)
    older = datetime(2026, 7, 1, 8, tzinfo=UTC)
    projection = _build(
        goals=(
            _goal(3, title="Третья", target_on=same_day, created_at=older),
            _goal(2, title="Вторая", target_on=same_day, created_at=older),
            _goal(1, title="Первая", target_on=same_day, created_at=older),
        )
    )
    goal = projection.primary_goal
    assert goal is not None
    assert goal.title == "Первая"


@pytest.mark.parametrize(
    "changes",
    [
        {"status": "cancelled"},
        {"account_id": _OTHER_ACCOUNT_ID},
    ],
)
def test_an_ineligible_goal_is_not_primary(changes: dict[str, object]) -> None:
    projection = _build(goals=(_goal(1, **changes),))  # type: ignore[arg-type]
    assert projection.primary_goal is None


def test_a_goal_created_after_the_cutoff_is_not_yet_visible() -> None:
    """The projection is a snapshot of facts as of `data_as_of`."""

    later = _GENERATED_AT.replace(hour=13)
    assert _build(goals=(_goal(1, created_at=later),)).primary_goal is None


def test_a_contribution_created_after_the_cutoff_is_not_yet_counted() -> None:
    projection = _build(
        goals=(_goal(1),),
        contributions=(
            _entry(1, amount="500.00"),
            _entry(2, amount="400.00", created_at=_GENERATED_AT.replace(hour=13)),
        ),
    )
    goal = projection.primary_goal
    assert goal is not None
    assert goal.current_amount == Decimal("500.00")


# --- the invariant this block must never break ------------------------------


def test_a_goal_never_touches_an_authoritative_total() -> None:
    """A contribution earmarks balance; it does not move money (ADR 0019)."""

    without = _build()
    with_goal = _build(
        goals=(_goal(1),),
        contributions=(_entry(1, amount="900.00"),),
    )
    assert with_goal.balance_amount == without.balance_amount
    assert with_goal.month_income == without.month_income
    assert with_goal.month_expense == without.month_expense
    assert with_goal.month_net_flow == without.month_net_flow
    assert with_goal.trend_total == without.trend_total
    assert with_goal.trend_points == without.trend_points
    assert with_goal.recent_transactions == without.recent_transactions


def test_progress_saturates_so_the_projection_bounds_always_hold() -> None:
    projection = _build(
        goals=(_goal(1, target="1000.00"),),
        contributions=(_entry(1, amount="2500.00"),),
    )
    goal = projection.primary_goal
    assert goal is not None
    # The amount stays honest about over-funding; only progress is capped.
    assert goal.current_amount == Decimal("2500.00")
    assert goal.progress_percent == Decimal(100)


def test_a_projected_goal_always_satisfies_the_api_contract() -> None:
    """A projection the API would reject is worse than no projection."""

    projection = _build(
        goals=(_goal(1, target="3000.00"),),
        contributions=(_entry(1, amount="1000.00"),),
    )
    goal = projection.primary_goal
    assert goal is not None
    rendered = HomeGoal.model_validate(
        {
            "id": goal.goal_id,
            "title": goal.title,
            "current": goal.current_amount,
            "target": goal.target_amount,
            "currency": goal.currency,
            "dueDate": goal.due_date,
            "progressPercent": goal.progress_percent,
            "monthlyContribution": goal.monthly_contribution,
        }
    )
    assert rendered.progress_percent <= Decimal(100)
    assert rendered.current >= 0


def test_a_repeating_ratio_still_fits_the_stored_numeric_scale() -> None:
    projection = _build(
        goals=(_goal(1, target="3.00"),),
        contributions=(_entry(1, amount="1.00"),),
    )
    goal = projection.primary_goal
    assert goal is not None
    exponent = goal.progress_percent.as_tuple().exponent
    assert isinstance(exponent, int)
    assert -exponent <= 18


# --- fail closed on corrupt source facts ------------------------------------


@pytest.mark.parametrize(
    "changes",
    [
        {"user_id": _OTHER_USER_ID},
        {"currency": "USD"},
        {"target": "0.00"},
        {"title": "   "},
    ],
)
def test_a_corrupt_goal_fails_closed(changes: dict[str, object]) -> None:
    with pytest.raises(HomeProjectionInvariantError):
        _build(goals=(_goal(1, **changes),))  # type: ignore[arg-type]


@pytest.mark.parametrize(
    "changes",
    [
        {"user_id": _OTHER_USER_ID},
        {"direction": "transfer"},
        {"amount": "0.00"},
    ],
)
def test_a_corrupt_contribution_fails_closed(changes: dict[str, object]) -> None:
    with pytest.raises(HomeProjectionInvariantError):
        _build(
            goals=(_goal(1),),
            contributions=(_entry(1, **changes),),  # type: ignore[arg-type]
        )


def test_a_ledger_that_sums_below_zero_fails_closed() -> None:
    """The write path forbids this under a row lock, so it means corruption."""

    with pytest.raises(HomeProjectionInvariantError):
        _build(
            goals=(_goal(1),),
            contributions=(
                _entry(1, amount="100.00"),
                _entry(2, direction="withdrawal", amount="150.00"),
            ),
        )
