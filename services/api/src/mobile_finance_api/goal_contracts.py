"""Strict versioned contracts for savings goals and contributions (ADR 0019).

A goal is a target and a contribution is an earmark of money that is already in
the account. Nothing here may be summed into a balance, a monthly total, a net
flow, or a trend point.

`current`, `progress_percent`, and `achieved` are derived from the contribution
ledger at read time and are never stored on the goal.
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from decimal import ROUND_DOWN, Decimal, InvalidOperation
from typing import Annotated, Literal, Self
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    PlainSerializer,
    StringConstraints,
    TypeAdapter,
    WithJsonSchema,
    model_validator,
)

# Shared with operation v1 and planned costs on purpose: these primitives encode
# the ADR 0006 transport rules, and a second copy of the decimal regex would
# eventually drift.
from .decimal_math import wide_decimal_context
from .operation_contracts import (
    CurrencyCode,
    EntryMoney,
    MoneyInput,
    OperationDate,
    UtcTimestamp,
)

_HUNDRED = Decimal(100)
_PERCENT_QUANTUM = Decimal(1).scaleb(-18)

# `MoneyInput` is strictly positive, which is right for a target and for a
# ledger entry. A goal's derived balance, its declared monthly intent, and its
# progress are legitimately zero, so they need their own primitive rather than a
# relaxation of the shared one.
_NON_NEGATIVE_DECIMAL_PATTERN = (
    r"^(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?|0(?:\.[0-9]{1,18})?)$"
)
_NON_NEGATIVE_DECIMAL = re.compile(_NON_NEGATIVE_DECIMAL_PATTERN)


def _parse_non_negative_money(value: object) -> Decimal:
    if isinstance(value, Decimal):
        amount = value
    elif isinstance(value, str) and _NON_NEGATIVE_DECIMAL.fullmatch(value) is not None:
        try:
            amount = Decimal(value)
        except InvalidOperation as error:  # pragma: no cover - guarded by regex
            raise ValueError("amount must be a decimal string") from error
    else:
        raise ValueError("amount must be a plain decimal string")
    if not amount.is_finite() or amount < 0:
        raise ValueError("amount must be non-negative and finite")
    exponent = amount.as_tuple().exponent
    if not isinstance(exponent, int):  # pragma: no cover - finite guard above
        raise ValueError("amount must be finite")
    if max(-exponent, 0) > 18 or max(amount.adjusted() + 1, 1) > 20:
        raise ValueError("amount exceeds NUMERIC(38,18)")
    return amount


def _non_negative_decimal_string(value: Decimal) -> str:
    rendered = format(value, "f")
    if "." in rendered:
        rendered = rendered.rstrip("0").rstrip(".")
    return rendered


NonNegativeMoney = Annotated[
    Decimal,
    BeforeValidator(_parse_non_negative_money),
    PlainSerializer(_non_negative_decimal_string, return_type=str, when_used="json"),
    WithJsonSchema(
        {
            "type": "string",
            "pattern": _NON_NEGATIVE_DECIMAL_PATTERN,
            "maxLength": 39,
            "description": (
                "Non-negative finite decimal string; max 20 integer and 18 "
                "fraction digits."
            ),
        }
    ),
]


def _safe_text(value: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("text contains control characters")
    return unicodedata.normalize("NFC", value)


GoalTitle = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_safe_text),
]

GoalStatus = Literal["active", "cancelled"]
GoalContributionDirection = Literal["deposit", "withdrawal"]

GoalIssueCode = Literal[
    "ACCOUNT_UNAVAILABLE",
    "ACCOUNT_CURRENCY_MISMATCH",
    "UNSUPPORTED_CURRENCY",
    "TARGET_BEFORE_ACCOUNT_BASELINE",
    "CONTRIBUTION_BEFORE_ACCOUNT_BASELINE",
    "FUTURE_CONTRIBUTION_DATE",
    "GOAL_NOT_ACTIVE",
    "WITHDRAWAL_EXCEEDS_GOAL_BALANCE",
]
GoalIssueField = Literal[
    "accountId",
    "currency",
    "targetOn",
    "occurredOn",
    "status",
    "amount",
]
GoalErrorCode = Literal[
    "MALFORMED_GOAL_COMMAND",
    "COMMAND_CONFLICT",
    "GOAL_REJECTED",
    "GOAL_NOT_FOUND",
    "GOAL_PERSISTENCE_UNAVAILABLE",
]


class GoalApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class CreateGoalCommand(GoalApiModel):
    """Untrusted request to record one savings target."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    account_id: UUID = Field(alias="accountId")
    title: GoalTitle
    target_amount: MoneyInput = Field(alias="targetAmount")
    currency: CurrencyCode
    # Required in v1: `HomeGoal.dueDate` is non-null on both Home revisions, so a
    # deadline-free goal cannot be rendered without a contract change (ADR 0019).
    target_on: OperationDate = Field(alias="targetOn")
    # The user's declared monthly intent. Nothing enforces it. Omitting it means
    # "no declared monthly plan"; a positive value is required when it is sent,
    # so a client cannot express absence two different ways.
    monthly_contribution: MoneyInput | None = Field(
        default=None,
        alias="monthlyContribution",
    )
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class CancelGoalCommand(GoalApiModel):
    """Untrusted request to stop pursuing one goal without erasing its ledger."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class RecordGoalContributionCommand(GoalApiModel):
    """Untrusted request to append one immutable ledger entry to a goal."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    direction: GoalContributionDirection
    amount: EntryMoney
    # Omitted means "today" in the account's canonical timezone, resolved by the
    # server. A client never has to guess which day the server considers today.
    occurred_on: OperationDate | None = Field(default=None, alias="occurredOn")
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class GoalIssue(GoalApiModel):
    code: GoalIssueCode
    field: GoalIssueField


