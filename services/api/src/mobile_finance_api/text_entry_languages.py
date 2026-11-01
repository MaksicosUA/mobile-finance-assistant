"""What the sentence parser knows in Ukrainian, English and German.

The Russian tables live beside the rules in `text_entry.py`, with the reasons
for each of them. These three are the same tables in other languages, and the
parser reads all four at once (ADR 0034): a sentence is not obliged to be in the
language of the interface, and people in Ukraine mix two in one breath.

Every entry is written the way the parser sees text: case-folded, so "ß" is
"ss", and with apostrophes removed, so "п'ять" is "пять". A test holds them to
that, and to not contradicting each other across languages.

The same rules apply here as there. Whole words for money, because a stem that
fires inside a word costs a wrong amount. Nothing that is also an ordinary word
in a money sentence: "got" stays out of income because «got a coffee» is
spending, and "pay" stays out of expense because "paycheck" starts with it.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Literal

SupportedDateExpression = Literal["сегодня", "вчера"]


@dataclass(frozen=True)
class Vocabulary:
    """One language's share of the parser's tables."""

    income_words: tuple[str, ...]
    expense_words: tuple[str, ...]
    #: Two or more words that together mean money arrived.
    income_phrases: tuple[str, ...]
    months: dict[str, int]
    #: The phrase, how many days ago it means, and what travels as a
    #: `sourceExpression`. The expression stays the one Finance Core's resolver
    #: knows, whichever language the phrase was in.
    relative_days: tuple[tuple[str, int, SupportedDateExpression | None], ...]
    #: A stretch of time, in every form a count can take, with how many days and
    #: months it is. An hour is neither, and its number must still not be read
    #: as money.
    time_units: dict[str, tuple[int, int]]
    #: What puts that stretch behind us, after it: "3 дні тому".
    ago_after: tuple[str, ...]
    #: The same, before it: "vor 3 Tagen".
    ago_before: tuple[str, ...]
    #: Stands where a number would and gives none: "кілька днів тому".
    vague_counts: tuple[str, ...]
    #: Monday is 0, as `date.weekday` counts.
    weekdays: dict[str, int]
    #: Before a weekday: "last Friday".
    last_words: tuple[str, ...]
    #: A past that names no single day: "last week".
    vague_dates: tuple[str, ...]
    ordinal_days: dict[str, int]
    ordinal_tens: dict[str, int]
    currency_words: dict[str, str]
    #: Words that name money this parser cannot resolve to one currency.
    ambiguous_currency_words: frozenset[str]
    #: Numerals that stand alone.
    spoken_units: dict[str, int]
    #: Multipliers said as words.
    spoken_multipliers: dict[str, int]
    #: Short forms that only ever follow digits: "5 тис", "3 Tsd".
    digit_multipliers: dict[str, int]
    spoken_halves: dict[str, Decimal]
    decimal_separators: frozenset[str]
    transfer_stems: tuple[str, ...]


def _ukrainian_income_phrases() -> tuple[str, ...]:
    verbs = (
        "прийшла",
        "прийшов",
        "прийшли",
        "прийшло",
        "надійшла",
        "надійшов",
        "надійшли",
    )
    arriving = (
        "оплата",
        "плата",
        "зарплата",
        "премія",
        "гроші",
        "платіж",
        "переказ",
        "повернення",
        "аванс",
        "виплата",
        "кешбек",
        "кешбэк",
        "гонорар",
    )
    given = (
        "подарував",
        "подарувала",
        "дав",
        "дала",
        "дали",
        "переказав",
        "переказала",
        "переказали",
        "перевів",
        "перевела",
        "перевели",
        "скинув",
        "скинула",
    )
    return (
        *(f"{verb} {money}" for verb in verbs for money in arriving),
        *(f"{verb} мені" for verb in given),
        *(f"мені {verb}" for verb in given),
    )


UKRAINIAN = Vocabulary(
    income_words=(
        "отримав",
        "отримала",
        "отримано",
        "одержав",
        "одержала",
        "заробив",
        "заробила",
        "зарплата",
        "зарплату",
        "зарплатня",
        "зарплатню",
        "аванс",
        "премія",
        "премію",
        "дохід",
        "надійшло",
        "надходження",
        "повернули",
        "повернення",
        "виплата",
        "виплатили",
        "подарували",
        "продав",
        "продала",
        "продали",
        "продано",
        "продаж",
        "кешбек",
        "скинули",
        "дали",
    ),
    expense_words=(
        "витратив",
        "витратила",
        "витрачено",
        "витрата",
        "купив",
        "купила",
        "заплатив",
        "заплатила",
        "сплатив",
        "сплатила",
        "оплатив",
        "оплатила",
        "оплата",
        "віддав",
        "віддала",
        "списали",
        "списано",
        "пішло",
        "подарував",
        "подарувала",
        "ми подарували",
        "замовив",
        "замовила",
    ),
    income_phrases=_ukrainian_income_phrases(),
    months={
        "січня": 1,
        "січень": 1,
        "лютого": 2,
        "лютий": 2,
        "березня": 3,
        "березень": 3,
        "квітня": 4,
        "квітень": 4,
        "травня": 5,
        "травень": 5,
        "червня": 6,
        "червень": 6,
        "липня": 7,
        "липень": 7,
        "серпня": 8,
        "серпень": 8,
        "вересня": 9,
        "вересень": 9,
        "жовтня": 10,
        "жовтень": 10,
        "листопада": 11,
        "листопад": 11,
        "грудня": 12,
        "грудень": 12,
    },
    relative_days=(
        ("позавчора", 2, None),
        ("позаучора", 2, None),
        ("поза вчора", 2, None),
        ("вчора", 1, "вчера"),
        ("учора", 1, "вчера"),
        ("сьогодні", 0, "сегодня"),
    ),
    time_units={
        "день": (1, 0),
        "дні": (1, 0),
        "дня": (1, 0),
        "днів": (1, 0),
        "тиждень": (7, 0),
        "тижні": (7, 0),
        "тижня": (7, 0),
        "тижнів": (7, 0),
        "місяць": (0, 1),
        "місяці": (0, 1),
        "місяця": (0, 1),
        "місяців": (0, 1),
        "рік": (0, 12),
        "роки": (0, 12),
        "року": (0, 12),
        "років": (0, 12),
        "годину": (0, 0),
        "години": (0, 0),
        "годин": (0, 0),
        "хвилину": (0, 0),
        "хвилини": (0, 0),
        "хвилин": (0, 0),
    },
    ago_after=("тому",),
    ago_before=(),
    vague_counts=("кілька", "кількох", "декілька"),
    weekdays={
        "понеділок": 0,
        "вівторок": 1,
        "середа": 2,
        "середу": 2,
        "четвер": 3,
        "пятниця": 4,
        "пятницю": 4,
        "субота": 5,
        "суботу": 5,
        "неділя": 6,
        "неділю": 6,
    },
    last_words=("минулий", "минула", "минулу", "минуле"),
    vague_dates=(
        "минулого тижня",
        "того тижня",
        "минулого місяця",
        "того місяця",
        "днями",
        "нещодавно",
    ),
    ordinal_days={
        "першого": 1,
        "другого": 2,
        "третього": 3,
        "четвертого": 4,
        "пятого": 5,
        "шостого": 6,
        "сьомого": 7,
        "восьмого": 8,
        "девятого": 9,
        "десятого": 10,
        "одинадцятого": 11,
        "дванадцятого": 12,
        "тринадцятого": 13,
        "чотирнадцятого": 14,
        "пятнадцятого": 15,
        "шістнадцятого": 16,
        "сімнадцятого": 17,
        "вісімнадцятого": 18,
        "девятнадцятого": 19,
        "двадцятого": 20,
        "тридцятого": 30,
    },
    ordinal_tens={"двадцять": 20, "тридцять": 30},
    currency_words={
        "євро": "EUR",
        "долар": "USD",
        "долара": "USD",
        "долари": "USD",
        "доларів": "USD",
        "доларах": "USD",
        "баксів": "USD",
        "рублів": "RUB",
        "рублі": "RUB",
        "гривня": "UAH",
        "гривні": "UAH",
        "гривню": "UAH",
        "гривнях": "UAH",
        "злотий": "PLN",
        "злоті": "PLN",
        "злотих": "PLN",
        "фунти": "GBP",
        "фунтів": "GBP",
        "франки": "CHF",
        "франків": "CHF",
        "ларі": "GEL",
        "ліра": "TRY",
        "ліри": "TRY",
        "лір": "TRY",
        "шекелі": "ILS",
        "шекелів": "ILS",
        "юані": "CNY",
        "юанів": "CNY",
        "єна": "JPY",
        "єни": "JPY",
        "єн": "JPY",
    },
    ambiguous_currency_words=frozenset(
        {
            "крони",
            "цент",
            "центи",
            "центів",
            "копійка",
            "копійки",
            "копійок",
        }
    ),
    spoken_units={
        "нуль": 0,
        "одне": 1,
        "дві": 2,
        "двох": 2,
        "трьох": 3,
        "чотири": 4,
        "чотирьох": 4,
        "шість": 6,
        "сім": 7,
        "вісім": 8,
        "одинадцять": 11,
        "дванадцять": 12,
        "тринадцять": 13,
        "чотирнадцять": 14,
        "пятнадцять": 15,
        "шістнадцять": 16,
        "сімнадцять": 17,
        "вісімнадцять": 18,
        "девятнадцять": 19,
        "двадцять": 20,
        "двадцяти": 20,
        "тридцять": 30,
        "тридцяти": 30,
        "пятдесят": 50,
        "шістдесят": 60,
        "сімдесят": 70,
        "вісімдесят": 80,
        "двісті": 200,
        "двохсот": 200,
        "трьохсот": 300,
        "чотириста": 400,
        "чотирьохсот": 400,
        "пятсот": 500,
        "шістсот": 600,
        "сімсот": 700,
        "вісімсот": 800,
        "девятсот": 900,
    },
    spoken_multipliers={
        "тисяча": 1000,
        "тисячі": 1000,
        "тисяч": 1000,
        "тисячу": 1000,
        "тисячею": 1000,
        "мільйон": 1_000_000,
        "мільйона": 1_000_000,
        "мільйони": 1_000_000,
        "мільйонів": 1_000_000,
    },
    digit_multipliers={"тис": 1000},
    spoken_halves={"півтора": Decimal("1.5"), "півтори": Decimal("1.5")},
    decimal_separators=frozenset({"цілих", "ціла", "цілу", "цілої", "кома"}),
    transfer_stems=("перев", "перек", "обмін", "обміня", "поміня", "конверт"),
)

ENGLISH = Vocabulary(
    income_words=(
        "received",
        "earned",
        "earnings",
        "salary",
        "wage",
        "paycheck",
        "payday",
        "payout",
        "bonus",
        "income",
        "refund",
        "reimburs",
        "cashback",
        "sold",
        "dividend",
    ),
    expense_words=(
        "spent",
        "spend",
        "bought",
        "buy",
        "paid",
        "purchas",
        "expense",
        "charged",
        "cost",
        "gave",
        "ordered",
    ),
    income_phrases=(
        "got paid",
        "got back",
        "got a gift",
        "gift from",
        "gave me",
        "sent me",
        "was given",
        "cash back",
        "money came",
        "payment came",
        "money arrived",
        "payment arrived",
    ),
    months={
        "january": 1,
        "february": 2,
        "march": 3,
        "april": 4,
        "may": 5,
        "june": 6,
        "july": 7,
        "august": 8,
        "september": 9,
        "october": 10,
        "november": 11,
        "december": 12,
    },
    relative_days=(
        ("the day before yesterday", 2, None),
        ("day before yesterday", 2, None),
        ("yesterday", 1, "вчера"),
        ("today", 0, "сегодня"),
    ),
    time_units={
        "day": (1, 0),
        "days": (1, 0),
        "week": (7, 0),
        "weeks": (7, 0),
        "month": (0, 1),
        "months": (0, 1),
        "year": (0, 12),
        "years": (0, 12),
        "hour": (0, 0),
        "hours": (0, 0),
        "minute": (0, 0),
        "minutes": (0, 0),
    },
    ago_after=("ago",),
    ago_before=(),
    vague_counts=("couple of", "couple", "few", "several"),
    weekdays={
        "monday": 0,
        "tuesday": 1,
        "wednesday": 2,
        "thursday": 3,
        "friday": 4,
        "saturday": 5,
        "sunday": 6,
    },
    last_words=("last",),
    vague_dates=("last week", "last month", "recently", "the other day"),
    ordinal_days={
        "first": 1,
        "second": 2,
        "third": 3,
        "fourth": 4,
        "fifth": 5,
        "sixth": 6,
        "seventh": 7,
        "eighth": 8,
        "ninth": 9,
        "tenth": 10,
        "eleventh": 11,
        "twelfth": 12,
        "thirteenth": 13,
        "fourteenth": 14,
        "fifteenth": 15,
        "sixteenth": 16,
        "seventeenth": 17,
        "eighteenth": 18,
        "nineteenth": 19,
        "twentieth": 20,
        "thirtieth": 30,
    },
    ordinal_tens={"twenty": 20, "thirty": 30},
    currency_words={
        "euro": "EUR",
        "euros": "EUR",
        "dollar": "USD",
        "dollars": "USD",
        "buck": "USD",
        "bucks": "USD",
        "pound": "GBP",
        "pounds": "GBP",
        "quid": "GBP",
        "ruble": "RUB",
        "rubles": "RUB",
        "rouble": "RUB",
        "roubles": "RUB",
        "hryvnia": "UAH",
        "hryvnias": "UAH",
        "hryvnya": "UAH",
        "hryvnyas": "UAH",
        "hryvnas": "UAH",
        "zloty": "PLN",
        "zlotys": "PLN",
        "franc": "CHF",
        "francs": "CHF",
        "tenge": "KZT",
        "lari": "GEL",
        "lira": "TRY",
        "liras": "TRY",
        "shekel": "ILS",
        "shekels": "ILS",
        "yuan": "CNY",
        "yen": "JPY",
        "rupee": "INR",
        "rupees": "INR",
    },
    ambiguous_currency_words=frozenset(
        {
            "crown",
            "crowns",
            "krona",
            "kronor",
            "krone",
            "kroner",
            "koruna",
            "cent",
            "cents",
            "penny",
            "pence",
        }
    ),
    spoken_units={
        "zero": 0,
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10,
        "eleven": 11,
        "twelve": 12,
        "thirteen": 13,
        "fourteen": 14,
        "fifteen": 15,
        "sixteen": 16,
        "seventeen": 17,
        "eighteen": 18,
        "nineteen": 19,
        "twenty": 20,
        "thirty": 30,
        "forty": 40,
        "fifty": 50,
        "sixty": 60,
        "seventy": 70,
        "eighty": 80,
        "ninety": 90,
    },
    spoken_multipliers={
        "thousand": 1000,
        "thousands": 1000,
        "grand": 1000,
        "million": 1_000_000,
        "millions": 1_000_000,
    },
    digit_multipliers={"mln": 1_000_000},
    spoken_halves={},
    decimal_separators=frozenset({"point"}),
    transfer_stems=("transfer", "exchang", "convert", "swap", "changed"),
)


def _german_ordinals() -> dict[str, int]:
    # The stems differ from the cardinals in four places ("erst", "dritt",
    # "siebt", "acht"), and everything above nineteen is built one way.
    below_twenty = (
        "erst",
        "zweit",
        "dritt",
        "viert",
        "fünft",
        "sechst",
        "siebt",
        "acht",
        "neunt",
        "zehnt",
        "elft",
        "zwölft",
        "dreizehnt",
        "vierzehnt",
        "fünfzehnt",
        "sechzehnt",
        "siebzehnt",
        "achtzehnt",
        "neunzehnt",
    )
    days = {stem: day for day, stem in enumerate(below_twenty, start=1)}
    days["zwanzigst"] = 20
    for unit, word in enumerate(_GERMAN_UNIT_PREFIXES, start=1):
        days[f"{word}undzwanzigst"] = 20 + unit
    days["dreissigst"] = 30
    days["einunddreissigst"] = 31
    return {
        f"{stem}{ending}": day for stem, day in days.items() for ending in ("en", "er")
    }


#: How a unit is written at the front of a compound numeral. "Eins" alone is
#: one, and "ein" is the article, so "ein" only ever counts inside a compound.
_GERMAN_UNIT_PREFIXES = (
    "ein",
    "zwei",
    "drei",
    "vier",
    "fünf",
    "sechs",
    "sieben",
    "acht",
    "neun",
)
_GERMAN_BELOW_TWENTY = (
    "zehn",
    "elf",
    "zwölf",
    "dreizehn",
    "vierzehn",
    "fünfzehn",
    "sechzehn",
    "siebzehn",
    "achtzehn",
    "neunzehn",
)
_GERMAN_TENS = {
    "zwanzig": 20,
    "dreissig": 30,
    "vierzig": 40,
    "fünfzig": 50,
    "sechzig": 60,
    "siebzig": 70,
    "achtzig": 80,
    "neunzig": 90,
}


def _german_below_hundred() -> dict[str, int]:
    words = {
        word: number
        for number, word in enumerate(_GERMAN_UNIT_PREFIXES, start=1)
        if number > 1
    }
    words["eins"] = 1
    words.update({word: 10 + n for n, word in enumerate(_GERMAN_BELOW_TWENTY)})
    for tens_word, tens in _GERMAN_TENS.items():
        words[tens_word] = tens
        for unit, unit_word in enumerate(_GERMAN_UNIT_PREFIXES, start=1):
            words[f"{unit_word}und{tens_word}"] = tens + unit
    return words


_GERMAN_BELOW_HUNDRED = _german_below_hundred()


def _german_below_thousand(word: str) -> int | None:
    head, hundred, tail = word.partition("hundert")
    if not hundred:
        return _GERMAN_BELOW_HUNDRED.get(word)
    if head and head not in _GERMAN_UNIT_PREFIXES:
        return None
    hundreds = _GERMAN_UNIT_PREFIXES.index(head) + 1 if head else 1
    tail = tail.removeprefix("und")
    if not tail:
        return hundreds * 100
    rest = _GERMAN_BELOW_HUNDRED.get(tail)
    return None if rest is None else hundreds * 100 + rest


def german_number(word: str) -> int | None:
    """Read one German numeral, which is written as a single word.

    "Zweihundertfünfundzwanzig" cannot be a table entry without the table being
    a million lines long, so it is read: thousands, then hundreds, then the
    rest, and anything left over means the word was not a numeral after all, as
    in "hundertprozentig".
    """

    head, thousand, tail = word.partition("tausend")
    if not thousand:
        return _german_below_thousand(word)
    thousands = 1 if head in ("", "ein") else _german_below_thousand(head)
    if thousands is None:
        return None
    tail = tail.removeprefix("und")
    if not tail:
        return thousands * 1000
    rest = _german_below_thousand(tail)
    return None if rest is None else thousands * 1000 + rest


GERMAN = Vocabulary(
    income_words=(
        "erhalten",
        "erhielt",
        "bekommen",
        "bekam",
        "gehalt",
        "monatsgehalt",
        "lohn",
        "verdient",
        "einnahme",
        "einkommen",
        "prämie",
        "bonus",
        "rückzahlung",
        "rückerstattung",
        "erstattet",
        "erstattung",
        "gutschrift",
        "gutgeschrieben",
        "ausgezahlt",
        "ausbezahlt",
        "eingegangen",
        "verkauft",
        "dividende",
        "cashback",
        "weihnachtsgeld",
        "urlaubsgeld",
        "kindergeld",
    ),
    expense_words=(
        "ausgegeben",
        "bezahlt",
        "gezahlt",
        "zahlte",
        "gekauft",
        "kaufte",
        "kauf",
        "einkauf",
        "ausgabe",
        "abgebucht",
        "überwiesen",
        "bestellt",
    ),
    income_phrases=(
        "mir geschenkt",
        "mir gegeben",
        "mir überwiesen",
        "hat mir",
        "haben mir",
    ),
    # April, August, September and November are the English words.
    months={
        "januar": 1,
        "februar": 2,
        "märz": 3,
        "maerz": 3,
        "mai": 5,
        "juni": 6,
        "juli": 7,
        "oktober": 10,
        "dezember": 12,
    },
    relative_days=(
        ("vorgestern", 2, None),
        ("gestern", 1, "вчера"),
        ("heute", 0, "сегодня"),
    ),
    time_units={
        "tag": (1, 0),
        "tage": (1, 0),
        "tagen": (1, 0),
        "woche": (7, 0),
        "wochen": (7, 0),
        "monat": (0, 1),
        "monate": (0, 1),
        "monaten": (0, 1),
        "jahr": (0, 12),
        "jahre": (0, 12),
        "jahren": (0, 12),
        "stunde": (0, 0),
        "stunden": (0, 0),
        "minute": (0, 0),
        "minuten": (0, 0),
    },
    ago_after=(),
    ago_before=("vor",),
    vague_counts=("ein paar", "paar", "einigen", "mehreren", "wenigen"),
    weekdays={
        "montag": 0,
        "dienstag": 1,
        "mittwoch": 2,
        "donnerstag": 3,
        "freitag": 4,
        "samstag": 5,
        "sonnabend": 5,
        "sonntag": 6,
    },
    last_words=("letzten", "letzte", "letzter", "vergangenen", "vorigen"),
    vague_dates=(
        "letzte woche",
        "letzter woche",
        "vorige woche",
        "letzten monat",
        "vor kurzem",
        "neulich",
        "kürzlich",
    ),
    ordinal_days=_german_ordinals(),
    ordinal_tens={},
    currency_words={
        "pfund": "GBP",
        "franken": "CHF",
        "rubel": "RUB",
        "griwna": "UAH",
        "griwnas": "UAH",
        "hrywnja": "UAH",
        "hrywnjas": "UAH",
        "hrywnia": "UAH",
        "złoty": "PLN",
        "schekel": "ILS",
        "rupie": "INR",
        "rupien": "INR",
    },
    ambiguous_currency_words=frozenset({"kronen"}),
    spoken_units={"null": 0},
    spoken_multipliers={
        "tausend": 1000,
        "million": 1_000_000,
        "millionen": 1_000_000,
    },
    digit_multipliers={"tsd": 1000, "mio": 1_000_000},
    spoken_halves={
        "anderthalb": Decimal("1.5"),
        "eineinhalb": Decimal("1.5"),
    },
    decimal_separators=frozenset({"komma"}),
    transfer_stems=(
        "überweis",
        "überwies",
        "umgetausch",
        "getauscht",
        "umtausch",
        "tausch",
        "wechsel",
        "gewechselt",
        "umgerechnet",
        "umgewandelt",
        "konvert",
    ),
)

#: The languages merged into the parser's tables, beside Russian.
VOCABULARIES = (UKRAINIAN, ENGLISH, GERMAN)

#: "Two hundred" and "zwei hundert" multiply what came before, unlike Russian
#: «двести», which is one word.
HUNDRED_WORDS = frozenset({"hundred", "hundert"})

#: "Two hundred and five". Only a joiner straight after hundreds or thousands:
#: anywhere else "and" separates two numbers.
NUMBER_JOINERS = frozenset({"and", "und"})
