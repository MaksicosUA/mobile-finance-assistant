"""The calendar arithmetic of a repeating planned cost (ADR 0025).

February is the whole difficulty. A monthly rule anchored on the 31st has to
land somewhere every month, and the choice recorded in the ADR is the last day
of the month — computed from the stored anchor, never from where the previous
month landed.
"""

from __future__ import annotations

from calendar import monthrange
from datetime import date

import pytest

from mobile_finance_api.planned_cost_recurrence import (
    MAX_PLANNED_ON,
    add_months,
    clamp_day_into_month,
    horizon_end,
    monthly_occurrences,
)


def _monthly(
    day_of_month: int,
    *,
    starts_on: date,
    through: date,
    ends_on: date | None = None,
    limit: int = 24,
) -> tuple[date, ...]:
    return monthly_occurrences(
        day_of_month=day_of_month,
        starts_on=starts_on,
        ends_on=ends_on,
        through=through,
        limit=limit,
    )


# --- clamping one month -------------------------------------------------------


def test_february_has_no_31st_so_the_month_shortens_it() -> None:
    assert clamp_day_into_month(year=2026, month=2, day_of_month=31) == date(
        2026, 2, 28
    )


def test_a_leap_february_keeps_its_29th() -> None:
    assert clamp_day_into_month(year=2028, month=2, day_of_month=31) == date(
        2028, 2, 29
    )
    assert clamp_day_into_month(year=2028, month=2, day_of_month=29) == date(
        2028, 2, 29
    )


def test_a_thirty_day_month_shortens_the_31st_too() -> None:
    """February is the famous case; April, June, September and November count."""

    for month in (4, 6, 9, 11):
        assert clamp_day_into_month(year=2026, month=month, day_of_month=31) == date(
            2026, month, 30
        )


def test_a_day_that_fits_is_never_moved() -> None:
    for month in range(1, 13):
        assert clamp_day_into_month(year=2026, month=month, day_of_month=28) == date(
            2026, month, 28
        )


def test_an_impossible_anchor_is_refused() -> None:
    with pytest.raises(ValueError):
        clamp_day_into_month(year=2026, month=1, day_of_month=32)
    with pytest.raises(ValueError):
        clamp_day_into_month(year=2026, month=1, day_of_month=0)


# --- the drift this design exists to prevent ----------------------------------


def test_the_31st_returns_to_the_31st_after_february() -> None:
    """The regression that clamping iteratively would cause.

    Deriving each occurrence from the previous one turns 31 January into 28
    February and then keeps every later month on the 28th — the rule silently
    leaves the day the user chose and never comes back.
    """

    occurrences = _monthly(
        31,
        starts_on=date(2026, 1, 1),
        through=date(2026, 6, 30),
    )

    assert occurrences == (
        date(2026, 1, 31),
        date(2026, 2, 28),
        date(2026, 3, 31),
        date(2026, 4, 30),
        date(2026, 5, 31),
        date(2026, 6, 30),
    )


def test_the_29th_survives_a_non_leap_february() -> None:
    occurrences = _monthly(
        29,
        starts_on=date(2026, 1, 1),
        through=date(2026, 4, 30),
    )

    assert occurrences == (
        date(2026, 1, 29),
        date(2026, 2, 28),
        date(2026, 3, 29),
        date(2026, 4, 29),
    )


def test_the_31st_is_the_last_day_of_every_month() -> None:
    """The claim the interface rests on (ADR 0025).

    Because clamping already lands on the month end, «31-е» and «последний день
    месяца» are the same schedule, so the UI can offer the second wording
    without a second concept in storage.
    """

    occurrences = _monthly(
        31,
        starts_on=date(2028, 1, 1),
        through=date(2028, 12, 31),
    )

    assert len(occurrences) == 12
    for occurrence in occurrences:
        last_day = monthrange(occurrence.year, occurrence.month)[1]
        assert occurrence.day == last_day


def test_occurrences_strictly_increase() -> None:
    occurrences = _monthly(
        31,
        starts_on=date(2026, 1, 1),
        through=date(2027, 12, 31),
    )

    assert list(occurrences) == sorted(set(occurrences))


# --- bounds -------------------------------------------------------------------


def test_the_anchor_already_past_inside_the_first_month_is_skipped() -> None:
    occurrences = _monthly(
        5,
        starts_on=date(2026, 3, 20),
        through=date(2026, 5, 31),
    )

    assert occurrences == (date(2026, 4, 5), date(2026, 5, 5))


def test_the_anchor_still_ahead_inside_the_first_month_counts() -> None:
    occurrences = _monthly(
        20,
        starts_on=date(2026, 3, 20),
        through=date(2026, 4, 30),
    )

    assert occurrences == (date(2026, 3, 20), date(2026, 4, 20))


def test_the_horizon_truncates_the_series() -> None:
    occurrences = _monthly(
        10,
        starts_on=date(2026, 1, 1),
        through=date(2026, 3, 9),
    )

    assert occurrences == (date(2026, 1, 10), date(2026, 2, 10))


def test_an_end_date_truncates_the_series() -> None:
    occurrences = _monthly(
        10,
        starts_on=date(2026, 1, 1),
        ends_on=date(2026, 2, 28),
        through=date(2026, 12, 31),
    )

    assert occurrences == (date(2026, 1, 10), date(2026, 2, 10))


def test_an_end_date_before_the_start_yields_nothing() -> None:
    """Validation refuses such a rule; the generator simply has no opinion."""

    assert (
        _monthly(
            10,
            starts_on=date(2026, 5, 1),
            ends_on=date(2026, 1, 1),
            through=date(2026, 12, 31),
        )
        == ()
    )


def test_the_limit_caps_a_long_window() -> None:
    occurrences = _monthly(
        1,
        starts_on=date(2026, 1, 1),
        through=date(2030, 1, 1),
        limit=3,
    )

    assert occurrences == (date(2026, 1, 1), date(2026, 2, 1), date(2026, 3, 1))


def test_the_series_stops_at_the_supported_calendar() -> None:
    occurrences = _monthly(
        31,
        starts_on=date(2100, 10, 1),
        through=date(2101, 12, 31),
        limit=24,
    )

    assert occurrences == (
        date(2100, 10, 31),
        date(2100, 11, 30),
        date(2100, 12, 31),
    )
    assert all(occurrence <= MAX_PLANNED_ON for occurrence in occurrences)


# --- the horizon itself -------------------------------------------------------


def test_the_horizon_reaches_three_months_ahead() -> None:
    assert horizon_end(today=date(2026, 1, 15)) == date(2026, 4, 15)


def test_the_horizon_clamps_its_own_day_too() -> None:
    """Run on 31 December, three months ahead is 31 March; on 30 November it is
    the end of February."""

    assert horizon_end(today=date(2026, 12, 31)) == date(2027, 3, 31)
    assert horizon_end(today=date(2025, 11, 30)) == date(2026, 2, 28)


def test_the_horizon_never_leaves_the_supported_calendar() -> None:
    assert horizon_end(today=date(2100, 12, 1)) == MAX_PLANNED_ON


def test_adding_months_crosses_a_year_boundary() -> None:
    assert add_months(anchor=date(2026, 11, 30), months=3) == date(2027, 2, 28)
    assert add_months(anchor=date(2026, 1, 31), months=-1) == date(2025, 12, 31)
