from __future__ import annotations

from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

import pytest

from mobile_finance_api.home_projection import (
    HomeProjectionInvariantError,
    ProjectionAccount,
    ProjectionOperation,
    build_current_home_revision,
)
from mobile_finance_api.models import HomeBalance, HomeTransaction

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_GENERATED_AT = datetime(2026, 7, 28, 12, tzinfo=UTC)


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
    **changes: object,
) -> ProjectionOperation:
    values: dict[str, object] = {
        "operation_id": UUID(f"00000000-0000-4000-8000-{number:012d}"),
        "user_id": _USER_ID,
        "account_id": _ACCOUNT_ID,
        "operation_type": "expense",
        "amount": Decimal("10.00"),
        "currency": "EUR",
        "category": "Synthetic category",
        "merchant": "Synthetic merchant",
        "occurred_on": date(2026, 7, 28),
        "occurred_at": None,
        "captured_timezone": "Europe/Berlin",
        "status": "confirmed",
        "created_at": datetime(2026, 7, 28, 10, number, tzinfo=UTC),
    }
    values.update(changes)
    return ProjectionOperation(**values)  # type: ignore[arg-type]


@pytest.mark.parametrize("opening", ["125.50", "0", "-75.25"])
def test_opening_balance_is_stock_only(opening: str) -> None:
    revision = build_current_home_revision(
        account=_account(opening_balance=Decimal(opening)),
        operations=(),
        generated_at=_GENERATED_AT,
    )

    assert revision.balance_amount == Decimal(opening)
    assert revision.month_income == 0
    assert revision.month_expense == 0
    assert revision.month_net_flow == 0
    assert revision.trend_total == 0
    assert revision.recent_transactions == ()


def test_balance_month_trend_and_recent_are_exact_and_deterministic() -> None:
    operations = (
        _operation(
            1,
            operation_type="income",
            amount=Decimal("200.00"),
            occurred_on=date(2026, 6, 20),
            occurred_at=datetime(2026, 6, 20, 9, tzinfo=UTC),
            created_at=datetime(2026, 6, 20, 10, tzinfo=UTC),
        ),
        _operation(
            2,
            amount=Decimal("25.25"),
            occurred_on=date(2026, 7, 22),
            occurred_at=datetime(2026, 7, 22, 18, tzinfo=UTC),
            created_at=datetime(2026, 7, 22, 19, tzinfo=UTC),
        ),
        _operation(
            3,
            operation_type="income",
            amount=Decimal("100.00"),
            occurred_on=date(2026, 7, 27),
            occurred_at=None,
            merchant=None,
            category=None,
            created_at=datetime(2026, 7, 27, 20, tzinfo=UTC),
        ),
        _operation(
            4,
            amount=Decimal("35.00"),
            occurred_on=date(2026, 7, 27),
            occurred_at=datetime(2026, 7, 27, 12, tzinfo=UTC),
            created_at=datetime(2026, 7, 27, 20, 1, tzinfo=UTC),
        ),
    )

    first = build_current_home_revision(
        account=_account(),
        operations=operations,
        generated_at=_GENERATED_AT,
    )
    reordered = build_current_home_revision(
        account=_account(),
        operations=tuple(reversed(operations)),
        generated_at=_GENERATED_AT,
    )

    assert first == reordered
    assert first.balance_amount == Decimal("1239.75")
    assert first.month_income == Decimal("100.00")
    assert first.month_expense == Decimal("60.25")
    assert first.month_net_flow == Decimal("39.75")
    assert first.balance_delta_amount == Decimal("39.75")
    assert first.balance_delta_percent == Decimal("3.31")
    assert [point.point_date for point in first.trend_points] == [
        date(2026, 7, day) for day in range(22, 29)
    ]
    assert [point.amount for point in first.trend_points] == [
        Decimal("25.25"),
        Decimal(0),
        Decimal(0),
        Decimal(0),
        Decimal(0),
        Decimal("35.00"),
        Decimal(0),
    ]
    assert first.trend_total == Decimal("60.25")
    assert [item.transaction_id for item in first.recent_transactions] == [
        str(operations[3].operation_id),
        str(operations[2].operation_id),
        str(operations[1].operation_id),
    ]
    assert first.recent_transactions[1].occurred_at is None
    assert first.recent_transactions[1].title is None
    assert first.recent_transactions[1].category is None
    assert first.recent_transactions[0].amount == Decimal("-35.00")


