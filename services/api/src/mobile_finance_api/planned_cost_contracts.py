"""Strict versioned contracts for planned costs (ADR 0018).

A planned cost is a forecast, never an authoritative financial fact. These
messages therefore describe intent and lifecycle only; nothing here may be
summed into a balance, a monthly total, a net flow, or a trend point.
"""

from __future__ import annotations

import hashlib
import json
import unicodedata
from datetime import date, datetime
from typing import Annotated, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
    TypeAdapter,
    model_validator,
)

# The money, timestamp, date-range, and currency primitives are shared with
# operation v1 on purpose. They encode ADR 0006 transport rules, not operation
# semantics, and a second copy of the decimal regex would eventually drift.
from .operation_contracts import (
    CurrencyCode,
    MoneyInput,
    OperationDate,
    UtcTimestamp,
)


def _safe_text(value: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("text contains control characters")
    return unicodedata.normalize("NFC", value)


PlannedCostTitle = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_safe_text),
]
PlannedCostCategory = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_safe_text),
]

PlannedCostStatus = Literal["planned", "confirmed", "skipped", "cancelled"]
PlannedCostTransition = Literal["confirm", "skip", "cancel"]

PlannedCostIssueCode = Literal[
    "ACCOUNT_UNAVAILABLE",
    "ACCOUNT_CURRENCY_MISMATCH",
    "UNSUPPORTED_CURRENCY",
    "PLAN_BEFORE_ACCOUNT_BASELINE",
    "INVALID_LIFECYCLE_TRANSITION",
    "CONFIRMING_OPERATION_MISSING",
]
PlannedCostIssueField = Literal[
    "accountId",
    "currency",
    "plannedOn",
    "transition",
    "operationCommandId",
]
PlannedCostErrorCode = Literal[
    "MALFORMED_PLANNED_COST",
    "COMMAND_CONFLICT",
    "PLANNED_COST_REJECTED",
    "PLANNED_COST_NOT_FOUND",
    "PLANNED_COST_PERSISTENCE_UNAVAILABLE",
]


def transition_target_status(transition: PlannedCostTransition) -> PlannedCostStatus:
    """Map a requested transition to its single terminal status."""

    match transition:
        case "confirm":
            return "confirmed"
        case "skip":
            return "skipped"
        case "cancel":
            return "cancelled"


class PlannedCostApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class CreatePlannedCostCommand(PlannedCostApiModel):
    """Untrusted request to record one intended future payment."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    account_id: UUID = Field(alias="accountId")
    amount: MoneyInput
    currency: CurrencyCode
    title: PlannedCostTitle
    category: PlannedCostCategory | None = None
    planned_on: OperationDate = Field(alias="plannedOn")
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class TransitionPlannedCostCommand(PlannedCostApiModel):
    """Untrusted request to move one planned cost to a terminal status."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    transition: PlannedCostTransition
    # Confirmation never creates an operation here. The client commits the
    # operation first through the operation v1 path and then reports the
    # command_id it used, which the server resolves to an existing operation.
    operation_command_id: UUID | None = Field(
        default=None,
        alias="operationCommandId",
    )
    requested_at: UtcTimestamp = Field(alias="requestedAt")

    @model_validator(mode="after")
    def confirmation_carries_its_operation(self) -> Self:
        if self.transition == "confirm" and self.operation_command_id is None:
            raise ValueError("confirming a planned cost requires operationCommandId")
        if self.transition != "confirm" and self.operation_command_id is not None:
            raise ValueError("only confirmation may carry operationCommandId")
        return self


class PlannedCostIssue(PlannedCostApiModel):
    code: PlannedCostIssueCode
    field: PlannedCostIssueField


