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
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.home_projection import (
    ProjectionAccount,
    ProjectionTransfer,
    build_current_home_revision,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.transfer_contracts import (
    CommittedTransfer,
    TransferDraft,
    TransferErrorDetail,
    TransferIssue,
    confirmed_transfer_command_hash,
    transfer_draft_hash,
)
from mobile_finance_api.transfer_core import (
    TransferCommandConflict,
    TransferCore,
    TransferPersistenceUnavailable,
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


# --- over HTTP ----------------------------------------------------------------


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


def _application(repository: object):  # type: ignore[no-untyped-def]
    return create_app(
        transfer_core=TransferCore(repository=repository),  # type: ignore[arg-type]
        current_user_authenticator=_StaticAuthenticator(),
    )


async def _post(app: object, path: str, body: dict[str, object], *, auth: bool = True):  # type: ignore[no-untyped-def]
    headers = {"Authorization": "Bearer synthetic-token"} if auth else {}
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        return await client.post(path, json=body, headers=headers)


def _commit_body(draft: TransferDraft, **changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "draft": draft.model_dump(mode="json", by_alias=True),
        "draftHash": transfer_draft_hash(draft),
        "confirmedAt": "2026-09-06T18:00:00Z",
    }
    body.update(changes)
    return body


def test_a_reviewed_transfer_answers_a_hash() -> None:
    async def scenario() -> None:
        response = await _post(
            _application(_Repository()),
            "/api/v1/transfers/evaluate",
            {"draft": _draft().model_dump(mode="json", by_alias=True)},
        )

        assert response.status_code == 200, response.text
        assert response.json()["decision"] == "NEEDS_CONFIRMATION"
        assert response.json()["draftHash"] == transfer_draft_hash(_draft())

    asyncio.run(scenario())


def test_a_confirmed_transfer_answers_201_and_a_replay_answers_200() -> None:
    async def scenario() -> None:
        draft = _draft()
        created = await _post(
            _application(_Repository()),
            "/api/v1/transfers/commit",
            _commit_body(draft),
        )
        assert created.status_code == 201, created.text
        assert created.json()["transfer"]["toAmount"] == "108"

        replayed = await _post(
            _application(
                _Repository(
                    replay=TransferWriteResult(
                        transfer=_committed(draft), idempotent_replay=True
                    )
                )
            ),
            "/api/v1/transfers/commit",
            _commit_body(draft),
        )
        assert replayed.status_code == 200, replayed.text
        assert replayed.json()["idempotentReplay"] is True

    asyncio.run(scenario())


def test_a_changed_draft_is_not_the_draft_that_was_reviewed() -> None:
    async def scenario() -> None:
        response = await _post(
            _application(_Repository()),
            "/api/v1/transfers/commit",
            _commit_body(_draft(), draftHash="0" * 64),
        )

        assert response.status_code == 422
        assert response.json()["detail"] == {
            "code": "CONFIRMATION_MISMATCH",
            "issues": [],
        }

    asyncio.run(scenario())


def test_a_reused_identity_with_other_content_is_a_conflict() -> None:
    class _Conflicting(_Repository):
        async def replay_transfer(self, **_: object) -> TransferWriteResult | None:
            raise TransferCommandConflict

    async def scenario() -> None:
        response = await _post(
            _application(_Conflicting()),
            "/api/v1/transfers/commit",
            _commit_body(_draft()),
        )

        assert response.status_code == 409
        assert response.json()["detail"]["code"] == "COMMAND_CONFLICT"

    asyncio.run(scenario())


def test_a_rejection_is_typed_and_names_its_field() -> None:
    async def scenario() -> None:
        draft = _draft(occurredOn="2026-09-07")
        response = await _post(
            _application(_Repository()),
            "/api/v1/transfers/commit",
            _commit_body(draft),
        )

        assert response.status_code == 422
        assert response.json()["detail"] == {
            "code": "TRANSFER_REJECTED",
            "issues": [{"code": "FUTURE_OCCURRED_DATE", "field": "occurredOn"}],
        }

    asyncio.run(scenario())


def test_a_persistence_failure_is_redacted() -> None:
    class _Broken(_Repository):
        async def get_transfer_wallets(self, **_: object):  # type: ignore[no-untyped-def]
            raise TransferPersistenceUnavailable

    async def scenario() -> None:
        response = await _post(
            _application(_Broken()),
            "/api/v1/transfers/evaluate",
            {"draft": _draft().model_dump(mode="json", by_alias=True)},
        )

        assert response.status_code == 503
        assert response.json()["detail"]["code"] == "TRANSFER_PERSISTENCE_UNAVAILABLE"
        # No amount and no wallet identifier escapes with the refusal.
        assert "108" not in response.text

    asyncio.run(scenario())


def test_an_anonymous_caller_is_refused() -> None:
    async def scenario() -> None:
        response = await _post(
            _application(_Repository()),
            "/api/v1/transfers/evaluate",
            {"draft": _draft().model_dump(mode="json", by_alias=True)},
            auth=False,
        )

        assert response.status_code == 401

    asyncio.run(scenario())


# --- what a transfer does to a balance ----------------------------------------


def _account() -> ProjectionAccount:
    return ProjectionAccount(
        account_id=_EURO,
        user_id=_USER_ID,
        currency="EUR",
        opening_balance=Decimal("1000.00"),
        opening_balance_on=_BASELINE,
        opening_timezone="Europe/Berlin",
        status="active",
        is_default=True,
        created_at=datetime(2026, 1, 1, tzinfo=UTC),
    )


def _projection_transfer(
    *,
    from_account: UUID = _EURO,
    to_account: UUID = _DOLLARS,
    from_amount: str = "100.00",
    to_amount: str = "108.00",
    occurred_on: date = date(2026, 9, 6),
) -> ProjectionTransfer:
    return ProjectionTransfer(
        transfer_id=UUID("66666666-6666-4666-8666-666666666666"),
        user_id=_USER_ID,
        from_account_id=from_account,
        from_amount=Decimal(from_amount),
        to_account_id=to_account,
        to_amount=Decimal(to_amount),
        occurred_on=occurred_on,
        created_at=_CAPTURED_AT,
    )


def _revision(*transfers: ProjectionTransfer):  # type: ignore[no-untyped-def]
    return build_current_home_revision(
        account=_account(),
        operations=(),
        generated_at=datetime(2026, 9, 6, 20, 0, tzinfo=UTC),
        transfers=transfers,
    )


def test_money_leaving_a_wallet_lowers_its_balance() -> None:
    assert _revision(_projection_transfer()).balance_amount == Decimal("900.00")


def test_money_arriving_raises_it_by_what_arrived() -> None:
    """Not by what left: nothing is converted, and the two are different
    numbers on purpose."""

    revision = _revision(_projection_transfer(from_account=_DOLLARS, to_account=_EURO))

    assert revision.balance_amount == Decimal("1108.00")


def test_a_transfer_is_neither_income_nor_expense() -> None:
    revision = _revision(_projection_transfer())

    assert revision.month_income == 0
    assert revision.month_expense == 0
    assert revision.month_net_flow == 0


def test_a_transfer_leaves_the_month_delta_alone() -> None:
    """Moving money between one's own wallets is not a result for the month.

    The owner decided this on 2026-10-15, after a real exchange showed as
    "−100,00 € за месяц" under the balance and read as money lost. The balance
    itself still moves — the euros did leave this wallet — but the delta under
    it is income minus expense, which a transfer is neither of (ADR 0029).
    """

    revision = _revision(_projection_transfer())

    assert revision.balance_amount == Decimal("900.00")
    assert revision.balance_delta_amount == 0
    assert revision.balance_delta_amount == revision.month_net_flow


def test_the_month_percent_ignores_a_transfer_too() -> None:
    """A percent beside a zero delta that is not zero would be two answers."""

    revision = _revision(_projection_transfer())

    assert revision.balance_delta_percent in {None, Decimal("0.00")}


def test_a_transfer_between_two_other_wallets_does_nothing_here() -> None:
    other = UUID("77777777-7777-4777-8777-777777777777")
    revision = _revision(_projection_transfer(from_account=other, to_account=_DOLLARS))

    assert revision.balance_amount == Decimal("1000.00")
    assert revision.balance_delta_amount == 0


def test_a_transfer_before_the_wallet_existed_does_not_count() -> None:
    revision = _revision(_projection_transfer(occurred_on=date(2025, 12, 31)))

    assert revision.balance_amount == Decimal("1000.00")
