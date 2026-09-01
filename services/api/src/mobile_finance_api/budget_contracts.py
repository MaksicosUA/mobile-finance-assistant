"""Strict versioned contract for monthly budgets (ADR 0027).

A budget carries a ceiling. Everything else on the wire — spent, remaining,
whether it is overspent — is derived from committed operations at read time and
sent already computed, so two screens cannot arrive at two answers.

Money crosses as a decimal string, exactly as it does on Home and Analytics.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from .models import DecimalString, UtcTimestamp
from .operation_contracts import CurrencyCode, MoneyInput

BudgetErrorCode = Literal[
    "MALFORMED_BUDGET",
    "COMMAND_CONFLICT",
    "BUDGET_REJECTED",
    "BUDGET_NOT_FOUND",
    "BUDGET_PERSISTENCE_UNAVAILABLE",
]
BudgetIssueCode = Literal[
    "ACCOUNT_UNAVAILABLE",
    "ACCOUNT_CURRENCY_MISMATCH",
    "UNSUPPORTED_CURRENCY",
    "CATEGORY_UNAVAILABLE",
    "CATEGORY_DIRECTION_MISMATCH",
    "BUDGET_ALREADY_REMOVED",
]
BudgetIssueField = Literal["accountId", "currency", "categoryId", "status"]


class BudgetApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class SetBudgetCommand(BudgetApiModel):
    """Declare or change one monthly ceiling."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    account_id: UUID = Field(alias="accountId")
    # Null is the overall monthly ceiling, not a missing value (ADR 0027).
    category_id: UUID | None = Field(default=None, alias="categoryId")
    limit: MoneyInput
    currency: CurrencyCode
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class RemoveBudgetCommand(BudgetApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class BudgetIssue(BudgetApiModel):
    code: BudgetIssueCode
    field: BudgetIssueField


class BudgetLine(BudgetApiModel):
    """One ceiling and how the month stands against it."""

    budget_id: UUID = Field(alias="budgetId")
    category_id: UUID | None = Field(alias="categoryId")
    #: The category's name, or null for the overall ceiling.
    name: Annotated[str, StringConstraints(max_length=100)] | None
    limit: DecimalString
    spent: DecimalString
    #: Limit minus spent. Negative when the month has gone over.
    remaining: DecimalString
    #: What is still planned for this period. Reported beside the remainder and
    #: never subtracted from it: mixing a forecast into the number that states
    #: fact is the one thing this product refuses to do (ADR 0018, ADR 0027).
    planned: DecimalString
    overspent: bool

    @model_validator(mode="after")
    def the_arithmetic_holds(self) -> Self:
        # Checked here so a wrong figure fails closed rather than being drawn.
        if self.remaining != self.limit - self.spent:
            raise ValueError("remaining must equal limit minus spent")
        if self.overspent != (self.remaining < 0):
            raise ValueError("overspent must agree with the remainder")
        if self.limit <= 0:
            raise ValueError("a ceiling must be positive")
        if self.spent < 0 or self.planned < 0:
            raise ValueError("spent and planned must not be negative")
        if (self.name is None) != (self.category_id is None):
            raise ValueError("a named line must carry a category, and vice versa")
        return self


class BudgetPeriod(BudgetApiModel):
    """The local month measured, in the account's canonical timezone."""

    start: date = Field(alias="from")
    end: date = Field(alias="to")

    @model_validator(mode="after")
    def start_precedes_end(self) -> Self:
        if self.start > self.end:
            raise ValueError("period start must not follow its end")
        return self


class BudgetsResponse(BudgetApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    period: BudgetPeriod
    currency: CurrencyCode
    #: The one ceiling on everything, when there is one.
    overall: BudgetLine | None
    categories: tuple[BudgetLine, ...]

    @model_validator(mode="after")
    def lines_are_the_shape_they_claim(self) -> Self:
        if self.overall is not None and self.overall.category_id is not None:
            raise ValueError("the overall ceiling carries no category")
        if any(line.category_id is None for line in self.categories):
            raise ValueError("a category line must carry its category")
        seen = [line.category_id for line in self.categories]
        if len(set(seen)) != len(seen):
            raise ValueError("a category may appear once")
        return self


class SetBudgetResponse(BudgetApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    budget_id: UUID = Field(alias="budgetId")
    category_id: UUID | None = Field(alias="categoryId")
    limit: DecimalString


class RemoveBudgetResponse(BudgetApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    budget_id: UUID = Field(alias="budgetId")


class BudgetErrorDetail(BudgetApiModel):
    code: BudgetErrorCode
    issues: tuple[BudgetIssue, ...] = ()

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "BUDGET_REJECTED" and not self.issues:
            raise ValueError("a budget rejection requires issues")
        if self.code != "BUDGET_REJECTED" and self.issues:
            raise ValueError("only a budget rejection may expose issues")
        return self


class BudgetErrorResponse(BudgetApiModel):
    detail: BudgetErrorDetail


def set_budget_command_hash(command: SetBudgetCommand) -> str:
    """Canonical hash binding a command_id to exact content."""

    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def remove_budget_command_hash(
    *,
    budget_id: UUID,
    command: RemoveBudgetCommand,
) -> str:
    """Canonical hash binding a command_id to one budget and one removal."""

    return _canonical_hash(
        {
            "budgetId": str(budget_id),
            "command": command.model_dump(mode="json", by_alias=True),
        }
    )


def _canonical_hash(payload: object) -> str:
    import hashlib
    import json

    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()