def test_zero_comparison_balance_never_invents_a_percentage() -> None:
    revision = build_current_home_revision(
        account=_account(opening_balance=Decimal(0)),
        operations=(_operation(1, operation_type="income", amount=Decimal("50.00")),),
        generated_at=_GENERATED_AT,
    )

    assert revision.balance_delta_percent is None
    assert (
        "balance_delta_percent_unavailable_zero_base",
        "balanceDeltaPercent",
    ) in {(warning.code, warning.block) for warning in revision.warnings}


def test_opening_mid_month_marks_percent_and_coverage_partial() -> None:
    revision = build_current_home_revision(
        account=_account(
            opening_balance_on=date(2026, 7, 26),
            created_at=datetime(2026, 7, 26, 8, tzinfo=UTC),
        ),
        operations=(),
        generated_at=_GENERATED_AT,
    )

    assert revision.balance_delta_percent is None
    assert {warning.code for warning in revision.warnings} == {
        "balance_delta_percent_unavailable_partial_period",
        "month_summary_partial_after_opening_balance",
        "trend_partial_before_opening_balance",
    }


def test_legacy_unallocated_operation_is_excluded_and_visible_as_warning() -> None:
    legacy = _operation(
        1,
        account_id=None,
        amount=Decimal("999.00"),
        merchant="Never projected",
    )
    revision = build_current_home_revision(
        account=_account(),
        operations=(legacy,),
        generated_at=_GENERATED_AT,
    )

    assert revision.balance_amount == Decimal("1000.00")
    assert revision.month_expense == 0
    assert revision.recent_transactions == ()
    assert "legacy_unallocated_operations_excluded" in {
        warning.code for warning in revision.warnings
    }


@pytest.mark.parametrize(
    "changes",
    [
        {"user_id": UUID("99999999-9999-4999-8999-999999999999")},
        {"currency": "USD"},
        {"occurred_on": date(2026, 5, 31)},
    ],
)
def test_inconsistent_allocated_operation_fails_closed(
    changes: dict[str, object],
) -> None:
    with pytest.raises(HomeProjectionInvariantError):
        build_current_home_revision(
            account=_account(),
            operations=(_operation(1, **changes),),
            generated_at=_GENERATED_AT,
        )


def test_another_wallets_operation_is_not_this_wallets_business() -> None:
    """It used to fail closed, when a user could only own one account.

    A user may now hold several wallets, one currency each (ADR 0029), and an
    operation naming another one belongs to that wallet's revision. It cannot
    name a wallet that does not exist: the database enforces that with a
    composite foreign key.
    """

    revision = build_current_home_revision(
        account=_account(),
        operations=(
            _operation(
                1,
                account_id=UUID("99999999-9999-4999-8999-999999999999"),
                currency="UAH",
            ),
        ),
        generated_at=_GENERATED_AT,
    )

    assert revision.balance_amount == _account().opening_balance
    assert revision.month_income == 0
    assert revision.month_expense == 0


def test_home_contract_serializes_explicit_unknown_values_without_fabrication() -> None:
    balance = HomeBalance(
        amount=Decimal(50),
        deltaAmount=Decimal(50),
        deltaPercent=None,
    )
    transaction = HomeTransaction(
        id="synthetic-operation",
        title=None,
        category=None,
        occurredOn=date(2026, 7, 27),
        occurredAt=None,
        amount=Decimal(-35),
        currency="EUR",
        direction="expense",
        status="confirmed",
    )

    assert balance.model_dump(mode="json", by_alias=True)["deltaPercent"] is None
    payload = transaction.model_dump(mode="json", by_alias=True)
    assert payload["occurredOn"] == "2026-07-27"
    assert payload["occurredAt"] is None
    assert payload["title"] is None
    assert payload["category"] is None
