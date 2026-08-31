"""Strict versioned contracts for recurring planned costs (ADR 0025).

A rule describes intent and generates ordinary planned costs. Like the plans it
produces, nothing here is an authoritative financial fact and nothing here may
be summed into a balance, a monthly total, a net flow, or a trend point.
"""

from __future__ import annotations

import hashlib
import json
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, model_validator

from .operation_contracts import (
    CurrencyCode,
    MoneyInput,
    OperationDate,
    UtcTimestamp,
)
from .planned_cost_contracts import PlannedCostCategory, PlannedCostTitle
from .planned_cost_recurrence import MAX_DAY_OF_MONTH, MIN_DAY_OF_MONTH

#: Monthly only for now. Weekly and yearly reuse the same anchor arithmetic and
#: are added by widening this deliberately, not by accident (ADR 0025).
RecurrenceFrequency = Literal["monthly"]
RecurrenceStatus = Literal["active", "ended"]

#: The day of the month the user meant, stored exactly as chosen. 29, 30 and 31
#: are accepted; each occurrence clamps into its own month, so a rule anchored
#: on the 31st lands on the last day of February rather than being refused.
DayOfMonth = Annotated[int, Field(ge=MIN_DAY_OF_MONTH, le=MAX_DAY_OF_MONTH)]

RecurrenceIssueCode = Literal[
    "ACCOUNT_UNAVAILABLE",
    "ACCOUNT_CURRENCY_MISMATCH",
    "UNSUPPORTED_CURRENCY",
    "RECURRENCE_BEFORE_ACCOUNT_BASELINE",
    "CATEGORY_UNAVAILABLE",
    "CATEGORY_DIRECTION_MISMATCH",
    "INVALID_LIFECYCLE_TRANSITION",
]
RecurrenceIssueField = Literal[
    "accountId",
    "currency",
    "startsOn",
    "categoryId",
    "status",
]
RecurrenceErrorCode = Literal[
    "MALFORMED_RECURRENCE",
    "COMMAND_CONFLICT",
    "RECURRENCE_REJECTED",
    "RECURRENCE_NOT_FOUND",
    "RECURRENCE_PERSISTENCE_UNAVAILABLE",
]


class RecurrenceApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class CreatePlannedCostRecurrenceCommand(RecurrenceApiModel):
    """Untrusted request to record one repeating intended payment."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    account_id: UUID = Field(alias="accountId")
    amount: MoneyInput
    currency: CurrencyCode
    title: PlannedCostTitle
    # The free text stays as the evidence of what the user wrote; the link is
    # what every report reads (ADR 0020).
    category: PlannedCostCategory | None = None
    category_id: UUID | None = Field(default=None, alias="categoryId")
    frequency: RecurrenceFrequency
    day_of_month: DayOfMonth = Field(alias="dayOfMonth")
    starts_on: OperationDate = Field(alias="startsOn")
    ends_on: OperationDate | None = Field(default=None, alias="endsOn")
    requested_at: UtcTimestamp = Field(alias="requestedAt")

    @model_validator(mode="after")
    def the_series_can_contain_something(self) -> Self:
        # Structural rather than a typed issue: a series that ends before it
        # begins is not a rule the product has an opinion about, it is a
        # malformed one.
        if self.ends_on is not None and self.ends_on < self.starts_on:
            raise ValueError("endsOn must not precede startsOn")
        return self


class EndPlannedCostRecurrenceCommand(RecurrenceApiModel):
    """Untrusted request to stop a rule from generating anything further.

    Ending a series is not skipping an instance: instances already generated
    and acted on are left exactly as they are (ADR 0025).
    """

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class RecurrenceIssue(RecurrenceApiModel):
    code: RecurrenceIssueCode
    field: RecurrenceIssueField


class PlannedCostRecurrence(RecurrenceApiModel):
    """Authoritative rule row. Never part of an authoritative money total."""

    recurrence_id: UUID = Field(alias="recurrenceId")
    user_id: UUID = Field(alias="userId")
    account_id: UUID = Field(alias="accountId")
    command_id: UUID = Field(alias="commandId")
    amount: MoneyInput
    currency: CurrencyCode
    title: PlannedCostTitle
    category: PlannedCostCategory | None
    category_id: UUID | None = Field(alias="categoryId")
    frequency: RecurrenceFrequency
    day_of_month: DayOfMonth = Field(alias="dayOfMonth")
    starts_on: OperationDate = Field(alias="startsOn")
    ends_on: OperationDate | None = Field(alias="endsOn")
    status: RecurrenceStatus
    created_at: UtcTimestamp = Field(alias="createdAt")
    updated_at: UtcTimestamp = Field(alias="updatedAt")

    @model_validator(mode="after")
    def the_series_is_consistent(self) -> Self:
        if self.ends_on is not None and self.ends_on < self.starts_on:
            raise ValueError("endsOn must not precede startsOn")
        if self.updated_at < self.created_at:
            raise ValueError("updatedAt must not precede createdAt")
        return self


class CreatePlannedCostRecurrenceResponse(RecurrenceApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    recurrence: PlannedCostRecurrence
    # The dates this rule has just materialised, so the interface can show the
    # user where the 31st actually lands before February surprises them.
    occurrences: tuple[OperationDate, ...]


class EndPlannedCostRecurrenceResponse(RecurrenceApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    recurrence: PlannedCostRecurrence
    # How many not-yet-acted-on future instances were withdrawn with it.
    cancelled_occurrences: int = Field(alias="cancelledOccurrences")


class ListPlannedCostRecurrencesResponse(RecurrenceApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    recurrences: tuple[PlannedCostRecurrence, ...]


class RecurrenceErrorDetail(RecurrenceApiModel):
    code: RecurrenceErrorCode
    issues: tuple[RecurrenceIssue, ...] = ()

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "RECURRENCE_REJECTED" and not self.issues:
            raise ValueError("recurrence rejection requires issues")
        if self.code != "RECURRENCE_REJECTED" and self.issues:
            raise ValueError("only recurrence rejection may expose issues")
        return self


class RecurrenceErrorResponse(RecurrenceApiModel):
    detail: RecurrenceErrorDetail


type PlannedCostRecurrenceMessage = (
    CreatePlannedCostRecurrenceCommand
    | EndPlannedCostRecurrenceCommand
    | CreatePlannedCostRecurrenceResponse
    | EndPlannedCostRecurrenceResponse
    | ListPlannedCostRecurrencesResponse
    | RecurrenceErrorResponse
)

_recurrence_message_adapter: TypeAdapter[PlannedCostRecurrenceMessage] = TypeAdapter(
    PlannedCostRecurrenceMessage
)


def create_recurrence_command_hash(
    command: CreatePlannedCostRecurrenceCommand,
) -> str:
    """Canonical hash binding a command_id to exact rule content."""

    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def end_recurrence_command_hash(
    *,
    recurrence_id: UUID,
    command: EndPlannedCostRecurrenceCommand,
) -> str:
    """Canonical hash binding a command_id to one rule and one ending.

    The target comes from the request path, so it is folded in explicitly:
    replaying the same command_id against a different rule must be a conflict
    rather than a second accepted ending.
    """

    return _canonical_hash(
        {
            "recurrenceId": str(recurrence_id),
            "command": command.model_dump(mode="json", by_alias=True),
        }
    )


def _canonical_hash(payload: object) -> str:
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def planned_cost_recurrence_contract_schema() -> dict[str, object]:
    """Build the canonical, reproducible JSON Schema for recurrence v1."""

    generated = _recurrence_message_adapter.json_schema(
        ref_template="#/$defs/{model}",
    )
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": (
            "https://mobile-finance-assistant.local/"
            "contracts/finance/v1/planned_cost_recurrence.schema.json"
        ),
        "title": "Planned cost recurrence v1 messages",
        "description": (
            "Strict messages for a rule that generates forecast-only planned "
            "costs, and for ending one."
        ),
        **generated,
    }


__all__ = [
    "CreatePlannedCostRecurrenceCommand",
    "CreatePlannedCostRecurrenceResponse",
    "DayOfMonth",
    "EndPlannedCostRecurrenceCommand",
    "EndPlannedCostRecurrenceResponse",
    "ListPlannedCostRecurrencesResponse",
    "PlannedCostRecurrence",
    "RecurrenceErrorCode",
    "RecurrenceErrorDetail",
    "RecurrenceErrorResponse",
    "RecurrenceFrequency",
    "RecurrenceIssue",
    "RecurrenceIssueCode",
    "RecurrenceIssueField",
    "RecurrenceStatus",
    "create_recurrence_command_hash",
    "end_recurrence_command_hash",
    "planned_cost_recurrence_contract_schema",
]
