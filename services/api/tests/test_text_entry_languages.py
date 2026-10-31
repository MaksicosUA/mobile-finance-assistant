"""One parser reads Russian, Ukrainian, English and German at once (ADR 0034).

These pin what each language has to get right. The Russian rules have their own
file; what is here is either another language's shape of the same rule, or a
rule that only became reachable because of one.
"""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from uuid import UUID

import pytest

from mobile_finance_api.text_entry import (
    CategoryOption,
    ParsedOperation,
    parse_operation_text,
    read_transfer_sides,
)
from mobile_finance_api.text_entry_languages import (
    ENGLISH,
    GERMAN,
    UKRAINIAN,
    VOCABULARIES,
    german_number,
)

_TODAY = date(2026, 10, 31)


def _parse(text: str, *categories: CategoryOption) -> ParsedOperation:
    return parse_operation_text(text=text, today=_TODAY, categories=categories)


@pytest.mark.parametrize(
    ("text", "direction", "amount", "currency"),
    [
        ("витратив 250 доларів", "expense", "250", "USD"),
        ("отримав зарплату 30000 гривень", "income", "30000", "UAH"),
        ("заплатив п'ятсот гривень", "expense", "500", "UAH"),
        ("заплатив п’ятсот гривень", "expense", "500", "UAH"),
        ("дві тисячі гривень на продукти", "expense", "2000", "UAH"),
        ("дев'ятнадцять п'ятдесят за каву", "expense", "19.50", "EUR"),
        ("півтори тисячі гривень", "expense", "1500", "UAH"),
        ("надійшла оплата 13 900 гривень", "income", "13900", "UAH"),
        ("Gehalt 3000 Euro bekommen", "income", "3000", "EUR"),
        ("Monatsgehalt 3000 Euro", "income", "3000", "EUR"),
        ("Geld zurück: 20 Euro erstattet", "income", "20", "EUR"),
        ("1.250,50 Euro Miete bezahlt", "expense", "1250.50", "EUR"),
        ("dreißig Euro für Benzin", "expense", "30", "EUR"),
        ("zweihundertfünfundzwanzig Euro ausgegeben", "expense", "225", "EUR"),
        ("zweitausendfünfhundert Euro Miete", "expense", "2500", "EUR"),
        ("zwei tausend Euro", "expense", "2000", "EUR"),
        ("anderthalb tausend Euro", "expense", "1500", "EUR"),
        ("drei fünfzig für Kaffee", "expense", "3.50", "EUR"),
        ("zwei komma fünf Euro", "expense", "2.50", "EUR"),
        ("100 Pfund", "expense", "100", "GBP"),
        ("received salary 3000 euros", "income", "3000", "EUR"),
        ("got paid 2,500.50 pounds", "income", "2500.50", "GBP"),
        ("paycheck 3000", "income", "3000", "EUR"),
        ("refund 20 dollars", "income", "20", "USD"),
        ("spent 1,250 dollars", "expense", "1250", "USD"),
        ("two hundred and fifty dollars", "expense", "250", "USD"),
        ("two hundred thousand dollars", "expense", "200000", "USD"),
        ("two thousand five hundred dollars", "expense", "2500", "USD"),
        ("fifteen hundred euros", "expense", "1500", "EUR"),
        ("a hundred euros", "expense", "100", "EUR"),
        ("three fifty for coffee", "expense", "3.50", "EUR"),
        ("nineteen ninety nine", "expense", "19.99", "EUR"),
        ("twenty-five euros on lunch", "expense", "25", "EUR"),
        ("two point five euros", "expense", "2.50", "EUR"),
    ],
)
def test_money_and_direction(
    text: str, direction: str, amount: str, currency: str
) -> None:
    parsed = _parse(text)

    assert parsed.operation_type == direction
    assert parsed.amount == Decimal(amount)
    assert parsed.currency == currency