class GoalContribution(GoalApiModel):
    """Authoritative, immutable ledger entry. Never an authoritative total."""

    contribution_id: UUID = Field(alias="contributionId")
    goal_id: UUID = Field(alias="goalId")
    user_id: UUID = Field(alias="userId")
    command_id: UUID = Field(alias="commandId")
    direction: GoalContributionDirection
    amount: MoneyInput
    currency: CurrencyCode
    occurred_on: OperationDate = Field(alias="occurredOn")
    created_at: UtcTimestamp = Field(alias="createdAt")

    @model_validator(mode="after")
    def amount_is_positive(self) -> Self:
        if self.amount <= 0:
            raise ValueError("a contribution amount must be positive")
        return self


class Goal(GoalApiModel):
    """Authoritative goal plus the figures derived from its ledger."""

    goal_id: UUID = Field(alias="goalId")
    user_id: UUID = Field(alias="userId")
    account_id: UUID = Field(alias="accountId")
    command_id: UUID = Field(alias="commandId")
    title: GoalTitle
    target_amount: MoneyInput = Field(alias="targetAmount")
    # Derived: the sum of the goal's ledger. Never stored, so it can never
    # disagree with the contributions behind it (ADR 0019).
    current_amount: NonNegativeMoney = Field(alias="currentAmount")
    monthly_contribution: NonNegativeMoney = Field(alias="monthlyContribution")
    currency: CurrencyCode
    target_on: OperationDate = Field(alias="targetOn")
    status: GoalStatus
    # Derived from current and target, so a later withdrawal simply stops being
    # achieved instead of needing a flag unflipped.
    achieved: bool
    # Saturates at 100 because the Home projection bounds it there; the amount
    # stays honest about over-funding.
    progress_percent: NonNegativeMoney = Field(alias="progressPercent")
    created_at: UtcTimestamp = Field(alias="createdAt")
    updated_at: UtcTimestamp = Field(alias="updatedAt")

    @model_validator(mode="after")
    def derived_values_are_consistent(self) -> Self:
        if self.target_amount <= 0:
            raise ValueError("a goal target must be positive")
        if self.current_amount < 0:
            raise ValueError("a goal balance must never be negative")
        if self.monthly_contribution < 0:
            raise ValueError("a declared monthly contribution must not be negative")
        if not Decimal(0) <= self.progress_percent <= _HUNDRED:
            raise ValueError("goal progress must be between 0 and 100")
        if self.achieved != (self.current_amount >= self.target_amount):
            raise ValueError("achieved must follow current and target")
        if self.updated_at < self.created_at:
            raise ValueError("updatedAt must not precede createdAt")
        return self


