"""Moving money between two wallets (ADR 0029).

Nothing here converts anything. A transfer carries two amounts because those
are the two numbers the person witnessed, and the rate between them is implied
rather than stored.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

import pytest
from pydantic import ValidationError

from mobile_finance_api.transfer_contracts import (
    CommittedTransfer,
    TransferDraft,
    TransferErrorDetail,
    TransferIssue,
    confirmed_transfer_command_hash,
    transfer_draft_hash,
)
from mobile_finance_api.transfer_core import (
    TransferCore,
    TransferRejected,
    TransferWalletSnapshot,
    TransferWriteResult,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_EURO = UUID("22222222-2222-4222-8222-222222222222")
_DOLLARS = UUID("33333333-3333-4333-8333-333333333333")
_COMMAND_ID = UUID("44444444-4444-4444-8444-444444444444")
_CAPTURED_AT = datetime(2026, 9, 6, 18, 0, tzinfo=UTC)
_BASELINE = date(2026, 1, 1)


def _draft(**changes: object) -> TransferDraft:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "fromAccountId": str(_EURO),
        "fromAmount": "100.00",
        "fromCurrency": "EUR",
        "toAccountId": str(_DOLLARS),
        "toAmount": "108.00",
        "toCurrency": "USD",
        "capturedAt": "2026-09-06T18:00:00Z",
        "capturedTimezone": "Europe/Berlin",
        "occurredOn": "2026-09-06",
    }
    payload.update(changes)
    return TransferDraft.model_validate(payload)


def _committed(draft: TransferDraft) -> CommittedTransfer:
    return CommittedTransfer(
        transfer_id=UUID("55555555-5555-4555-8555-555555555555"),
        user_id=_USER_ID,
        command_id=draft.command_id,
        from_account_id=draft.from_account_id,
        from_amount=draft.from_amount,
        from_currency=draft.from_currency,
        to_account_id=draft.to_account_id,
        to_amount=draft.to_amount,
        to_currency=draft.to_currency,
        occurred_on=draft.occurred_on,
        status="confirmed",
        confirmed_at=_CAPTURED_AT,
        created_at=_CAPTURED_AT,
    )


class _Repository:
    def __init__(
        self,
        *,
        wallets: tuple[TransferWalletSnapshot, ...] | None = None,
        replay: TransferWriteResult | None = None,
    ) -> None:
        self._wallets = (
            wallets
            if wallets is not None
            else (
                TransferWalletSnapshot(
                    account_id=_EURO, currency="EUR", opening_balance_on=_BASELINE
                ),
                TransferWalletSnapshot(
                    account_id=_DOLLARS, currency="USD", opening_balance_on=_BASELINE
                ),
            )
        )
        self._replay = replay
        self.committed: list[TransferDraft] = []

    async def get_transfer_wallets(
        self, *, user_id: UUID, account_ids: tuple[UUID, ...]
    ) -> tuple[TransferWalletSnapshot, ...]:
        del user_id
        return tuple(
            wallet for wallet in self._wallets if wallet.account_id in account_ids
        )

    async def replay_transfer(
        self, *, user_id: UUID, command_id: UUID, payload_hash: bytes
    ) -> TransferWriteResult | None:
        del user_id, command_id
        assert len(payload_hash) == 32
        return self._replay

    async def commit_transfer(
        self,
        *,
        user_id: UUID,
        draft: TransferDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> TransferWriteResult:
        del user_id, confirmed_at
        assert len(payload_hash) == 32
        self.committed.append(draft)
        return TransferWriteResult(transfer=_committed(draft), idempotent_replay=False)


# --- the contract -------------------------------------------------------------


def test_a_transfer_needs_two_different_wallets() -> None:
    with pytest.raises(ValidationError):
        _draft(toAccountId=str(_EURO))


def test_an_unknown_key_is_refused_rather_than_ignored() -> None:
    with pytest.raises(ValidationError):
        _draft(rate="1.08")


def test_no_rate_travels_on_the_wire() -> None:
    """The rate is implied by the two amounts and is never sent or stored."""

    wire = _draft().model_dump(mode="json", by_alias=True)

    assert set(wire) == {
        "schemaVersion",
        "commandId",
        "fromAccountId",
        "fromAmount",
        "fromCurrency",
        "toAccountId",
        "toAmount",
        "toCurrency",
        "capturedAt",
        "capturedTimezone",
        "occurredOn",
    }


def test_the_hash_binds_both_sides() -> None:
    baseline = transfer_draft_hash(_draft())

    assert transfer_draft_hash(_draft(toAmount="109.00")) != baseline
    assert transfer_draft_hash(_draft(fromAmount="101.00")) != baseline
    assert transfer_draft_hash(_draft(toCurrency="GBP")) != baseline
    assert transfer_draft_hash(_draft()) == baseline


def test_the_command_hash_binds_the_confirmation_too() -> None:
    draft = _draft()
    evaluated = transfer_draft_hash(draft)
    first = confirmed_transfer_command_hash(
        draft=draft, confirmed_at=_CAPTURED_AT, evaluated_draft_hash=evaluated
    )
    later = confirmed_transfer_command_hash(
        draft=draft,
        confirmed_at=datetime(2026, 9, 6, 18, 5, tzinfo=UTC),
        evaluated_draft_hash=evaluated,
    )

    assert first != later


def test_only_a_rejection_may_carry_issues() -> None:
    with pytest.raises(ValidationError):
        TransferErrorDetail(
            code="TRANSFER_PERSISTENCE_UNAVAILABLE",
            issues=(TransferIssue(code="WALLET_UNAVAILABLE", field="fromAccountId"),),
        )
    with pytest.raises(ValidationError):
        TransferErrorDetail(code="TRANSFER_REJECTED")


# --- what it refuses ----------------------------------------------------------


def _evaluate(repository: _Repository, draft: TransferDraft) -> tuple[str, ...]:
    core = TransferCore(repository=repository)  # type: ignore[arg-type]
    response = asyncio.run(core.evaluate(user_id=_USER_ID, draft=draft))
    return tuple(issue.code for issue in response.issues)


def test_an_accepted_transfer_is_confirmable() -> None:
    core = TransferCore(repository=_Repository())  # type: ignore[arg-type]
    response = asyncio.run(core.evaluate(user_id=_USER_ID, draft=_draft()))

    assert response.decision == "NEEDS_CONFIRMATION"
    assert response.draft_hash == transfer_draft_hash(_draft())


def test_a_wallet_that_is_not_owned_is_refused() -> None:
    repository = _Repository(
        wallets=(
            TransferWalletSnapshot(
                account_id=_EURO, currency="EUR", opening_balance_on=_BASELINE
            ),
        )
    )

    assert _evaluate(repository, _draft()) == ("WALLET_UNAVAILABLE",)


def test_an_amount_in_a_currency_the_wallet_does_not_hold_is_refused() -> None:
    assert _evaluate(_Repository(), _draft(toCurrency="GBP")) == (
        "WALLET_CURRENCY_MISMATCH",
    )


def test_money_cannot_leave_a_wallet_before_it_existed() -> None:
    assert _evaluate(_Repository(), _draft(occurredOn="2025-12-31")) == (
        "TRANSFER_BEFORE_WALLET_BASELINE",
        "TRANSFER_BEFORE_WALLET_BASELINE",
    )


def test_a_transfer_cannot_be_dated_in_the_future() -> None:
    """Judged where the money moved, not on the server's clock (ADR 0007)."""

    assert _evaluate(_Repository(), _draft(occurredOn="2026-09-07")) == (
        "FUTURE_OCCURRED_DATE",
    )


