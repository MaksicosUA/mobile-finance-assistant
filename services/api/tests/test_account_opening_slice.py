from __future__ import annotations

import asyncio
import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient, Response
from pydantic import ValidationError

from mobile_finance_api.account_contracts import (
    AccountDraft,
    CommittedFinanceAccount,
    account_contract_schema,
    account_draft_hash,
    confirmed_account_command_hash,
)
from mobile_finance_api.account_core import (
    AccountAlreadyInitialized,
    AccountCommandConflict,
    AccountCore,
    AccountListSnapshot,
    AccountPersistenceUnavailable,
    AccountSetupSnapshot,
    AccountWriteResult,
    FinanceAccountSnapshot,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_SECOND_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_NOW = datetime(2026, 7, 27, 12, tzinfo=UTC)


def _draft(**changes: object) -> AccountDraft:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "44444444-4444-4444-8444-444444444444",
        "name": "Основной счёт",
        "currency": "EUR",
        "openingBalance": "1250.50",
        "openingBalanceOn": "2026-07-26",
        "canonicalTimezone": "Europe/Berlin",
    }
    payload.update(changes)
    return AccountDraft.model_validate(payload)


@pytest.mark.parametrize(
    ("value", "serialized"),
    [
        ("0", "0"),
        ("-0.00", "0"),
        ("1250.5000", "1250.5"),
        ("-75.25", "-75.25"),
        ("999999999999999.99", "999999999999999.99"),
        ("-999999999999999.99", "-999999999999999.99"),
    ],
)
def test_opening_balance_accepts_strict_signed_decimal_strings(
    value: str,
    serialized: str,
) -> None:
    draft = _draft(openingBalance=value)
    assert draft.model_dump(mode="json", by_alias=True)["openingBalance"] == serialized


@pytest.mark.parametrize(
    "value",
    [
        0,
        1,
        -1,
        1.25,
        "",
        " 1",
        "+1",
        "01",
        "1e2",
        "NaN",
        "Infinity",
        "100000000000000000000",
        "1.1234567890123456789",
    ],
)
def test_opening_balance_rejects_non_contract_money(value: object) -> None:
    with pytest.raises(ValidationError):
        _draft(openingBalance=value)


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("openingBalanceOn", "1899-12-31"),
        ("openingBalanceOn", "2101-01-01"),
        ("canonicalTimezone", ""),
        ("canonicalTimezone", " Europe/Berlin"),
        ("canonicalTimezone", "+02:00"),
        ("canonicalTimezone", "Not/A_Timezone"),
        ("canonicalTimezone", "localtime"),
        ("canonicalTimezone", "Factory"),
        ("canonicalTimezone", "posixrules"),
    ],
)
def test_account_date_and_timezone_are_strict(field: str, value: str) -> None:
    with pytest.raises(ValidationError):
        _draft(**{field: value})


def test_account_name_is_trimmed_normalized_and_safe() -> None:
    draft = _draft(name="  Cafe\u0301  ")
    assert draft.name == "Café"
    with pytest.raises(ValidationError):
        _draft(name="unsafe\nname")
    with pytest.raises(ValidationError):
        _draft(name="x" * 101)


@pytest.mark.parametrize(
    "field",
    ["userId", "accountId", "createdAt", "currentBalance"],
)
def test_account_draft_rejects_server_owned_mass_assignment(field: str) -> None:
    with pytest.raises(ValidationError):
        _draft(**{field: str(_SECOND_USER_ID)})


def test_account_hash_is_canonical_and_binds_every_reviewed_field() -> None:
    original = _draft(name="Cafe\u0301", openingBalance="-0.00")
    equivalent = _draft(name="Café", openingBalance="0")
    changed = _draft(canonicalTimezone="Europe/Paris")

    assert account_draft_hash(original) == account_draft_hash(equivalent)
    assert account_draft_hash(original) != account_draft_hash(changed)

    evaluated_hash = account_draft_hash(original)
    first = confirmed_account_command_hash(
        draft=original,
        confirmed_at=datetime(2026, 7, 27, 12, 1, tzinfo=UTC),
        evaluated_draft_hash=evaluated_hash,
    )
    later = confirmed_account_command_hash(
        draft=original,
        confirmed_at=datetime(2026, 7, 27, 12, 2, tzinfo=UTC),
        evaluated_draft_hash=evaluated_hash,
    )
    assert first != later