class CreateGoalResponse(GoalApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    goal: Goal


class CancelGoalResponse(GoalApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    goal: Goal


class RecordGoalContributionResponse(GoalApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    contribution: GoalContribution
    # The goal is returned with the entry already applied, so a client never has
    # to recompute the derived total itself.
    goal: Goal


class ListGoalsResponse(GoalApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    # The local date the server used, so a client never has to guess it.
    evaluated_on: OperationDate = Field(alias="evaluatedOn")
    goals: tuple[Goal, ...]


class ListGoalContributionsResponse(GoalApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    goal: Goal
    contributions: tuple[GoalContribution, ...]


class GoalErrorDetail(GoalApiModel):
    code: GoalErrorCode
    issues: tuple[GoalIssue, ...] = ()

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "GOAL_REJECTED" and not self.issues:
            raise ValueError("goal rejection requires issues")
        if self.code != "GOAL_REJECTED" and self.issues:
            raise ValueError("only goal rejection may expose issues")
        return self


class GoalErrorResponse(GoalApiModel):
    detail: GoalErrorDetail


type GoalMessage = (
    CreateGoalCommand
    | CancelGoalCommand
    | RecordGoalContributionCommand
    | CreateGoalResponse
    | CancelGoalResponse
    | RecordGoalContributionResponse
    | ListGoalsResponse
    | ListGoalContributionsResponse
    | GoalErrorResponse
)

_goal_message_adapter: TypeAdapter[GoalMessage] = TypeAdapter(GoalMessage)


def create_goal_command_hash(command: CreateGoalCommand) -> str:
    """Canonical hash binding a command_id to exact creation content."""

    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def cancel_goal_command_hash(*, goal_id: UUID, command: CancelGoalCommand) -> str:
    """Canonical hash binding a command_id to one goal and one cancellation.

    The target goal comes from the request path, so it is folded in explicitly:
    replaying the same command_id against a different goal must be a conflict
    rather than a second accepted cancellation.
    """

    return _canonical_hash(
        {
            "goalId": str(goal_id),
            "command": command.model_dump(mode="json", by_alias=True),
        }
    )


def contribution_command_hash(
    *,
    goal_id: UUID,
    command: RecordGoalContributionCommand,
) -> str:
    """Canonical hash binding a command_id to one goal and one ledger entry."""

    return _canonical_hash(
        {
            "goalId": str(goal_id),
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


def apply_contribution(
    *,
    current: Decimal,
    direction: str,
    amount: Decimal,
) -> Decimal:
    """Fold one ledger entry into a running goal balance."""

    return current + amount if direction == "deposit" else current - amount


def derive_goal_balance(
    entries: tuple[tuple[str, Decimal], ...],
) -> Decimal:
    """Sum a goal's ledger as deposits minus withdrawals."""

    total = Decimal(0)
    for direction, amount in entries:
        total = apply_contribution(current=total, direction=direction, amount=amount)
    return total


def derive_progress_percent(*, current: Decimal, target: Decimal) -> Decimal:
    """Progress toward a goal, saturated at 100 and never negative.

    Saturation is required by `ck_home_projection_primary_goals_bounds` and
    loses nothing: the honest over-funded figure stays visible as `current`.
    """

    if target <= 0:  # pragma: no cover - forbidden by the schema and contract
        raise ValueError("a goal target must be positive")
    if current <= 0:
        return Decimal(0)
    if current >= target:
        return _HUNDRED
    with wide_decimal_context():
        ratio = (current / target) * _HUNDRED
    # An exact ratio rarely fits NUMERIC(38,18). Truncating rather than rounding
    # keeps a goal one cent short of its target from displaying as 100%.
    return ratio.quantize(_PERCENT_QUANTUM, rounding=ROUND_DOWN)


def derive_achieved(*, current: Decimal, target: Decimal) -> bool:
    """A goal is achieved while its ledger covers its target."""

    return current >= target


def goal_contract_schema() -> dict[str, object]:
    """Build the canonical, reproducible JSON Schema for goal v1."""

    generated = _goal_message_adapter.json_schema(ref_template="#/$defs/{model}")
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": (
            "https://mobile-finance-assistant.local/"
            "contracts/finance/v1/goal.schema.json"
        ),
        "title": "Savings goal v1 messages",
        "description": (
            "Strict messages for savings goals and their append-only "
            "contribution ledger. No message here is an authoritative money "
            "movement."
        ),
        **generated,
    }
