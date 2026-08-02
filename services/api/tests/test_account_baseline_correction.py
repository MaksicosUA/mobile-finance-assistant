"""ADR 0016: an audited correction of the account opening baseline date."""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient, Response

from mobile_finance_api.account_contracts import (
    CommittedFinanceAccount,
    CorrectBaselineDraft,
    baseline_draft_hash,
)
from mobile_finance_api.account_core import (
    AccountCommandConflict,
    AccountConfirmationMismatch,
    AccountCore,
    AccountUnavailable,
    BaselineCorrectionSnapshot,
    BaselineRejected,
    BaselineWriteResult,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_OPEN_COMMAND_ID = UUID("44444444-4444-4444-8444-444444444444")
_CORRECTION_ID = UUID("55555555-5555-4555-8555-555555555555")
_OTHER_CORRECTION_ID = UUID("66666666-6666-4666-8666-666666666666")
_NOW = datetime(2026, 8, 2, 12, tzinfo=UTC)
_CURRENT_BASELINE = date(2026, 8, 2)


def _draft(**changes: object) -> CorrectBaselineDraft:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_CORRECTION_ID),
        "accountId": str(_ACCOUNT_ID),
        "openingBalanceOn": "2026-01-01",
    }
    payload.update(changes)
    return CorrectBaselineDraft.model_validate(payload)


def _account(opening_balance_on: date = _CURRENT_BASELINE) -> CommittedFinanceAccount:
    return CommittedFinanceAccount.model_validate(
        {
            "accountId": str(_ACCOUNT_ID),
            "userId": str(_USER_ID),
            "commandId": str(_OPEN_COMMAND_ID),
            "name": "Основной счёт",
            "currency": "EUR",
            "openingBalance": "1250.50",
            "openingBalanceOn": opening_balance_on.isoformat(),
            "openingTimezone": "Europe/Berlin",
            "status": "active",
            "isDefault": True,
            "confirmedAt": "2026-08-02T10:00:00Z",
            "createdAt": "2026-08-02T10:00:00Z",
        }
    )


def _core(repository: _MemoryBaselineRepository) -> AccountCore:
    return AccountCore(repository=repository, clock=lambda: _NOW)


def test_baseline_evaluation_confirms_an_earlier_date() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        response = await _core(repository).evaluate_baseline(
            user_id=_USER_ID,
            draft=_draft(),
        )

        assert response.decision == "NEEDS_CONFIRMATION"
        assert response.draft_hash == baseline_draft_hash(_draft())
        assert response.current_opening_balance_on == _CURRENT_BASELINE
        assert response.earliest_operation_on is None
        assert response.issues == ()

    asyncio.run(scenario())


@pytest.mark.parametrize(
    ("requested", "expected"),
    [
        # Equal to the current baseline: only the direction rule applies.
        ("2026-08-02", ["BASELINE_NOT_EARLIER"]),
        # Later than today as well, so both bounds report in a fixed order.
        ("2026-08-03", ["BASELINE_NOT_EARLIER", "BASELINE_DATE_IN_FUTURE"]),
    ],
)
def test_baseline_refuses_a_date_that_is_not_earlier(
    requested: str,
    expected: list[str],
) -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        response = await _core(repository).evaluate_baseline(
            user_id=_USER_ID,
            draft=_draft(openingBalanceOn=requested),
        )

        assert response.decision == "REJECT"
        assert response.draft_hash is None
        assert [issue.code for issue in response.issues] == expected

    asyncio.run(scenario())


def test_baseline_refuses_a_future_date_in_the_canonical_calendar() -> None:
    """Defensive while corrections move earlier; the rule must still hold."""

    async def scenario() -> None:
        repository = _MemoryBaselineRepository(
            snapshot_baseline=date(2027, 1, 1),
        )
        response = await _core(repository).evaluate_baseline(
            user_id=_USER_ID,
            draft=_draft(openingBalanceOn="2026-12-31"),
        )

        assert response.decision == "REJECT"
        assert [issue.code for issue in response.issues] == ["BASELINE_DATE_IN_FUTURE"]

    asyncio.run(scenario())


def test_baseline_refuses_a_date_after_an_existing_operation() -> None:
    """Defensive while corrections move earlier; the rule must still hold."""

    async def scenario() -> None:
        repository = _MemoryBaselineRepository(
            snapshot_baseline=date(2026, 1, 1),
            earliest_operation_on=date(2025, 6, 1),
        )
        response = await _core(repository).evaluate_baseline(
            user_id=_USER_ID,
            draft=_draft(openingBalanceOn="2025-12-01"),
        )

        assert response.decision == "REJECT"
        assert [issue.code for issue in response.issues] == [
            "BASELINE_AFTER_EXISTING_OPERATION"
        ]

    asyncio.run(scenario())


