from __future__ import annotations

import asyncio
import hashlib
import json
import logging
from contextlib import asynccontextmanager
from datetime import UTC, date, datetime
from decimal import ROUND_HALF_EVEN, Decimal
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from httpx import ASGITransport, AsyncClient

from mobile_finance_api import projector_runtime
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.home_projection import (
    HomeProjectionInvariantError,
    ProjectedHomeRevision,
    ProjectionAccount,
    ProjectionOperation,
    build_current_home_revision,
    percent_at_its_scale,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.models import (
    HomeBalance,
    HomeMonthSummary,
    HomeResponse,
    HomeTransaction,
    HomeTrend,
    HomeUser,
    HomeV1Response,
)
from mobile_finance_api.postgres_home_projector import (
    PostgresHomeProjector,
    ProjectionCycleResult,
)
from mobile_finance_api.postgres_home_repository import _validate_temporal_projection
from mobile_finance_api.projector_supervision import (
    EventRetryPolicy,
    RevisionRetentionPolicy,
)
from mobile_finance_api.repository import SyntheticHomeRepository

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_OTHER_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_OTHER_ACCOUNT_ID = UUID("44444444-4444-4444-8444-444444444444")
_REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


def _account(
    *,
    opening_balance: str = "100.00",
    opening_balance_on: date = date(2026, 6, 1),
    opening_timezone: str = "Europe/Berlin",
    created_at: datetime = datetime(2026, 6, 1, 8, tzinfo=UTC),
) -> ProjectionAccount:
    return ProjectionAccount(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency="EUR",
        opening_balance=Decimal(opening_balance),
        opening_balance_on=opening_balance_on,
        opening_timezone=opening_timezone,
        status="active",
        is_default=True,
        created_at=created_at,
    )


def _operation(
    operation_number: int,
    *,
    operation_type: str = "expense",
    amount: str = "1.00",
    occurred_on: date = date(2026, 7, 1),
    occurred_at: datetime | None = None,
    captured_timezone: str = "Europe/Berlin",
    created_at: datetime = datetime(2026, 7, 1, 12, tzinfo=UTC),
    account_id: UUID | None = _ACCOUNT_ID,
    user_id: UUID = _USER_ID,
    currency: str = "EUR",
    category: str | None = "Продукты",
    merchant: str | None = "Магазин",
    status: str = "confirmed",
) -> ProjectionOperation:
    return ProjectionOperation(
        operation_id=UUID(int=operation_number),
        user_id=user_id,
        account_id=account_id,
        operation_type=operation_type,
        amount=Decimal(amount),
        currency=currency,
        category=category,
        merchant=merchant,
        occurred_on=occurred_on,
        occurred_at=occurred_at,
        captured_timezone=captured_timezone,
        status=status,
        created_at=created_at,
    )


def _warning_codes(revision: ProjectedHomeRevision) -> set[str]:
    return {warning.code for warning in revision.warnings}


def test_opening_stock_prior_ledger_and_current_month_use_decimal_formulas() -> None:
    account = _account(opening_balance="100.25")
    operations = (
        _operation(
            1,
            operation_type="income",
            amount="50.00",
            occurred_on=date(2026, 6, 15),
        ),
        _operation(2, amount="20.00", occurred_on=date(2026, 6, 20)),
        _operation(
            3,
            operation_type="income",
            amount="40.00",
            occurred_on=date(2026, 7, 2),
        ),
        _operation(4, amount="5.25", occurred_on=date(2026, 7, 3)),
    )

    revision = build_current_home_revision(
        account=account,
        operations=operations,
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_amount == Decimal("165.00")
    assert revision.month_income == Decimal("40.00")
    assert revision.month_expense == Decimal("5.25")
    assert revision.month_net_flow == Decimal("34.75")
    assert revision.balance_delta_amount == Decimal("34.75")
    expected_percent = (Decimal("34.75") / Decimal("130.25") * 100).quantize(
        Decimal("0.01"),
        rounding=ROUND_HALF_EVEN,
    )
    assert revision.balance_delta_percent == expected_percent
    assert revision.period_start == date(2026, 7, 1)
    assert revision.period_end == date(2026, 7, 31)
    assert revision.generated_at == datetime(2026, 7, 28, 10, tzinfo=UTC)
    assert revision.data_as_of == revision.generated_at


def test_home_read_validators_preserve_numeric_38_18_precision() -> None:
    maximum = Decimal("99999999999999999999.999999999999999999")
    summary = HomeMonthSummary(
        from_=date(2026, 7, 1),
        to=date(2026, 7, 31),
        income=maximum,
        expense=Decimal("0.000000000000000001"),
        net_flow=Decimal("99999999999999999999.999999999999999998"),
    )
    assert summary.net_flow == Decimal("99999999999999999999.999999999999999998")

    point_amount = Decimal("33333333333333333333.333333333333333333")
    trend_points = tuple(
        SimpleNamespace(
            point_date=date(2026, 7, 22 + offset),
            amount=point_amount if offset < 3 else Decimal(0),
        )
        for offset in range(7)
    )
    _validate_temporal_projection(
        snapshot=SimpleNamespace(
            generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
            trend_metric="expense",
            trend_period="7d",
            trend_total=maximum,
        ),
        timezone=ZoneInfo("Europe/Berlin"),
        trend_points=trend_points,
        transactions=(),
    )


def test_projector_preserves_numeric_38_18_precision_beyond_default_context() -> None:
    revision = build_current_home_revision(
        account=_account(opening_balance="99999999999999999998.999999999999999999"),
        operations=(
            _operation(
                1,
                operation_type="income",
                amount="0.000000000000000001",
                occurred_on=date(2026, 7, 10),
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_amount == Decimal("99999999999999999999.000000000000000000")


@pytest.mark.parametrize(
    ("opening_balance", "operation_type"),
    [
        ("99999999999999999999.999999999999999999", "income"),
        ("-99999999999999999999.999999999999999999", "expense"),
    ],
)
def test_projector_rejects_numeric_38_18_aggregate_overflow(
    opening_balance: str,
    operation_type: str,
) -> None:
    with pytest.raises(
        HomeProjectionInvariantError,
        match="projection decimal exceeds authoritative storage bounds",
    ):
        build_current_home_revision(
            account=_account(opening_balance=opening_balance),
            operations=(
                _operation(
                    1,
                    operation_type=operation_type,
                    amount="0.000000000000000001",
                    occurred_on=date(2026, 7, 10),
                ),
            ),
            generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
        )


@pytest.mark.parametrize(
    ("opening_balance", "month_income", "expected_percent", "has_warning"),
    [
        ("0", "10", None, True),
        ("0", "0", None, True),
        ("100", "10", Decimal("10.00"), False),
        ("-100", "10", Decimal("10.00"), False),
    ],
)
def test_delta_percentage_uses_absolute_baseline_and_null_for_zero(
    opening_balance: str,
    month_income: str,
    expected_percent: Decimal | None,
    has_warning: bool,
) -> None:
    operations = (
        ()
        if month_income == "0"
        else (
            _operation(
                1,
                operation_type="income",
                amount=month_income,
                occurred_on=date(2026, 7, 10),
            ),
        )
    )

    revision = build_current_home_revision(
        account=_account(opening_balance=opening_balance),
        operations=operations,
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_delta_percent == expected_percent
    warning_present = "balance_delta_percent_unavailable_zero_base" in _warning_codes(
        revision
    )
    assert warning_present is has_warning


def test_delta_percentage_rounds_half_even_to_two_decimal_places() -> None:
    revision = build_current_home_revision(
        account=_account(opening_balance="32"),
        operations=(
            _operation(
                1,
                operation_type="income",
                amount="1",
                occurred_on=date(2026, 7, 10),
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_delta_percent == Decimal("3.12")


def test_opening_after_month_start_publishes_partial_period_warnings() -> None:
    revision = build_current_home_revision(
        account=_account(
            opening_balance="25",
            opening_balance_on=date(2026, 7, 10),
            created_at=datetime(2026, 7, 10, 8, tzinfo=UTC),
        ),
        operations=(
            _operation(
                1,
                operation_type="income",
                amount="10",
                occurred_on=date(2026, 7, 11),
                created_at=datetime(2026, 7, 11, 12, tzinfo=UTC),
            ),
            _operation(
                2,
                amount="3",
                occurred_on=date(2026, 7, 12),
                created_at=datetime(2026, 7, 12, 12, tzinfo=UTC),
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_amount == Decimal(32)
    assert revision.month_income == Decimal(10)
    assert revision.month_expense == Decimal(3)
    assert revision.balance_delta_percent is None
    assert {
        "balance_delta_percent_unavailable_partial_period",
        "month_summary_partial_after_opening_balance",
    } <= _warning_codes(revision)


def test_seven_day_expense_trend_zero_fills_across_month_and_dst_boundary() -> None:
    created_at = datetime(2026, 3, 30, 10, tzinfo=UTC)
    operations = (
        _operation(
            1,
            amount="1",
            occurred_on=date(2026, 3, 27),
            created_at=created_at,
        ),
        _operation(
            2,
            amount="2",
            occurred_on=date(2026, 3, 28),
            occurred_at=datetime(2026, 3, 29, 6, 30, tzinfo=UTC),
            captured_timezone="America/Los_Angeles",
            created_at=created_at,
        ),
        _operation(
            3,
            amount="3",
            occurred_on=date(2026, 3, 29),
            occurred_at=datetime(2026, 3, 29, 1, 30, tzinfo=UTC),
            created_at=created_at,
        ),
        _operation(
            4,
            operation_type="income",
            amount="100",
            occurred_on=date(2026, 4, 1),
            created_at=created_at,
        ),
        _operation(
            5,
            amount="4",
            occurred_on=date(2026, 4, 2),
            created_at=created_at,
        ),
    )
    revision = build_current_home_revision(
        account=_account(
            opening_balance_on=date(2026, 3, 1),
            created_at=datetime(2026, 3, 1, 8, tzinfo=UTC),
        ),
        operations=operations,
        generated_at=datetime(2026, 4, 2, 12, tzinfo=UTC),
    )

    assert [point.point_date for point in revision.trend_points] == [
        date(2026, 3, 27),
        date(2026, 3, 28),
        date(2026, 3, 29),
        date(2026, 3, 30),
        date(2026, 3, 31),
        date(2026, 4, 1),
        date(2026, 4, 2),
    ]
    assert [point.amount for point in revision.trend_points] == [
        Decimal(1),
        Decimal(2),
        Decimal(3),
        Decimal(0),
        Decimal(0),
        Decimal(0),
        Decimal(4),
    ]
    assert revision.trend_total == Decimal(10)
    assert revision.month_income == Decimal(100)
    assert revision.month_expense == Decimal(4)


def test_trend_marks_dates_before_the_opening_baseline_as_partial() -> None:
    revision = build_current_home_revision(
        account=_account(
            opening_balance_on=date(2026, 7, 25),
            created_at=datetime(2026, 7, 25, 8, tzinfo=UTC),
        ),
        operations=(),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert len(revision.trend_points) == 7
    assert all(point.amount == 0 for point in revision.trend_points)
    assert "trend_partial_before_opening_balance" in _warning_codes(revision)


def test_recent_transactions_are_nullable_and_deterministically_sorted() -> None:
    common_created_at = datetime(2026, 7, 27, 15, tzinfo=UTC)
    operations = (
        _operation(
            1,
            operation_type="income",
            amount="10",
            occurred_on=date(2026, 7, 27),
            occurred_at=datetime(2026, 7, 27, 10, tzinfo=UTC),
            created_at=common_created_at,
            merchant="Зарплата",
            category="Доход",
        ),
        _operation(
            2,
            amount="5",
            occurred_on=date(2026, 7, 27),
            occurred_at=datetime(2026, 7, 27, 9, tzinfo=UTC),
            created_at=common_created_at,
            merchant="Кофейня",
            category="Кафе",
        ),
        _operation(
            3,
            amount="1",
            occurred_on=date(2026, 7, 27),
            created_at=common_created_at,
        ),
        _operation(
            4,
            amount="2",
            occurred_on=date(2026, 7, 27),
            created_at=common_created_at,
            merchant=None,
            category=None,
        ),
        _operation(5, amount="50", occurred_on=date(2026, 7, 26)),
    )

    forward = build_current_home_revision(
        account=_account(),
        operations=operations,
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )
    reversed_input = build_current_home_revision(
        account=_account(),
        operations=tuple(reversed(operations)),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert forward == reversed_input
    assert [
        transaction.transaction_id for transaction in forward.recent_transactions
    ] == [
        str(UUID(int=1)),
        str(UUID(int=2)),
        str(UUID(int=4)),
    ]
    assert [transaction.amount for transaction in forward.recent_transactions] == [
        Decimal(10),
        Decimal(-5),
        Decimal(-2),
    ]
    date_only = forward.recent_transactions[2]
    assert date_only.occurred_on == date(2026, 7, 27)
    assert date_only.occurred_at is None
    assert date_only.title is None
    assert date_only.category is None


def test_exact_time_later_on_same_occurred_on_does_not_change_eligibility() -> None:
    operation = _operation(
        1,
        amount="5",
        occurred_on=date(2026, 7, 28),
        occurred_at=datetime(2026, 7, 28, 18, tzinfo=UTC),
        created_at=datetime(2026, 7, 28, 8, tzinfo=UTC),
    )

    revision = build_current_home_revision(
        account=_account(),
        operations=(operation,),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_amount == Decimal(95)
    assert revision.month_expense == Decimal(5)
    assert [row.transaction_id for row in revision.recent_transactions] == [
        str(operation.operation_id)
    ]


def test_future_occurred_on_is_excluded_until_canonical_date_reconciliation() -> None:
    future_operation = _operation(
        1,
        operation_type="income",
        amount="25",
        occurred_on=date(2026, 7, 29),
        created_at=datetime(2026, 7, 27, 12, tzinfo=UTC),
    )

    before = build_current_home_revision(
        account=_account(),
        operations=(future_operation,),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )
    after = build_current_home_revision(
        account=_account(),
        operations=(future_operation,),
        generated_at=datetime(2026, 7, 29, 10, tzinfo=UTC),
    )

    assert before.balance_amount == Decimal(100)
    assert before.month_income == 0
    assert before.recent_transactions == ()
    assert after.balance_amount == Decimal(125)
    assert after.month_income == Decimal(25)
    assert [row.transaction_id for row in after.recent_transactions] == [
        str(future_operation.operation_id)
    ]


def test_legacy_unallocated_operations_are_excluded_and_reported() -> None:
    revision = build_current_home_revision(
        account=_account(),
        operations=(
            _operation(1, amount="5", occurred_on=date(2026, 7, 10)),
            _operation(
                2,
                operation_type="income",
                amount="999",
                occurred_on=date(2026, 7, 10),
                account_id=None,
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert revision.balance_amount == Decimal(95)
    assert revision.month_income == 0
    assert revision.month_expense == Decimal(5)
    assert [row.transaction_id for row in revision.recent_transactions] == [
        str(UUID(int=1))
    ]
    assert "legacy_unallocated_operations_excluded" in _warning_codes(revision)


@pytest.mark.parametrize(
    ("occurred_on", "expected_blocks"),
    [
        (date(2026, 6, 15), {"balance", "recentTransactions"}),
        (
            date(2026, 7, 10),
            {"balance", "monthSummary", "recentTransactions"},
        ),
        (
            date(2026, 7, 28),
            {"balance", "monthSummary", "trend", "recentTransactions"},
        ),
    ],
)
def test_legacy_warning_names_every_affected_home_block(
    occurred_on: date,
    expected_blocks: set[str],
) -> None:
    revision = build_current_home_revision(
        account=_account(),
        operations=(
            _operation(
                1,
                account_id=None,
                occurred_on=occurred_on,
                created_at=datetime(2026, 7, 1, 12, tzinfo=UTC),
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert {
        warning.block
        for warning in revision.warnings
        if warning.code == "legacy_unallocated_operations_excluded"
    } == expected_blocks


def test_old_legacy_operation_does_not_mark_full_recent_top_three_partial() -> None:
    revision = build_current_home_revision(
        account=_account(),
        operations=(
            _operation(1, occurred_on=date(2026, 7, 28)),
            _operation(2, occurred_on=date(2026, 7, 27)),
            _operation(3, occurred_on=date(2026, 7, 26)),
            _operation(
                4,
                account_id=None,
                occurred_on=date(2026, 7, 10),
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    legacy_blocks = {
        warning.block
        for warning in revision.warnings
        if warning.code == "legacy_unallocated_operations_excluded"
    }
    assert legacy_blocks == {"balance", "monthSummary"}
    assert [row.transaction_id for row in revision.recent_transactions] == [
        str(UUID(int=1)),
        str(UUID(int=2)),
        str(UUID(int=3)),
    ]


def test_consume_next_rescans_after_another_worker_wins_candidate_race() -> None:
    first_user = UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    second_user = UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")

    class _RacingProjector(PostgresHomeProjector):
        def __init__(self) -> None:
            self.selected_users = [first_user, second_user]
            self.projected_users: list[UUID] = []

        async def _next_candidate(  # type: ignore[no-untyped-def]
            self,
            *,
            excluded_user_ids,
        ):
            assert excluded_user_ids == set()
            if not self.selected_users:
                return None
            return SimpleNamespace(user_id=self.selected_users.pop(0))

        async def _project_user(  # type: ignore[no-untyped-def]
            self,
            user_id: UUID,
            *,
            require_pending: bool,
        ) -> bool:
            assert require_pending is True
            self.projected_users.append(user_id)
            return user_id == second_user

    async def scenario() -> None:
        projector = _RacingProjector()
        assert await projector.consume_next() is True
        assert projector.projected_users == [first_user, second_user]

    asyncio.run(scenario())


@pytest.mark.parametrize(
    "occurred_on",
    [date(2026, 5, 31), date(2026, 7, 29)],
)
def test_legacy_warning_ignores_facts_outside_the_projection_horizon(
    occurred_on: date,
) -> None:
    revision = build_current_home_revision(
        account=_account(),
        operations=(
            _operation(
                1,
                account_id=None,
                occurred_on=occurred_on,
                created_at=datetime(2026, 7, 1, 12, tzinfo=UTC),
            ),
        ),
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
    )

    assert "legacy_unallocated_operations_excluded" not in _warning_codes(revision)


@pytest.mark.parametrize(
    ("account_created_at", "operation_created_at"),
    [
        (
            datetime(2026, 7, 28, 10, 0, 1, tzinfo=UTC),
            datetime(2026, 7, 27, 12, tzinfo=UTC),
        ),
        (
            datetime(2026, 6, 1, 8, tzinfo=UTC),
            datetime(2026, 7, 28, 10, 0, 1, tzinfo=UTC),
        ),
    ],
)
def test_source_fact_newer_than_cutoff_fails_closed(
    account_created_at: datetime,
    operation_created_at: datetime,
) -> None:
    with pytest.raises(
        HomeProjectionInvariantError,
        match="projection clock precedes an authoritative fact",
    ):
        build_current_home_revision(
            account=_account(created_at=account_created_at),
            operations=(
                _operation(
                    1,
                    occurred_on=date(2026, 7, 10),
                    created_at=operation_created_at,
                ),
            ),
            generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
        )


@pytest.mark.parametrize(
    "operation",
    [
        _operation(1, user_id=_OTHER_USER_ID, merchant="Sensitive Shop"),
        _operation(3, currency="USD", merchant="Sensitive Shop"),
        _operation(4, status="pending", merchant="Sensitive Shop"),
        _operation(
            5,
            amount="12345.67",
            occurred_on=date(2026, 7, 10),
            occurred_at=datetime(2026, 7, 9, 20, tzinfo=UTC),
            merchant="Sensitive Shop",
        ),
    ],
)
def test_inconsistent_authoritative_facts_fail_with_sanitized_errors(
    operation: ProjectionOperation,
) -> None:
    with pytest.raises(HomeProjectionInvariantError) as captured:
        build_current_home_revision(
            account=_account(),
            operations=(operation,),
            generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
        )

    message = str(captured.value)
    assert "Sensitive Shop" not in message
    assert "12345.67" not in message
    assert str(_OTHER_USER_ID) not in message
    assert str(_OTHER_ACCOUNT_ID) not in message


def test_naive_source_timestamps_fail_closed_without_echoing_fact_values() -> None:
    naive = datetime(2026, 7, 27, 12)  # noqa: DTZ001 - deliberately invalid fact
    with pytest.raises(HomeProjectionInvariantError) as captured:
        build_current_home_revision(
            account=_account(),
            operations=(_operation(1, created_at=naive),),
            generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
        )

    assert str(naive) not in str(captured.value)


def test_projector_runtime_logs_only_exception_type(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    async def fail_once(
        *,
        max_cycles: int,
        heartbeat_stale_seconds: float,
        retry_policy: EventRetryPolicy,
        retention_policy: RevisionRetentionPolicy,
    ) -> None:
        del (
            max_cycles,
            heartbeat_stale_seconds,
            retry_policy,
            retention_policy,
        )
        raise RuntimeError("Sensitive Shop amount=12345.67")

    monkeypatch.setattr(projector_runtime, "_run_once", fail_once)
    with caplog.at_level(
        logging.ERROR,
        logger="mobile_finance_api.home_projector",
    ):
        exit_code = projector_runtime.main(["--once", "--max-cycles", "1"])

    assert exit_code == 1
    assert "RuntimeError" in caplog.text
    assert "Sensitive Shop" not in caplog.text
    assert "12345.67" not in caplog.text


@pytest.mark.parametrize(
    ("argument", "value"),
    [
        ("--poll-seconds", "nan"),
        ("--poll-seconds", "inf"),
        ("--poll-seconds", "-inf"),
        ("--reconcile-seconds", "nan"),
        ("--reconcile-seconds", "inf"),
        ("--reconcile-seconds", "-inf"),
    ],
)
def test_projector_runtime_rejects_non_finite_intervals(
    argument: str,
    value: str,
) -> None:
    expected = f"--{argument.removeprefix('--')} must be positive"
    with pytest.raises(SystemExit, match=expected):
        projector_runtime.main([f"{argument}={value}"])


class _StubRecurrences:
    """Stands in for the materialiser the projector leader now also runs.

    Recurrence has its own tests; here it only has to be present and quiet, so
    a cycle's shape can still be asserted without a database.
    """

    def __init__(self, **kwargs: object) -> None:
        del kwargs

    async def materialise_active_rules(self, **kwargs: object) -> int:
        del kwargs
        return 0


def test_one_shot_processes_healthy_streams_then_reports_aggregate_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[object] = []

    class _Engine:
        async def dispose(self) -> None:
            calls.append("dispose")

    class _Lease:
        async def heartbeat(self, *, status: str) -> None:
            calls.append(("heartbeat", status))

    class _Projector:
        def __init__(
            self,
            *,
            session_factory: object,
            retry_policy: EventRetryPolicy,
        ) -> None:
            assert session_factory == "synthetic-session-factory"
            assert retry_policy == EventRetryPolicy()

        async def reconcile_all(self) -> ProjectionCycleResult:
            calls.append("reconcile")
            return ProjectionCycleResult(
                published=2,
                inspected=2,
                failures_present=False,
            )

        async def drain_available(
            self,
            *,
            max_candidates: int,
        ) -> ProjectionCycleResult:
            calls.append(("drain", max_candidates))
            return ProjectionCycleResult(
                published=3,
                inspected=4,
                failures_present=True,
            )

    async def prune(**kwargs) -> int:  # type: ignore[no-untyped-def]
        del kwargs
        calls.append("prune")
        return 1

    monkeypatch.setattr(
        projector_runtime,
        "create_database",
        lambda database_url: (
            _Engine(),
            "synthetic-session-factory",
        ),
    )
    monkeypatch.setattr(
        projector_runtime,
        "require_database_url",
        lambda: "postgresql+asyncpg://synthetic.invalid/test",
    )
    monkeypatch.setattr(projector_runtime, "PostgresHomeProjector", _Projector)
    monkeypatch.setattr(
        projector_runtime,
        "PostgresPlannedCostRecurrenceRepository",
        _StubRecurrences,
    )
    monkeypatch.setattr(projector_runtime, "prune_home_revisions", prune)

    async def no_due_erasures(session_factory: object, **kwargs: object) -> int:
        # Scheduled erasure (ADR 0030) is proved against PostgreSQL elsewhere;
        # here the cycle only has to run past it.
        assert session_factory == "synthetic-session-factory"
        del kwargs
        return 0

    monkeypatch.setattr(projector_runtime, "erase_due_accounts", no_due_erasures)

    @asynccontextmanager
    async def leadership(**kwargs):  # type: ignore[no-untyped-def]
        assert isinstance(kwargs["engine"], _Engine)
        yield _Lease()

    monkeypatch.setattr(
        projector_runtime,
        "acquire_projector_leadership",
        leadership,
    )

    with pytest.raises(
        RuntimeError,
        match="one or more projection streams failed",
    ):
        asyncio.run(
            projector_runtime._run_once(
                max_cycles=7,
                heartbeat_stale_seconds=30,
                retry_policy=EventRetryPolicy(),
                retention_policy=RevisionRetentionPolicy(),
            )
        )

    assert calls[:4] == [
        ("heartbeat", "starting"),
        "reconcile",
        ("drain", 7),
        "prune",
    ]
    assert calls[-1] == "dispose"
    assert all(call == ("heartbeat", "degraded") for call in calls[4:-1])


def _nullable_home_response(*, delta_percent: Decimal | None) -> HomeResponse:
    return HomeResponse(
        generated_at=datetime(2026, 7, 28, 10, tzinfo=UTC),
        data_as_of=datetime(2026, 7, 28, 10, tzinfo=UTC),
        base_currency="EUR",
        user=HomeUser(display_name="Synthetic User"),
        balance=HomeBalance(
            amount=Decimal("95.00"),
            delta_amount=Decimal("-5.00"),
            delta_percent=delta_percent,
        ),
        month_summary=HomeMonthSummary(
            from_=date(2026, 7, 1),
            to=date(2026, 7, 31),
            income=Decimal(0),
            expense=Decimal(5),
            net_flow=Decimal(-5),
        ),
        trend=HomeTrend(
            metric="expense",
            period="7d",
            total=Decimal(5),
            points=(),
        ),
        primary_goal=None,
        upcoming_payments=(),
        recent_transactions=(
            HomeTransaction(
                id="operation-1",
                title=None,
                category=None,
                occurred_on=date(2026, 7, 27),
                occurred_at=None,
                amount=Decimal(-5),
                currency="EUR",
                direction="expense",
                status="confirmed",
            ),
        ),
        available_actions=("voice_entry",),
        warnings=(),
    )


def test_v2_preserves_nullable_authoritative_facts_and_v1_fails_closed() -> None:
    nullable_percent = _nullable_home_response(delta_percent=None)
    nullable_transaction = _nullable_home_response(delta_percent=Decimal(0))

    wire = nullable_percent.model_dump(mode="json", by_alias=True)
    assert wire["balance"]["deltaPercent"] is None
    assert wire["recentTransactions"] == [
        {
            "id": "operation-1",
            "title": None,
            "category": None,
            "occurredOn": "2026-07-27",
            "occurredAt": None,
            "amount": "-5",
            "currency": "EUR",
            "direction": "expense",
            "status": "confirmed",
        }
    ]
    with pytest.raises(ValueError, match="cannot be represented by v1"):
        HomeV1Response.from_v2(nullable_percent)
    with pytest.raises(ValueError, match="cannot be represented by v1"):
        HomeV1Response.from_v2(nullable_transaction)


def test_v1_fails_closed_when_utc_instant_would_display_another_date() -> None:
    home = _nullable_home_response(delta_percent=Decimal("1.00")).model_copy(
        update={
            "recent_transactions": (
                HomeTransaction(
                    id="operation-near-midnight",
                    title="Synthetic merchant",
                    category="Synthetic category",
                    occurred_on=date(2026, 7, 11),
                    occurred_at=datetime(2026, 7, 10, 22, 30, tzinfo=UTC),
                    amount=Decimal("-1.00"),
                    currency="EUR",
                    direction="expense",
                    status="confirmed",
                ),
            )
        }
    )

    with pytest.raises(ValueError, match="cannot be represented by v1"):
        HomeV1Response.from_v2(home)


def test_versioned_home_routes_preserve_v2_and_fail_closed_for_v1() -> None:
    async def scenario() -> None:
        app = create_app(
            home_repository=_StaticHomeRepository(
                _nullable_home_response(delta_percent=None)
            ),
            current_user_authenticator=_StaticAuthenticator(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            v2 = await client.get(
                "/api/v2/home",
                params={"period": "current_month", "timezone": "Europe/Berlin"},
                headers={"Authorization": "Bearer synthetic-token"},
            )
            v1 = await client.get(
                "/api/v1/home",
                params={"period": "current_month", "timezone": "Europe/Berlin"},
                headers={"Authorization": "Bearer synthetic-token"},
            )

        assert v2.status_code == 200, v2.text
        assert v2.json()["balance"]["deltaPercent"] is None
        assert v2.json()["recentTransactions"][0]["occurredOn"] == "2026-07-27"
        assert v2.json()["recentTransactions"][0]["occurredAt"] is None
        assert v1.status_code == 503
        assert v1.json() == {"detail": "Home temporarily unavailable"}

    asyncio.run(scenario())


def test_home_v2_cache_vary_and_etag_match_v1_endpoint_policy() -> None:
    async def scenario() -> None:
        app = create_app(
            home_repository=SyntheticHomeRepository(),
            current_user_authenticator=_StaticAuthenticator(),
        )
        params = {"period": "current_month", "timezone": "Europe/Berlin"}
        authorization = {"Authorization": "Bearer synthetic-token"}
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            representations = {}
            for path in ("/api/v1/home", "/api/v2/home"):
                response = await client.get(
                    path,
                    params=params,
                    headers=authorization,
                )
                assert response.status_code == 200, response.text
                assert response.headers["cache-control"] == "private, no-cache"
                assert response.headers["vary"].lower() == "authorization"
                etag = response.headers["etag"]
                assert len(etag) == 66 and etag.startswith('"') and etag.endswith('"')
                int(etag[1:-1], 16)

                unchanged = await client.get(
                    path,
                    params=params,
                    headers={**authorization, "If-None-Match": etag},
                )
                assert unchanged.status_code == 304
                assert unchanged.content == b""
                assert unchanged.headers["etag"] == etag
                assert unchanged.headers["cache-control"] == "private, no-cache"
                assert unchanged.headers["vary"].lower() == "authorization"
                representations[path] = (response.content, etag)

        assert representations["/api/v1/home"] != representations["/api/v2/home"]

    asyncio.run(scenario())


def test_checked_in_home_v2_schema_requires_nullable_projection_fact_fields() -> None:
    schema_path = _REPOSITORY_ROOT / "contracts/home/v2/home.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    balance = schema["properties"]["balance"]
    transaction = schema["properties"]["recentTransactions"]["items"]

    assert schema["$id"].endswith("/contracts/home/v2/home.schema.json")
    assert "deltaPercent" in balance["required"]
    assert {
        branch.get("type") for branch in balance["properties"]["deltaPercent"]["oneOf"]
    } >= {"null"}
    assert {"title", "category", "occurredOn", "occurredAt"} <= set(
        transaction["required"]
    )
    assert transaction["properties"]["occurredOn"]["$ref"] == "#/$defs/date"
    assert {
        branch.get("type") for branch in transaction["properties"]["title"]["oneOf"]
    } >= {"null"}
    assert {
        branch.get("type")
        for branch in transaction["properties"]["occurredAt"]["oneOf"]
    } >= {"null"}


def test_checked_in_home_v1_schema_is_frozen_non_nullable_contract() -> None:
    schema_path = _REPOSITORY_ROOT / "contracts/home/v1/home.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    canonical = json.dumps(
        schema,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode()
    balance = schema["properties"]["balance"]
    transaction = schema["properties"]["recentTransactions"]["items"]

    # Any semantic v1 schema edit must be an explicit compatibility decision.
    assert hashlib.sha256(canonical).hexdigest() == (
        "8bc0c8f164f8f437ca2f9098fe31a05fb9089c6f9b48f4d8e82cc39783dcb6d4"
    )
    assert schema["$id"].endswith("/contracts/home/v1/home.schema.json")
    assert balance["properties"]["deltaPercent"] == {"$ref": "#/$defs/decimal"}
    assert set(transaction["required"]) == {
        "id",
        "title",
        "category",
        "occurredAt",
        "amount",
        "currency",
        "direction",
        "status",
    }
    assert "occurredOn" not in transaction["properties"]


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(
            subject=str(_USER_ID),
            display_name="Synthetic User",
        )


class _StaticHomeRepository:
    def __init__(self, home: HomeResponse) -> None:
        self._home = home

    async def get_home(self, **_: object) -> HomeResponse:
        return self._home


def test_a_stored_percent_leaves_without_its_column_padding() -> None:
    """PostgreSQL returns -0.07 from a NUMERIC(38, 18) column with sixteen zeros.

    They reached the phone as «−0,0700000000000000%» beside the balance.
    """

    padded = Decimal("-0.070000000000000000")

    assert str(percent_at_its_scale(padded)) == "-0.07"
    assert percent_at_its_scale(padded) == padded
    assert percent_at_its_scale(None) is None
