"""Strict versioned contract for proposing an operation from a sentence.

A proposal is powerless on purpose (ADR 0022): no command id, no confirmation
hash, no authority. The client turns it into an ordinary `OperationDraft` and
Finance Core decides. Nothing here can create financial state.
"""

from __future__ import annotations

import unicodedata
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    StringConstraints,
)

from .operation_contracts import (
    CurrencyCode,
    MoneyInput,
    OperationDate,
    OptionalShortText,
    TimezoneName,
    UtcTimestamp,
)
from .text_entry import MAX_TEXT_LENGTH


def _safe_text(value: str) -> str:
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise ValueError("text contains control characters")
    return unicodedata.normalize("NFC", value)


EntryText = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        min_length=1,
        max_length=MAX_TEXT_LENGTH,
    ),
    AfterValidator(_safe_text),
]

#: Why a field could not be filled. A gap is never an error: the user is
#: looking at an editable form and fills it in.
ParseGap = Literal[
    "AMOUNT_NOT_FOUND",
    "AMBIGUOUS_AMOUNT",
    "DATE_NOT_UNDERSTOOD",
    "CATEGORY_NOT_MATCHED",
    "CURRENCY_NOT_UNDERSTOOD",
    # The sentence is a transfer, so no amount is proposed at all. A client
    # that does not know this code drops it and sees a proposal with no
    # amount, which is the safe reading: nothing is filled, nothing is
    # confirmed, and no money is invented.
    "TRANSFER_NOT_AN_OPERATION",
]

TextEntryErrorCode = Literal["TEXT_ENTRY_UNAVAILABLE"]


class TextEntryApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class ParseOperationRequest(TextEntryApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    text: EntryText
    # The same capture pair the draft carries, so the day the sentence means is
    # resolved in the user's own timezone and never on server wall-clock time
    # (ADR 0007).
    captured_at: UtcTimestamp = Field(alias="capturedAt")
    captured_timezone: TimezoneName = Field(alias="capturedTimezone")
    # The wallet being recorded into, which is what a sentence naming no
    # currency means. Omitted by every client older than issue 0013.
    account_currency: CurrencyCode | None = Field(default=None, alias="accountCurrency")


class ParsedOperationProposal(TextEntryApiModel):
    """What the sentence appears to mean. Not a draft, and not confirmable."""

    operation_type: Literal["expense", "income"] = Field(alias="type")
    # Null when the sentence names no amount that could be trusted. The one
    # field this refuses to guess.
    amount: MoneyInput | None = None
    currency: CurrencyCode
    occurred_on: OperationDate = Field(alias="occurredOn")
    # Only ever a phrase Finance Core's own resolver accepts, so a draft built
    # from this proposal cannot fail on an unsupported expression.
    source_expression: Literal["сегодня", "вчера"] | None = Field(
        default=None,
        alias="sourceExpression",
    )
    category_id: UUID | None = Field(default=None, alias="categoryId")
    category: OptionalShortText | None = None
    gaps: tuple[ParseGap, ...] = ()


class ParseOperationResponse(TextEntryApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    proposal: ParsedOperationProposal


class ParsedTransferSide(TextEntryApiModel):
    """One half of an exchange, exactly as the sentence states it."""

    amount: MoneyInput
    currency: CurrencyCode


class ParsedTransferProposal(TextEntryApiModel):
    """Both halves, in the order the sentence says them.

    No wallets and no rate. The wallets are the client's to resolve — it holds
    the list already — and a rate is never stored anywhere: it is implied by
    two amounts the person witnessed (ADR 0029).
    """

    sent: ParsedTransferSide
    received: ParsedTransferSide
    occurred_on: OperationDate = Field(alias="occurredOn")


class ParseTransferResponse(TextEntryApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    #: Null when the sentence is not an exchange. Saying so is the honest
    #: answer; the caller asked a question and this is the answer to it.
    proposal: ParsedTransferProposal | None = None


class TextEntryErrorDetail(TextEntryApiModel):
    code: TextEntryErrorCode


class TextEntryErrorResponse(TextEntryApiModel):
    detail: TextEntryErrorDetail
