"""The windows analytics can report, and what each compares against.

One definition of a period, shared with the Home projection (ADR 0021): two
definitions is how two screens start disagreeing about the same month.
"""

from __future__ import annotations

from datetime import UTC, date, datetime

import pytest

from mobile_finance_api.home_projection import (
    ReportingPeriodKind,
    preceding_period,
    reporting_period,
    resolved_period,
)

_BERLIN = "Europe/Berlin"


def _at(moment: datetime, kind: ReportingPeriodKind, **bounds: date):
    return resolved_period(
        kind=kind, timezone_name=_BERLIN, generated_at=moment, **bounds
    )


_AUGUST = datetime(2026, 8, 22, 9, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    ("kind", "start", "end"),
    [
        ("last_7_days", date(2026, 8, 16), date(2026, 8, 22)),
        ("month", date(2026, 8, 1), date(2026, 8, 31)),
        ("quarter", date(2026, 7, 1), date(2026, 9, 30)),
        ("year", date(2026, 1, 1), date(2026, 12, 31)),
    ],
)
def test_each_window_resolves_to_its_calendar_bounds(
    kind: ReportingPeriodKind, start: date, end: date
) -> None:
    period = _at(_AUGUST, kind)

    assert (period.period_start, period.period_end) == (start, end)


def test_a_window_never_reports_beyond_today() -> None:
    """The future holds no committed operations; showing it as zero would read
    as a fact rather than an absence."""

    for kind in ("month", "quarter", "year"):
        assert _at(_AUGUST, kind).cutoff_local_date == date(2026, 8, 22)


def test_the_month_window_is_the_one_home_projects() -> None:
    """Analytics and Home must never disagree about which month it is."""

    shared = reporting_period(timezone_name=_BERLIN, generated_at=_AUGUST)

    assert _at(_AUGUST, "month") == shared


@pytest.mark.parametrize(
    ("kind", "moment", "start", "end"),
    [
        # A calendar window steps calendrically. Subtracting "the same number
        # of days" would put February's comparison in January.
        (
            "month",
            datetime(2026, 3, 10, 9, 0, tzinfo=UTC),
            date(2026, 2, 1),
            date(2026, 2, 28),
        ),
        (
            "month",
            datetime(2026, 1, 10, 9, 0, tzinfo=UTC),
            date(2025, 12, 1),
            date(2025, 12, 31),
        ),
        # Q3 has 92 days and Q2 has 91, so day arithmetic loses a day here too.
        ("quarter", _AUGUST, date(2026, 4, 1), date(2026, 6, 30)),
        ("year", _AUGUST, date(2025, 1, 1), date(2025, 12, 31)),
        # A rolling window has no calendar to follow.
        ("last_7_days", _AUGUST, date(2026, 8, 9), date(2026, 8, 15)),
    ],
)
def test_the_compared_window_has_the_same_shape(
    kind: ReportingPeriodKind, moment: datetime, start: date, end: date
) -> None:
    previous = preceding_period(_at(moment, kind), kind=kind)

    assert (previous.period_start, previous.period_end) == (start, end)
    # A past window has no future to trim.
    assert previous.cutoff_local_date == end


def test_a_custom_window_compares_against_the_same_length_before_it() -> None:
    period = _at(
        _AUGUST, "custom", from_date=date(2026, 7, 1), to_date=date(2026, 7, 15)
    )
    previous = preceding_period(period, kind="custom")

    assert (previous.period_start, previous.period_end) == (
        date(2026, 6, 16),
        date(2026, 6, 30),
    )


def test_a_custom_window_needs_both_bounds_in_order() -> None:
    for bounds in (
        {},
        {"from_date": date(2026, 7, 1)},
        {"to_date": date(2026, 7, 1)},
        {"from_date": date(2026, 7, 16), "to_date": date(2026, 7, 1)},
    ):
        with pytest.raises(ValueError):
            _at(_AUGUST, "custom", **bounds)  # type: ignore[arg-type]


def test_the_window_is_local_not_utc() -> None:
    """22:30 UTC is already the next day in Berlin, and a month can turn on it."""

    period = _at(datetime(2026, 7, 31, 22, 30, tzinfo=UTC), "month")

    assert period.period_start == date(2026, 8, 1)
