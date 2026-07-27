"""Strict versioned contracts for deterministic Finance Core operations."""

from __future__ import annotations

import re
import unicodedata
from datetime import UTC, date, datetime
from decimal import Decimal, InvalidOperation
from typing import Annotated, Literal, Self
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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

_POSITIVE_DECIMAL_PATTERN = (
    r"^(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?"
    r"|0\.(?!0{1,18}$)[0-9]{1,18})$"
)
_DECIMAL_PATTERN = re.compile(_POSITIVE_DECIMAL_PATTERN)
_CURRENCY_PATTERN = r"^[A-Z]{3}$"
_MIN_OPERATION_DATE = date(1900, 1, 1)
_MAX_OPERATION_DATE = date(2100, 12, 31)


def _parse_money(value: object) -> Decimal:
    if isinstance(value, Decimal):
        amount = value
    elif isinstance(value, str) and _DECIMAL_PATTERN.fullmatch(value) is not None:
        try:
            amount = Decimal(value)
        except InvalidOperation as error:  # pragma: no cover - guarded by regex
            raise ValueError("amount must be a decimal string") from error
    else:
        raise ValueError("amount must be a plain decimal string")
    if not amount.is_finite() or amount <= 0:
        raise ValueError("amount must be positive and finite")
    exponent = amount.as_tuple().exponent
    if not isinstance(exponent, int):  # pragma: no cover - finite guard above
        raise ValueError("amount must be finite")
    fractional_digits = max(-exponent, 0)
    integral_digits = max(amount.adjusted() + 1, 1)
    if fractional_digits > 18 or integral_digits > 20:
        raise ValueError("amount exceeds NUMERIC(38,18)")
    return amount


def _decimal_string(value: Decimal) -> str:
    rendered = format(value, "f")
    if "." in rendered:
        rendered = rendered.rstrip("0").rstrip(".")
    return rendered


def _utc_datetime(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamp must include a timezone")
    try:
        utc_value = value.astimezone(UTC)
    except (OverflowError, ValueError) as error:
        raise ValueError("timestamp is outside the supported range") from error
    if not (_MIN_OPERATION_DATE <= utc_value.date() <= _MAX_OPERATION_DATE):
        raise ValueError("timestamp is outside the supported range")
    return utc_value


def _utc_timestamp(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _timezone_name(value: str) -> str:
    if value != value.strip() or any(
        ord(character) < 0x20 or ord(character) == 0x7F for character in value
    ):
        raise ValueError("invalid IANA timezone")
    try:
        timezone = ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError) as error:
        raise ValueError("invalid IANA timezone") from error
    if timezone.key != value:
        raise ValueError("timezone must use its canonical IANA name")
    return value


def _operation_date(value: date) -> date:
    if not (_MIN_OPERATION_DATE <= value <= _MAX_OPERATION_DATE):
        raise ValueError("date is outside the supported range")
    return value


def _safe_text(value: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("text contains control characters")
    return unicodedata.normalize("NFC", value)


MoneyInput = Annotated[
    Decimal,
    BeforeValidator(_parse_money),
    PlainSerializer(_decimal_string, return_type=str, when_used="json"),
    WithJsonSchema(
        {
            "type": "string",
            "pattern": _POSITIVE_DECIMAL_PATTERN,
            "maxLength": 39,
            "description": (
                "Positive finite decimal string; max 20 integer and 18 fraction digits."
            ),
        }
    ),
]
UtcTimestamp = Annotated[
    datetime,
    AfterValidator(_utc_datetime),
    PlainSerializer(_utc_timestamp, return_type=str, when_used="json"),
    WithJsonSchema(
        {
            "type": "string",
            "format": "date-time",
            "formatMinimum": "1900-01-01T00:00:00Z",
            "formatMaximum": "2100-12-31T23:59:59.999999Z",
            "description": "Timezone-aware instant normalized to UTC.",
        }
    ),
]
OperationDate = Annotated[
    date,
    AfterValidator(_operation_date),
    WithJsonSchema(
        {
            "type": "string",
            "format": "date",
            "formatMinimum": "1900-01-01",
            "formatMaximum": "2100-12-31",
        }
    ),
]
CurrencyCode = Annotated[
    str,
    StringConstraints(min_length=3, max_length=3, pattern=_CURRENCY_PATTERN),
]
TimezoneName = Annotated[
    str,
    StringConstraints(min_length=1, max_length=128),
    AfterValidator(_timezone_name),
]
OptionalShortText = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_safe_text),
]
OptionalMerchant = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=160),
    AfterValidator(_safe_text),
]
OptionalSourceExpression = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=128),
    AfterValidator(_safe_text),
]
DraftHash = Annotated[
    str,
    StringConstraints(pattern=r"^[a-f0-9]{64}$", min_length=64, max_length=64),
]
OperationErrorCode = Literal[
    "MALFORMED_OPERATION",
    "CONFIRMATION_MISMATCH",
    "COMMAND_CONFLICT",
    "OPERATION_REJECTED",
    "AUTHENTICATION_UNAVAILABLE",
    "FINANCE_PERSISTENCE_UNAVAILABLE",
]


class OperationApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class OperationDraft(OperationApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    operation_type: Literal["expense", "income"] = Field(alias="type")
    amount: MoneyInput
    currency: CurrencyCode
    account_id: UUID | None = Field(default=None, alias="accountId")
    category: OptionalShortText | None = None
    merchant: OptionalMerchant | None = None
    captured_at: UtcTimestamp = Field(alias="capturedAt")
    captured_timezone: TimezoneName = Field(alias="capturedTimezone")
    source_expression: OptionalSourceExpression | None = Field(
        default=None,
        alias="sourceExpression",
    )
    date_resolver_version: Literal["calendar-relative-v1"] = Field(
        alias="dateResolverVersion"
    )
    occurred_on: OperationDate = Field(alias="occurredOn")
    occurred_at: UtcTimestamp | None = Field(default=None, alias="occurredAt")
    source: Literal["manual_text", "voice"]


class OperationIssue(OperationApiModel):
    code: Literal[
        "ACCOUNT_UNAVAILABLE",
        "FUTURE_OCCURRED_DATE",
        "RELATIVE_DATE_MISMATCH",
        "OCCURRED_AT_DATE_MISMATCH",
        "CONFIRMATION_BEFORE_CAPTURE",
        "UNSUPPORTED_DATE_EXPRESSION",
        "UNSUPPORTED_CURRENCY",
    ]
    field: Literal[
        "accountId",
        "occurredOn",
        "occurredAt",
        "confirmedAt",
        "sourceExpression",
        "currency",
    ]


class EvaluateOperationRequest(OperationApiModel):
    draft: OperationDraft


class EvaluateOperationResponse(OperationApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["REJECT", "NEEDS_CONFIRMATION"]
    draft: OperationDraft
    draft_hash: DraftHash | None = Field(alias="draftHash")
    issues: tuple[OperationIssue, ...] = ()

    @model_validator(mode="after")
    def decision_is_consistent(self) -> Self:
        if self.decision == "REJECT" and (
            not self.issues or self.draft_hash is not None
        ):
            raise ValueError("rejected drafts require issues and no confirmation hash")
        if self.decision == "NEEDS_CONFIRMATION" and (
            self.issues or self.draft_hash is None
        ):
            raise ValueError("confirmable drafts require a hash and no issues")
        return self


class CommitOperationRequest(OperationApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    draft: OperationDraft
    draft_hash: DraftHash = Field(alias="draftHash")
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")


class CommittedOperation(OperationApiModel):
    operation_id: UUID = Field(alias="operationId")
    user_id: UUID = Field(alias="userId")
    command_id: UUID = Field(alias="commandId")
    operation_type: Literal["expense", "income"] = Field(alias="type")
    amount: MoneyInput
    currency: CurrencyCode
    account_id: UUID | None = Field(alias="accountId")
    category: OptionalShortText | None
    merchant: OptionalMerchant | None
    captured_at: UtcTimestamp = Field(alias="capturedAt")
    captured_timezone: TimezoneName = Field(alias="capturedTimezone")
    source_expression: OptionalSourceExpression | None = Field(alias="sourceExpression")
    date_resolver_version: Literal["calendar-relative-v1"] = Field(
        alias="dateResolverVersion"
    )
    occurred_on: OperationDate = Field(alias="occurredOn")
    occurred_at: UtcTimestamp | None = Field(alias="occurredAt")
    source: Literal["manual_text", "voice"]
    status: Literal["confirmed"]
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")
    created_at: UtcTimestamp = Field(alias="createdAt")


class CommitOperationResponse(OperationApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["ACCEPT"] = "ACCEPT"
    idempotent_replay: bool = Field(alias="idempotentReplay")
    operation: CommittedOperation


class OperationErrorDetail(OperationApiModel):
    code: OperationErrorCode
    issues: tuple[OperationIssue, ...] = ()

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "OPERATION_REJECTED" and not self.issues:
            raise ValueError("operation rejection requires issues")
        if self.code != "OPERATION_REJECTED" and self.issues:
            raise ValueError("only operation rejection may expose issues")
        return self


class OperationErrorResponse(OperationApiModel):
    detail: OperationErrorDetail


type OperationMessage = (
    EvaluateOperationRequest
    | EvaluateOperationResponse
    | CommitOperationRequest
    | CommitOperationResponse
    | OperationErrorResponse
)

_operation_message_adapter: TypeAdapter[OperationMessage] = TypeAdapter(
    OperationMessage
)


def operation_contract_schema() -> dict[str, object]:
    """Build the canonical, reproducible JSON Schema for operation v1."""

    generated = _operation_message_adapter.json_schema(
        ref_template="#/$defs/{model}",
    )
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": (
            "https://mobile-finance-assistant.local/"
            "contracts/finance/v1/operation.schema.json"
        ),
        "title": "Finance operation v1 messages",
        "description": (
            "Strict messages for deterministic evaluation and idempotent "
            "confirmed commit."
        ),
        **generated,
    }
