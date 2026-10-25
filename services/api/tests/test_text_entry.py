"""Reading one written sentence into a proposed operation.

The parser proposes; Finance Core still decides (ADR 0022). These tests pin
the two things that matter most: what it understands, and what it refuses to
guess.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.category_contracts import Category, ListCategoriesResponse
from mobile_finance_api.main import create_app
from mobile_finance_api.text_entry import (
    CategoryOption,
    parse_operation_text,
    read_transfer_sides,
)
from mobile_finance_api.text_entry_contracts import (
    ParsedOperationProposal,
    ParseOperationRequest,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_GROCERIES = UUID("22222222-2222-4222-8222-222222222222")
_SALARY = UUID("33333333-3333-4333-8333-333333333333")
_CAFE = UUID("44444444-4444-4444-8444-444444444444")
_TODAY = date(2026, 8, 13)
_AUTH = {"Authorization": "Bearer synthetic-token"}

_CATEGORIES = (
    CategoryOption(category_id=_GROCERIES, name="Продукты", direction="expense"),
    CategoryOption(category_id=_CAFE, name="Кафе", direction="expense"),
    CategoryOption(category_id=_SALARY, name="Зарплата", direction="income"),
)


def _parse(text: str) -> object:
    return parse_operation_text(text=text, today=_TODAY, categories=_CATEGORIES)


# --- what it understands -----------------------------------------------------


def test_an_ordinary_expense_sentence_becomes_a_proposal() -> None:
    parsed = _parse("Потратил 12,50 на продукты")

    assert parsed.operation_type == "expense"
    assert parsed.amount == Decimal("12.50")
    assert parsed.currency == "EUR"
    assert parsed.occurred_on == _TODAY
    assert parsed.category_id == _GROCERIES
    assert parsed.gaps == ()


def test_income_verbs_flip_the_direction() -> None:
    parsed = _parse("Получил зарплата 2000")

    assert parsed.operation_type == "income"
    assert parsed.category_id == _SALARY


def test_an_unmarked_sentence_is_an_expense() -> None:
    """Most entries are spending, and the user can flip it on the card."""

    parsed = _parse("300 на кафе")

    assert parsed.operation_type == "expense"
    assert parsed.amount == Decimal("300")


def test_a_category_of_the_wrong_direction_is_not_matched() -> None:
    """Filing an expense under an income category corrupts every breakdown."""

    parsed = _parse("Потратил 50 на зарплата")

    assert parsed.category_id is None
    assert "CATEGORY_NOT_MATCHED" in parsed.gaps


def test_the_quoted_category_is_what_the_user_wrote() -> None:
    parsed = _parse("Потратил 40 на ПРОДУКТЫ")

    # The text is evidence of what they wrote; the link is what reports read.
    assert parsed.category_id == _GROCERIES
    assert parsed.category == "ПРОДУКТЫ"


def test_the_longest_matching_category_wins() -> None:
    parsed = parse_operation_text(
        text="Потратил 30 на кафе и рестораны",
        today=_TODAY,
        categories=(
            CategoryOption(category_id=_CAFE, name="Кафе", direction="expense"),
            CategoryOption(
                category_id=_GROCERIES,
                name="Кафе и рестораны",
                direction="expense",
            ),
        ),
    )

    assert parsed.category_id == _GROCERIES


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Потратил 1 500 на продукты", Decimal("1500")),
        ("Потратил 1500.50 на продукты", Decimal("1500.50")),
        ("Потратил 1500,50 на продукты", Decimal("1500.50")),
        ("Потратил 500 евро на продукты", Decimal("500")),
        ("Потратил €500 на продукты", Decimal("500")),
    ],
)
def test_amount_shapes(text: str, expected: Decimal) -> None:
    assert _parse(text).amount == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        # Speech carries no digits: a transcript says "двадцать", and the same
        # sentence typed says "20". One parser has to read both.
        ("Потратил двадцать евро на продукты", Decimal("20")),
        ("Потратил сто двадцать пять на продукты", Decimal("125")),
        ("Потратил тысячу на продукты", Decimal("1000")),
        ("Потратил две тысячи триста на продукты", Decimal("2300")),
        ("Потратил полторы тысячи на продукты", Decimal("1500")),
        ("Потратил полтора евро на продукты", Decimal("1.5")),
        ("Потратил девятьсот девяносто девять на продукты", Decimal("999")),
        # Oblique forms people actually say.
        ("Потратил около двадцати евро на продукты", Decimal("20")),
        ("Потратил пятьдесят евро на продукты", Decimal("50")),
    ],
)
def test_amounts_spoken_as_words(text: str, expected: Decimal) -> None:
    assert _parse(text).amount == expected


def test_a_whole_spoken_amount_is_not_written_with_a_fraction() -> None:
    """1500, not 1500.0, in the field the user is about to confirm."""

    parsed = _parse("Потратил полторы тысячи на продукты")
    assert str(parsed.amount) == "1500"


def test_digits_win_over_words() -> None:
    """Otherwise a sentence that works today becomes a gap.

    "два кофе" is a count, not money. A written number is unambiguous
    evidence, so words are only read when there are no digits at all.
    """

    parsed = _parse("Купил два кофе за 300 в кафе")
    assert parsed.amount == Decimal("300")
    assert parsed.gaps == ()


def test_two_spoken_numbers_are_ambiguous_like_two_written_ones() -> None:
    parsed = _parse("Потратил двадцать на продукты тридцать")
    assert parsed.amount is None
    assert "AMBIGUOUS_AMOUNT" in parsed.gaps


def test_a_currency_marker_breaks_a_tie_between_spoken_numbers() -> None:
    """The same tie-break digits already get, on the same spans."""

    parsed = _parse("Заказал двадцать штук за сорок евро в кафе")
    assert parsed.amount == Decimal("40")


def test_a_numeral_case_the_table_does_not_list_is_a_gap() -> None:
    """A gap costs one correction; a wrong amount costs trust."""

    parsed = _parse("Потратил осьмнадцать на продукты")
    assert parsed.amount is None
    assert "AMOUNT_NOT_FOUND" in parsed.gaps


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        # A price said aloud is two numbers in a row: whole units, then the
        # hundredths. Adding them is what read «три пятьдесят» as 53 and put an
        # amount fifteen times too large on an ordinary-looking card (0009).
        ("Купил кофе за три пятьдесят", Decimal("3.50")),
        ("Потратил пятнадцать пятьдесят в кафе", Decimal("15.50")),
        ("Отдал шестьдесят шесть шестьдесят", Decimal("66.60")),
        ("Заплатил девяносто девять девяносто девять", Decimal("99.99")),
        ("Заплатил триста тридцать три тридцать три", Decimal("333.33")),
    ],
)
def test_a_spoken_price_is_whole_units_and_hundredths(
    text: str, expected: Decimal
) -> None:
    parsed = _parse(text)

    assert parsed.amount == expected
    assert parsed.gaps == () or "AMBIGUOUS_AMOUNT" not in parsed.gaps


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        # The parts of one number descend: hundreds, then tens, then units.
        # These must stay single numbers, or the fix above would break reading
        # every ordinary spoken amount.
        ("Потратил сто двадцать пять на продукты", Decimal("125")),
        ("Потратил сто один евро", Decimal("101")),
        ("Купил на четыреста сорок четыре", Decimal("444")),
        ("Заплатил двадцать две тысячи двести", Decimal("22200")),
        ("Потратил одна тысяча одиннадцать", Decimal("1011")),
        ("Отдал две тысячи двадцать два", Decimal("2022")),
        ("Купил за пятнадцать тысяч пятьсот", Decimal("15500")),
        ("Потратил полторы тысячи на продукты", Decimal("1500")),
    ],
)
def test_a_number_whose_parts_descend_stays_one_number(
    text: str, expected: Decimal
) -> None:
    assert _parse(text).amount == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Потратил ноль целых пять", Decimal("0.50")),
        ("Потратил две целых двадцать пять", Decimal("2.25")),
    ],
)
def test_a_dictated_decimal_keeps_its_fraction(text: str, expected: Decimal) -> None:
    assert _parse(text).amount == expected


@pytest.mark.parametrize(
    "text",
    [
        # Words between two numbers mean two things were counted, not a price.
        "Купил два кофе и три булки",
        # A correction spoken aloud. Picking either number writes money the
        # user did not spend.
        "Купил за тринадцать, не за тридцать",
        # Too small to be hundredths: refusing beats inventing 3,05 or 3,50.
        "Купил три пять",
    ],
)
def test_numbers_that_are_not_a_price_stay_a_gap(text: str) -> None:
    parsed = _parse(text)

    assert parsed.amount is None
    assert "AMBIGUOUS_AMOUNT" in parsed.gaps


@pytest.mark.parametrize(
    ("text", "code"),
    [
        ("Потратил 500 евро", "EUR"),
        ("Получил 500 долларов", "USD"),
        ("Потратил 500 рублей", "RUB"),
        ("Потратил 500 гривен", "UAH"),
        ("Потратил 500 грн", "UAH"),
        ("Потратил 500 ₴", "UAH"),
        ("Потратил 500 злотых", "PLN"),
        ("Потратил 500 фунтов", "GBP"),
        ("Потратил 500 франков", "CHF"),
        ("Потратил 500 тенге", "KZT"),
        ("Потратил 500 лари", "GEL"),
        ("Потратил 500", "EUR"),
    ],
)
def test_currency_is_read_or_defaults(text: str, code: str) -> None:
    # Every currency the parser knows reports its own code. Nothing quietly
    # becomes euro: the euro default is only for a sentence that names no
    # currency at all.
    assert _parse(text).currency == code
    assert "CURRENCY_NOT_UNDERSTOOD" not in _parse(text).gaps


@pytest.mark.parametrize(
    ("text", "code"),
    [
        # "руб" sits inside "рубашку", and the match used to fire from there.
        ("Купил рубашку за 3000 гривен", "UAH"),
        ("Купил рубашку за 3000", "EUR"),
        # So does "евро" inside "еврочехол".
        ("Купил еврочехол за 40 долларов", "USD"),
    ],
)
def test_a_currency_word_is_read_from_a_word_start(text: str, code: str) -> None:
    """A currency word inside another word is not a currency.

    The same rule the category keywords use (ADR 0020): a stem matches from a
    word start, so a shirt is not roubles.
    """

    assert _parse(text).currency == code


@pytest.mark.parametrize("text", ["Потратил 120 ₦", "Получил 500 ¥", "Отдал 40 ₡"])
def test_a_currency_symbol_it_cannot_name_is_a_gap(text: str) -> None:
    """A currency sign the table does not know is reported, never assumed.

    An unknown sign and no sign at all used to be the same thing, and the
    euro default applied to both. ¥ is here because it names two currencies:
    a symbol that cannot be resolved is not resolved.
    """

    parsed = _parse(text)

    assert "CURRENCY_NOT_UNDERSTOOD" in parsed.gaps
    # The amount was read perfectly well. Only the currency is missing.
    assert parsed.amount is not None


@pytest.mark.parametrize(
    ("text", "amount"),
    [
        ("Купил на 800 крон еды", Decimal("800")),
        ("Отдал 200 крон за такси", Decimal("200")),
    ],
)
def test_a_currency_word_this_table_cannot_resolve_is_a_gap(
    text: str, amount: Decimal
) -> None:
    """A crown is Swedish, Norwegian, Danish, Czech or Icelandic, and the
    sentence does not say which. Booking it as euro was silent and wrong; the
    gap costs one correction (0009)."""

    parsed = _parse(text)

    assert "CURRENCY_NOT_UNDERSTOOD" in parsed.gaps
    # Only the unit is unknown; the number itself still reads.
    assert parsed.amount == amount


def test_a_sentence_with_no_currency_is_not_a_gap() -> None:
    parsed = _parse("Потратил 12,50 на продукты")

    assert parsed.currency == "EUR"
    assert "CURRENCY_NOT_UNDERSTOOD" not in parsed.gaps


@pytest.mark.parametrize(
    ("text", "expected", "expression"),
    [
        ("Потратил 20 сегодня", date(2026, 8, 13), "сегодня"),
        ("Потратил 20 вчера", date(2026, 8, 12), "вчера"),
        ("Потратил 20 позавчера", date(2026, 8, 11), None),
        ("Потратил 20 3 августа", date(2026, 8, 3), None),
        ("Потратил 20 03.08", date(2026, 8, 3), None),
        ("Потратил 20 03.08.2025", date(2025, 8, 3), None),
    ],
)
def test_dates(text: str, expected: date, expression: str | None) -> None:
    parsed = _parse(text)

    assert parsed.occurred_on == expected
    # Only phrases Finance Core's resolver knows may travel as an expression;
    # anything else is resolved here and sent as a plain date, so a draft can
    # never fail on an unsupported expression (ADR 0007).
    assert parsed.source_expression == expression


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Потратил 12.50 на продукты", Decimal("12.50")),
        # The dangerous one: 12.05 is a valid day and month, so this used to
        # date the operation to 12 May without saying anything, and lose the
        # amount on top.
        ("Потратил 12.05 на продукты", Decimal("12.05")),
        ("Потратил 25.12 на подарок", Decimal("25.12")),
        ("Потратил 3.08 на кофе", Decimal("3.08")),
    ],
)
def test_a_dotted_pair_that_is_the_only_number_is_money(
    text: str, expected: Decimal
) -> None:
    """Twelve fifty, not the twelfth of May.

    Both readings are grammatical. The one that silently dates an operation
    months back and drops the amount is the one that must not win.
    """

    parsed = _parse(text)

    assert parsed.amount == expected
    assert parsed.occurred_on == _TODAY
    assert "AMOUNT_NOT_FOUND" not in parsed.gaps
    assert "DATE_NOT_UNDERSTOOD" not in parsed.gaps


def test_a_dotted_date_still_reads_when_the_amount_is_elsewhere() -> None:
    """The discriminator is whether anything else could be the amount."""

    assert _parse("Потратил 20 03.08").occurred_on == date(2026, 8, 3)
    assert _parse("Потратил двадцать 03.08").occurred_on == date(2026, 8, 3)
    # A year settles it outright, whatever else is in the sentence.
    assert _parse("Потратил 03.08.2025").occurred_on == date(2025, 8, 3)


def test_a_day_without_a_year_takes_the_most_recent_one() -> None:
    """An entry in January about 31 декабря means the year that just ended."""

    parsed = parse_operation_text(
        text="Потратил 20 31 декабря",
        today=date(2026, 1, 5),
        categories=(),
    )

    assert parsed.occurred_on == date(2025, 12, 31)


def test_a_date_is_not_read_as_money() -> None:
    parsed = _parse("Потратил 03.08 сумму 40")

    assert parsed.occurred_on == date(2026, 8, 3)
    assert parsed.amount == Decimal("40")


def test_a_month_name_does_not_match_an_ordinary_word() -> None:
    """A stemmed month table used to date a sentence by accident."""

    parsed = parse_operation_text(
        text="Потратил 5 маек по 20 евро", today=_TODAY, categories=()
    )

    assert parsed.occurred_on == _TODAY


# --- keywords (ADR 0020 step 3) ----------------------------------------------

_CAR = UUID("55555555-5555-4555-8555-555555555555")
_KEYWORD_CATEGORIES = (
    CategoryOption(
        category_id=_CAR,
        name="Автомобиль",
        direction="expense",
        keywords=("авто", "машин", "заправ", "car", "wagen"),
    ),
    CategoryOption(
        category_id=_GROCERIES,
        name="Продукты",
        direction="expense",
        keywords=("продукт",),
    ),
    CategoryOption(
        category_id=_CAFE,
        name="Прочее",
        direction="expense",
        keywords=(),
    ),
    CategoryOption(
        category_id=_SALARY,
        name="Криптовалюта",
        direction="income",
        keywords=("крипт",),
    ),
)


def _by_keyword(text: str) -> object:
    return parse_operation_text(text=text, today=_TODAY, categories=_KEYWORD_CATEGORIES)


@pytest.mark.parametrize(
    "text",
    [
        # The three shapes a keyword has to cover: the word itself, a compound
        # that starts with it, and a different verb entirely.
        "заправил авто на 20 евро",
        "купил для машины автохимию за 35",
        "сделал сервис авто поменял масло 180",
        "paid for car service 90",
    ],
)
def test_a_keyword_reaches_a_category_its_name_would_miss(text: str) -> None:
    """ "Автомобиль" is the right label; nobody writes it in a sentence."""

    assert _by_keyword(text).category_id == _CAR


def test_a_keyword_matches_an_inflected_form() -> None:
    """Matching a word start is what replaces a morphology dictionary."""

    assert _by_keyword("купил продуктов на 30").category_id == _GROCERIES
    assert _by_keyword("получил доход с криптовалюты 40").category_id == _SALARY


def test_the_word_the_user_wrote_is_kept_not_the_stem() -> None:
    parsed = _by_keyword("Заправил авто на 20 евро")

    # The stored text is evidence of what they typed; "заправ" is not a word.
    assert parsed.category == "Заправил"


def test_a_keyword_never_fires_from_inside_a_word() -> None:
    """Anchored at a word start, so a stem cannot hit a word that merely
    contains it.

    A keyword that is itself too broad is the user's own call — that is what
    the minimum length guards against, not this.
    """

    parsed = parse_operation_text(
        text="заплатил за квартиру 800",
        today=_TODAY,
        categories=(
            CategoryOption(
                category_id=_CAR,
                name="Развлечения",
                # "тир" sits inside "квартиру" but does not start it.
                direction="expense",
                keywords=("тир",),
            ),
        ),
    )

    assert parsed.category_id is None


def test_the_longer_evidence_wins() -> None:
    """A specific word beats a broad one, whichever order they arrive in."""

    broad = CategoryOption(
        category_id=_CAR, name="Транспорт", direction="expense", keywords=("авто",)
    )
    specific = CategoryOption(
        category_id=_GROCERIES,
        name="Автобус",
        direction="expense",
        keywords=("автобус",),
    )
    for order in ((broad, specific), (specific, broad)):
        parsed = parse_operation_text(
            text="потратил 3 на автобус", today=_TODAY, categories=order
        )
        assert parsed.category_id == _GROCERIES


def test_a_keyword_of_the_wrong_direction_is_not_considered() -> None:
    assert _by_keyword("потратил 50 на криптовалюту").category_id is None


def test_a_keyword_shorter_than_the_minimum_is_ignored() -> None:
    """A two-letter keyword would drag half of every sentence into it."""

    parsed = parse_operation_text(
        text="потратил 10 на ужин",
        today=_TODAY,
        categories=(
            CategoryOption(
                category_id=_CAR, name="Еда", direction="expense", keywords=("уж",)
            ),
        ),
    )

    assert parsed.category_id is None


# --- what it refuses to guess ------------------------------------------------


def test_a_sentence_without_an_amount_reports_a_gap() -> None:
    parsed = _parse("Купил продукты")

    assert parsed.amount is None
    assert "AMOUNT_NOT_FOUND" in parsed.gaps
    # It still understood the rest, so the form is not left empty.
    assert parsed.category_id == _GROCERIES


def test_two_numbers_and_no_currency_is_a_gap_not_a_guess() -> None:
    parsed = _parse("Купил 2 кофе за 5")

    # Picking the larger number writes the wrong amount confidently; a gap
    # costs the user one correction.
    assert parsed.amount is None
    assert "AMBIGUOUS_AMOUNT" in parsed.gaps


def test_a_currency_marker_breaks_the_tie() -> None:
    parsed = _parse("Купил 2 кофе за 5 евро")

    assert parsed.amount == Decimal("5")
    assert parsed.gaps == ("CATEGORY_NOT_MATCHED",)


def test_an_impossible_date_is_reported_not_silently_replaced() -> None:
    parsed = _parse("Потратил 20 32.13")

    assert "DATE_NOT_UNDERSTOOD" in parsed.gaps
    assert parsed.occurred_on == _TODAY


def test_control_characters_and_oversize_text_are_refused() -> None:
    with pytest.raises(ValueError):
        parse_operation_text(text="Потратил\u000740", today=_TODAY)
    with pytest.raises(ValueError):
        parse_operation_text(text="а" * 281, today=_TODAY)
    with pytest.raises(ValueError):
        parse_operation_text(text="   ", today=_TODAY)


# --- contract ----------------------------------------------------------------


def test_a_proposal_carries_no_command_id_and_no_hash() -> None:
    """It is a proposal, not a draft: it must not be confirmable on its own."""

    payload = ParsedOperationProposal(
        operation_type="expense",
        amount=Decimal("10"),
        currency="EUR",
        occurred_on=_TODAY,
    ).model_dump(mode="json", by_alias=True)

    assert "commandId" not in payload
    assert "draftHash" not in payload
    assert payload["amount"] == "10"


def test_a_proposal_refuses_an_expression_the_resolver_does_not_know() -> None:
    with pytest.raises(ValidationError):
        ParsedOperationProposal(
            operation_type="expense",
            amount=Decimal("10"),
            currency="EUR",
            occurred_on=_TODAY,
            source_expression="позавчера",
        )


def test_the_request_refuses_an_empty_or_oversized_sentence() -> None:
    for text in ("", "а" * 281):
        with pytest.raises(ValidationError):
            ParseOperationRequest.model_validate(
                {
                    "text": text,
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                }
            )


# --- transport ---------------------------------------------------------------


def test_parsing_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/operations/parse",
                json={
                    "text": "Потратил 10",
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
            )
        assert response.status_code == 401

    asyncio.run(scenario())


def test_the_day_is_resolved_in_the_caller_timezone() -> None:
    """22:30 UTC is already the next day in Berlin, and the sentence means it."""

    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCategories(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/operations/parse",
                json={
                    "text": "Потратил 12 на продукты сегодня",
                    "capturedAt": "2026-08-12T22:30:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
                headers=_AUTH,
            )
        assert response.status_code == 200, response.text
        proposal = response.json()["proposal"]
        assert proposal["occurredOn"] == "2026-08-13"
        assert proposal["amount"] == "12"
        assert proposal["categoryId"] == str(_GROCERIES)

    asyncio.run(scenario())


def test_only_the_caller_own_categories_can_be_proposed() -> None:
    async def scenario() -> None:
        repository = _FakeCategories()
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=repository,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            await client.post(
                "/api/v1/operations/parse",
                json={
                    "text": "Потратил 12 на продукты",
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
                headers=_AUTH,
            )
        assert repository.requested == [_USER_ID]

    asyncio.run(scenario())


def test_a_failure_never_echoes_the_sentence() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_ExplodingCategories(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/operations/parse",
                json={
                    "text": "Потратил 12 на секретную покупку",
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
                headers=_AUTH,
            )
        assert response.status_code == 503, response.text
        assert response.json() == {"detail": {"code": "TEXT_ENTRY_UNAVAILABLE"}}
        assert "секретную" not in response.text

    asyncio.run(scenario())


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


class _FakeCategories:
    def __init__(self) -> None:
        self.requested: list[UUID] = []

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        self.requested.append(user_id)
        created = datetime(2026, 6, 1, tzinfo=UTC)
        return ListCategoriesResponse(
            categories=(
                Category(
                    category_id=_GROCERIES,
                    name="Продукты",
                    direction="expense",
                    created_at=created,
                ),
                Category(
                    category_id=_SALARY,
                    name="Зарплата",
                    direction="income",
                    created_at=created,
                ),
            )
        )

    async def list_category_keywords(
        self, *, user_id: UUID
    ) -> dict[UUID, tuple[str, ...]]:
        del user_id
        return {_GROCERIES: ("продукт",)}

    async def __getattr__(self, name: str) -> object:  # pragma: no cover
        raise AttributeError(name)


class _ExplodingCategories:
    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        del user_id
        raise RuntimeError("the catalogue is unavailable")


# --- a transfer is not an operation ------------------------------------------
#
# Issue 0009, second half. «Перевёл 100 евро получил 5200 гривен» was booked as
# income of 100 EUR: money that never entered the profile, in a month's totals.


def test_an_exchange_is_refused_rather_than_booked_as_income() -> None:
    parsed = _parse("Перевёл 100 евро получил 5200 гривен")

    assert parsed.amount is None
    assert "TRANSFER_NOT_AN_OPERATION" in parsed.gaps


def test_an_exchange_said_the_other_way_is_refused_too() -> None:
    parsed = _parse("обменял 50 евро на 2600 гривен")

    assert parsed.amount is None
    assert "TRANSFER_NOT_AN_OPERATION" in parsed.gaps


def test_money_sent_to_someone_else_stays_an_ordinary_expense() -> None:
    """One currency and one amount: the money left, so it is spending.

    This is the line the recognition must not cross. Sending euros to a person
    and exchanging euros for hryvnia are both said with «перевёл», and only the
    second names two currencies.
    """

    parsed = _parse("Перевёл 100 евро маме")

    assert parsed.operation_type == "expense"
    assert parsed.amount == Decimal("100")
    assert parsed.currency == "EUR"
    assert "TRANSFER_NOT_AN_OPERATION" not in parsed.gaps


def test_two_currencies_without_a_transfer_word_are_left_alone() -> None:
    """Naming a second currency is not by itself a transfer."""

    parsed = _parse("Купил за 50 евро, в чеке было 2600 гривен")

    assert "TRANSFER_NOT_AN_OPERATION" not in parsed.gaps


def test_the_two_sides_of_an_exchange_are_read_in_order() -> None:
    sides = read_transfer_sides("Перевёл 100 евро получил 5200 гривен", today=_TODAY)

    assert sides is not None
    sent, received = sides
    assert (sent.amount, sent.currency) == (Decimal("100"), "EUR")
    assert (received.amount, received.currency) == (Decimal("5200"), "UAH")


def test_a_sentence_that_is_not_an_exchange_has_no_sides() -> None:
    assert read_transfer_sides("Потратил 12,50 на продукты", today=_TODAY) is None


def test_the_transfer_route_reads_both_sides_and_the_day() -> None:
    """The sentence the operation route refuses is read here, in full."""

    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCategories(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/transfers/parse",
                json={
                    "text": "Вчера перевёл 100 евро получил 5200 гривен",
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
                headers=_AUTH,
            )
        assert response.status_code == 200, response.text
        proposal = response.json()["proposal"]
        assert proposal["sent"] == {"amount": "100", "currency": "EUR"}
        assert proposal["received"] == {"amount": "5200", "currency": "UAH"}
        assert proposal["occurredOn"] == "2026-08-12"
        # No rate travels, and none is stored anywhere (ADR 0029).
        assert set(proposal) == {"sent", "received", "occurredOn"}

    asyncio.run(scenario())


def test_the_transfer_route_says_plainly_when_a_sentence_is_not_one() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCategories(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/transfers/parse",
                json={
                    "text": "Потратил 12,50 на продукты",
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
                headers=_AUTH,
            )
        assert response.status_code == 200, response.text
        assert response.json()["proposal"] is None

    asyncio.run(scenario())


def test_the_transfer_route_needs_authentication() -> None:
    async def scenario() -> None:
        app = create_app(category_repository=_FakeCategories())
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/transfers/parse",
                json={
                    "text": "перевёл 100 евро получил 5200 гривен",
                    "capturedAt": "2026-08-13T09:00:00Z",
                    "capturedTimezone": "Europe/Berlin",
                },
            )
        assert response.status_code == 401

    asyncio.run(scenario())


# --- what the first voice measurement found ------------------------------------
#
# 22 phrases were recorded on a phone and transcribed (2026-10-26). Every amount
# was heard right; these three were read wrong by the parser, and each is wrong
# when typed too, so none of them is a voice defect.


@pytest.mark.parametrize(
    ("text", "expected", "amount"),
    [
        ("Третьего августа заплатил 150 за страховку", date(2026, 8, 3), "150"),
        ("Пятнадцатого июля купил билеты за 240", date(2026, 7, 15), "240"),
        ("Десятого августа заплатил 45", date(2026, 8, 10), "45"),
        # The tens word belongs to the date, not to the money.
        ("Двадцать восьмого июля купил телефон за 600", date(2026, 7, 28), "600"),
        (
            "Двадцать восьмого июля купил телефон за шестьсот",
            date(2026, 7, 28),
            "600",
        ),
        ("Тридцатого июля заплатил 12", date(2026, 7, 30), "12"),
        # How recognition writes «третьего» when it prefers digits.
        ("3-го августа заплатил 150 за страховку", date(2026, 8, 3), "150"),
        ("3го августа заплатил 150 за страховку", date(2026, 8, 3), "150"),
    ],
)
def test_a_day_said_as_an_ordinal_is_a_date(
    text: str, expected: date, amount: str
) -> None:
    """«Третьего августа» used to fall back to today without a word."""

    parsed = _parse(text)

    assert parsed.occurred_on == expected
    assert parsed.amount == Decimal(amount)
    assert parsed.source_expression is None
    assert "DATE_NOT_UNDERSTOOD" not in parsed.gaps
    assert "AMBIGUOUS_AMOUNT" not in parsed.gaps


def test_an_ordinal_day_without_a_year_takes_the_most_recent_one() -> None:
    """On 13 August, «третьего сентября» is last September, not next."""

    assert _parse("Третьего сентября заплатил 150").occurred_on == date(2025, 9, 3)


@pytest.mark.parametrize(
    ("text", "today", "expected"),
    [
        ("Первого числа заплатил 900 за аренду", _TODAY, date(2026, 8, 1)),
        ("5-го числа заплатил 70", _TODAY, date(2026, 8, 5)),
        # The day has not come yet this month, so it is last month's.
        ("Двадцатого числа заплатил 70", _TODAY, date(2026, 7, 20)),
        # July has a 31st; a month without one is skipped rather than invented.
        ("Тридцать первого числа заплатил 70", date(2026, 10, 26), date(2026, 8, 31)),
    ],
)
def test_a_day_of_the_month_is_its_most_recent_occurrence(
    text: str, today: date, expected: date
) -> None:
    parsed = parse_operation_text(text=text, today=today, categories=())

    assert parsed.occurred_on == expected
    assert parsed.amount is not None
    assert "AMBIGUOUS_AMOUNT" not in parsed.gaps


@pytest.mark.parametrize(
    "text",
    ["Поза вчера заплатил 80 за свет", "Поза-вчера заплатил 80 за свет"],
)
def test_the_day_before_yesterday_split_in_two_is_still_two_days(text: str) -> None:
    """Recognition writes «поза вчера»; reading only «вчера» lost a day silently."""

    parsed = _parse(text)

    assert parsed.occurred_on == date(2026, 8, 11)
    assert parsed.source_expression is None
    assert parsed.amount == Decimal("80")


@pytest.mark.parametrize(
    ("text", "amount", "currency"),
    [
        ("Пришла оплата за заказ 13 900 гривен", "13900", "UAH"),
        # As recognition heard it.
        ("Пришла плата за заказ. 13 900 гривен.", "13900", "UAH"),
        ("Поступил платёж 500", "500", "EUR"),
        ("Пришли деньги 200 евро", "200", "EUR"),
    ],
)
def test_money_that_arrived_is_income(text: str, amount: str, currency: str) -> None:
    """«Пришла оплата» was booked as a payment made: «оплата» is an expense word
    and only the neuter «пришло» was known to mean money coming in."""

    parsed = _parse(text)

    assert parsed.operation_type == "income"
    assert parsed.amount == Decimal(amount)
    assert parsed.currency == currency


@pytest.mark.parametrize(
    "text",
    [
        "Пришла в кафе и заплатила 20",
        "Пришёл в магазин, купил хлеб за 3",
        "Оплата интернета 20",
    ],
)
def test_a_verb_of_arrival_alone_proves_nothing(text: str) -> None:
    """A person arrives too. Only the verb next to what arrived means income."""

    assert _parse(text).operation_type == "expense"
