"""Strict versioned contracts for authoritative Finance accounts."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from datetime import UTC, date, datetime
from decimal import Decimal, InvalidOperation
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

from .timezones import validated_iana_timezone_key

_SIGNED_DECIMAL_PATTERN = (
    r"^-?(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?"
    r"|0(?:\.[0-9]{1,18})?)$"
)
_SIGNED_DECIMAL = re.compile(_SIGNED_DECIMAL_PATTERN)
_CURRENCY_PATTERN = r"^[A-Z]{3}$"
_MIN_ACCOUNT_DATE = date(1900, 1, 1)
_MAX_ACCOUNT_DATE = date(2100, 12, 31)


def _parse_signed_money(value: object) -> Decimal:
    if isinstance(value, Decimal):
        amount = value
    elif isinstance(value, str) and _SIGNED_DECIMAL.fullmatch(value) is not None:
        try:
            amount = Decimal(value)
        except InvalidOperation as error:  # pragma: no cover - guarded by regex
            raise ValueError("opening balance must be a decimal string") from error
    else:
        raise ValueError("opening balance must be a plain decimal string")
    if not amount.is_finite():
        raise ValueError("opening balance must be finite")
    exponent = amount.as_tuple().exponent
    if not isinstance(exponent, int):  # pragma: no cover - finite guard above
        raise ValueError("opening balance must be finite")
    fractional_digits = max(-exponent, 0)
    integral_digits = max(amount.adjusted() + 1, 1) if amount else 1
    if fractional_digits > 18 or integral_digits > 20:
        raise ValueError("opening balance exceeds NUMERIC(38,18)")
    return Decimal(0) if amount == 0 else amount


def _decimal_string(value: Decimal) -> str:
    if value == 0:
        return "0"
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
    if not (_MIN_ACCOUNT_DATE <= utc_value.date() <= _MAX_ACCOUNT_DATE):
        raise ValueError("timestamp is outside the supported range")
    return utc_value


def _utc_timestamp(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _account_date(value: date) -> date:
    if not (_MIN_ACCOUNT_DATE <= value <= _MAX_ACCOUNT_DATE):
        raise ValueError("date is outside the supported range")
    return value


def _timezone_name(value: str) -> str:
    return validated_iana_timezone_key(value)


def _safe_text(value: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("text contains control characters")
    return unicodedata.normalize("NFC", value)


SignedMoneyInput = Annotated[
    Decimal,
    BeforeValidator(_parse_signed_money),
    PlainSerializer(_decimal_string, return_type=str, when_used="json"),
    WithJsonSchema(
        {
            "type": "string",
            "pattern": _SIGNED_DECIMAL_PATTERN,
            "maxLength": 40,
            "description": (
                "Signed finite decimal string; max 20 integer and 18 fraction digits."
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
AccountDate = Annotated[
    date,
    AfterValidator(_account_date),
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
AccountName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_safe_text),
]
DraftHash = Annotated[
    str,
    StringConstraints(pattern=r"^[a-f0-9]{64}$", min_length=64, max_length=64),
]
AccountErrorCode = Literal[
    "MALFORMED_ACCOUNT",
    "CONFIRMATION_MISMATCH",
    "COMMAND_CONFLICT",
    "ACCOUNT_ALREADY_INITIALIZED",
    "ACCOUNT_REJECTED",
    "ACCOUNT_UNAVAILABLE",
    "BASELINE_REJECTED",
    "TIMEZONE_REJECTED",
    "AUTHENTICATION_UNAVAILABLE",
    "FINANCE_PERSISTENCE_UNAVAILABLE",
]


class AccountApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class AccountDraft(AccountApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    name: AccountName
    currency: CurrencyCode
    opening_balance: SignedMoneyInput = Field(alias="openingBalance")
    opening_balance_on: AccountDate = Field(alias="openingBalanceOn")
    canonical_timezone: TimezoneName = Field(alias="canonicalTimezone")


class AccountIssue(AccountApiModel):
    code: Literal[
        "ACCOUNT_ALREADY_INITIALIZED",
        "OPENING_BALANCE_DATE_IN_FUTURE",
        "UNSUPPORTED_CURRENCY",
    ]
    field: Literal["account", "openingBalanceOn", "currency"]


class EvaluateAccountRequest(AccountApiModel):
    draft: AccountDraft


class EvaluateAccountResponse(AccountApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["REJECT", "NEEDS_CONFIRMATION"]
    draft: AccountDraft
    draft_hash: DraftHash | None = Field(alias="draftHash")
    issues: tuple[AccountIssue, ...] = ()

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


class CommitAccountRequest(AccountApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    draft: AccountDraft
    draft_hash: DraftHash = Field(alias="draftHash")
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")


class CommittedFinanceAccount(AccountApiModel):
    account_id: UUID = Field(alias="accountId")
    user_id: UUID = Field(alias="userId")
    command_id: UUID = Field(alias="commandId")
    name: AccountName
    currency: CurrencyCode
    opening_balance: SignedMoneyInput = Field(alias="openingBalance")
    opening_balance_on: AccountDate = Field(alias="openingBalanceOn")
    opening_timezone: TimezoneName = Field(alias="openingTimezone")
    status: Literal["active"]
    # A user may hold several wallets and exactly one of them is the default —
    # the one a screen means when it names no wallet (ADR 0029).
    is_default: bool = Field(alias="isDefault")
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")
    created_at: UtcTimestamp = Field(alias="createdAt")


class CommitAccountResponse(AccountApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["ACCEPT"] = "ACCEPT"
    idempotent_replay: bool = Field(alias="idempotentReplay")
    canonical_timezone: TimezoneName = Field(alias="canonicalTimezone")
    timezone_revision: Literal[1] = Field(alias="timezoneRevision")
    account: CommittedFinanceAccount

    @model_validator(mode="after")
    def timezone_matches_opening_snapshot(self) -> Self:
        if self.canonical_timezone != self.account.opening_timezone:
            raise ValueError("account and profile timezones must match at bootstrap")
        return self


class ListAccountsResponse(AccountApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    canonical_timezone: TimezoneName | None = Field(alias="canonicalTimezone")
    # A count of how many times the timezone has been settled, not a flag:
    # correcting it raises the number (ADR 0028). Zero still means unset.
    timezone_revision: int = Field(alias="timezoneRevision", ge=0)
    accounts: tuple[CommittedFinanceAccount, ...] = Field(max_length=1)

    @model_validator(mode="after")
    def setup_state_is_consistent(self) -> Self:
        if not self.accounts:
            if self.canonical_timezone is not None or self.timezone_revision != 0:
                raise ValueError("an empty account list requires an unset timezone")
            return self
        if self.canonical_timezone is None or self.timezone_revision < 1:
            raise ValueError("an initialized account list requires a settled timezone")
        account = self.accounts[0]
        if account.opening_timezone != self.canonical_timezone:
            raise ValueError("account and profile timezones are inconsistent")
        return self


class CorrectBaselineDraft(AccountApiModel):
    """An explicit request to move an account baseline date earlier."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    account_id: UUID = Field(alias="accountId")
    opening_balance_on: AccountDate = Field(alias="openingBalanceOn")