@pytest.mark.parametrize(
    ("text", "occurred_on", "expression"),
    [
        ("вчора 50 гривень", date(2026, 10, 30), "вчера"),
        ("учора 50 гривень", date(2026, 10, 30), "вчера"),
        ("сьогодні 50 гривень", _TODAY, "сегодня"),
        ("позавчора 50 гривень", date(2026, 10, 29), None),
        ("3 серпня 500 грн", date(2026, 8, 3), None),
        ("3-го серпня 500 грн", date(2026, 8, 3), None),
        ("третього вересня 100 гривень", date(2026, 9, 3), None),
        ("двадцять восьмого липня 100 гривень", date(2026, 7, 28), None),
        ("gestern 12,50", date(2026, 10, 30), "вчера"),
        ("heute 12,50", _TODAY, "сегодня"),
        ("vorgestern 12,50", date(2026, 10, 29), None),
        ("am 3. August 50 Euro", date(2026, 8, 3), None),
        ("am dritten September 20 Euro", date(2026, 9, 3), None),
        ("einundzwanzigsten Mai 20 Euro", date(2026, 5, 21), None),
        ("yesterday 12.50", date(2026, 10, 30), "вчера"),
        ("today 12.50", _TODAY, "сегодня"),
        ("the day before yesterday 12.50", date(2026, 10, 29), None),
        ("August 3rd paid 50 euros", date(2026, 8, 3), None),
        ("paid 50 euros on the 3rd of August", date(2026, 8, 3), None),
        ("paid 50 euros on September third", date(2026, 9, 3), None),
        ("paid 50 euros on the twenty-first of March", date(2026, 3, 21), None),
    ],
)
def test_dates(text: str, occurred_on: date, expression: str | None) -> None:
    parsed = _parse(text)

    assert parsed.occurred_on == occurred_on
    assert parsed.source_expression == expression
    assert "DATE_NOT_UNDERSTOOD" not in parsed.gaps


def test_a_month_followed_by_a_price_is_the_price() -> None:
    parsed = _parse("August 20 euro")

    assert parsed.amount == Decimal("20")
    assert parsed.occurred_on == _TODAY


def test_a_word_containing_a_date_is_not_a_date() -> None:
    assert _parse("scheute 20 Euro").occurred_on == _TODAY


@pytest.mark.parametrize(
    ("text", "amount"),
    [
        ("потратил 3 тысячи на продукты", "3000"),
        ("3 тыс на ремонт", "3000"),
        ("заплатил 2 млн", "2000000"),
        ("1,5 тысячи на кафе", "1500"),
        ("потратил 5к", "5000"),
        ("три тисячі гривень", "3000"),
        ("3 тисячі гривень", "3000"),
        ("3 Tsd Euro", "3000"),
        ("2 Mio Euro", "2000000"),
        ("3 thousand euros", "3000"),
        ("5k on rent", "5000"),
        ("2 grand", "2000"),
    ],
)
def test_a_multiplier_after_digits_multiplies_them(text: str, amount: str) -> None:
    assert _parse(text).amount == Decimal(amount)


def test_a_lone_letter_after_a_space_is_a_word_not_a_thousand() -> None:
    assert _parse("5 к обеду").amount == Decimal("5")


def test_a_figure_that_has_its_thousands_is_not_multiplied_again() -> None:
    # How recognition wrote «четыре тысячи» on a real recording.
    assert _parse("получил зарплату 4000 тыс").amount == Decimal("4000")


@pytest.mark.parametrize(
    ("text", "amount"),
    [
        ("1,250", "1250"),
        ("1.250", "1250"),
        ("1,250,000", "1250000"),
        ("1.250.000", "1250000"),
        ("1,250.50", "1250.50"),
        ("1.250,50", "1250.50"),
        ("1 250,50", "1250.50"),
        ("12,50", "12.50"),
        ("12.50", "12.50"),
    ],
)
def test_digits_need_no_language_to_be_named(text: str, amount: str) -> None:
    assert _parse(f"spent {text}").amount == Decimal(amount)


@pytest.mark.parametrize("text", ["0,125", "0.125", "1.25.50", "1,25,50"])
def test_digits_that_fit_no_convention_stay_a_gap(text: str) -> None:
    parsed = _parse(f"spent {text}")

    assert parsed.amount is None


@pytest.mark.parametrize(
    "text",
    [
        "50 центов",
        "50 копеек",
        "50 центів",
        "50 копійок",
        "50 cents",
        "50 Cent",
        "800 Kronen",
        "800 крон",
        "800 kroner",
    ],
)
def test_money_with_no_single_currency_is_a_gap(text: str) -> None:
    assert "CURRENCY_NOT_UNDERSTOOD" in _parse(text).gaps


@pytest.mark.parametrize(
    ("text", "currency"),
    [
        ("hair gel 10", "EUR"),
        ("hair gel 10 euro", "EUR"),
        ("try the new place 20", "EUR"),
        ("500 GEL", "GEL"),
        ("500 TRY", "TRY"),
        ("500 rub", "RUB"),
    ],
)
def test_a_code_that_is_also_a_word_counts_only_in_capitals(
    text: str, currency: str
) -> None:
    assert _parse(text).currency == currency


