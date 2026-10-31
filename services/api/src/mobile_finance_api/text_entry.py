"""Deterministic extraction of a proposed operation from one written sentence.

Pure and side-effect free: it reads a sentence and the user's own category
catalogue and returns a *proposal*. It writes nothing, decides nothing
financial, and carries no authority — the client turns the proposal into an
ordinary draft and Finance Core remains the only thing that validates and
commits it (ADR 0022).

Everything here is rules: number shapes, a currency dictionary, a small date
vocabulary, direction verbs, and matching against categories the user already
owns. No model, so every filled field can be explained to the user who asks why.

The tables below are Russian. Ukrainian, English and German are merged into them
from `text_entry_languages`, so one parser reads all four and needs no language
to be named (ADR 0034).
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from typing import Literal
from uuid import UUID

from .text_entry_languages import (
    HUNDRED_WORDS,
    NUMBER_JOINERS,
    VOCABULARIES,
    SupportedDateExpression,
    german_number,
)

OperationDirection = Literal["expense", "income"]

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
    haystack = _folded(original)

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


#: In capitals these two are currency codes. In lower case they are English
#: words, and "hair gel 10" is not ten lari. A code becomes its sign, padded so
#: the sentence keeps its length.
_WORDLIKE_CODES = {"TRY": "₺  ", "GEL": "₾  "}
_WORDLIKE_CODE = re.compile(r"\b(?:" + "|".join(_WORDLIKE_CODES) + r")\b")

#: Ukrainian writes an apostrophe inside a word, and `_WORD` would split there:
#: "п'ять" would be a stray "п" and "ять". Without it the word is the one the
#: tables hold, however it was typed.
_APOSTROPHES = str.maketrans("", "", "'’ʼ`")


def _folded(text: str) -> str:
    """The sentence as the tables are written: one spelling per word."""

    with_signs = _WORDLIKE_CODE.sub(lambda code: _WORDLIKE_CODES[code.group()], text)
    return with_signs.casefold().translate(_APOSTROPHES)


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
) + tuple(word for language in VOCABULARIES for word in language.income_words)

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
) + tuple(word for language in VOCABULARIES for word in language.expense_words)


# Money arriving is said with a verb of motion, and the verb alone proves
# nothing: «пришла в кафе» is a person. Only the verb next to what arrived reads
# as income, and it has to be read, because «оплата» on its own is an expense
# word: without the pair, «пришла оплата» was booked as a payment made.
_ARRIVAL_VERBS = (
    "пришла",
    "пришёл",
    "пришел",
    "пришли",
    "поступила",
    "поступил",
    "поступили",
)
_ARRIVING_MONEY = (
    "оплата",
    # How recognition hears «оплата» after «пришла».
    "плата",
    "зарплата",
    "премия",
    "деньги",
    "платёж",
    "платеж",
    "перевод",
    "возврат",
    "аванс",
    "выплата",
    "кэшбэк",
    "кешбэк",
    "гонорар",
)
_INCOME_PHRASES = tuple(
    f"{verb} {money}" for verb in _ARRIVAL_VERBS for money in _ARRIVING_MONEY
) + tuple(phrase for language in VOCABULARIES for phrase in language.income_phrases)


def _from_a_word_start(words: tuple[str, ...]) -> re.Pattern[str]:
    """Any of `words`, starting where a word starts.

    The same rule keywords follow. Without it "got paid" fires inside "forgot
    paid" and «вернули» inside «перевернули».
    """

    longest_first = sorted(words, key=len, reverse=True)
    return re.compile(r"\b(?:" + "|".join(map(re.escape, longest_first)) + ")")


_INCOME = _from_a_word_start(_INCOME_WORDS + _INCOME_PHRASES)
_EXPENSE = _from_a_word_start(_EXPENSE_WORDS)


def _find_direction(haystack: str) -> OperationDirection:
    income = _first_index(haystack, _INCOME)
    expense = _first_index(haystack, _EXPENSE)
    if income is None:
        return "expense"
    if expense is None:
        return "income"
    # Both are named; the earlier verb is the one the sentence is about.
    return "income" if income < expense else "expense"


def _first_index(haystack: str, words: re.Pattern[str]) -> int | None:
    found = words.search(haystack)
    return found.start() if found else None


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
    **{
        word: month
        for language in VOCABULARIES
        for word, month in language.months.items()
    },
}

# The relative days this understands, and — third element — the phrase that may
# travel to the server as a `sourceExpression`. Only the two Finance Core's own
# resolver knows may travel; "позавчера" is resolved here and sent as a plain
# date, because sending it would be rejected as unsupported (ADR 0007).
_RELATIVE_DAYS: tuple[tuple[str, int, SupportedDateExpression | None], ...] = (
    ("позавчера", 2, None),
    # Recognition writes it in two; read as «вчера» it lost a day in silence.
    # Both must come before «вчера», which they contain.
    ("поза вчера", 2, None),
    ("поза-вчера", 2, None),
    ("вчера", 1, "вчера"),
    ("сегодня", 0, "сегодня"),
    *(day for language in VOCABULARIES for day in language.relative_days),
)
_RELATIVE_DAY_PHRASES = tuple(
    (re.compile(r"\b" + re.escape(phrase)), offset, expression)
    for phrase, offset, expression in _RELATIVE_DAYS
)

# 03.08, 3.8.2026, 03/08 — a day and a month, optionally a year. The
# separator is captured because a dotted pair without a year is also how money
# is written: 12.50 is both "12 May" and twelve fifty.
_NUMERIC_DATE = re.compile(
    r"\b(\d{1,2})([./])(\d{1,2})(?:\2(\d{4}|\d{2}))?\b",
)
# «числа» stands where a month would: the day of the month, the most recent one.
_THIS_MONTH = "числа"
_MONTH_NAMES = "|".join(sorted(_MONTHS, key=len, reverse=True))
_MONTH_WORDS = _MONTH_NAMES + "|" + _THIS_MONTH

# What may stand between a day written in digits and its month: 3-го августа,
# 3rd of August, 3. August.
_DAY_SUFFIX = r"(?:-?го|-?ого|-?е|-?є|st|nd|rd|th|\.)?"

# 3 августа, 3-го августа, 3го августа, 3 августа 2026, 5-го числа, 3rd of August
_NAMED_DATE = re.compile(
    r"\b(\d{1,2})"
    + _DAY_SUFFIX
    + r"\s+(?:of\s+)?("
    + _MONTH_WORDS
    + r")(?:\s+(\d{4}))?\b"
)

# August 3, August 3rd, August 3, 2026. English writes the month first. So does a
# price in any language, "August 20 euro", which is why this one must leave an
# amount behind to count as a date.
_MONTH_FIRST_DATE = re.compile(
    r"\b(" + _MONTH_NAMES + r")\s+(\d{1,2})"
    r"(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?(?![\d.,]*\d)\b"
)

# A day said as an ordinal: «третьего сентября», «двадцать восьмого июля»,
# «первого числа». The tens word is part of the match so it is cut out with
# the date instead of being read as money.
_ORDINAL_DAYS = {
    "первого": 1,
    "второго": 2,
    "третьего": 3,
    "четвертого": 4,
    "четвёртого": 4,
    "пятого": 5,
    "шестого": 6,
    "седьмого": 7,
    "восьмого": 8,
    "девятого": 9,
    "десятого": 10,
    "одиннадцатого": 11,
    "двенадцатого": 12,
    "тринадцатого": 13,
    "четырнадцатого": 14,
    "пятнадцатого": 15,
    "шестнадцатого": 16,
    "семнадцатого": 17,
    "восемнадцатого": 18,
    "девятнадцатого": 19,
    "двадцатого": 20,
    "тридцатого": 30,
    **{
        word: day
        for language in VOCABULARIES
        for word, day in language.ordinal_days.items()
    },
}
_ORDINAL_TENS = {
    "двадцать": 20,
    "тридцать": 30,
    **{
        word: tens
        for language in VOCABULARIES
        for word, tens in language.ordinal_tens.items()
    },
}
_ORDINAL = (
    r"(?:("
    + "|".join(_ORDINAL_TENS)
    + r")[\s-]+)?("
    + "|".join(sorted(_ORDINAL_DAYS, key=len, reverse=True))
    + r")"
)
_ORDINAL_DATE = re.compile(
    r"\b" + _ORDINAL + r"\s+(?:of\s+)?(" + _MONTH_WORDS + r")(?:\s+(\d{4}))?\b"
)
# September third, September the twenty-first.
_MONTH_FIRST_ORDINAL_DATE = re.compile(
    r"\b(" + _MONTH_NAMES + r")\s+(?:the\s+)?" + _ORDINAL + r"(?:,?\s+(\d{4}))?\b"
)


def _find_date(
    haystack: str, *, today: date
) -> tuple[date, SupportedDateExpression | None, tuple[int, int] | None, bool]:
    """Return the day, the phrase to send as `sourceExpression`, its span, and
    whether every date-shaped token was understood."""

    for phrase, offset, expression in _RELATIVE_DAY_PHRASES:
        found = phrase.search(haystack)
        if found is None:
            continue
        return today - timedelta(days=offset), expression, found.span(), True

    match = _ORDINAL_DATE.search(haystack)
    if match is not None:
        return _ordinal_date(match, tens=1, unit=2, month=3, year=4, today=today)

    match = _NAMED_DATE.search(haystack)
    if match is not None:
        day = int(match.group(1))
        year = int(match.group(3)) if match.group(3) else None
        resolved = _named_day(day=day, month=match.group(2), year=year, today=today)
        if resolved is None:
            return today, None, match.span(), False
        return resolved, None, match.span(), True

    match = _MONTH_FIRST_ORDINAL_DATE.search(haystack)
    if match is not None:
        return _ordinal_date(match, tens=2, unit=3, month=1, year=4, today=today)

    match = _MONTH_FIRST_DATE.search(haystack)
    if (
        match is not None
        and int(match.group(2)) <= 31
        and _leaves_an_amount(haystack, match.span())
    ):
        year = int(match.group(3)) if match.group(3) else None
        resolved = _named_day(
            day=int(match.group(2)), month=match.group(1), year=year, today=today
        )
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


def _ordinal_date(
    match: re.Match[str], *, tens: int, unit: int, month: int, year: int, today: date
) -> tuple[date, None, tuple[int, int], bool]:
    """A day said as an ordinal, wherever its groups fell in the pattern."""

    ones = _ORDINAL_DAYS[match.group(unit)]
    tens_value = _ORDINAL_TENS.get(match.group(tens) or "", 0)
    # «двадцать двадцатого» is not a day; a gap, not a guess.
    day = tens_value + ones if not tens_value or ones < 10 else 0
    resolved = _named_day(
        day=day,
        month=match.group(month),
        year=int(match.group(year)) if match.group(year) else None,
        today=today,
    )
    if resolved is None:
        return today, None, match.span(), False
    return resolved, None, match.span(), True


def _leaves_an_amount(haystack: str, span: tuple[int, int]) -> bool:
    """Would anything still read as the amount without this token?"""

    start, end = span
    remainder = haystack[:start] + " " * (end - start) + haystack[end:]
    return bool(_digit_amounts(remainder) or _spoken_amounts(remainder))


def _named_day(*, day: int, month: str, year: int | None, today: date) -> date | None:
    if month != _THIS_MONTH:
        return _calendar_date(day=day, month=_MONTHS[month], year=year, today=today)
    if year is not None or not 1 <= day <= 31:
        return None
    # The most recent month that has this day and has reached it: on
    # 26 October, «тридцать первого числа» is 31 August, because September has
    # no 31st and October's has not come.
    year, month_number = today.year, today.month
    for _ in range(12):
        try:
            candidate = date(year, month_number, day)
        except ValueError:
            candidate = None
        if candidate is not None and candidate <= today:
            return candidate
        year, month_number = (
            (year, month_number - 1) if month_number > 1 else (year - 1, 12)
        )
    return None


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
    "лира": "TRY",
    "лиры": "TRY",
    "лир": "TRY",
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
    **{
        word: code
        for language in VOCABULARIES
        for word, code in language.currency_words.items()
    },
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

# A comma or a dot groups thousands only in front of exactly three digits, and a
# cent has two, so "1,250" and "1.250" are both 1250 in every language and "12,50"
# and "12.50" both twelve fifty. No language has to be named. The first group
# cannot be a bare zero: "0,125" is not 125.
_AMOUNT = re.compile(
    r"(?<![\d.,])("
    r"\d{1,3}(?:[" + _THOUSANDS_SEPARATORS + r"]\d{3})+(?:[.,]\d{1,2})?"
    r"|[1-9]\d{0,2}(?:,\d{3})+(?:\.\d{1,2})?"
    r"|[1-9]\d{0,2}(?:\.\d{3})+(?:,\d{1,2})?"
    r"|\d+(?:[.,]\d{1,2})?)"
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
    **{
        word: value
        for language in VOCABULARIES
        for word, value in language.spoken_units.items()
    },
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
    **{
        word: value
        for language in VOCABULARIES
        for word, value in language.spoken_multipliers.items()
    },
}

#: What may follow digits and multiply them: "3 тысячи" is 3000, not 3. Read as
#: three it was off by a thousand with nothing to show for it. The short forms
#: are here rather than among the spoken words because nobody says them alone.
_DIGIT_MULTIPLIERS: dict[str, int] = {
    **_SPOKEN_MULTIPLIERS,
    "тыс": 1000,
    "млн": 1_000_000,
    **{
        word: value
        for language in VOCABULARIES
        for word, value in language.digit_multipliers.items()
    },
}
# A lone letter counts only when it touches the digits: "5к" is five thousand,
# and "5 к обеду" is five, towards lunch.
_AFTER_DIGITS = re.compile(
    r"(?:\s+(" + "|".join(sorted(_DIGIT_MULTIPLIERS, key=len, reverse=True)) + r")"
    r"|([кk]))\b"
)

#: "полторы тысячи" is 1500, and people say it constantly.
_SPOKEN_HALVES: dict[str, Decimal] = {
    "полтора": Decimal("1.5"),
    "полторы": Decimal("1.5"),
    **{
        word: value
        for language in VOCABULARIES
        for word, value in language.spoken_halves.items()
    },
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
_THOUSANDS, _HUNDREDS, _TENS, _UNITS = 4, 3, 2, 1

#: "ноль целых пять" is how a decimal is dictated: the word is the point.
_DECIMAL_SEPARATORS = frozenset(
    {"целых", "целая", "целую", "целой", "целого", "целые"}
).union(*(language.decimal_separators for language in VOCABULARIES))


def _numeral_class(value: Decimal) -> int:
    if value >= 1000:
        return _THOUSANDS
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
        if word in NUMBER_JOINERS and started and last_class in (0, _HUNDREDS):
            continue
        if word in HUNDRED_WORDS:
            # "Two hundred" and "two hundred thousand" both start here, so this
            # builds the number in hand rather than adding to the total.
            if current >= 100:
                close_number()
            if not started:
                start = match.start()
                started = True
            current = (current if current > 0 else Decimal(1)) * 100
            last_class = _HUNDREDS
            end = match.end()
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
        elif (german := german_number(word)) is not None:
            value = Decimal(german)
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
        end = match.end()
        after = _AFTER_DIGITS.match(haystack, end)
        # Recognition hears «четыре тысячи» and writes "4000 тыс". A figure that
        # already has its thousands is not multiplied again.
        if after is not None and value < 1000:
            word = after.group(1)
            value *= _DIGIT_MULTIPLIERS[word] if word else 1000
            # "1,5 тысячи" should read as 1500 in the field, not 1500.0.
            if value == value.to_integral_value():
                value = value.to_integral_value()
            end = after.end()
        candidates.append(_AmountCandidate(start=match.start(), end=end, value=value))
    return candidates


#: Words that name a currency this table cannot resolve. A crown is Swedish,
#: Norwegian, Danish, Czech or Icelandic, and a sentence does not say which, so
#: the honest answer is the gap an unresolvable currency sign already gets
#: rather than a silent euro.
#:
#: A cent is here for the same reason: "50 центов" is not fifty of anything the
#: sentence names, and reading it as fifty euro is off by a hundred.
_AMBIGUOUS_CURRENCY_WORDS = frozenset(
    {
        "крон",
        "крона",
        "кроны",
        "крону",
        "кроне",
        "кронах",
        "кронами",
        "цент",
        "цента",
        "центов",
        "копейка",
        "копейки",
        "копеек",
    }
).union(*(language.ambiguous_currency_words for language in VOCABULARIES))


# --- a transfer is not an operation ------------------------------------------

#: Word starts that say money moved between the person's own places. A stem,
#: because the parser already matches from a word start everywhere else:
#: "перев" reads «перевёл», «перевел», «перевод» and «переведено».
_TRANSFER_STEMS = ("перев", "обмен", "поменя", "конверт") + tuple(
    stem for language in VOCABULARIES for stem in language.transfer_stems
)


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
        haystack = _folded(_normalized(text))
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
    normalized = raw
    for separator in _THOUSANDS_SEPARATORS:
        normalized = normalized.replace(separator, "")
    normalized = _without_grouping(normalized).replace(",", ".")
    try:
        amount = Decimal(normalized)
    except InvalidOperation:
        return None
    if not amount.is_finite() or amount <= 0:
        return None
    return amount


def _without_grouping(digits: str) -> str:
    """Drop a comma or a dot that groups thousands rather than marks a decimal."""

    for separator in ",.":
        groups = digits.split(separator)
        if len(groups) > 1 and all(len(group) == 3 for group in groups[1:]):
            return "".join(groups)
    # "1.250,50": the separator before the last group of three is the grouping.
    decimal_mark = max(digits.rfind(","), digits.rfind("."))
    if decimal_mark > 0:
        head = digits[:decimal_mark]
        return head.replace(",", "").replace(".", "") + digits[decimal_mark:]
    return digits


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
            folded = _folded(keyword)
            for word in words:
                if word.group().startswith(folded):
                    offer(span=word.span(), weight=len(folded), category=category)
                    break
        needle = _folded(unicodedata.normalize("NFC", category.name))
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