def test_account_evaluation_uses_the_canonical_timezone_calendar() -> None:
    async def scenario() -> None:
        def clock() -> datetime:
            return datetime(2026, 7, 27, 22, 30, tzinfo=UTC)

        berlin = AccountCore(repository=_MemoryAccountRepository(), clock=clock)
        new_york = AccountCore(repository=_MemoryAccountRepository(), clock=clock)

        accepted = await berlin.evaluate(
            user_id=_USER_ID,
            draft=_draft(openingBalanceOn="2026-07-28"),
        )
        rejected = await new_york.evaluate(
            user_id=_USER_ID,
            draft=_draft(
                openingBalanceOn="2026-07-28",
                canonicalTimezone="America/New_York",
            ),
        )

        assert accepted.decision == "NEEDS_CONFIRMATION"
        assert [issue.code for issue in rejected.issues] == [
            "OPENING_BALANCE_DATE_IN_FUTURE"
        ]

    asyncio.run(scenario())


def test_a_second_account_is_a_wallet_rather_than_a_refusal() -> None:
    """A later account is a wallet in another currency (ADR 0029).

    It used to be `ACCOUNT_ALREADY_INITIALIZED`, and a non-euro currency used
    to be `UNSUPPORTED_CURRENCY`. Nothing is converted, so neither refusal is
    honest any more — but a wallet may not introduce a second reporting
    timezone, because months must not depend on which wallet is read.
    """

    async def scenario() -> None:
        repository = _MemoryAccountRepository()
        core = AccountCore(repository=repository, clock=lambda: _NOW)

        draft = _draft()
        evaluated = await core.evaluate(user_id=_USER_ID, draft=draft)
        await core.commit(
            user_id=_USER_ID,
            draft=draft,
            expected_draft_hash=str(evaluated.draft_hash),
            confirmed_at=datetime(2026, 7, 27, 12, 1, tzinfo=UTC),
        )

        wallet = await core.evaluate(
            user_id=_USER_ID,
            draft=_draft(
                commandId="55555555-5555-4555-8555-555555555555",
                currency="UAH",
            ),
        )
        assert wallet.issues == ()
        assert wallet.decision == "NEEDS_CONFIRMATION"

        elsewhere = await core.evaluate(
            user_id=_USER_ID,
            draft=_draft(
                commandId="66666666-6666-4666-8666-666666666666",
                currency="UAH",
                canonicalTimezone="Europe/Kyiv",
            ),
        )
        assert [issue.code for issue in elsewhere.issues] == [
            "PROFILE_TIMEZONE_MISMATCH"
        ]

    asyncio.run(scenario())


def test_account_exact_replay_precedes_clock_and_current_business_validation() -> None:
    async def scenario() -> None:
        repository = _MemoryAccountRepository()
        initial_core = AccountCore(repository=repository, clock=lambda: _NOW)
        original = _draft()
        confirmed_at = datetime(2026, 7, 27, 12, 1, tzinfo=UTC)
        evaluation = await initial_core.evaluate(user_id=_USER_ID, draft=original)
        accepted = await initial_core.commit(
            user_id=_USER_ID,
            draft=original,
            expected_draft_hash=str(evaluation.draft_hash),
            confirmed_at=confirmed_at,
        )
        assert accepted.idempotent_replay is False

        def unavailable_clock() -> datetime:
            raise AssertionError(
                "an exact replay or command conflict must not read clock"
            )

        replay_core = AccountCore(repository=repository, clock=unavailable_clock)
        replay = await replay_core.commit(
            user_id=_USER_ID,
            draft=original,
            expected_draft_hash=account_draft_hash(original),
            confirmed_at=confirmed_at,
        )
        assert replay.idempotent_replay is True
        assert replay.account == accepted.account

        changed_and_currently_invalid = _draft(
            currency="USD",
            openingBalanceOn="2026-07-28",
        )
        with pytest.raises(AccountCommandConflict):
            await replay_core.commit(
                user_id=_USER_ID,
                draft=changed_and_currently_invalid,
                expected_draft_hash=account_draft_hash(changed_and_currently_invalid),
                confirmed_at=confirmed_at,
            )

    asyncio.run(scenario())