@pytest.mark.parametrize(
    ("text", "sent", "received"),
    [
        ("переказав 100 євро отримав 5200 гривень", "EUR", "UAH"),
        ("обміняв 100 євро на 5200 гривень", "EUR", "UAH"),
        ("100 Euro gewechselt und 5200 Griwna bekommen", "EUR", "UAH"),
        ("100 Euro umgetauscht in 108 Dollar", "EUR", "USD"),
        ("exchanged 100 euros for 5200 hryvnias", "EUR", "UAH"),
        ("changed 100 dollars to 92 euros", "USD", "EUR"),
    ],
)
def test_an_exchange_is_refused_as_an_operation_and_read_as_a_transfer(
    text: str, sent: str, received: str
) -> None:
    assert _parse(text).gaps == ("TRANSFER_NOT_AN_OPERATION",)

    sides = read_transfer_sides(text, today=_TODAY)
    assert sides is not None
    assert (sides[0].currency, sides[1].currency) == (sent, received)


@pytest.mark.parametrize(
    "text",
    ["Переказав 100 євро мамі", "100 Euro an Anna überwiesen", "transferred 100 euros"],
)
def test_a_transfer_word_alone_is_still_spending(text: str) -> None:
    parsed = _parse(text)

    assert parsed.operation_type == "expense"
    assert parsed.amount == Decimal("100")
    assert read_transfer_sides(text, today=_TODAY) is None


def test_an_apostrophe_does_not_hide_a_category_name() -> None:
    meat = CategoryOption(
        category_id=UUID("22222222-2222-4222-8222-222222222222"),
        name="М'ясо",
        direction="expense",
    )

    assert _parse("купив м’ясо за 200", meat).category_id == meat.category_id


def test_a_keyword_with_a_sharp_s_matches_as_the_sentence_is_folded() -> None:
    tram = CategoryOption(
        category_id=UUID("22222222-2222-4222-8222-222222222222"),
        name="Verkehr",
        direction="expense",
        keywords=("straßenbahn",),
    )

    assert _parse("Straßenbahn 3 Euro", tram).category_id == tram.category_id


@pytest.mark.parametrize(
    ("word", "value"),
    [
        ("eins", 1),
        ("zwölf", 12),
        ("einundzwanzig", 21),
        ("neunundneunzig", 99),
        ("hundert", 100),
        ("einhundert", 100),
        ("hunderteins", 101),
        ("hundertundfünf", 105),
        ("zweihundertfünfundzwanzig", 225),
        ("tausend", 1000),
        ("eintausend", 1000),
        ("zweitausend", 2000),
        ("zweitausendfünfhundert", 2500),
        ("zwölftausenddreihundertvierundfünfzig", 12354),
    ],
)
def test_a_german_numeral_is_read_as_one_word(word: str, value: int) -> None:
    assert german_number(word) == value


@pytest.mark.parametrize(
    "word", ["ein", "eine", "hundertprozentig", "tausendfach", "zweier", "euro"]
)
def test_a_german_word_that_only_looks_like_a_numeral_is_not_one(word: str) -> None:
    assert german_number(word) is None


# --- the tables themselves ---------------------------------------------------


def _entries() -> list[str]:
    found: list[str] = []
    for language in VOCABULARIES:
        found += [
            *language.income_words,
            *language.expense_words,
            *language.income_phrases,
            *language.months,
            *(phrase for phrase, _, _ in language.relative_days),
            *language.ordinal_days,
            *language.ordinal_tens,
            *language.currency_words,
            *language.ambiguous_currency_words,
            *language.spoken_units,
            *language.spoken_multipliers,
            *language.digit_multipliers,
            *language.spoken_halves,
            *language.decimal_separators,
            *language.transfer_stems,
        ]
    return found


def test_every_entry_is_written_the_way_the_parser_sees_text() -> None:
    assert not [
        entry
        for entry in _entries()
        if entry != entry.casefold() or any(mark in entry for mark in "'’ʼ`")
    ]


def test_no_word_means_both_income_and_expense() -> None:
    income = {word for language in VOCABULARIES for word in language.income_words}
    expense = {word for language in VOCABULARIES for word in language.expense_words}

    assert not income & expense


def test_no_income_word_starts_with_an_expense_word() -> None:
    # The two are matched from a word start, and a tie goes to expense, so
    # "pay" among the expense words would turn every "paycheck" into spending.
    income = [word for language in VOCABULARIES for word in language.income_words]
    expense = [word for language in VOCABULARIES for word in language.expense_words]

    assert not [
        (word, stem) for word in income for stem in expense if word.startswith(stem)
    ]


def test_no_currency_word_is_also_a_numeral_or_a_multiplier() -> None:
    currencies = {word for language in VOCABULARIES for word in language.currency_words}
    numerals = {
        word
        for language in VOCABULARIES
        for word in (*language.spoken_units, *language.spoken_multipliers)
    }

    assert not currencies & numerals


def test_a_word_names_at_most_one_currency_across_languages() -> None:
    seen: dict[str, str] = {}
    for language in (UKRAINIAN, ENGLISH, GERMAN):
        for word, code in language.currency_words.items():
            assert seen.setdefault(word, code) == code
