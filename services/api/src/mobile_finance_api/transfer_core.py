"""Deterministic decision and commit boundary for a transfer between wallets.

A transfer moves money and creates no income and no expense (ADR 0029). It
follows the same evaluate/review/commit shape a confirmed operation does,
because an amount that changes a balance deserves the same explicit
confirmation, and the hash is what makes that confirmation mean something.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .transfer_contracts import (
    CommittedTransfer,
    EvaluateTransferResponse,
    TransferDraft,
    TransferIssue,
    confirmed_transfer_command_hash,
    transfer_draft_hash,
)


class TransferPersistenceUnavailable(Exception):
    """The authoritative store could not answer. Never a user's fault."""


class TransferConfirmationMismatch(Exception):
    """The confirmed draft is not the draft that was reviewed."""


class TransferCommandConflict(Exception):
    """The command id has already settled different content."""


class TransferRejected(Exception):
    def __init__(self, issues: tuple[TransferIssue, ...]) -> None:
        super().__init__("transfer rejected")
        self.issues = issues


@dataclass(frozen=True, slots=True)
class TransferWalletSnapshot:
    """What a wallet must say about itself before money may leave or enter."""

    account_id: UUID
    currency: str
    opening_balance_on: date


@dataclass(frozen=True, slots=True)
class TransferWriteResult:
    transfer: CommittedTransfer
    idempotent_replay: bool


class TransferRepository(Protocol):
    async def get_transfer_wallets(
        self,
        *,
        user_id: UUID,
        account_ids: tuple[UUID, ...],
    ) -> tuple[TransferWalletSnapshot, ...]: ...

    async def replay_transfer(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> TransferWriteResult | None: ...

    async def commit_transfer(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> TransferWriteResult: ...


class UnavailableTransferRepository:
    """Fail-closed default until a deployment configures a data adapter."""

    async def get_transfer_wallets(
        self,
        *,
        user_id: UUID,
        account_ids: tuple[UUID, ...],
    ) -> tuple[TransferWalletSnapshot, ...]:
        del user_id, account_ids
        raise TransferPersistenceUnavailable

    async def replay_transfer(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> TransferWriteResult | None:
        del user_id, command_id, payload_hash
        raise TransferPersistenceUnavailable

    async def commit_transfer(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> TransferWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise TransferPersistenceUnavailable


class TransferCore:
    def __init__(
        self,
        *,
        repository: TransferRepository,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._clock = clock or _utc_now

    async def evaluate(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
    ) -> EvaluateTransferResponse:
        issues = await self._issues(user_id=user_id, draft=draft)
        if issues:
            return EvaluateTransferResponse(
                decision="REJECT",
                draft=draft,
                draft_hash=None,
                issues=issues,
            )
        return EvaluateTransferResponse(
            decision="NEEDS_CONFIRMATION",
            draft=draft,
            draft_hash=transfer_draft_hash(draft),
            issues=(),
        )

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
        expected_draft_hash: str,
        confirmed_at: datetime,
    ) -> TransferWriteResult:
        actual_hash = transfer_draft_hash(draft)
        if actual_hash != expected_draft_hash:
            raise TransferConfirmationMismatch
        payload_hash = bytes.fromhex(
            confirmed_transfer_command_hash(
                draft=draft,
                confirmed_at=confirmed_at,
                evaluated_draft_hash=actual_hash,
            )
        )
        # The exact same command settles once. A retry after a lost answer
        # replays it rather than moving the money a second time (ADR 0008).
        replay = await self._repository.replay_transfer(
            user_id=user_id,
            command_id=draft.command_id,
            payload_hash=payload_hash,
        )
        if replay is not None:
            _validate_result(result=replay, user_id=user_id, draft=draft)
            return replay

        # Re-checked at commit and not only at review: a rejection that only
        # happens at review lets a stale draft settle what the review refused.
        issues = await self._issues(
            user_id=user_id,
            draft=draft,
            confirmed_at=_aware_utc(confirmed_at),
        )
        if issues:
            raise TransferRejected(issues)
        result = await self._repository.commit_transfer(
            user_id=user_id,
            draft=draft,
            payload_hash=payload_hash,
            confirmed_at=confirmed_at,
        )
        _validate_result(result=result, user_id=user_id, draft=draft)
        return result

    async def _issues(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
        confirmed_at: datetime | None = None,
    ) -> tuple[TransferIssue, ...]:
        wallets = await self._repository.get_transfer_wallets(
            user_id=user_id,
            account_ids=(draft.from_account_id, draft.to_account_id),
        )
        by_id = {wallet.account_id: wallet for wallet in wallets}
        issues: list[TransferIssue] = []
        for account_id, currency, field in (
            (draft.from_account_id, draft.from_currency, "fromAccountId"),
            (draft.to_account_id, draft.to_currency, "toAccountId"),
        ):
            wallet = by_id.get(account_id)
            if wallet is None:
                issues.append(TransferIssue(code="WALLET_UNAVAILABLE", field=field))  # type: ignore[arg-type]
                continue
            if wallet.currency != currency:
                issues.append(
                    TransferIssue(code="WALLET_CURRENCY_MISMATCH", field=field)  # type: ignore[arg-type]
                )
            if draft.occurred_on < wallet.opening_balance_on:
                issues.append(
                    TransferIssue(code="TRANSFER_BEFORE_WALLET_BASELINE", field=field)  # type: ignore[arg-type]
                )

        # "Today" is the day where the money moved, not on the server's clock
        # (ADR 0007).
        captured_local_date = draft.captured_at.astimezone(
            ZoneInfo(draft.captured_timezone)
        ).date()
        if draft.occurred_on > captured_local_date:
            issues.append(
                TransferIssue(code="FUTURE_OCCURRED_DATE", field="occurredOn")
            )
        if confirmed_at is not None and confirmed_at < _aware_utc(draft.captured_at):
            issues.append(
                TransferIssue(code="CONFIRMATION_BEFORE_CAPTURE", field="confirmedAt")
            )
        return tuple(issues)


def _validate_result(
    *,
    result: TransferWriteResult,
    user_id: UUID,
    draft: TransferDraft,
) -> None:
    """Refuse to report a receipt that does not describe what was asked for."""

    transfer = result.transfer
    if (
        transfer.user_id != user_id
        or transfer.command_id != draft.command_id
        or transfer.from_account_id != draft.from_account_id
        or transfer.to_account_id != draft.to_account_id
        or transfer.from_amount != draft.from_amount
        or transfer.to_amount != draft.to_amount
        or transfer.from_currency != draft.from_currency
        or transfer.to_currency != draft.to_currency
        or transfer.occurred_on != draft.occurred_on
    ):
        raise TransferPersistenceUnavailable


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("timestamp must be timezone-aware")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
