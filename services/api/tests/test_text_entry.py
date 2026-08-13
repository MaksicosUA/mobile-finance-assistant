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
from mobile_finance_api.text_entry import CategoryOption, parse_operation_text
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
    ("text", "code"),
    [
        ("Потратил 500 евро", "EUR"),
        ("Получил 500 долларов", "USD"),
        ("Потратил 500 рублей", "RUB"),
        ("Потратил 500", "EUR"),
    ],
)
def test_currency_is_read_or_defaults(text: str, code: str) -> None:
    # An unsupported currency is still reported honestly: Finance Core is the
    # thing that refuses it, and it already does.
    assert _parse(text).currency == code


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

    async def __getattr__(self, name: str) -> object:  # pragma: no cover
        raise AttributeError(name)


class _ExplodingCategories:
    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        del user_id
        raise RuntimeError("the catalogue is unavailable")
