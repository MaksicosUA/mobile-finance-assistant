"""Strict versioned contracts for moving money between two of a user's wallets.

A transfer is neither income nor expense (ADR 0029). It carries **two amounts**,
one per side, because those are the two numbers the person witnessed: 100 €
left one wallet and 108 $ arrived in the other. No rate travels and none is
stored — it is implied by the pair.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime
from typing import Literal, Self
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .operation_contracts import (
    CurrencyCode,
    DraftHash,
    EntryMoney,
    MoneyInput,
    OperationDate,
    TimezoneName,
    UtcTimestamp,
)

TransferErrorCode = Literal[
    "MALFORMED_TRANSFER",
    "TRANSFER_REJECTED",
    "CONFIRMATION_MISMATCH",
    "COMMAND_CONFLICT",
    "TRANSFER_PERSISTENCE_UNAVAILABLE",
]


class TransferApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class TransferDraft(TransferApiModel):
    """One proposed movement between two wallets, not yet authoritative."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    command_id: UUID = Field(alias="commandId")
    from_account_id: UUID = Field(alias="fromAccountId")
    from_amount: EntryMoney = Field(alias="fromAmount")
    from_currency: CurrencyCode = Field(alias="fromCurrency")
    to_account_id: UUID = Field(alias="toAccountId")
    to_amount: EntryMoney = Field(alias="toAmount")
    to_currency: CurrencyCode = Field(alias="toCurrency")
    captured_at: UtcTimestamp = Field(alias="capturedAt")
    captured_timezone: TimezoneName = Field(alias="capturedTimezone")
    #: The local date the money moved, resolved by the caller and frozen from
    #: here on (ADR 0007).
    occurred_on: OperationDate = Field(alias="occurredOn")

    @model_validator(mode="after")
    def two_wallets_are_two(self) -> Self:
        if self.from_account_id == self.to_account_id:
            raise ValueError("a transfer needs two different wallets")
        return self


class TransferIssue(TransferApiModel):
    code: Literal[
        # One of the two named wallets is not an owned active one.
        "WALLET_UNAVAILABLE",
        # The amount's currency is not the currency that wallet holds.
        "WALLET_CURRENCY_MISMATCH",
        # Money cannot leave a wallet before the wallet existed.
        "TRANSFER_BEFORE_WALLET_BASELINE",
        "FUTURE_OCCURRED_DATE",
        "CONFIRMATION_BEFORE_CAPTURE",
    ]
    field: Literal["fromAccountId", "toAccountId", "occurredOn", "confirmedAt"]


class EvaluateTransferRequest(TransferApiModel):
    draft: TransferDraft


class EvaluateTransferResponse(TransferApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["REJECT", "NEEDS_CONFIRMATION"]
    draft: TransferDraft
    draft_hash: DraftHash | None = Field(alias="draftHash")
    issues: tuple[TransferIssue, ...] = ()

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


class CommitTransferRequest(TransferApiModel):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    draft: TransferDraft
    draft_hash: DraftHash = Field(alias="draftHash")
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")


class CommittedTransfer(TransferApiModel):
    transfer_id: UUID = Field(alias="transferId")
    user_id: UUID = Field(alias="userId")
    command_id: UUID = Field(alias="commandId")
    from_account_id: UUID = Field(alias="fromAccountId")
    from_amount: MoneyInput = Field(alias="fromAmount")
    from_currency: CurrencyCode = Field(alias="fromCurrency")
    to_account_id: UUID = Field(alias="toAccountId")
    to_amount: MoneyInput = Field(alias="toAmount")
    to_currency: CurrencyCode = Field(alias="toCurrency")
    occurred_on: OperationDate = Field(alias="occurredOn")
    status: Literal["confirmed"]
    confirmed_at: UtcTimestamp = Field(alias="confirmedAt")
    created_at: UtcTimestamp = Field(alias="createdAt")


class CommitTransferResponse(TransferApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    decision: Literal["ACCEPT"] = "ACCEPT"
    idempotent_replay: bool = Field(alias="idempotentReplay")
    transfer: CommittedTransfer


class TransferErrorDetail(TransferApiModel):
    code: TransferErrorCode
    issues: tuple[TransferIssue, ...] = ()

    @model_validator(mode="after")
    def issues_are_consistent(self) -> Self:
        if self.code == "TRANSFER_REJECTED" and not self.issues:
            raise ValueError("a rejection requires issues")
        if self.code != "TRANSFER_REJECTED" and self.issues:
            raise ValueError("only a rejection may expose issues")
        return self


class TransferErrorResponse(TransferApiModel):
    detail: TransferErrorDetail


def transfer_draft_hash(draft: TransferDraft) -> str:
    """The canonical SHA-256 binding for a reviewed transfer draft."""

    return _canonical_hash(draft.model_dump(mode="json", by_alias=True))


def confirmed_transfer_command_hash(
    *,
    draft: TransferDraft,
    confirmed_at: datetime,
    evaluated_draft_hash: str,
) -> str:
    """Bind every field of an explicitly confirmed transfer."""

    command = CommitTransferRequest(
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


__all__ = [
    "CommitTransferRequest",
    "CommitTransferResponse",
    "CommittedTransfer",
    "EvaluateTransferRequest",
    "EvaluateTransferResponse",
    "TransferDraft",
    "TransferErrorCode",
    "TransferErrorDetail",
    "TransferErrorResponse",
    "TransferIssue",
    "confirmed_transfer_command_hash",
    "transfer_draft_hash",
]
