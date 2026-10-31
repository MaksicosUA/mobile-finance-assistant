"""The words that lead to a category (ADR 0020 step 3).

A name and a keyword do different jobs: the name is what reports show, the
keyword is what a sentence is matched against. These tests pin the rules that
keep that separation honest — one word means one category per direction, the
stored form is normalized, and a word is never silently taken from another
category.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.category_contracts import (
    MAXIMUM_CATEGORY_KEYWORDS,
    MINIMUM_CATEGORY_KEYWORD_LENGTH,
    SEEDED_CATEGORIES,
    SEEDED_CATEGORY_KEYWORDS,
    CatalogueLanguage,
    CategoryKeywordsResponse,
    ReplaceCategoryKeywordsCommand,
    catalogue_language,
    seeded_categories,
    seeded_category_keywords,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.postgres_category_repository import (
    CategoryArchived,
    CategoryKeywordTaken,
    CategoryNotFound,
    seeded_category_keyword_rows,
    seeded_category_rows,
)
from mobile_finance_api.text_entry import CategoryOption, parse_operation_text

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_CAR = UUID("22222222-2222-4222-8222-222222222222")
_MISSING = UUID("99999999-9999-4999-8999-999999999999")
_AUTH = {"Authorization": "Bearer synthetic-token"}
_PATH = f"/api/v1/categories/{_CAR}/keywords"


# --- the starting vocabulary -------------------------------------------------


def test_every_seeded_keyword_set_belongs_to_a_seeded_category() -> None:
    keys = {seeded.system_key for seeded in SEEDED_CATEGORIES}

    assert set(SEEDED_CATEGORY_KEYWORDS) <= keys


def test_no_seeded_word_leads_to_two_categories_of_one_direction() -> None:
    """The database enforces this per user; here it is caught before shipping.

    Two categories claiming one word would make the match depend on row order.
    """

    direction_of = {seeded.system_key: seeded.direction for seeded in SEEDED_CATEGORIES}
    seen: dict[tuple[str, str], str] = {}
    for key, keywords in SEEDED_CATEGORY_KEYWORDS.items():
        for keyword in keywords:
            slot = (direction_of[key], keyword)
            assert slot not in seen, (slot, seen.get(slot), key)
            seen[slot] = key


def test_every_seeded_keyword_satisfies_the_stored_shape() -> None:
    for keywords in SEEDED_CATEGORY_KEYWORDS.values():
        accepted = ReplaceCategoryKeywordsCommand(keywords=keywords).keywords
        assert accepted == keywords
        for keyword in keywords:
            assert len(keyword) >= MINIMUM_CATEGORY_KEYWORD_LENGTH


def test_the_catch_all_categories_claim_nothing() -> None:
    """ "Прочее" must never win a sentence: it is where nothing else fit."""

    assert "other_expense" not in SEEDED_CATEGORY_KEYWORDS
    assert "other_income" not in SEEDED_CATEGORY_KEYWORDS


# --- contract ----------------------------------------------------------------


def test_a_keyword_is_stored_in_one_spelling() -> None:
    command = ReplaceCategoryKeywordsCommand.model_validate(
        {"keywords": ["  Авто ", "МАШИН", "Car"]}
    )

    # Matching must not depend on how the word was typed.
    assert command.keywords == ("авто", "машин", "car")


@pytest.mark.parametrize(
    "keywords",
    [
        ["ав"],
        ["с пробелом"],
        ["под_черк"],
        ["авто", "авто"],
        ["слово"] * (MAXIMUM_CATEGORY_KEYWORDS + 1),
    ],
)
def test_malformed_keyword_sets_are_refused(keywords: list[str]) -> None:
    with pytest.raises(ValidationError):
        ReplaceCategoryKeywordsCommand.model_validate({"keywords": keywords})


def test_an_empty_set_is_allowed() -> None:
    """Removing every word is a real intent, not a malformed request."""

    assert ReplaceCategoryKeywordsCommand(keywords=()).keywords == ()


# --- transport ---------------------------------------------------------------


def test_reading_or_writing_keywords_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            read = await client.get(_PATH)
            written = await client.put(_PATH, json={"keywords": ["авто"]})
        assert read.status_code == 401
        assert written.status_code == 401

    asyncio.run(scenario())


def test_the_words_of_a_category_are_readable() -> None:
    async def scenario() -> None:
        response = await _call("get", _FakeKeywords(current=("авто", "машин")))
        assert response.status_code == 200, response.text
        assert response.json()["keywords"] == ["авто", "машин"]
        assert response.json()["categoryId"] == str(_CAR)

    asyncio.run(scenario())


def test_replacing_the_set_sends_the_whole_set() -> None:
    async def scenario() -> None:
        repository = _FakeKeywords(current=("авто",))
        response = await _call("put", repository, json={"keywords": ["авто", "заправ"]})
        assert response.status_code == 200, response.text
        assert response.json()["keywords"] == ["авто", "заправ"]
        assert repository.replaced == [("авто", "заправ")]
        assert "X-Category-Unchanged" not in response.headers

    asyncio.run(scenario())


def test_an_unchanged_set_says_so_instead_of_failing() -> None:
    async def scenario() -> None:
        repository = _FakeKeywords(current=("авто",), changed=False)
        response = await _call("put", repository, json={"keywords": ["авто"]})
        assert response.status_code == 200, response.text
        # A retried request is not an error; the caller's intent already holds.
        assert response.headers["X-Category-Unchanged"] == "1"

    asyncio.run(scenario())


def test_a_word_that_leads_elsewhere_is_refused_with_its_owner() -> None:
    async def scenario() -> None:
        repository = _FakeKeywords(
            failure=CategoryKeywordTaken(keyword="авто", owner="Транспорт")
        )
        response = await _call("put", repository, json={"keywords": ["авто"]})
        assert response.status_code == 409, response.text
        detail = response.json()["detail"]
        assert detail["code"] == "CATEGORY_KEYWORD_TAKEN"
        # Named so the user can act on the refusal rather than guess.
        assert detail["keyword"] == "авто"
        assert detail["owner"] == "Транспорт"

    asyncio.run(scenario())


def test_a_hidden_category_is_not_taught_new_words() -> None:
    async def scenario() -> None:
        repository = _FakeKeywords(failure=CategoryArchived())
        response = await _call("put", repository, json={"keywords": ["авто"]})
        assert response.status_code == 409, response.text
        assert response.json()["detail"]["code"] == "CATEGORY_ARCHIVED"

    asyncio.run(scenario())


def test_another_user_category_is_not_found_rather_than_refused() -> None:
    async def scenario() -> None:
        repository = _FakeKeywords(failure=CategoryNotFound())
        for method, payload in (("get", None), ("put", {"keywords": ["авто"]})):
            response = await _call(method, repository, json=payload)
            assert response.status_code == 404, response.text

    asyncio.run(scenario())


def test_a_malformed_keyword_never_reaches_the_store() -> None:
    async def scenario() -> None:
        repository = _FakeKeywords()
        response = await _call("put", repository, json={"keywords": ["ав"]})
        assert response.status_code == 422, response.text
        assert repository.replaced == []

    asyncio.run(scenario())


async def _call(
    method: str,
    repository: _FakeKeywords,
    *,
    json: dict[str, object] | None = None,
):  # type: ignore[no-untyped-def]
    app = create_app(
        current_user_authenticator=_StaticAuthenticator(),
        category_repository=repository,
    )
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        if method == "get":
            return await client.get(_PATH, headers=_AUTH)
        return await client.put(_PATH, json=json, headers=_AUTH)


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


class _FakeKeywords:
    def __init__(
        self,
        *,
        current: tuple[str, ...] = (),
        changed: bool = True,
        failure: Exception | None = None,
    ) -> None:
        self.current = current
        self.changed = changed
        self.failure = failure
        self.replaced: list[tuple[str, ...]] = []

    async def list_keywords(
        self, *, user_id: UUID, category_id: UUID
    ) -> CategoryKeywordsResponse:
        del user_id
        if self.failure is not None:
            raise self.failure
        return CategoryKeywordsResponse(category_id=category_id, keywords=self.current)

    async def replace_keywords(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
        command: ReplaceCategoryKeywordsCommand,
    ) -> tuple[CategoryKeywordsResponse, bool]:
        del user_id
        if self.failure is not None:
            raise self.failure
        self.replaced.append(command.keywords)
        return (
            CategoryKeywordsResponse(
                category_id=category_id, keywords=command.keywords
            ),
            self.changed,
        )


# --- the catalogue in other languages (ADR 0034) ------------------------------


@pytest.mark.parametrize("language", ["ru", "uk", "en", "de"])
def test_every_language_seeds_the_same_set(language: CatalogueLanguage) -> None:
    seeded = seeded_categories(language)

    assert [row.system_key for row in seeded] == [
        row.system_key for row in SEEDED_CATEGORIES
    ]
    assert [row.direction for row in seeded] == [
        row.direction for row in SEEDED_CATEGORIES
    ]
    pairs = [(row.direction, row.name) for row in seeded]
    assert len(pairs) == len(set(pairs))


@pytest.mark.parametrize("language", ["uk", "en", "de"])
def test_another_language_really_is_another_language(
    language: CatalogueLanguage,
) -> None:
    russian = {row.name for row in SEEDED_CATEGORIES}

    # «Транспорт» and «Зарплата» are spelled the same in Ukrainian.
    assert len({row.name for row in seeded_categories(language)} & russian) <= 2


@pytest.mark.parametrize("language", ["ru", "uk", "en", "de"])
def test_a_language_keeps_the_rules_of_the_vocabulary(
    language: CatalogueLanguage,
) -> None:
    vocabulary = seeded_category_keywords(language)
    direction_of = {row.system_key: row.direction for row in SEEDED_CATEGORIES}
    assert set(vocabulary) == set(SEEDED_CATEGORY_KEYWORDS)

    seen: dict[tuple[str, str], str] = {}
    for key, keywords in vocabulary.items():
        accepted = ReplaceCategoryKeywordsCommand(keywords=keywords).keywords
        assert accepted == keywords
        for keyword in keywords:
            assert len(keyword) >= MINIMUM_CATEGORY_KEYWORD_LENGTH
            slot = (direction_of[key], keyword)
            assert slot not in seen, (slot, seen.get(slot), key)
            seen[slot] = key


@pytest.mark.parametrize(
    ("language", "sentence", "key"),
    [
        ("uk", "купив продукти на 200", "groceries"),
        ("uk", "заплатив за оренду квартири 300", "housing"),
        ("en", "bought groceries for 20", "groceries"),
        ("en", "paid the rent 800", "housing"),
        ("de", "Lebensmittel für 20 Euro gekauft", "groceries"),
        ("de", "Straßenbahn 3 Euro", "transport"),
        ("de", "Miete 800 Euro bezahlt", "housing"),
    ],
)
def test_a_seeded_word_reads_a_sentence_in_its_language(
    language: CatalogueLanguage, sentence: str, key: str
) -> None:
    vocabulary = seeded_category_keywords(language)
    ids = {row.system_key: uuid4() for row in SEEDED_CATEGORIES}
    options = tuple(
        CategoryOption(
            category_id=ids[row.system_key],
            name=row.name,
            direction=row.direction,
            keywords=vocabulary.get(row.system_key, ()),
        )
        for row in seeded_categories(language)
    )

    parsed = parse_operation_text(
        text=sentence, today=date(2026, 10, 31), categories=options
    )

    assert parsed.category_id == ids[key]


@pytest.mark.parametrize(
    ("header", "language"),
    [
        (None, "ru"),
        ("ru", "ru"),
        ("ru-RU", "ru"),
        ("uk", "uk"),
        ("uk-UA,uk;q=0.9", "uk"),
        ("de-DE", "de"),
        ("en-GB", "en"),
        ("fr-FR", "en"),
        ("*", "en"),
        ("", "en"),
    ],
)
def test_the_language_a_client_asks_for(
    header: str | None, language: CatalogueLanguage
) -> None:
    assert catalogue_language(header) == language


def test_a_catalogue_seeded_in_german_is_written_in_german() -> None:
    now = datetime(2026, 10, 31, tzinfo=UTC)
    categories = seeded_category_rows(user_id=uuid4(), created_at=now, language="de")
    keywords = seeded_category_keyword_rows(
        categories=categories, created_at=now, language="de"
    )

    assert "Lebensmittel" in {row.name for row in categories}
    assert "lebensmittel" in {row.keyword for row in keywords}
