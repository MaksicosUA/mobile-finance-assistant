"""Correcting and removing a confirmed operation (ADR 0023).

An operation used to be final. Since a written sentence fills the form and a
keyword picks the category, being wrong occasionally is designed in, so being
unable to fix it is not acceptable.

Nothing here mutates an operation: a reversal is its own row, a correction
writes the replacement in the same transaction, and a removal is a reversal
with no replacement.
"""

from __future__ import annotations

import asyncio
from datetime import date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.account_core import FinanceAccountSnapshot
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.finance_core import (
    FinanceCore,
    OperationAlreadyReversed,
    OperationCommandConflict,
    OperationNotFound,
    OperationReversalResult,
    OperationWriteResult,
    correction_command_hash,
    draft_hash,
    removal_command_hash,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.operation_contracts import (
    CommittedOperation,
    CorrectOperationRequest,
    CorrectOperationResponse,
    OperationDraft,
    OperationReversal,
    RemoveOperationRequest,
    RemoveOperationResponse,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_TARGET_ID = UUID("33333333-3333-4333-8333-333333333333")
_OTHER_TARGET_ID = UUID("99999999-9999-4999-8999-999999999999")
_COMMAND_ID = UUID("44444444-4444-4444-8444-444444444444")
_CONFIRMED_AT = "2026-07-27T18:01:00Z"
_AUTH = {"Authorization": "Bearer synthetic-token"}


def _draft(**changes: object) -> OperationDraft:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "type": "expense",
        "amount": "35.00",
        "currency": "EUR",
        "accountId": str(_ACCOUNT_ID),
        "category": "Продукты",
        "merchant": None,
        "capturedAt": "2026-07-27T18:00:00Z",
        "capturedTimezone": "Europe/Berlin",
        "sourceExpression": "вчера",
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": "2026-07-26",
        "occurredAt": None,
        "source": "manual_text",
    }
    payload.update(changes)
    return OperationDraft.model_validate(payload)


def _correction(**changes: object) -> dict[str, object]:
    draft = _draft()
    body: dict[str, object] = {
        "schemaVersion": "1",
        "targetOperationId": str(_TARGET_ID),
        "draft": draft.model_dump(mode="json", by_alias=True),
        "draftHash": draft_hash(draft),
        "confirmedAt": _CONFIRMED_AT,
    }
    body.update(changes)
    return body


def _removal(**changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "targetOperationId": str(_TARGET_ID),
        "commandId": str(_COMMAND_ID),
        "confirmedAt": _CONFIRMED_AT,
    }
    body.update(changes)
    return body


# --- contract rules ---------------------------------------------------------


def test_a_correction_must_return_the_replacement_it_wrote() -> None:
    """The receipt cannot describe a reversal it did not perform."""

    replacement_id = uuid4()
    with pytest.raises(ValidationError):
        CorrectOperationResponse(
            idempotentReplay=False,
            reversal=_reversal(replacement_operation_id=uuid4()),
            operation=_committed(operation_id=replacement_id),
        )
    accepted = CorrectOperationResponse(
        idempotentReplay=False,
        reversal=_reversal(replacement_operation_id=replacement_id),
        operation=_committed(operation_id=replacement_id),
    )
    assert accepted.reversal.replacement_operation_id == replacement_id


def test_a_removal_cannot_carry_a_replacement() -> None:
    with pytest.raises(ValidationError):
        RemoveOperationResponse(
            idempotentReplay=False,
            reversal=_reversal(replacement_operation_id=uuid4()),
        )
    assert (
        RemoveOperationResponse(
            idempotentReplay=False,
            reversal=_reversal(replacement_operation_id=None),
        ).reversal.replacement_operation_id
        is None
    )


def test_the_command_identity_includes_the_operation_being_corrected() -> None:
    """Otherwise a retry could withdraw a different operation.

    The same replacement draft aimed at another target is a different command,
    so a replay that names the wrong one is refused as a conflict instead of
    quietly reversing something else.
    """

    first = CorrectOperationRequest.model_validate(_correction())
    elsewhere = CorrectOperationRequest.model_validate(
        _correction(targetOperationId=str(_OTHER_TARGET_ID))
    )
    assert correction_command_hash(first) != correction_command_hash(elsewhere)

    removal = RemoveOperationRequest.model_validate(_removal())
    removal_elsewhere = RemoveOperationRequest.model_validate(
        _removal(targetOperationId=str(_OTHER_TARGET_ID))
    )
    assert removal_command_hash(removal) != removal_command_hash(removal_elsewhere)


# --- correcting -------------------------------------------------------------


def test_a_correction_withdraws_the_original_and_writes_its_replacement() -> None:
    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            response = await client.post(
                "/api/v1/operations/correction",
                json=_correction(),
                headers=_AUTH,
            )
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["decision"] == "ACCEPT"
        assert body["idempotentReplay"] is False
        assert body["reversal"]["operationId"] == str(_TARGET_ID)
        # One transaction wrote both, so the money is never gone with nothing
        # in its place.
        assert (
            body["reversal"]["replacementOperationId"]
            == body["operation"]["operationId"]
        )
        assert repository.reversals == [(_TARGET_ID, _COMMAND_ID, True)]

    asyncio.run(scenario())


def test_replaying_the_same_correction_returns_the_same_result() -> None:
    """A lost response must not withdraw the money twice."""

    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            first = await client.post(
                "/api/v1/operations/correction",
                json=_correction(),
                headers=_AUTH,
            )
            second = await client.post(
                "/api/v1/operations/correction",
                json=_correction(),
                headers=_AUTH,
            )
        assert first.status_code == 201, first.text
        # 200 rather than 201: nothing new was created.
        assert second.status_code == 200, second.text
        assert second.json()["idempotentReplay"] is True
        assert (
            first.json()["reversal"]["reversalId"]
            == (second.json()["reversal"]["reversalId"])
        )
        assert len(repository.reversals) == 1

    asyncio.run(scenario())


def test_the_same_command_aimed_at_another_operation_is_a_conflict() -> None:
    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            await client.post(
                "/api/v1/operations/correction",
                json=_correction(),
                headers=_AUTH,
            )
            elsewhere = await client.post(
                "/api/v1/operations/correction",
                json=_correction(targetOperationId=str(_OTHER_TARGET_ID)),
                headers=_AUTH,
            )
        assert elsewhere.status_code == 409, elsewhere.text
        assert elsewhere.json()["detail"]["code"] == "COMMAND_CONFLICT"
        # The second target was never touched.
        assert len(repository.reversals) == 1

    asyncio.run(scenario())


def test_an_already_corrected_operation_is_refused() -> None:
    """Two corrections of one operation would withdraw the same money twice."""

    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            await client.post(
                "/api/v1/operations/correction",
                json=_correction(),
                headers=_AUTH,
            )
            # A second, honest attempt: its own command id, its own hash.
            second_attempt = _draft(commandId=str(uuid4()), amount="36.00")
            again = await client.post(
                "/api/v1/operations/correction",
                json=_correction(
                    draft=second_attempt.model_dump(mode="json", by_alias=True),
                    draftHash=draft_hash(second_attempt),
                ),
                headers=_AUTH,
            )
        assert again.status_code == 409, again.text
        assert again.json()["detail"]["code"] == "OPERATION_ALREADY_REVERSED"
        # Correcting a correction means correcting its replacement, not the
        # original again.
        assert len(repository.reversals) == 1

    asyncio.run(scenario())


def test_an_unknown_operation_and_another_users_answer_the_same_404() -> None:
    """The API never confirms an identifier exists outside the caller's ledger."""

    async def scenario() -> None:
        repository = _RecordingRepository(known={_TARGET_ID})
        async with _client(repository) as client:
            response = await client.post(
                "/api/v1/operations/correction",
                json=_correction(targetOperationId=str(_OTHER_TARGET_ID)),
                headers=_AUTH,
            )
        assert response.status_code == 404, response.text
        assert response.json() == {
            "detail": {"code": "OPERATION_NOT_FOUND", "issues": []}
        }

    asyncio.run(scenario())


def test_a_replacement_is_validated_exactly_like_a_new_operation() -> None:
    """A correction must not be a way past the rules a write obeys."""

    async def scenario() -> None:
        repository = _RecordingRepository()
        future = _draft(occurredOn="2026-07-28", sourceExpression=None)
        async with _client(repository) as client:
            response = await client.post(
                "/api/v1/operations/correction",
                json=_correction(
                    draft=future.model_dump(mode="json", by_alias=True),
                    draftHash=draft_hash(future),
                ),
                headers=_AUTH,
            )
        assert response.status_code == 422, response.text
        detail = response.json()["detail"]
        assert detail["code"] == "OPERATION_REJECTED"
        assert {issue["code"] for issue in detail["issues"]} == {"FUTURE_OCCURRED_DATE"}
        # Nothing was withdrawn: the original is still the user's record.
        assert repository.reversals == []

    asyncio.run(scenario())


def test_a_correction_confirmed_against_a_different_draft_is_refused() -> None:
    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            response = await client.post(
                "/api/v1/operations/correction",
                json=_correction(draftHash="0" * 64),
                headers=_AUTH,
            )
        assert response.status_code == 409, response.text
        assert response.json()["detail"]["code"] == "CONFIRMATION_MISMATCH"
        assert repository.reversals == []

    asyncio.run(scenario())


# --- removing ---------------------------------------------------------------


def test_a_removal_withdraws_without_replacing() -> None:
    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            response = await client.post(
                "/api/v1/operations/removal",
                json=_removal(),
                headers=_AUTH,
            )
        assert response.status_code == 201, response.text
        assert response.json()["reversal"]["replacementOperationId"] is None
        assert repository.reversals == [(_TARGET_ID, _COMMAND_ID, False)]

    asyncio.run(scenario())


def test_replaying_a_removal_does_not_withdraw_twice() -> None:
    async def scenario() -> None:
        repository = _RecordingRepository()
        async with _client(repository) as client:
            first = await client.post(
                "/api/v1/operations/removal", json=_removal(), headers=_AUTH
            )
            second = await client.post(
                "/api/v1/operations/removal", json=_removal(), headers=_AUTH
            )
        assert first.status_code == 201, first.text
        assert second.status_code == 200, second.text
        assert second.json()["idempotentReplay"] is True
        assert len(repository.reversals) == 1

    asyncio.run(scenario())


def test_a_removal_needs_no_draft_and_refuses_one() -> None:
    """There is nothing to review, so there is nothing to confirm a hash for."""

    async def scenario() -> None:
        async with _client(_RecordingRepository()) as client:
            response = await client.post(
                "/api/v1/operations/removal",
                json=_removal(draft=_draft().model_dump(mode="json", by_alias=True)),
                headers=_AUTH,
            )
        assert response.status_code == 422, response.text

    asyncio.run(scenario())


def test_persistence_failure_is_redacted_to_a_typed_code() -> None:
    async def scenario() -> None:
        async with _client(_RecordingRepository(broken=True)) as client:
            response = await client.post(
                "/api/v1/operations/removal", json=_removal(), headers=_AUTH
            )
        assert response.status_code == 503, response.text
        assert response.json() == {
            "detail": {"code": "FINANCE_PERSISTENCE_UNAVAILABLE", "issues": []}
        }

    asyncio.run(scenario())


# --- helpers ----------------------------------------------------------------


def _client(repository: _RecordingRepository) -> AsyncClient:
    core = FinanceCore(
        repository=repository,
        account_directory=_StaticAccountDirectory(),
    )
    app = create_app(
        current_user_authenticator=_StaticAuthenticator(),
        finance_core=core,
    )
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


def _reversal(*, replacement_operation_id: UUID | None) -> OperationReversal:
    return OperationReversal(
        reversalId=uuid4(),
        operationId=_TARGET_ID,
        replacementOperationId=replacement_operation_id,
        commandId=_COMMAND_ID,
        confirmedAt=_CONFIRMED_AT,
        createdAt=_CONFIRMED_AT,
    )


def _committed(*, operation_id: UUID) -> CommittedOperation:
    draft = _draft()
    return CommittedOperation(
        operationId=operation_id,
        userId=_USER_ID,
        commandId=draft.command_id,
        type=draft.operation_type,
        amount=Decimal("35.00"),
        currency=draft.currency,
        accountId=draft.account_id,
        category=draft.category,
        categoryId=draft.category_id,
        merchant=draft.merchant,
        capturedAt=draft.captured_at,
        capturedTimezone=draft.captured_timezone,
        sourceExpression=draft.source_expression,
        dateResolverVersion=draft.date_resolver_version,
        occurredOn=draft.occurred_on,
        occurredAt=draft.occurred_at,
        source=draft.source,
        status="confirmed",
        confirmedAt=_CONFIRMED_AT,
        createdAt=_CONFIRMED_AT,
    )


class _RecordingRepository:
    """An in-memory stand-in that keeps the rules the database enforces."""

    def __init__(
        self,
        *,
        known: set[UUID] | None = None,
        broken: bool = False,
    ) -> None:
        self._known = known if known is not None else {_TARGET_ID, _OTHER_TARGET_ID}
        self._broken = broken
        self._by_command: dict[UUID, OperationReversalResult] = {}
        self._by_operation: dict[UUID, OperationReversalResult] = {}
        self._hashes: dict[UUID, bytes] = {}
        self.reversals: list[tuple[UUID, UUID, bool]] = []

    async def replay_existing(self, **_: object) -> OperationWriteResult | None:
        return None

    async def commit(self, **_: object) -> OperationWriteResult:
        raise AssertionError("a correction must not go through the create path")

    async def replay_reversal(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationReversalResult | None:
        del user_id
        if self._broken:
            raise RuntimeError("synthetic persistence failure")
        recorded = self._by_command.get(command_id)
        if recorded is None:
            return None
        if self._hashes[command_id] != payload_hash:
            raise OperationCommandConflict
        return recorded

    async def reverse(
        self,
        *,
        user_id: UUID,
        target_operation_id: UUID,
        command_id: UUID,
        replacement: OperationDraft | None,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationReversalResult:
        del user_id, confirmed_at
        if target_operation_id not in self._known:
            raise OperationNotFound
        if target_operation_id in self._by_operation:
            raise OperationAlreadyReversed
        replacement_id = uuid4() if replacement is not None else None
        result = OperationReversalResult(
            reversal=OperationReversal(
                reversalId=uuid4(),
                operationId=target_operation_id,
                replacementOperationId=replacement_id,
                commandId=command_id,
                confirmedAt=_CONFIRMED_AT,
                createdAt=_CONFIRMED_AT,
            ),
            replacement=(
                None
                if replacement_id is None
                else _committed(operation_id=replacement_id)
            ),
            idempotent_replay=True,
        )
        self._by_command[command_id] = result
        self._by_operation[target_operation_id] = result
        self._hashes[command_id] = payload_hash
        self.reversals.append(
            (target_operation_id, command_id, replacement is not None)
        )
        return OperationReversalResult(
            reversal=result.reversal,
            replacement=result.replacement,
            idempotent_replay=False,
        )


class _StaticAccountDirectory:
    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        if user_id != _USER_ID or account_id != _ACCOUNT_ID:
            return None
        return FinanceAccountSnapshot(
            account_id=_ACCOUNT_ID,
            user_id=_USER_ID,
            currency="EUR",
            opening_balance_on=date(2026, 7, 1),
            status="active",
        )


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic User")
