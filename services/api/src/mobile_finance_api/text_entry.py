"""Deterministic extraction of a proposed operation from one written sentence.

Pure and side-effect free: it reads a sentence and the user's own category
catalogue and returns a *proposal*. It writes nothing, decides nothing
financial, and carries no authority — the client turns the proposal into an
ordinary draft and Finance Core remains the only thing that validates and
commits it (ADR 0022).

Everything here is rules: number shapes, a currency dictionary, a small Russian
date vocabulary, direction verbs, and matching against categories the user
already owns. No model, so every filled field can be explained to the user who
asks why.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from typing import Literal
from uuid import UUID

OperationDirection = Literal["expense", "income"]

#: The only date phrases that may be sent as a draft's `sourceExpression`,
#: because they are exactly the ones Finance Core's resolver accepts.
SupportedDateExpression = Literal["сегодня", "вчера"]

ParseGapCode = Literal[
    # Nothing that could be an amount. The one field that cannot be guessed.
    "AMOUNT_NOT_FOUND",
    # Several candidates and no currency marker to break the tie.
    "AMBIGUOUS_AMOUNT",
    # A date-shaped token that is not a real day.
    "DATE_NOT_UNDERSTOOD",
    # No category of this direction is named in the sentence.
    "CATEGORY_NOT_MATCHED",
]

#: The longest sentence accepted. A phrase is one operation, not a paragraph.
MAX_TEXT_LENGTH = 280

#: What an unstated currency is assumed to be. Finance Core is the authority
#: that accepts or refuses a currency; this is only the proposal's default.
DEFAULT_CURRENCY = "EUR"

#: The shortest keyword allowed. Below this a keyword stops describing a
#: category and starts matching everything.
MINIMUM_KEYWORD_LENGTH = 3

#: A word of the sentence. Keywords match from a word start only, so "прочее"
#: never fires on "прочитал" and a stem cannot hit the middle of a word.
_WORD = re.compile(r"\w+")


@dataclass(frozen=True)
class CategoryOption:
    """The part of a catalogue entry this parser needs (ADR 0020)."""

    category_id: UUID
    name: str
    direction: OperationDirection
    #: Words that lead to this category, already normalized to lower case.
    #: They exist because a name has a different job: it is what reports and
    #: the picker show, so "Автомобиль" must stay readable while "авто",
    #: "машин" and "car" are what people actually write.
    keywords: tuple[str, ...] = ()


@dataclass(frozen=True)
class ParsedOperation:
    operation_type: OperationDirection
    amount: Decimal | None
    currency: str
    occurred_on: date
    #: Only ever a phrase Finance Core's resolver already accepts, so the draft
    #: it produces cannot fail on UNSUPPORTED_DATE_EXPRESSION (ADR 0007).
    source_expression: SupportedDateExpression | None
    category_id: UUID | None
    #: The words the user actually wrote for that category, not the catalogue
    #: spelling: the text is evidence, the link is what reports read.
    category: str | None
    gaps: tuple[ParseGapCode, ...]


def parse_operation_text(
    *,
    text: str,
    today: date,
    categories: tuple[CategoryOption, ...] = (),
) -> ParsedOperation:
    """Propose an operation from `text`, as understood on `today`.

    `today` is the local date in the account's canonical timezone, already
    resolved by the caller: this function never decides what "today" means.
    """

    original = _normalized(text)
    haystack = original.casefold()

    occurred_on, expression, date_span, date_understood = _find_date(
        haystack, today=today
    )
    direction = _find_direction(haystack)
    # The date is cut out before looking for money, so "03.08" cannot be read
    # as the numbers 3 and 8.
    without_date = _blank_span(haystack, date_span)
    amount, currency, amount_gap = _find_amount(without_date)
    category_id, category_text = _find_category(
        haystack, original=original, direction=direction, categories=categories
    )

    gaps: list[ParseGapCode] = []
    if amount_gap is not None:
        gaps.append(amount_gap)
    if not date_understood:
        gaps.append("DATE_NOT_UNDERSTOOD")
    if category_id is None:
        gaps.append("CATEGORY_NOT_MATCHED")

    return ParsedOperation(
        operation_type=direction,
        amount=amount,
        currency=currency,
        occurred_on=occurred_on,
        source_expression=expression,
        category_id=category_id,
        category=category_text,
        gaps=tuple(gaps),
    )


def _normalized(text: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in text):
        raise ValueError("text contains control characters")
    collapsed = " ".join(unicodedata.normalize("NFC", text).split())
    if not collapsed:
        raise ValueError("text is empty")
    if len(collapsed) > MAX_TEXT_LENGTH:
        raise ValueError("text is too long")
    return collapsed


# --- direction ---------------------------------------------------------------

_INCOME_WORDS = (
    "получил",
    "получила",
    "получено",
    "заработал",
    "заработала",
    "зарплата",
    "зарплату",
    "аванс",
    "премия",
    "премию",
    "доход",
    "приход",
    "пришло",
    "поступило",
    "поступление",
    "вернули",
    "возврат",
    "выплата",
    "выплатили",
)

_EXPENSE_WORDS = (
    "потратил",
    "потратила",
    "потрачено",
    "трата",
    "купил",
    "купила",
    "заплатил",
    "заплатила",
    "оплатил",
    "оплатила",
    "оплата",
    "отдал",
    "отдала",
    "расход",
    "списал",
    "списано",
    "ушло",
)


def _find_direction(haystack: str) -> OperationDirection:
    income = _first_index(haystack, _INCOME_WORDS)
    expense = _first_index(haystack, _EXPENSE_WORDS)
    if income is None:
        return "expense"
    if expense is None:
        return "income"
    # Both are named; the earlier verb is the one the sentence is about.
    return "income" if income < expense else "expense"


def _first_index(haystack: str, words: tuple[str, ...]) -> int | None:
    found = [haystack.find(word) for word in words]
    positions = [index for index in found if index >= 0]
    return min(positions) if positions else None


# --- dates -------------------------------------------------------------------

# Written out in full rather than stemmed: a stem like "ма" for May also
# matches the start of ordinary words and would date an operation by accident.
_MONTHS = {
    "января": 1,
    "январь": 1,
    "февраля": 2,
    "февраль": 2,
    "марта": 3,
    "март": 3,
    "апреля": 4,
    "апрель": 4,
    "мая": 5,
    "май": 5,
    "июня": 6,
    "июнь": 6,
    "июля": 7,
    "июль": 7,
    "августа": 8,
    "август": 8,
    "сентября": 9,
    "сентябрь": 9,
    "октября": 10,
    "октябрь": 10,
    "ноября": 11,
    "ноябрь": 11,
    "декабря": 12,
    "декабрь": 12,
}

# The relative days this understands, and — third element — the phrase that may
# travel to the server as a `sourceExpression`. Only the two Finance Core's own
# resolver knows may travel; "позавчера" is resolved here and sent as a plain
# date, because sending it would be rejected as unsupported (ADR 0007).
_RELATIVE_DAYS: tuple[tuple[str, int, SupportedDateExpression | None], ...] = (
    ("позавчера", 2, None),
    ("вчера", 1, "вчера"),
    ("сегодня", 0, "сегодня"),
)

# 03.08, 3.8.2026, 03/08 — a day and a month, optionally a year.
_NUMERIC_DATE = re.compile(
    r"\b(\d{1,2})[./](\d{1,2})(?:[./](\d{4}|\d{2}))?\b",
)
# 3 августа, 3 августа 2026
_NAMED_DATE = re.compile(
    r"\b(\d{1,2})\s+("
    + "|".join(sorted(_MONTHS, key=len, reverse=True))
    + r")(?:\s+(\d{4}))?\b"
)


def _find_date(
    haystack: str, *, today: date
) -> tuple[date, SupportedDateExpression | None, tuple[int, int] | None, bool]:
    """Return the day, the phrase to send as `sourceExpression`, its span, and
    whether every date-shaped token was understood."""

    for phrase, offset, expression in _RELATIVE_DAYS:
        index = haystack.find(phrase)
        if index < 0:
            continue
        span = (index, index + len(phrase))
        return today - timedelta(days=offset), expression, span, True

    match = _NAMED_DATE.search(haystack)
    if match is not None:
        day = int(match.group(1))
        month = _MONTHS[match.group(2)]
        year = int(match.group(3)) if match.group(3) else None
        resolved = _calendar_date(day=day, month=month, year=year, today=today)
        if resolved is None:
            return today, None, match.span(), False
        return resolved, None, match.span(), True

    match = _NUMERIC_DATE.search(haystack)
    if match is not None:
        day = int(match.group(1))
        month = int(match.group(2))
        raw_year = match.group(3)
        year = None
        if raw_year is not None:
            year = int(raw_year) if len(raw_year) == 4 else 2000 + int(raw_year)
        resolved = _calendar_date(day=day, month=month, year=year, today=today)
        if resolved is None:
            return today, None, match.span(), False
        return resolved, None, match.span(), True

    return today, None, None, True


def _calendar_date(
    *, day: int, month: int, year: int | None, today: date
) -> date | None:
    if year is not None:
        try:
            return date(year, month, day)
        except ValueError:
            return None
    # No year written: the most recent day that is not in the future, so an
    # entry made in January about "31 декабря" lands on the year that just
    # ended instead of one that has not happened.
    for candidate_year in (today.year, today.year - 1):
        try:
            candidate = date(candidate_year, month, day)
        except ValueError:
            continue
        if candidate <= today:
            return candidate
    return None


# --- money -------------------------------------------------------------------

_CURRENCIES: tuple[tuple[str, str], ...] = (
    ("€", "EUR"),
    ("eur", "EUR"),
    ("евро", "EUR"),
    ("$", "USD"),
    ("usd", "USD"),
    ("доллар", "USD"),
    ("₽", "RUB"),
    ("руб", "RUB"),
    ("рубл", "RUB"),
)

# The thousands separator may be a space or a non-breaking space; both are
# written as escapes because an invisible character in a pattern is a
# character an editor can silently lose.
_THOUSANDS_SEPARATORS = " \u00a0\u202f"

_AMOUNT = re.compile(
    r"(?<![\d.,])(\d{1,3}(?:[" + _THOUSANDS_SEPARATORS + r"]\d{3})+"
    r"(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"
    r"(?![\d.,]*\d)"
)


# --- numerals written as words -----------------------------------------------

# Speech does not carry digits. A person typing writes "20", the same person
# speaking says "двадцать", and a transcript reports whichever the recogniser
# felt like. Reading both is what makes one parser serve a keyboard and a
# microphone.
#
# Whole words, not stems: "два" is a prefix of "двадцать", and matching from a
# word start would read "двадцать пять" as two. The cost is that a case this
# table does not list becomes a gap -- which is the parser's rule everywhere
# else, and cheaper than a confidently wrong amount.
_SPOKEN_UNITS: dict[str, int] = {
    "ноль": 0,
    "один": 1,
    "одна": 1,
    "одно": 1,
    "одну": 1,
    "два": 2,
    "две": 2,
    "двух": 2,
    "три": 3,
    "трёх": 3,
    "трех": 3,
    "четыре": 4,
    "четырёх": 4,
    "четырех": 4,
    "пять": 5,
    "пяти": 5,
    "шесть": 6,
    "шести": 6,
    "семь": 7,
    "семи": 7,
    "восемь": 8,
    "восьми": 8,
    "девять": 9,
    "девяти": 9,
    "десять": 10,
    "десяти": 10,
    "одиннадцать": 11,
    "двенадцать": 12,
    "тринадцать": 13,
    "четырнадцать": 14,
    "пятнадцать": 15,
    "шестнадцать": 16,
    "семнадцать": 17,
    "восемнадцать": 18,
    "девятнадцать": 19,
    "двадцать": 20,
    "двадцати": 20,
    "тридцать": 30,
    "тридцати": 30,
    "сорок": 40,
    "сорока": 40,
    "пятьдесят": 50,
    "пятидесяти": 50,
    "шестьдесят": 60,
    "шестидесяти": 60,
    "семьдесят": 70,
    "семидесяти": 70,
    "восемьдесят": 80,
    "восьмидесяти": 80,
    "девяносто": 90,
    "девяноста": 90,
    "сто": 100,
    "ста": 100,
    "двести": 200,
    "двухсот": 200,
    "триста": 300,
    "трёхсот": 300,
    "трехсот": 300,
    "четыреста": 400,
    "четырёхсот": 400,
    "четырехсот": 400,
    "пятьсот": 500,
    "пятисот": 500,
    "шестьсот": 600,
    "шестисот": 600,
    "семьсот": 700,
    "семисот": 700,
    "восемьсот": 800,
    "восьмисот": 800,
    "девятьсот": 900,
    "девятисот": 900,
}

#: A word that multiplies everything gathered before it.
_SPOKEN_MULTIPLIERS: dict[str, int] = {
    "тысяча": 1000,
    "тысячи": 1000,
    "тысяч": 1000,
    "тысячу": 1000,
    "тысячей": 1000,
    "миллион": 1_000_000,
    "миллиона": 1_000_000,
    "миллионов": 1_000_000,
    "миллиону": 1_000_000,
}

#: "полторы тысячи" is 1500, and people say it constantly.
_SPOKEN_HALVES: dict[str, Decimal] = {
    "полтора": Decimal("1.5"),
    "полторы": Decimal("1.5"),
}


@dataclass(frozen=True, slots=True)
class _AmountCandidate:
    """One thing in the sentence that could be the amount, and where it is."""

    start: int
    end: int
    value: Decimal


def _spoken_amounts(haystack: str) -> list[_AmountCandidate]:
    """Every maximal run of numeral words, read into a number.

    A run ends at the first word that is not a numeral, so "двадцать евро
    тридцать" is two candidates rather than one impossible number, and the
    ordinary currency tie-break decides between them.
    """

    candidates: list[_AmountCandidate] = []
    total = Decimal(0)
    current = Decimal(0)
    started = False
    start = 0
    end = 0

    def flush() -> None:
        nonlocal total, current, started
        if started:
            value = total + current
            # "полторы тысячи" arrives as 1500.0; a whole number should read
            # as a whole number in the field the user is about to confirm.
            if value == value.to_integral_value():
                value = value.to_integral_value()
            candidates.append(_AmountCandidate(start=start, end=end, value=value))
        total = Decimal(0)
        current = Decimal(0)
        started = False

    for match in _WORD.finditer(haystack):
        word = match.group()
        if word in _SPOKEN_UNITS:
            value = Decimal(_SPOKEN_UNITS[word])
        elif word in _SPOKEN_HALVES:
            value = _SPOKEN_HALVES[word]
        elif word in _SPOKEN_MULTIPLIERS:
            multiplier = Decimal(_SPOKEN_MULTIPLIERS[word])
            if not started:
                start = match.start()
                started = True
            # "тысяча" on its own is one thousand, not zero thousands.
            total += (current if current > 0 else Decimal(1)) * multiplier
            current = Decimal(0)
            end = match.end()
            continue
        else:
            flush()
            continue

        if not started:
            start = match.start()
            started = True
        current += value
        end = match.end()

    flush()
    return [candidate for candidate in candidates if candidate.value > 0]


def _find_amount(
    haystack: str,
) -> tuple[Decimal | None, str, ParseGapCode | None]:
    currency, currency_span = _find_currency(haystack)
    candidates = _digit_amounts(haystack)
    # Digits win outright. A written number is unambiguous evidence, and
    # reading "купил два кофе за 300" as two candidates would turn a sentence
    # that works today into a gap.
    if not candidates:
        candidates = _spoken_amounts(haystack)
    if not candidates:
        return None, currency, "AMOUNT_NOT_FOUND"

    chosen = candidates[0] if len(candidates) == 1 else None
    if chosen is None and currency_span is not None:
        chosen = _nearest_to_currency(candidates, currency_span)
    if chosen is None:
        # Several numbers and nothing to tell them apart. Guessing here writes
        # the wrong amount confidently; a gap costs one correction.
        return None, currency, "AMBIGUOUS_AMOUNT"
    return chosen.value, currency, None


def _digit_amounts(haystack: str) -> list[_AmountCandidate]:
    candidates: list[_AmountCandidate] = []
    for match in _AMOUNT.finditer(haystack):
        value = _decimal(match.group(1))
        if value is None:
            continue
        candidates.append(
            _AmountCandidate(start=match.start(), end=match.end(), value=value)
        )
    return candidates


def _find_currency(haystack: str) -> tuple[str, tuple[int, int] | None]:
    best: tuple[int, int, str] | None = None
    for token, code in _CURRENCIES:
        index = haystack.find(token)
        if index < 0:
            continue
        if best is None or index < best[0]:
            best = (index, index + len(token), code)
    if best is None:
        return DEFAULT_CURRENCY, None
    return best[2], (best[0], best[1])


def _nearest_to_currency(
    matches: list[_AmountCandidate], currency_span: tuple[int, int]
) -> _AmountCandidate | None:
    start, end = currency_span
    scored = sorted(
        matches,
        key=lambda match: min(
            abs(match.start - end),
            abs(start - match.end),
        ),
    )
    closest = scored[0]
    if len(scored) > 1:
        first = min(abs(closest.start - end), abs(start - closest.end))
        second = min(abs(scored[1].start - end), abs(start - scored[1].end))
        if first == second:
            return None
    return closest


def _decimal(raw: str) -> Decimal | None:
    normalized = raw.replace(",", ".")
    for separator in _THOUSANDS_SEPARATORS:
        normalized = normalized.replace(separator, "")
    try:
        amount = Decimal(normalized)
    except InvalidOperation:
        return None
    if not amount.is_finite() or amount <= 0:
        return None
    return amount


def _blank_span(haystack: str, span: tuple[int, int] | None) -> str:
    if span is None:
        return haystack
    start, end = span
    return haystack[:start] + " " * (end - start) + haystack[end:]


# --- categories --------------------------------------------------------------


def _find_category(
    haystack: str,
    *,
    original: str,
    direction: OperationDirection,
    categories: tuple[CategoryOption, ...],
) -> tuple[UUID | None, str | None]:
    """Match a category the user already owns; never invent one (ADR 0020).

    Two ways in, and the longer evidence wins so a specific word beats a broad
    one: a keyword that starts a word in the sentence, or the category name
    appearing literally. Keywords carry the load — matching a *word start*
    rather than a whole word is what makes one entry cover an inflected form
    ("продукт" reads "продуктов") and a compound ("авто" reads "автохимию")
    without a morphology dictionary or a model.
    """

    candidates = [
        category for category in categories if category.direction == direction
    ]
    words = list(_WORD.finditer(haystack))
    # Ranked by how much evidence matched, but quoting the whole word the user
    # wrote: a keyword is a stem, and storing "заправ" as what they typed would
    # be a worse record than storing "заправил".
    best: tuple[int, tuple[int, int], CategoryOption] | None = None

    def offer(*, span: tuple[int, int], weight: int, category: CategoryOption) -> None:
        nonlocal best
        if best is None or weight > best[0]:
            best = (weight, span, category)

    for category in candidates:
        for keyword in category.keywords:
            if len(keyword) < MINIMUM_KEYWORD_LENGTH:
                # Two letters would drag half the sentences into one category.
                continue
            for word in words:
                if word.group().startswith(keyword):
                    offer(span=word.span(), weight=len(keyword), category=category)
                    break
        needle = unicodedata.normalize("NFC", category.name).casefold()
        if not needle:
            continue
        index = haystack.find(needle)
        if index >= 0:
            offer(
                span=(index, index + len(needle)),
                weight=len(needle),
                category=category,
            )

    if best is None:
        return None, None
    _, (start, end), category = best
    # The user's own spelling, not the catalogue's, because the text is the
    # evidence of what they wrote. Casefolding can change a string's length in
    # some scripts, which would slice the wrong span, so that case falls back
    # to the catalogue name rather than quoting the user inaccurately.
    if len(haystack) != len(original):
        return category.category_id, category.name
    return category.category_id, original[start:end]