# --- committing ---------------------------------------------------------------


def test_a_confirmed_transfer_settles_once() -> None:
    repository = _Repository()
    core = TransferCore(repository=repository)  # type: ignore[arg-type]
    draft = _draft()

    result = asyncio.run(
        core.commit(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=transfer_draft_hash(draft),
            confirmed_at=_CAPTURED_AT,
        )
    )

    assert result.idempotent_replay is False
    assert result.transfer.from_amount == Decimal("100.00")
    assert result.transfer.to_amount == Decimal("108.00")
    assert len(repository.committed) == 1


def test_a_replay_does_not_move_the_money_again() -> None:
    draft = _draft()
    repository = _Repository(
        replay=TransferWriteResult(transfer=_committed(draft), idempotent_replay=True)
    )
    core = TransferCore(repository=repository)  # type: ignore[arg-type]

    result = asyncio.run(
        core.commit(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=transfer_draft_hash(draft),
            confirmed_at=_CAPTURED_AT,
        )
    )

    assert result.idempotent_replay is True
    assert repository.committed == []


def test_a_rejection_at_review_is_a_rejection_at_commit() -> None:
    """A stale draft must not settle what the review refused."""

    draft = _draft(occurredOn="2026-09-07")
    core = TransferCore(repository=_Repository())  # type: ignore[arg-type]

    with pytest.raises(TransferRejected):
        asyncio.run(
            core.commit(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash=transfer_draft_hash(draft),
                confirmed_at=_CAPTURED_AT,
            )
        )


def test_confirming_before_the_capture_is_refused() -> None:
    draft = _draft()
    core = TransferCore(repository=_Repository())  # type: ignore[arg-type]

    with pytest.raises(TransferRejected) as rejection:
        asyncio.run(
            core.commit(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash=transfer_draft_hash(draft),
                confirmed_at=datetime(2026, 9, 6, 17, 0, tzinfo=UTC),
            )
        )

    assert [issue.code for issue in rejection.value.issues] == [
        "CONFIRMATION_BEFORE_CAPTURE"
    ]
