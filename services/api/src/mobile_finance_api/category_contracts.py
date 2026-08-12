"""Strict versioned contracts for the category catalogue (ADR 0020).

A category is a label, never money. Nothing here may be summed into a balance,
a monthly total, a net flow, or a trend point.
"""

from __future__ import annotations

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
    "CATEGORY_PERSISTENCE_UNAVAILABLE",
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
