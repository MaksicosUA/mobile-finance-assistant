"""The calendar arithmetic behind a repeating planned cost (ADR 0025).

Pure functions over dates: no database, no clock, no request. The set of dates a
rule must produce is a function of the rule, the horizon and today, and keeping
it that way is what lets the generator run twice, concurrently, or after a crash
without writing a duplicate.

The one rule that carries the weight: **every occurrence is clamped from the
stored anchor day, never derived from the previous occurrence.** Iterating would
turn 31 January into 28 February and then keep every later month on the 28th,
and the rule would drift off its own day and never come back.
"""

from __future__ import annotations

from calendar import monthrange
from datetime import date

#: Same supported calendar as operations and one-off plans.
MIN_PLANNED_ON = date(1900, 1, 1)
MAX_PLANNED_ON = date(2100, 12, 31)

#: How far ahead a rule materialises. Three months is enough for Home to show
#: what is coming and short enough that a rule with no end date never becomes a
#: backlog.
HORIZON_MONTHS = 3

#: A guard, not a product limit: monthly rules never approach it. It exists so a
#: future frequency cannot make one rule write an unbounded number of rows.
MAX_OCCURRENCES_PER_RULE = 12

#: The anchor days a rule may store. 29, 30 and 31 are accepted and clamped.
MIN_DAY_OF_MONTH = 1
MAX_DAY_OF_MONTH = 31


def clamp_day_into_month(*, year: int, month: int, day_of_month: int) -> date:
    """Place the anchor day inside one month, shortening it when it does not fit.

    February has no 31st, so a rule anchored there lands on the 28th — or the
    29th in a leap year. April has no 31st either; the same clamp covers both.
    """

    if not MIN_DAY_OF_MONTH <= day_of_month <= MAX_DAY_OF_MONTH:
        raise ValueError("day_of_month must be between 1 and 31")
    days_in_month = monthrange(year, month)[1]
    return date(year, month, min(day_of_month, days_in_month))


def add_months(*, anchor: date, months: int) -> date:
    """Move a date whole months, clamping the day the same way an occurrence is."""

    total = anchor.year * 12 + (anchor.month - 1) + months
    year, month = divmod(total, 12)
    return clamp_day_into_month(year=year, month=month + 1, day_of_month=anchor.day)


def horizon_end(*, today: date, months: int = HORIZON_MONTHS) -> date:
    """The last date a rule materialises into, given the local day it is run on."""

    if months < 0:
        raise ValueError("horizon must not reach into the past")
    end = add_months(anchor=today, months=months)
    return min(end, MAX_PLANNED_ON)


def earliest_occurrence(*, through: date) -> date:
    """The oldest date a run may write, given the horizon it is filling up to.

    The start of the month before today. A rule therefore keeps running however
    long it lives, because the walk begins near today and not at its first date,
    and one begun years ago does not arrive as years of overdue bills. A month
    back rather than none, so a run that was down over a month's end still
    writes the date it missed.
    """

    return add_months(
        anchor=through.replace(day=1),
        months=-(HORIZON_MONTHS + 1),
    )


def monthly_occurrences(
    *,
    day_of_month: int,
    starts_on: date,
    ends_on: date | None,
    through: date,
    limit: int = MAX_OCCURRENCES_PER_RULE,
    earliest: date | None = None,
) -> tuple[date, ...]:
    """Every date a monthly rule covers from ``starts_on`` up to ``through``.

    Occurrences are strictly increasing, so the walk can stop at the first date
    past the horizon rather than scanning to the end of the calendar.

    ``earliest`` moves the start of the walk forward. Without it the walk begins
    at ``starts_on`` and ``limit`` is spent there, so a rule older than the limit
    never reaches today.

    A rule whose ``ends_on`` precedes its ``starts_on`` yields nothing rather
    than raising: validation refuses such a rule at the boundary, and the
    generator has no business having an opinion about it.
    """

    if limit < 0:
        raise ValueError("limit must not be negative")
    if starts_on < MIN_PLANNED_ON:
        raise ValueError("starts_on precedes the supported calendar")

    first = starts_on if earliest is None else max(starts_on, earliest)
    occurrences: list[date] = []
    year, month = first.year, first.month
    while len(occurrences) < limit:
        if year > MAX_PLANNED_ON.year:
            break
        occurrence = clamp_day_into_month(
            year=year,
            month=month,
            day_of_month=day_of_month,
        )
        if occurrence > through or occurrence > MAX_PLANNED_ON:
            break
        if ends_on is not None and occurrence > ends_on:
            break
        # The anchor day can fall before the start inside the first month only;
        # every later month is wholly after it.
        if occurrence >= first:
            occurrences.append(occurrence)
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)
    return tuple(occurrences)