def test_baseline_commit_moves_the_date_and_records_the_previous_one() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        draft = _draft()
        result = await _core(repository).commit_baseline(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=baseline_draft_hash(draft),
            confirmed_at=_NOW,
        )

        assert result.idempotent_replay is False
        assert result.previous_opening_balance_on == _CURRENT_BASELINE
        assert result.account.opening_balance_on == date(2026, 1, 1)
        assert repository.corrections == 1
        assert repository.audit == [
            (_CORRECTION_ID, _CURRENT_BASELINE, date(2026, 1, 1))
        ]
        assert repository.invalidations == [_CORRECTION_ID]

    asyncio.run(scenario())


def test_baseline_replay_returns_the_original_and_corrects_once() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        core = _core(repository)
        draft = _draft()
        first = await core.commit_baseline(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=baseline_draft_hash(draft),
            confirmed_at=_NOW,
        )
        replayed = await core.commit_baseline(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=baseline_draft_hash(draft),
            confirmed_at=_NOW,
        )

        assert first.idempotent_replay is False
        assert replayed.idempotent_replay is True
        assert replayed.previous_opening_balance_on == _CURRENT_BASELINE
        assert replayed.account.opening_balance_on == date(2026, 1, 1)
        # The decisive property: an exact replay never corrects a second time.
        assert repository.corrections == 1
        assert repository.invalidations == [_CORRECTION_ID]

    asyncio.run(scenario())


def test_baseline_rejects_reused_command_identity_with_new_content() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        core = _core(repository)
        draft = _draft()
        await core.commit_baseline(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=baseline_draft_hash(draft),
            confirmed_at=_NOW,
        )
        conflicting = _draft(openingBalanceOn="2025-01-01")
        with pytest.raises(AccountCommandConflict):
            await core.commit_baseline(
                user_id=_USER_ID,
                draft=conflicting,
                expected_draft_hash=baseline_draft_hash(conflicting),
                confirmed_at=_NOW,
            )
        assert repository.corrections == 1

    asyncio.run(scenario())


def test_baseline_commit_requires_the_evaluated_hash() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        with pytest.raises(AccountConfirmationMismatch):
            await _core(repository).commit_baseline(
                user_id=_USER_ID,
                draft=_draft(),
                expected_draft_hash=baseline_draft_hash(
                    _draft(openingBalanceOn="2025-01-01")
                ),
                confirmed_at=_NOW,
            )
        assert repository.corrections == 0

    asyncio.run(scenario())


def test_baseline_revalidates_between_evaluation_and_confirmation() -> None:
    """An operation committed after evaluation must block the correction."""

    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        core = _core(repository)
        draft = _draft()
        evaluation = await core.evaluate_baseline(user_id=_USER_ID, draft=draft)
        assert evaluation.decision == "NEEDS_CONFIRMATION"

        # The window between the two requests is exactly where state can move.
        repository.snapshot_baseline = date(2025, 1, 1)

        with pytest.raises(BaselineRejected) as rejection:
            await core.commit_baseline(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash=baseline_draft_hash(draft),
                confirmed_at=_NOW,
            )
        assert [issue.code for issue in rejection.value.issues] == [
            "BASELINE_NOT_EARLIER"
        ]
        assert repository.corrections == 0

    asyncio.run(scenario())


def test_baseline_refuses_an_account_that_is_not_owned() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository(missing=True)
        with pytest.raises(AccountUnavailable):
            await _core(repository).evaluate_baseline(
                user_id=_USER_ID,
                draft=_draft(),
            )

    asyncio.run(scenario())