class PlannedCost(PlannedCostApiModel):
    """Authoritative forecast row. Never part of an authoritative money total."""

    planned_cost_id: UUID = Field(alias="plannedCostId")
    user_id: UUID = Field(alias="userId")
    account_id: UUID = Field(alias="accountId")
    command_id: UUID = Field(alias="commandId")
    amount: MoneyInput
    currency: CurrencyCode
    title: PlannedCostTitle
    category: PlannedCostCategory | None
    planned_on: OperationDate = Field(alias="plannedOn")
    status: PlannedCostStatus
    # Derived at read time from planned_on and today in the account's canonical
    # timezone. Never stored: a stored flag would need a per-timezone midnight
    # job and would assert something false whenever that job was late.
    is_due: bool = Field(alias="isDue")
    confirmed_operation_id: UUID | None = Field(alias="confirmedOperationId")
    created_at: UtcTimestamp = Field(alias="createdAt")
    updated_at: UtcTimestamp = Field(alias="updatedAt")

    @model_validator(mode="after")
    def lifecycle_is_consistent(self) -> Self:
        if self.is_due and self.status != "planned":
            raise ValueError("only a planned cost that is still planned can be due")
        if (self.status == "confirmed") != (self.confirmed_operation_id is not None):
            raise ValueError("confirmed status and operation link must agree")
        if self.updated_at < self.created_at:
            raise ValueError("updatedAt must not precede createdAt")
        return self


class CreatePlannedCostResponse(PlannedCostApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    planned_cost: PlannedCost = Field(alias="plannedCost")


class TransitionPlannedCostResponse(PlannedCostApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    planned_cost: PlannedCost = Field(alias="plannedCost")


class ListPlannedCostsResponse(PlannedCostApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    # The local date the server used to derive `isDue`, so a client never has to
    # guess which day the server considered "today".
    evaluated_on: OperationDate = Field(alias="evaluatedOn")
    planned_costs: tuple[PlannedCost, ...] = Field(alias="plannedCosts")


class PlannedCostErrorDetail(PlannedCostApiModel):
    code: PlannedCostErrorCode
    issues: tuple[PlannedCostIssue, ...] = ()

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "PLANNED_COST_REJECTED" and not self.issues:
            raise ValueError("planned cost rejection requires issues")
        if self.code != "PLANNED_COST_REJECTED" and self.issues:
            raise ValueError("only planned cost rejection may expose issues")
        return self


class PlannedCostErrorResponse(PlannedCostApiModel):
    detail: PlannedCostErrorDetail


type PlannedCostMessage = (
    CreatePlannedCostCommand
    | TransitionPlannedCostCommand
    | CreatePlannedCostResponse
    | TransitionPlannedCostResponse
    | ListPlannedCostsResponse
    | PlannedCostErrorResponse
)

_planned_cost_message_adapter: TypeAdapter[PlannedCostMessage] = TypeAdapter(
    PlannedCostMessage
)


def create_planned_cost_command_hash(command: CreatePlannedCostCommand) -> str:
    """Canonical hash binding a command_id to exact creation content."""

    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def transition_planned_cost_command_hash(
    *,
    planned_cost_id: UUID,
    command: TransitionPlannedCostCommand,
) -> str:
    """Canonical hash binding a command_id to one plan and one transition.

    The target plan comes from the request path, so it is folded in explicitly:
    replaying the same command_id against a different plan must be a conflict
    rather than a second accepted transition.
    """

    return _canonical_hash(
        {
            "plannedCostId": str(planned_cost_id),
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


def derive_is_due(*, planned_on: date, status: str, today_local: date) -> bool:
    """A plan is due once its local date arrives and it is still outstanding."""

    return status == "planned" and planned_on <= today_local


def local_today(*, now_utc: datetime, timezone: ZoneInfo) -> date:
    """Resolve the account-local calendar date for an aware UTC instant."""

    if now_utc.tzinfo is None or now_utc.utcoffset() is None:
        raise ValueError("now_utc must be timezone-aware")
    return now_utc.astimezone(timezone).date()


def planned_cost_contract_schema() -> dict[str, object]:
    """Build the canonical, reproducible JSON Schema for planned cost v1."""

    generated = _planned_cost_message_adapter.json_schema(
        ref_template="#/$defs/{model}",
    )
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": (
            "https://mobile-finance-assistant.local/"
            "contracts/finance/v1/planned_cost.schema.json"
        ),
        "title": "Planned cost v1 messages",
        "description": (
            "Strict messages for forecast-only planned costs and their "
            "idempotent lifecycle transitions."
        ),
        **generated,
    }