class BaselineIssue(AccountApiModel):
    code: Literal[
        "BASELINE_NOT_EARLIER",
        "BASELINE_DATE_IN_FUTURE",
        "BASELINE_AFTER_EXISTING_OPERATION",
    ]
    field: Literal["openingBalanceOn"]


class CorrectTimezoneCommand(AccountApiModel):
    """An explicit request to change where this account's months are drawn.

    One phase, not the evaluate/confirm handshake a baseline needs: no balance
    moves. An operation keeps the local date it was captured with (ADR 0007),
    so what changes is only what "today" and "this month" mean from now on.
    """

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    account_id: UUID = Field(alias="accountId")
    canonical_timezone: TimezoneName = Field(alias="canonicalTimezone")
    requested_at: UtcTimestamp = Field(alias="requestedAt")


class TimezoneIssue(AccountApiModel):
    code: Literal[
        # The account already reports in this zone; nothing to correct.
        "TIMEZONE_UNCHANGED",
        # Moving there would date a recorded operation in the future, and a
        # future-dated operation is excluded from the balance until the day
        # catches up. Refused rather than letting money vanish for hours.
        "TIMEZONE_BEHIND_RECORDED_OPERATIONS",
    ]
    field: Literal["canonicalTimezone"]


class CorrectTimezoneResponse(AccountApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    idempotent_replay: bool = Field(alias="idempotentReplay")
    account_id: UUID = Field(alias="accountId")
    canonical_timezone: TimezoneName = Field(alias="canonicalTimezone")
    timezone_revision: int = Field(alias="timezoneRevision", ge=1)


class EvaluateBaselineRequest(AccountApiModel):
    draft: CorrectBaselineDraft


class EvaluateBaselineResponse(AccountApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["REJECT", "NEEDS_CONFIRMATION"]
    draft: CorrectBaselineDraft
    draft_hash: DraftHash | None = Field(alias="draftHash")
    current_opening_balance_on: AccountDate = Field(alias="currentOpeningBalanceOn")
    earliest_operation_on: AccountDate | None = Field(alias="earliestOperationOn")
    issues: tuple[BaselineIssue, ...] = ()

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


class CommitBaselineRequest(AccountApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    draft: CorrectBaselineDraft
    draft_hash: DraftHash = Field(alias="draftHash")
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")


class CommitBaselineResponse(AccountApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["ACCEPT"] = "ACCEPT"
    idempotent_replay: bool = Field(alias="idempotentReplay")
    previous_opening_balance_on: AccountDate = Field(alias="previousOpeningBalanceOn")
    account: CommittedFinanceAccount

    @model_validator(mode="after")
    def correction_moves_earlier(self) -> Self:
        if self.account.opening_balance_on > self.previous_opening_balance_on:
            raise ValueError("a baseline correction may only move the date earlier")
        return self


class AccountErrorDetail(AccountApiModel):
    code: AccountErrorCode
    issues: tuple[AccountIssue, ...] = ()
    baseline_issues: tuple[BaselineIssue, ...] = Field(
        default=(), alias="baselineIssues"
    )
    timezone_issues: tuple[TimezoneIssue, ...] = Field(
        default=(), alias="timezoneIssues"
    )

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "ACCOUNT_REJECTED" and not self.issues:
            raise ValueError("account rejection requires issues")
        if self.code != "ACCOUNT_REJECTED" and self.issues:
            raise ValueError("only account rejection may expose issues")
        if self.code == "BASELINE_REJECTED" and not self.baseline_issues:
            raise ValueError("baseline rejection requires issues")
        if self.code != "BASELINE_REJECTED" and self.baseline_issues:
            raise ValueError("only baseline rejection may expose baseline issues")
        if self.code == "TIMEZONE_REJECTED" and not self.timezone_issues:
            raise ValueError("timezone rejection requires issues")
        if self.code != "TIMEZONE_REJECTED" and self.timezone_issues:
            raise ValueError("only timezone rejection may expose timezone issues")
        return self


class AccountErrorResponse(AccountApiModel):
    detail: AccountErrorDetail


type AccountMessage = (
    EvaluateAccountRequest
    | EvaluateAccountResponse
    | CommitAccountRequest
    | CommitAccountResponse
    | ListAccountsResponse
    | EvaluateBaselineRequest
    | EvaluateBaselineResponse
    | CommitBaselineRequest
    | CommitBaselineResponse
    | AccountErrorResponse
)

_account_message_adapter: TypeAdapter[AccountMessage] = TypeAdapter(AccountMessage)


def account_draft_hash(draft: AccountDraft) -> str:
    """Return the canonical SHA-256 binding for a reviewed account draft."""

    return _canonical_hash(draft.model_dump(mode="json", by_alias=True))


def confirmed_account_command_hash(
    *,
    draft: AccountDraft,
    confirmed_at: datetime,
    evaluated_draft_hash: str,
) -> str:
    """Bind every field of an explicitly confirmed account command."""

    command = CommitAccountRequest(
        schema_version="1",
        draft=draft,
        draft_hash=evaluated_draft_hash,
        confirmed_at=confirmed_at,
    )
    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def baseline_draft_hash(draft: CorrectBaselineDraft) -> str:
    """Return the canonical SHA-256 binding for a reviewed baseline draft."""

    return _canonical_hash(draft.model_dump(mode="json", by_alias=True))


def confirmed_baseline_command_hash(
    *,
    draft: CorrectBaselineDraft,
    confirmed_at: datetime,
    evaluated_draft_hash: str,
) -> str:
    """Bind every field of an explicitly confirmed baseline correction."""

    command = CommitBaselineRequest(
        schema_version="1",
        draft=draft,
        draft_hash=evaluated_draft_hash,
        confirmed_at=confirmed_at,
    )
    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def _canonical_hash(payload: object) -> str:
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def account_contract_schema() -> dict[str, object]:
    """Build the canonical, reproducible JSON Schema for account v1."""

    generated = _account_message_adapter.json_schema(
        ref_template="#/$defs/{model}",
    )
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": (
            "https://mobile-finance-assistant.local/"
            "contracts/finance/v1/account.schema.json"
        ),
        "title": "Finance account v1 messages",
        "description": (
            "Strict messages for explicit account bootstrap, deterministic "
            "evaluation, idempotent commit, and authoritative account reads."
        ),
        **generated,
    }


def correct_timezone_command_hash(command: CorrectTimezoneCommand) -> str:
    """Canonical hash binding a command_id to exact timezone content."""

    return _canonical_hash(command.model_dump(mode="json", by_alias=True))