def test_account_core_fails_closed_on_inconsistent_or_cross_user_reads() -> None:
    async def scenario() -> None:
        inconsistent = AccountCore(repository=_InconsistentAccountRepository())
        with pytest.raises(AccountPersistenceUnavailable):
            await inconsistent.evaluate(user_id=_USER_ID, draft=_draft())

        leaking = AccountCore(repository=_LeakingAccountRepository())
        with pytest.raises(AccountPersistenceUnavailable):
            await leaking.list_accounts(user_id=_USER_ID)

    asyncio.run(scenario())


def test_account_api_evaluate_commit_replay_and_list_are_stable() -> None:
    async def scenario() -> None:
        repository = _MemoryAccountRepository()
        core = AccountCore(repository=repository, clock=lambda: _NOW)
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            account_core=core,
        )
        headers = {
            "Authorization": "Bearer synthetic-token",
            "X-Request-ID": "account-contract-test",
        }
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            empty = await client.get("/api/v1/accounts", headers=headers)
            assert empty.status_code == 200
            assert empty.json() == {
                "schemaVersion": "1",
                "canonicalTimezone": None,
                "timezoneRevision": 0,
                "accounts": [],
            }
            _assert_private_response(empty)

            evaluation = await client.post(
                "/api/v1/accounts/evaluate",
                json={"draft": _draft().model_dump(mode="json", by_alias=True)},
                headers=headers,
            )
            assert evaluation.status_code == 200
            assert evaluation.json()["decision"] == "NEEDS_CONFIRMATION"
            _assert_private_response(evaluation)

            commit_body = {
                "schemaVersion": "1",
                "draft": _draft().model_dump(mode="json", by_alias=True),
                "draftHash": evaluation.json()["draftHash"],
                "confirmedAt": "2026-07-27T12:01:00Z",
            }
            mismatched_confirmation = await client.post(
                "/api/v1/accounts/commit",
                json={**commit_body, "draftHash": "0" * 64},
                headers=headers,
            )
            assert mismatched_confirmation.status_code == 409
            assert mismatched_confirmation.json() == {
                "detail": {"code": "CONFIRMATION_MISMATCH", "issues": []}
            }
            _assert_private_response(mismatched_confirmation)

            accepted = await client.post(
                "/api/v1/accounts/commit",
                json=commit_body,
                headers=headers,
            )
            replay = await client.post(
                "/api/v1/accounts/commit",
                json=commit_body,
                headers=headers,
            )
            assert accepted.status_code == 201
            assert replay.status_code == 200
            assert accepted.json()["idempotentReplay"] is False
            assert replay.json()["idempotentReplay"] is True
            assert accepted.json()["account"] == replay.json()["account"]
            assert accepted.json()["account"]["openingBalance"] == "1250.5"
            _assert_private_response(accepted)
            _assert_private_response(replay)

            listed = await client.get("/api/v1/accounts", headers=headers)
            assert listed.status_code == 200
            assert listed.json()["canonicalTimezone"] == "Europe/Berlin"
            assert listed.json()["timezoneRevision"] == 1
            assert len(listed.json()["accounts"]) == 1
            _assert_private_response(listed)

            changed_confirmation = await client.post(
                "/api/v1/accounts/commit",
                json={**commit_body, "confirmedAt": "2026-07-27T12:02:00Z"},
                headers=headers,
            )
            assert changed_confirmation.status_code == 409
            assert changed_confirmation.json() == {
                "detail": {"code": "COMMAND_CONFLICT", "issues": []}
            }
            _assert_private_response(changed_confirmation)

            second = _draft(commandId="55555555-5555-4555-8555-555555555555")
            second_commit = await client.post(
                "/api/v1/accounts/commit",
                json={
                    "schemaVersion": "1",
                    "draft": second.model_dump(mode="json", by_alias=True),
                    "draftHash": account_draft_hash(second),
                    "confirmedAt": "2026-07-27T12:03:00Z",
                },
                headers=headers,
            )
            assert second_commit.status_code == 409
            assert second_commit.json() == {
                "detail": {
                    "code": "ACCOUNT_ALREADY_INITIALIZED",
                    "issues": [],
                }
            }
            _assert_private_response(second_commit)

    asyncio.run(scenario())


