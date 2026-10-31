"""Strict versioned contracts for the category catalogue (ADR 0020).

A category is a label, never money. Nothing here may be summed into a balance,
a monthly total, a net flow, or a trend point.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    TypeAdapter,
    model_validator,
)

from .operation_contracts import UtcTimestamp


def _safe_text(value: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("text contains control characters")
    return unicodedata.normalize("NFC", value)


CategoryName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_safe_text),
]
# A stable slug, never user-authored text: the client renders a localized label
# for a key it knows and falls back to the stored name otherwise.
CategorySystemKey = Annotated[
    str,
    StringConstraints(pattern=r"^[a-z][a-z0-9_]{0,62}$"),
]

CategoryDirection = Literal["expense", "income"]

CategoryErrorCode = Literal[
    "MALFORMED_CATEGORY_QUERY",
    "MALFORMED_CATEGORY_COMMAND",
    "CATEGORY_NOT_FOUND",
    "CATEGORY_NAME_TAKEN",
    "CATEGORY_ARCHIVED",
    # A word leads to exactly one category per direction, so claiming one that
    # is already taken is refused with the owner named rather than silently
    # moved (ADR 0020 step 3).
    "CATEGORY_KEYWORD_TAKEN",
    "CATEGORY_PERSISTENCE_UNAVAILABLE",
]

#: The shortest keyword allowed. Below this it stops describing a category and
#: starts matching everything.
MINIMUM_CATEGORY_KEYWORD_LENGTH = 3

#: How many words one category may claim. A bound, not a judgement: it keeps
#: one request and one match cheap.
MAXIMUM_CATEGORY_KEYWORDS = 32

_KEYWORD_PATTERN = re.compile(r"^[^\W_]{3,40}$", re.UNICODE)


def _normalized_keyword(value: str) -> str:
    """One spelling per word, so matching never depends on how it was typed."""

    folded = _safe_text(value).strip().lower()
    if _KEYWORD_PATTERN.match(folded) is None:
        raise ValueError("a keyword is 3 to 40 letters or digits, without spaces")
    return folded


CategoryKeyword = Annotated[
    str,
    AfterValidator(_normalized_keyword),
]


class CategoryApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class Category(CategoryApiModel):
    """One owned category as the server stores it."""

    category_id: UUID = Field(alias="categoryId")
    name: CategoryName
    direction: CategoryDirection
    # Present only while the row is still the seeded one. Renaming clears it,
    # because after that the user's own name is the right label to show.
    system_key: CategorySystemKey | None = Field(default=None, alias="systemKey")
    created_at: UtcTimestamp = Field(alias="createdAt")


class ListCategoriesResponse(CategoryApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    categories: tuple[Category, ...]

    @model_validator(mode="after")
    def names_are_unique_per_direction(self) -> Self:
        seen: set[tuple[str, str]] = set()
        for category in self.categories:
            key = (category.direction, category.name.casefold())
            if key in seen:
                raise ValueError("duplicate category name in one direction")
            seen.add(key)
        return self


class ManagedCategory(Category):
    """One category as the management screen sees it.

    Deliberately a separate model from [Category] rather than a field added to
    it. The picker's `GET /api/v1/categories` is parsed by installed clients
    with a closed key set, item and envelope alike, so an additive field there
    would not degrade — it would stop the picker from loading at all. Managing
    the catalogue is a newer capability, so it gets its own representation and
    leaves the older one untouched.
    """

    # Null while the category is offered for new operations. Set once it is
    # hidden; the row itself is never deleted, so historical operations keep
    # their grouping (ADR 0020).
    archived_at: UtcTimestamp | None = Field(default=None, alias="archivedAt")


class ManagedCategoryListResponse(CategoryApiModel):
    """Every category the user owns, hidden ones included."""

    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    categories: tuple[ManagedCategory, ...]

    @model_validator(mode="after")
    def active_names_are_unique_per_direction(self) -> Self:
        # Only active rows are constrained. Two hidden categories may share a
        # name, and a hidden one may share a name with an active one, because
        # the uniqueness the database enforces excludes archived rows.
        seen: set[tuple[str, str]] = set()
        for category in self.categories:
            if category.archived_at is not None:
                continue
            key = (category.direction, category.name.casefold())
            if key in seen:
                raise ValueError("duplicate active category name in one direction")
            seen.add(key)
        return self


class CategoryResponse(CategoryApiModel):
    """The category as it stands after an accepted write."""

    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    category: ManagedCategory


class CreateCategoryCommand(CategoryApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    name: CategoryName
    direction: CategoryDirection


class RenameCategoryCommand(CategoryApiModel):
    """Rename one category.

    Carries no client command id. Every catalogue write is idempotent by target
    state: renaming to the name a category already has, hiding a hidden one, or
    restoring an active one all succeed without writing anything. A duplicate
    request therefore converges on one state rather than needing a replay key
    the way a financial command does (ADR 0009).
    """

    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    name: CategoryName


class CategoryErrorDetail(CategoryApiModel):
    code: CategoryErrorCode


class CategoryErrorResponse(CategoryApiModel):
    detail: CategoryErrorDetail


type CategoryMessage = (
    ListCategoriesResponse
    | ManagedCategoryListResponse
    | CategoryResponse
    | CreateCategoryCommand
    | RenameCategoryCommand
    | CategoryErrorResponse
)

_category_message_adapter: TypeAdapter[CategoryMessage] = TypeAdapter(CategoryMessage)


class SeededCategory(CategoryApiModel):
    """One entry of the starting set written at account bootstrap."""

    system_key: CategorySystemKey = Field(alias="systemKey")
    name: CategoryName
    direction: CategoryDirection


#: The languages a fresh catalogue can be written in (ADR 0034).
CatalogueLanguage = Literal["ru", "uk", "en", "de"]


def catalogue_language(accept_language: str | None) -> CatalogueLanguage:
    """The language a client asked for, in the terms a catalogue is written.

    No header means Russian, because every client that predates this sends none
    and they are all Russian. Asking for something else means English, which is
    the language most people can read when theirs is missing.
    """

    if accept_language is None:
        return "ru"
    tag = accept_language.split(",")[0].split(";")[0].strip().lower()
    language = tag.split("-")[0]
    if language == "ru":
        return "ru"
    if language == "uk":
        return "uk"
    if language == "de":
        return "de"
    return "en"


# Russian first, as the product requires. The key is what stays stable across
# languages; the name is the fallback label and the value a rename replaces.
SEEDED_CATEGORIES: tuple[SeededCategory, ...] = (
    SeededCategory(system_key="groceries", name="Продукты", direction="expense"),
    SeededCategory(
        system_key="eating_out", name="Кафе и рестораны", direction="expense"
    ),
    SeededCategory(system_key="transport", name="Транспорт", direction="expense"),
    SeededCategory(system_key="housing", name="Жильё", direction="expense"),
    SeededCategory(
        system_key="utilities", name="Связь и интернет", direction="expense"
    ),
    SeededCategory(system_key="health", name="Здоровье", direction="expense"),
    SeededCategory(system_key="clothing", name="Одежда", direction="expense"),
    SeededCategory(system_key="entertainment", name="Развлечения", direction="expense"),
    SeededCategory(system_key="education", name="Образование", direction="expense"),
    SeededCategory(system_key="gifts_out", name="Подарки", direction="expense"),
    SeededCategory(system_key="other_expense", name="Прочее", direction="expense"),
    SeededCategory(system_key="salary", name="Зарплата", direction="income"),
    SeededCategory(system_key="freelance", name="Подработка", direction="income"),
    SeededCategory(system_key="gifts_in", name="Подарки", direction="income"),
    SeededCategory(system_key="interest", name="Проценты", direction="income"),
    SeededCategory(system_key="other_income", name="Прочее", direction="income"),
)


class CategoryKeywordsResponse(CategoryApiModel):
    """The words that currently lead to one category."""

    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    category_id: UUID = Field(alias="categoryId")
    keywords: tuple[CategoryKeyword, ...]

    @model_validator(mode="after")
    def keywords_are_unique_and_bounded(self) -> Self:
        if len(set(self.keywords)) != len(self.keywords):
            raise ValueError("a keyword appears at most once")
        if len(self.keywords) > MAXIMUM_CATEGORY_KEYWORDS:
            raise ValueError("too many keywords")
        return self


class ReplaceCategoryKeywordsCommand(CategoryApiModel):
    """The whole set a category should end up with.

    Replacing rather than adding keeps the write idempotent by target state,
    which is how every other catalogue write behaves: no client command id, and
    sending the same set twice changes nothing.
    """

    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    keywords: tuple[CategoryKeyword, ...]

    @model_validator(mode="after")
    def keywords_are_unique_and_bounded(self) -> Self:
        if len(set(self.keywords)) != len(self.keywords):
            raise ValueError("a keyword appears at most once")
        if len(self.keywords) > MAXIMUM_CATEGORY_KEYWORDS:
            raise ValueError("too many keywords")
        return self


#: What a fresh catalogue starts knowing, keyed by the seeded category's stable
#: key. Chosen to be stems rather than whole words, because the parser matches
#: from a word start: "продукт" reads "продуктов", "авто" reads "автохимию".
#: Deliberately conservative — a wrong keyword misfiles money quietly, and the
#: user can add their own vocabulary, which no seeded list can guess.
SEEDED_CATEGORY_KEYWORDS: dict[str, tuple[str, ...]] = {
    "groceries": ("продукт", "еда", "магазин", "супермаркет", "grocer"),
    "eating_out": ("кафе", "ресторан", "кофе", "обед", "ужин", "бар"),
    "transport": (
        "транспорт",
        "такси",
        "метро",
        "автобус",
        "трамвай",
        "поезд",
        "билет",
    ),
    "housing": ("жиль", "аренда", "квартир", "ипотек", "коммунал"),
    "utilities": ("интернет", "связь", "мобильн", "телефон", "провайдер"),
    "health": ("здоровь", "врач", "аптек", "лекарств", "стоматолог", "клиник"),
    "clothing": ("одежд", "обувь", "куртк", "джинс", "футболк"),
    "entertainment": ("развлеч", "кино", "театр", "концерт", "игр", "подписк"),
    "education": ("образован", "курс", "учеб", "книг", "школ", "универ"),
    "gifts_out": ("подар", "сувенир"),
    "salary": ("зарплат", "оклад", "аванс"),
    "freelance": ("подработ", "фриланс", "заказ", "проект"),
    "gifts_in": ("подар",),
    "interest": ("процент", "вклад", "депозит"),
}

#: The same starting set in the other languages, keyed the same way. A name here
#: is written once, when the catalogue is created, and from then on is the
#: person's own like any name they typed: changing the app's language does not
#: rewrite it (ADR 0034).
_TRANSLATED_CATEGORY_NAMES: dict[CatalogueLanguage, dict[str, str]] = {
    "uk": {
        "groceries": "Продукти",
        "eating_out": "Кафе й ресторани",
        "transport": "Транспорт",
        "housing": "Житло",
        "utilities": "Зв'язок та інтернет",
        "health": "Здоров'я",
        "clothing": "Одяг",
        "entertainment": "Розваги",
        "education": "Освіта",
        "gifts_out": "Подарунки",
        "other_expense": "Інше",
        "salary": "Зарплата",
        "freelance": "Підробіток",
        "gifts_in": "Подарунки",
        "interest": "Відсотки",
        "other_income": "Інше",
    },
    "en": {
        "groceries": "Groceries",
        "eating_out": "Cafes and restaurants",
        "transport": "Transport",
        "housing": "Housing",
        "utilities": "Phone and internet",
        "health": "Health",
        "clothing": "Clothing",
        "entertainment": "Entertainment",
        "education": "Education",
        "gifts_out": "Gifts",
        "other_expense": "Other",
        "salary": "Salary",
        "freelance": "Side income",
        "gifts_in": "Gifts",
        "interest": "Interest",
        "other_income": "Other",
    },
    "de": {
        "groceries": "Lebensmittel",
        "eating_out": "Cafés und Restaurants",
        "transport": "Verkehr",
        "housing": "Wohnen",
        "utilities": "Telefon und Internet",
        "health": "Gesundheit",
        "clothing": "Kleidung",
        "entertainment": "Freizeit",
        "education": "Bildung",
        "gifts_out": "Geschenke",
        "other_expense": "Sonstiges",
        "salary": "Gehalt",
        "freelance": "Nebenverdienst",
        "gifts_in": "Geschenke",
        "interest": "Zinsen",
        "other_income": "Sonstiges",
    },
}

_TRANSLATED_CATEGORY_KEYWORDS: dict[CatalogueLanguage, dict[str, tuple[str, ...]]] = {
    "uk": {
        "groceries": ("продукт", "їжа", "їжу", "магазин", "супермаркет"),
        "eating_out": ("кафе", "ресторан", "кава", "каву", "обід", "вечер", "бар"),
        "transport": (
            "транспорт",
            "таксі",
            "метро",
            "автобус",
            "трамвай",
            "потяг",
            "поїзд",
            "квит",
        ),
        "housing": ("житл", "оренд", "квартир", "іпотек", "комунал"),
        "utilities": ("інтернет", "звязок", "мобільн", "телефон", "провайдер"),
        "health": ("здоров", "лікар", "аптек", "ліки", "стоматолог", "клінік"),
        "clothing": ("одяг", "взутт", "куртк", "джинс", "футболк"),
        "entertainment": ("розваг", "кіно", "театр", "концерт", "ігр", "підписк"),
        "education": ("освіт", "курс", "навчан", "книг", "школ", "універ"),
        "gifts_out": ("подарун", "сувенір"),
        "salary": ("зарплат", "оклад", "аванс"),
        "freelance": ("підробіт", "фріланс", "замовлен", "проєкт", "проект"),
        "gifts_in": ("подарун",),
        "interest": ("відсот", "вклад", "депозит"),
    },
    "en": {
        "groceries": ("grocer", "food", "supermarket"),
        "eating_out": (
            "cafe",
            "restaurant",
            "coffee",
            "lunch",
            "dinner",
            "breakfast",
        ),
        "transport": (
            "transport",
            "taxi",
            "uber",
            "metro",
            "subway",
            "train",
            "tram",
            "ticket",
        ),
        "housing": ("rent", "mortgage", "apartment", "housing"),
        "utilities": ("internet", "phone", "mobile", "broadband"),
        "health": ("health", "doctor", "pharmacy", "medicine", "dentist", "clinic"),
        "clothing": ("clothes", "clothing", "shoes", "jacket", "jeans", "shirt"),
        "entertainment": (
            "entertainment",
            "cinema",
            "movie",
            "theatre",
            "theater",
            "concert",
            "game",
            "subscription",
        ),
        "education": ("education", "course", "tuition", "book", "school", "universit"),
        "gifts_out": ("gift", "souvenir"),
        "salary": ("salary", "wage", "paycheck"),
        "freelance": ("freelance", "side", "project"),
        "gifts_in": ("gift",),
        "interest": ("interest", "deposit", "savings"),
    },
    "de": {
        "groceries": ("lebensmittel", "supermarkt", "einkauf", "rewe", "edeka", "aldi"),
        "eating_out": (
            "cafe",
            "café",
            "restaurant",
            "kaffee",
            "mittagessen",
            "abendessen",
            "kneipe",
        ),
        "transport": (
            "verkehr",
            "taxi",
            "bahn",
            "ubahn",
            "sbahn",
            "straßenbahn",
            "fahrkarte",
            "ticket",
        ),
        "housing": ("miete", "wohnung", "hypothek", "nebenkosten"),
        "utilities": ("internet", "telefon", "handy", "mobilfunk"),
        "health": (
            "gesundheit",
            "arzt",
            "zahnarzt",
            "apotheke",
            "medikament",
            "klinik",
        ),
        "clothing": ("kleidung", "schuhe", "jacke", "jeans", "hemd"),
        "entertainment": ("freizeit", "kino", "theater", "konzert", "spiel", "abo"),
        "education": ("bildung", "kurs", "schule", "buch", "bücher", "studium"),
        "gifts_out": ("geschenk", "souvenir"),
        "salary": ("gehalt", "lohn"),
        "freelance": ("nebenjob", "nebenverdienst", "freelance", "auftrag", "honorar"),
        "gifts_in": ("geschenk",),
        "interest": ("zinsen", "festgeld", "tagesgeld"),
    },
}


def seeded_categories(language: CatalogueLanguage) -> tuple[SeededCategory, ...]:
    """The starting set, named in `language`."""

    if language == "ru":
        return SEEDED_CATEGORIES
    names = _TRANSLATED_CATEGORY_NAMES[language]
    return tuple(
        seeded.model_copy(update={"name": names[seeded.system_key]})
        for seeded in SEEDED_CATEGORIES
    )


def seeded_category_keywords(
    language: CatalogueLanguage,
) -> dict[str, tuple[str, ...]]:
    """The starting vocabulary in `language`."""

    if language == "ru":
        return SEEDED_CATEGORY_KEYWORDS
    return _TRANSLATED_CATEGORY_KEYWORDS[language]


def category_contract_schema() -> dict[str, object]:
    """Build the canonical, reproducible JSON Schema for category v1."""

    generated = _category_message_adapter.json_schema(ref_template="#/$defs/{model}")
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": (
            "https://mobile-finance-assistant.local/"
            "contracts/finance/v1/category.schema.json"
        ),
        "title": "Category catalogue v1 messages",
        "description": (
            "Strict messages for the owned category catalogue. A category is a "
            "label and never an authoritative money value."
        ),
        **generated,
    }