def test_baseline_api_confirms_replays_and_reports_issues() -> None:
    async def scenario() -> None:
        repository = _MemoryBaselineRepository()
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            account_core=_core(repository),
        )
        headers = {
            "Authorization": "Bearer synthetic-token",
            "X-Request-ID": "baseline-contract-test",
        }
        draft_json = _draft().model_dump(mode="json", by_alias=True)
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            evaluation = await client.post(
                "/api/v1/accounts/baseline/evaluate",
                json={"draft": draft_json},
                headers=headers,
            )
            assert evaluation.status_code == 200
            body = evaluation.json()
            assert body["decision"] == "NEEDS_CONFIRMATION"
            assert body["currentOpeningBalanceOn"] == "2026-08-02"
            assert body["earliestOperationOn"] is None
            _assert_private_response(evaluation)

            commit_payload = {
                "schemaVersion": "1",
                "draft": draft_json,
                "draftHash": body["draftHash"],
                "confirmedAt": "2026-08-02T12:00:00Z",
            }
            accepted = await client.post(
                "/api/v1/accounts/baseline/commit",
                json=commit_payload,
                headers=headers,
            )
            assert accepted.status_code == 200
            accepted_body = accepted.json()
            assert accepted_body["decision"] == "ACCEPT"
            assert accepted_body["idempotentReplay"] is False
            assert accepted_body["previousOpeningBalanceOn"] == "2026-08-02"
            assert accepted_body["account"]["openingBalanceOn"] == "2026-01-01"
            _assert_private_response(accepted)

            replayed = await client.post(
                "/api/v1/accounts/baseline/commit",
                json=commit_payload,
                headers=headers,
            )
            assert replayed.status_code == 200
            assert replayed.json()["idempotentReplay"] is True
            assert repository.corrections == 1

            rejected = await client.post(
                "/api/v1/accounts/baseline/commit",
                json={
                    **commit_payload,
                    "draft": {
                        **draft_json,
                        "commandId": str(_OTHER_CORRECTION_ID),
                        "openingBalanceOn": "2026-06-01",
                    },
                    "draftHash": baseline_draft_hash(
                        _draft(
                            commandId=str(_OTHER_CORRECTION_ID),
                            openingBalanceOn="2026-06-01",
                        )
                    ),
                },
                headers=headers,
            )
            assert rejected.status_code == 422
            assert rejected.json()["detail"] == {
                "code": "BASELINE_REJECTED",
                "issues": [],
                "baselineIssues": [
                    {
                        "code": "BASELINE_NOT_EARLIER",
                        "field": "openingBalanceOn",
                    }
                ],
            }
            _assert_private_response(rejected)

    asyncio.run(scenario())


def test_baseline_api_reports_a_missing_account_without_leaking_state() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            account_core=_core(_MemoryBaselineRepository(missing=True)),
        )
        headers = {
            "Authorization": "Bearer synthetic-token",
            "X-Request-ID": "baseline-missing-test",
        }
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/accounts/baseline/evaluate",
                json={"draft": _draft().model_dump(mode="json", by_alias=True)},
                headers=headers,
            )

        assert response.status_code == 404
        # No baselineIssues key: the shape of non-baseline errors is unchanged
        # for installed clients that parse it strictly.
        assert response.json()["detail"] == {
            "code": "ACCOUNT_UNAVAILABLE",
            "issues": [],
        }
        _assert_private_response(response)

    asyncio.run(scenario())


class _MemoryBaselineRepository:
    """In-memory stand-in that mirrors the audited correction guarantees."""

    def __init__(
        self,
        *,
        missing: bool = False,
        snapshot_baseline: date = _CURRENT_BASELINE,
        earliest_operation_on: date | None = None,
    ) -> None:
        self._account = _account()
        self._has_account = not missing
        self.snapshot_baseline = snapshot_baseline
        self.earliest_operation_on = earliest_operation_on
        self.corrections = 0
        self.audit: list[tuple[UUID, date, date]] = []
        self.invalidations: list[UUID] = []
        self._commands: dict[UUID, tuple[bytes, date, date]] = {}

    async def get_baseline_snapshot(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> BaselineCorrectionSnapshot | None:
        if not self._has_account or account_id != _ACCOUNT_ID:
            return None
        return BaselineCorrectionSnapshot(
            account_id=_ACCOUNT_ID,
            user_id=user_id,
            opening_balance_on=self.snapshot_baseline,
            canonical_timezone="Europe/Berlin",
            earliest_operation_on=self.earliest_operation_on,
        )

    async def replay_existing_baseline(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BaselineWriteResult | None:
        del user_id, account_id
        recorded = self._commands.get(command_id)
        if recorded is None:
            return None
        stored_hash, previous, corrected = recorded
        if stored_hash != payload_hash:
            raise AccountCommandConflict
        return BaselineWriteResult(
            account=self._account.model_copy(update={"opening_balance_on": corrected}),
            previous_opening_balance_on=previous,
            idempotent_replay=True,
        )

    async def correct_opening_baseline(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> BaselineWriteResult:
        del user_id, confirmed_at
        previous = self.snapshot_baseline
        self.snapshot_baseline = draft.opening_balance_on
        self._account = self._account.model_copy(
            update={"opening_balance_on": draft.opening_balance_on}
        )
        self.corrections += 1
        self.audit.append((draft.command_id, previous, draft.opening_balance_on))
        self.invalidations.append(draft.command_id)
        self._commands[draft.command_id] = (
            payload_hash,
            previous,
            draft.opening_balance_on,
        )
        return BaselineWriteResult(
            account=self._account,
            previous_opening_balance_on=previous,
            idempotent_replay=False,
        )


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(
            subject=str(_USER_ID),
            display_name="Synthetic User",
        )


def _assert_private_response(response: Response) -> None:
    headers = response.headers
    assert headers["cache-control"] == "no-store"
    assert headers["pragma"] == "no-cache"
    assert headers["x-request-id"]