def test_account_api_errors_are_no_store_and_redacted() -> None:
    async def scenario() -> None:
        marker = "sensitive-account-marker"
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            account_core=AccountCore(
                repository=_MemoryAccountRepository(),
                clock=lambda: _NOW,
            ),
        )
        headers = {"Authorization": "Bearer synthetic-token"}
        malformed = _draft().model_dump(mode="json", by_alias=True)
        malformed["name"] = marker
        malformed["openingBalance"] = -812.25

        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/accounts/evaluate",
                json={"draft": malformed},
                headers=headers,
            )
            assert response.status_code == 422
            assert response.json() == {
                "detail": {"code": "MALFORMED_ACCOUNT", "issues": []}
            }
            assert marker not in response.text
            assert "812.25" not in response.text
            _assert_private_response(response)

            unauthenticated = await client.get("/api/v1/accounts")
            assert unauthenticated.status_code == 401
            _assert_private_response(unauthenticated)

            ahead = _draft(openingBalanceOn="2030-01-01")
            rejected = await client.post(
                "/api/v1/accounts/commit",
                json={
                    "schemaVersion": "1",
                    "draft": ahead.model_dump(mode="json", by_alias=True),
                    "draftHash": account_draft_hash(ahead),
                    "confirmedAt": "2026-07-27T12:01:00Z",
                },
                headers=headers,
            )
            assert rejected.status_code == 422
            assert rejected.json() == {
                "detail": {
                    "code": "ACCOUNT_REJECTED",
                    "issues": [
                        {
                            "code": "OPENING_BALANCE_DATE_IN_FUTURE",
                            "field": "openingBalanceOn",
                        }
                    ],
                }
            }
            assert "1250" not in rejected.text
            _assert_private_response(rejected)

        unavailable_app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=unavailable_app),
            base_url="http://test",
        ) as client:
            unavailable = await client.get(
                "/api/v1/accounts",
                headers=headers,
            )
        assert unavailable.status_code == 503
        assert unavailable.json() == {
            "detail": {
                "code": "FINANCE_PERSISTENCE_UNAVAILABLE",
                "issues": [],
            }
        }
        _assert_private_response(unavailable)

    asyncio.run(scenario())


@pytest.mark.parametrize("timezone", ["localtime", "Factory", "posixrules"])
def test_home_api_rejects_unstable_tzdb_keys(timezone: str) -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/v1/home",
                params={"period": "current_month", "timezone": timezone},
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 422
        assert response.json() == {"detail": "Invalid IANA timezone"}

    asyncio.run(scenario())


def test_checked_in_account_contract_is_reproducible() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    checked_in = json.loads(
        (repository_root / "contracts/finance/v1/account.schema.json").read_text(
            encoding="utf-8"
        )
    )
    assert checked_in == account_contract_schema()


