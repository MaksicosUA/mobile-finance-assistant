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
    # A currency sign is written that this parser cannot name. Reported rather
    # than quietly replaced by the default, because an unknown currency and an
    # unstated one are not the same thing.
    "CURRENCY_NOT_UNDERSTOOD",
    # The sentence moves money between the person's own places rather than in
    # or out of them. No amount is proposed, because booking either side as
    # income or expense invents money that never entered or left (ADR 0029).
    "TRANSFER_NOT_AN_OPERATION",
]

#: The longest sentence accepted. A phrase is one operation, not a paragraph.
MAX_TEXT_LENGTH = 280

#: What a sentence that names **no** currency at all is assumed to mean. It is
#: never applied to a sentence that does name one: an unreadable currency is a
#: gap, because assuming euro there writes a wrong amount confidently.
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
    # An exchange states both sides, and neither is income or expense. Booking
    # one of them would put money in a month's totals that never entered or
    # left the profile, so the sentence is refused as an operation and the two
    # sides are offered as a transfer instead (ADR 0029).
    if _transfer_sides(without_date) is not None:
        return ParsedOperation(
            operation_type=direction,
            amount=None,
            currency=DEFAULT_CURRENCY,
            occurred_on=occurred_on,
            source_expression=expression,
            category_id=None,
            category=None,
            gaps=("TRANSFER_NOT_AN_OPERATION",),
        )
    currency = _find_currency(without_date)
    amount, amount_gap = _find_amount(without_date, currency)
    category_id, category_text = _find_category(
        haystack, original=original, direction=direction, categories=categories
    )

    gaps: list[ParseGapCode] = []
    if amount_gap is not None:
        gaps.append(amount_gap)
    if not currency.understood:
        gaps.append("CURRENCY_NOT_UNDERSTOOD")
    if not date_understood:
        gaps.append("DATE_NOT_UNDERSTOOD")
    if category_id is None:
        gaps.append("CATEGORY_NOT_MATCHED")

    return ParsedOperation(
        operation_type=direction,
        amount=amount,
        currency=currency.code,
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

# 03.08, 3.8.2026, 03/08 — a day and a month, optionally a year. The
# separator is captured because a dotted pair without a year is also how money
# is written: 12.50 is both "12 May" and twelve fifty.
_NUMERIC_DATE = re.compile(
    r"\b(\d{1,2})([./])(\d{1,2})(?:\2(\d{4}|\d{2}))?\b",
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

    for match in _NUMERIC_DATE.finditer(haystack):
        raw_year = match.group(4)
        if (
            match.group(2) == "."
            and raw_year is None
            and not _leaves_an_amount(haystack, match.span())
        ):
            # "Потратил 12.50" is twelve fifty, not the twelfth of May. Reading
            # it as a date ate the only number in the sentence and dated the
            # operation months back without saying so -- a wrong value nobody
            # was shown. When taking the token as a date would leave nothing
            # that could be the amount, it is money.
            continue
        day = int(match.group(1))
        month = int(match.group(3))
        year = None
        if raw_year is not None:
            year = int(raw_year) if len(raw_year) == 4 else 2000 + int(raw_year)
        resolved = _calendar_date(day=day, month=month, year=year, today=today)
        if resolved is None:
            return today, None, match.span(), False
        return resolved, None, match.span(), True

    return today, None, None, True


def _leaves_an_amount(haystack: str, span: tuple[int, int]) -> bool:
    """Would anything still read as the amount without this token?"""

    start, end = span
    remainder = haystack[:start] + " " * (end - start) + haystack[end:]
    return bool(_digit_amounts(remainder) or _spoken_amounts(remainder))


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

#: Currency words, matched as **whole words** and never as a prefix.
#:
#: Every inflection is written out instead of matching a stem the way category
#: keywords do (ADR 0020). A keyword that fires from inside a word costs a
#: wrong label; a currency that does costs a wrong amount — "рубашку" starts
#: with "руб", and "Франкфурт" with "франк".
_CURRENCY_WORDS: dict[str, str] = {
    "евро": "EUR",
    "eur": "EUR",
    "доллар": "USD",
    "доллара": "USD",
    "долларов": "USD",
    "долларам": "USD",
    "долларах": "USD",
    "бакс": "USD",
    "баксов": "USD",
    "usd": "USD",
    "рубль": "RUB",
    "рубля": "RUB",
    "рублей": "RUB",
    "рублям": "RUB",
    "рублях": "RUB",
    "руб": "RUB",
    "rub": "RUB",
    "гривна": "UAH",
    "гривны": "UAH",
    "гривне": "UAH",
    "гривну": "UAH",
    "гривен": "UAH",
    "гривень": "UAH",
    "грн": "UAH",
    "uah": "UAH",
    "злотый": "PLN",
    "злотых": "PLN",
    "злотые": "PLN",
    "злотого": "PLN",
    "pln": "PLN",
    "фунт": "GBP",
    "фунта": "GBP",
    "фунтов": "GBP",
    "фунтам": "GBP",
    "gbp": "GBP",
    "франк": "CHF",
    "франка": "CHF",
    "франков": "CHF",
    "франкам": "CHF",
    "chf": "CHF",
    "тенге": "KZT",
    "kzt": "KZT",
    "лари": "GEL",
    "gel": "GEL",
    "лира": "TRY",
    "лиры": "TRY",
    "лир": "TRY",
    "try": "TRY",
    "шекель": "ILS",
    "шекеля": "ILS",
    "шекелей": "ILS",
    "ils": "ILS",
    "юань": "CNY",
    "юаня": "CNY",
    "юаней": "CNY",
    "cny": "CNY",
    "иена": "JPY",
    "иены": "JPY",
    "иен": "JPY",
    "jpy": "JPY",
    "czk": "CZK",
}

#: Currency signs, matched anywhere, because they are not word characters.
#:
#: A sign that names more than one currency is deliberately absent — ¥ is both
#: the yen and the yuan, and guessing between them is the failure this whole
#: change exists to stop. It is reported as unreadable instead.
_CURRENCY_SIGNS: dict[str, str] = {
    "€": "EUR",
    "$": "USD",
    "₽": "RUB",
    "₴": "UAH",
    "£": "GBP",
    "₸": "KZT",
    "₾": "GEL",
    "₺": "TRY",
    "₪": "ILS",
    "₹": "INR",
}

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
class _Currency:
    """What the sentence says about currency, and whether that could be read."""

    code: str
    #: Where the marker sits, used to break a tie between two amounts.
    span: tuple[int, int] | None
    #: False when a currency sign is present that this table cannot name.
    understood: bool


@dataclass(frozen=True, slots=True)
class _AmountCandidate:
    """One thing in the sentence that could be the amount, and where it is."""

    start: int
    end: int
    value: Decimal


#: What a numeral word contributes to the number being built. The parts of one
#: number descend through these — "сто двадцать пять" is hundreds, then tens,
#: then units — so a part that does not descend cannot belong to the same
#: number. That is what tells "сто двадцать" from "три пятьдесят".
_HUNDREDS, _TENS, _UNITS = 3, 2, 1

#: "ноль целых пять" is how a decimal is dictated: the word is the point.
_DECIMAL_SEPARATORS = frozenset({"целых", "целая", "целую", "целой", "целого", "целые"})


def _numeral_class(value: Decimal) -> int:
    if value >= 100:
        return _HUNDREDS
    if value >= 20 and value % 10 == 0:
        return _TENS
    return _UNITS


def _spoken_amounts(haystack: str) -> list[_AmountCandidate]:
    """Every run of numeral words, read into numbers.

    A run ends at the first word that is not a numeral, so "двадцать евро
    тридцать" is two candidates rather than one impossible number, and the
    ordinary currency tie-break decides between them.

    Inside a run, a part that does not descend begins a second number, and two
    numbers side by side are a price: "три пятьдесят" is 3,50, not 53. Anything
    else a run produces stays several candidates, which the caller reports as
    an ambiguous amount rather than guessing between them.
    """

    found: list[_AmountCandidate] = []
    numbers: list[_AmountCandidate] = []
    total = Decimal(0)
    current = Decimal(0)
    last_class = 0
    start = 0
    end = 0
    started = False
    dictated_point = False

    def close_number() -> None:
        nonlocal total, current, last_class, started
        if not started:
            return
        value = total + current
        # "полторы тысячи" arrives as 1500.0; a whole number should read
        # as a whole number in the field the user is about to confirm.
        if value == value.to_integral_value():
            value = value.to_integral_value()
        numbers.append(_AmountCandidate(start=start, end=end, value=value))
        total = Decimal(0)
        current = Decimal(0)
        last_class = 0
        started = False

    def flush_run() -> None:
        nonlocal dictated_point
        close_number()
        if numbers:
            found.extend(_read_run(tuple(numbers), dictated_point=dictated_point))
        numbers.clear()
        dictated_point = False

    for match in _WORD.finditer(haystack):
        word = match.group()
        if word in _DECIMAL_SEPARATORS:
            if started:
                close_number()
                dictated_point = True
            continue
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
            # Hundreds may follow a thousand: "две тысячи триста" is 2300.
            last_class = 0
            end = match.end()
            continue
        else:
            flush_run()
            continue

        rank = _numeral_class(value)
        if started and last_class and rank >= last_class:
            # "шестьдесят шесть шестьдесят": the second sixty cannot be part of
            # the first number, so that number ends here and another begins.
            close_number()
        if not started:
            start = match.start()
            started = True
        current += value
        last_class = rank
        end = match.end()

    flush_run()
    return [candidate for candidate in found if candidate.value > 0]


def _read_run(
    numbers: tuple[_AmountCandidate, ...],
    *,
    dictated_point: bool,
) -> list[_AmountCandidate]:
    """One run's numbers as candidates, joining a price into a single amount."""

    if len(numbers) == 2:
        major, minor = numbers
        fraction = _fraction(minor.value, dictated_point=dictated_point)
        if fraction is not None:
            return [
                _AmountCandidate(
                    start=major.start,
                    end=minor.end,
                    value=(major.value + fraction).quantize(Decimal("0.01")),
                )
            ]
    return list(numbers)


def _fraction(value: Decimal, *, dictated_point: bool) -> Decimal | None:
    """The run's second number as a fraction of the first, or None."""

    if value != value.to_integral_value() or value < 0 or value > 99:
        return None
    if dictated_point:
        # "ноль целых пять" is 0,5; "две целых двадцать пять" is 2,25.
        return value / Decimal(10 ** len(str(int(value))))
    if value < 10:
        # "три пять" could be 3,05 or 3,50, and is nobody's way of saying a
        # price. Two candidates, and the caller reports the ambiguity.
        return None
    return value / Decimal(100)


def _find_amount(
    haystack: str,
    currency: _Currency,
) -> tuple[Decimal | None, ParseGapCode | None]:
    candidates = _digit_amounts(haystack)
    # Digits win outright. A written number is unambiguous evidence, and
    # reading "купил два кофе за 300" as two candidates would turn a sentence
    # that works today into a gap.
    if not candidates:
        candidates = _spoken_amounts(haystack)
    if not candidates:
        return None, "AMOUNT_NOT_FOUND"

    chosen = candidates[0] if len(candidates) == 1 else None
    if chosen is None and currency.span is not None:
        chosen = _nearest_to_currency(candidates, currency.span)
    if chosen is None:
        # Several numbers and nothing to tell them apart. Guessing here writes
        # the wrong amount confidently; a gap costs one correction.
        return None, "AMBIGUOUS_AMOUNT"
    return chosen.value, None


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


#: Words that name a currency this table cannot resolve. A crown is Swedish,
#: Norwegian, Danish, Czech or Icelandic, and a sentence does not say which, so
#: the honest answer is the gap an unresolvable currency sign already gets
#: rather than a silent euro.
_AMBIGUOUS_CURRENCY_WORDS = frozenset(
    {"крон", "крона", "кроны", "крону", "кроне", "кронах", "кронами"}
)


# --- a transfer is not an operation ------------------------------------------

#: Word starts that say money moved between the person's own places. A stem,
#: because the parser already matches from a word start everywhere else:
#: "перев" reads «перевёл», «перевел», «перевод» and «переведено».
_TRANSFER_STEMS = ("перев", "обмен", "поменя", "конверт")


@dataclass(frozen=True)
class TransferSide:
    """One half of an exchange, exactly as the sentence states it."""

    amount: Decimal
    currency: str


def read_transfer_sides(
    text: str, *, today: date
) -> tuple[TransferSide, TransferSide] | None:
    """Read a sentence as a transfer, or decide it is not one.

    `today` is only needed to cut the date out before looking for money, the
    same way an operation is read; this function never decides what today is.
    """

    try:
        haystack = _normalized(text).casefold()
    except ValueError:
        return None
    _, _, date_span, _ = _find_date(haystack, today=today)
    return _transfer_sides(_blank_span(haystack, date_span))


def _transfer_sides(haystack: str) -> tuple[TransferSide, TransferSide] | None:
    """Both halves of an exchange, or None when the sentence is not one.

    Deliberately narrow. A transfer word alone proves nothing — «перевёл 100
    евро маме» is spending, and reading it as a transfer would lose a real
    expense. What distinguishes the two is that an exchange states **both**
    sides, so two different currencies must be named and each must have an
    amount of its own. Anything less stays an ordinary operation, which is the
    behaviour that was already right.
    """

    if not any(
        word.group().startswith(stem)
        for word in _WORD.finditer(haystack)
        for stem in _TRANSFER_STEMS
    ):
        return None

    mentions = _currency_mentions(haystack)
    ordered: list[tuple[int, int, str]] = []
    for mention in mentions:
        if all(mention[2] != seen[2] for seen in ordered):
            ordered.append(mention)
    if len(ordered) < 2:
        return None

    candidates = _digit_amounts(haystack) or _spoken_amounts(haystack)
    if len(candidates) < 2:
        return None

    first = _nearest_to_currency(candidates, (ordered[0][0], ordered[0][1]))
    second = _nearest_to_currency(candidates, (ordered[1][0], ordered[1][1]))
    # A tie, or both currencies claiming the same number, is a sentence this
    # parser cannot read as two sides. It says so instead of inventing one.
    if first is None or second is None or first is second:
        return None
    return (
        TransferSide(amount=first.value, currency=ordered[0][2]),
        TransferSide(amount=second.value, currency=ordered[1][2]),
    )


def _currency_mentions(haystack: str) -> list[tuple[int, int, str]]:
    """Every currency the sentence names, in the order it names them."""

    found: list[tuple[int, int, str]] = []
    for match in _WORD.finditer(haystack):
        code = _CURRENCY_WORDS.get(match.group())
        if code is not None:
            found.append((match.start(), match.end(), code))
    for index, character in enumerate(haystack):
        code = _CURRENCY_SIGNS.get(character)
        if code is not None:
            found.append((index, index + 1, code))
    found.sort()
    return found


def _find_currency(haystack: str) -> _Currency:
    best: tuple[int, int, str] | None = None
    for match in _WORD.finditer(haystack):
        code = _CURRENCY_WORDS.get(match.group())
        if code is not None and (best is None or match.start() < best[0]):
            best = (match.start(), match.end(), code)
    for index, character in enumerate(haystack):
        code = _CURRENCY_SIGNS.get(character)
        if code is not None and (best is None or index < best[0]):
            best = (index, index + 1, code)

    # A sign this table cannot name is always reported, even beside one it can:
    # a sentence naming two currencies is not one this parser should resolve.
    understood = not any(
        unicodedata.category(character) == "Sc" and character not in _CURRENCY_SIGNS
        for character in haystack
    ) and not any(
        match.group() in _AMBIGUOUS_CURRENCY_WORDS for match in _WORD.finditer(haystack)
    )
    if best is None:
        return _Currency(code=DEFAULT_CURRENCY, span=None, understood=understood)
    return _Currency(code=best[2], span=(best[0], best[1]), understood=understood)


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