class _MemoryAccountRepository:
    def __init__(self) -> None:
        self._accounts: dict[UUID, CommittedFinanceAccount] = {}
        self._command_hashes: dict[tuple[UUID, UUID], bytes] = {}

    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        account = self._accounts.get(user_id)
        if account is None or account.account_id != account_id:
            return None
        return FinanceAccountSnapshot(
            account_id=account.account_id,
            user_id=account.user_id,
            currency=account.currency,
            opening_balance_on=account.opening_balance_on,
            status="active",
        )

    async def get_setup_snapshot(self, *, user_id: UUID) -> AccountSetupSnapshot:
        account = self._accounts.get(user_id)
        if account is None:
            return AccountSetupSnapshot(
                account_id=None,
                canonical_timezone=None,
                timezone_revision=0,
            )
        return AccountSetupSnapshot(
            account_id=account.account_id,
            canonical_timezone=account.opening_timezone,
            timezone_revision=1,
        )

    async def list_accounts(self, *, user_id: UUID) -> AccountListSnapshot:
        account = self._accounts.get(user_id)
        if account is None:
            return AccountListSnapshot(
                canonical_timezone=None,
                timezone_revision=0,
                accounts=(),
            )
        return AccountListSnapshot(
            canonical_timezone=account.opening_timezone,
            timezone_revision=1,
            accounts=(account,),
        )

    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> AccountWriteResult | None:
        command_key = (user_id, command_id)
        previous_hash = self._command_hashes.get(command_key)
        if previous_hash is None:
            return None
        if previous_hash != payload_hash:
            raise AccountCommandConflict
        account = self._accounts[user_id]
        return AccountWriteResult(
            account=account,
            canonical_timezone=account.opening_timezone,
            timezone_revision=1,
            idempotent_replay=True,
        )

    async def commit_account(
        self,
        *,
        user_id: UUID,
        draft: AccountDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> AccountWriteResult:
        command_key = (user_id, draft.command_id)
        previous_hash = self._command_hashes.get(command_key)
        if previous_hash is not None:
            if previous_hash != payload_hash:
                raise AccountCommandConflict
            account = self._accounts[user_id]
            return AccountWriteResult(
                account=account,
                canonical_timezone=account.opening_timezone,
                timezone_revision=1,
                idempotent_replay=True,
            )
        if user_id in self._accounts:
            raise AccountAlreadyInitialized

        account = CommittedFinanceAccount(
            accountId=_ACCOUNT_ID,
            userId=user_id,
            commandId=draft.command_id,
            name=draft.name,
            currency=draft.currency,
            openingBalance=draft.opening_balance,
            openingBalanceOn=draft.opening_balance_on,
            openingTimezone=draft.canonical_timezone,
            status="active",
            isDefault=True,
            confirmedAt=confirmed_at,
            createdAt=_NOW,
        )
        self._accounts[user_id] = account
        self._command_hashes[command_key] = payload_hash
        return AccountWriteResult(
            account=account,
            canonical_timezone=draft.canonical_timezone,
            timezone_revision=1,
            idempotent_replay=False,
        )


class _InconsistentAccountRepository(_MemoryAccountRepository):
    async def get_setup_snapshot(self, *, user_id: UUID) -> AccountSetupSnapshot:
        del user_id
        return AccountSetupSnapshot(
            account_id=None,
            canonical_timezone="Europe/Berlin",
            timezone_revision=1,
        )


class _LeakingAccountRepository(_MemoryAccountRepository):
    async def list_accounts(self, *, user_id: UUID) -> AccountListSnapshot:
        del user_id
        account = CommittedFinanceAccount(
            accountId=_ACCOUNT_ID,
            userId=_SECOND_USER_ID,
            commandId="44444444-4444-4444-8444-444444444444",
            name="Synthetic foreign account",
            currency="EUR",
            openingBalance="0",
            openingBalanceOn="2026-07-26",
            openingTimezone="Europe/Berlin",
            status="active",
            isDefault=True,
            confirmedAt="2026-07-27T12:01:00Z",
            createdAt="2026-07-27T12:01:00Z",
        )
        return AccountListSnapshot(
            canonical_timezone="Europe/Berlin",
            timezone_revision=1,
            accounts=(account,),
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
