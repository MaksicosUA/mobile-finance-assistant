from __future__ import annotations

import asyncio
import json
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import TypeAdapter, ValidationError

from mobile_finance_api.account_core import (
    FinanceAccountSnapshot,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.finance_core import (
    ConfirmationMismatch,
    FinanceCore,
    OperationAccountUnavailable,
    OperationCommandConflict,
    OperationRejected,
    OperationWriteResult,
    confirmed_command_hash,
    draft_hash,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.operation_contracts import (
    MAX_ENTRY_AMOUNT,
    CommittedOperation,
    MoneyInput,
    OperationDraft,
    operation_contract_schema,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_OTHER_USER_ID = UUID("22222222-2222-4222-8222-222222222222")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")


def _draft(**changes: object) -> OperationDraft:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "44444444-4444-4444-8444-444444444444",
        "type": "expense",
        "amount": "35.00",
        "currency": "EUR",
        "accountId": str(_ACCOUNT_ID),
        "category": "Продукты",
        "merchant": "Lidl",
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


def _account(
    *,
    account_id: UUID = _ACCOUNT_ID,
    user_id: UUID = _USER_ID,
    currency: str = "EUR",
    opening_balance_on: date = date(1900, 1, 1),
) -> FinanceAccountSnapshot:
    return FinanceAccountSnapshot(
        account_id=account_id,
        user_id=user_id,
        currency=currency,
        opening_balance_on=opening_balance_on,
        status="active",
    )


def _evaluate(
    draft: OperationDraft,
    *,
    account: FinanceAccountSnapshot | None = None,
    user_id: UUID = _USER_ID,
) -> object:
    async def scenario() -> object:
        core = FinanceCore(
            repository=_NoWriteRepository(),
            account_directory=_StaticAccountDirectory(account or _account()),
        )
        return await core.evaluate(user_id=user_id, draft=draft)

    return asyncio.run(scenario())


@pytest.mark.parametrize(
    "amount",
    [0, 35.0, "0", "0.0", "-1", "1e2", "NaN", "Infinity"],
)
def test_money_requires_a_positive_plain_decimal_string(amount: object) -> None:
    with pytest.raises(ValidationError):
        _draft(amount=amount)


def test_money_precision_matches_numeric_38_18() -> None:
    assert _draft(amount="1.123456789012345678").amount
    with pytest.raises(ValidationError):
        _draft(amount="1.1234567890123456789")


def test_an_entry_stops_well_short_of_what_a_balance_can_hold() -> None:
    """A balance is a sum: entries at the column's limit overflow on the second."""

    assert _draft(amount="999999999999999.99").amount
    with pytest.raises(ValidationError):
        _draft(amount="1000000000000000")
    with pytest.raises(ValidationError):
        _draft(amount="99999999999999999999.123456789012345678")


def test_a_stored_amount_is_still_read_whatever_the_column_holds() -> None:
    """The limit is on what is entered. An existing row must never stop loading."""

    stored = TypeAdapter(MoneyInput).validate_python(
        Decimal("99999999999999999999.123456789012345678")
    )

    assert stored > MAX_ENTRY_AMOUNT


def test_contract_rejects_mass_assignment_and_naive_time() -> None:
    with pytest.raises(ValidationError):
        _draft(userId=str(uuid4()))
    with pytest.raises(ValidationError):
        _draft(capturedAt="2026-07-27T18:00:00")


@pytest.mark.parametrize("timezone", ["localtime", "Factory", "posixrules"])
def test_operation_contract_rejects_unstable_tzdb_keys(timezone: str) -> None:
    with pytest.raises(ValidationError):
        _draft(capturedTimezone=timezone)


def test_omitted_account_id_remains_parseable_but_new_command_is_rejected() -> None:
    payload = _draft().model_dump(mode="json", by_alias=True)
    payload.pop("accountId")
    legacy_compatible = OperationDraft.model_validate(payload)

    assert legacy_compatible.account_id is None
    result = _evaluate(legacy_compatible)
    assert result.decision == "REJECT"
    assert [issue.code for issue in result.issues] == ["ACCOUNT_REQUIRED"]


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("capturedAt", "0001-01-01T00:00:00Z"),
        ("capturedAt", "9999-12-31T23:59:59Z"),
        ("occurredOn", "1899-12-31"),
        ("occurredOn", "2101-01-01"),
    ],
)
def test_operation_dates_are_bounded_before_timezone_arithmetic(
    field: str,
    value: str,
) -> None:
    with pytest.raises(ValidationError):
        _draft(**{field: value})


def test_text_is_trimmed_nfc_normalized_and_control_chars_are_rejected() -> None:
    draft = _draft(merchant="  Cafe\u0301  ")
    assert draft.merchant == "Café"
    with pytest.raises(ValidationError):
        _draft(merchant="unsafe\nmerchant")


def test_relative_yesterday_uses_captured_iana_local_date() -> None:
    draft = _draft(
        capturedAt="2026-07-27T22:30:00Z",
        occurredOn="2026-07-27",
    )
    result = _evaluate(draft)
    assert result.decision == "NEEDS_CONFIRMATION"
    assert result.issues == ()


@pytest.mark.parametrize(
    ("captured_at", "occurred_on"),
    [
        ("2026-03-29T01:30:00Z", "2026-03-28"),
        ("2026-10-25T01:30:00Z", "2026-10-24"),
        ("2026-01-01T12:00:00Z", "2025-12-31"),
        ("2024-03-01T12:00:00Z", "2024-02-29"),
    ],
)
def test_relative_yesterday_is_calendar_based_across_boundaries(
    captured_at: str,
    occurred_on: str,
) -> None:
    result = _evaluate(_draft(capturedAt=captured_at, occurredOn=occurred_on))
    assert result.decision == "NEEDS_CONFIRMATION"


def test_relative_date_uses_capture_timezone_not_account_profile_timezone() -> None:
    # At this instant it is July 26 in New York and July 27 in Berlin. The
    # account snapshot intentionally contains no timezone: ADR 0007 keeps the
    # immutable capture timezone authoritative for the relative expression.
    draft = _draft(
        capturedAt="2026-07-27T02:00:00Z",
        capturedTimezone="America/New_York",
        occurredOn="2026-07-25",
    )
    result = _evaluate(draft)
    assert result.decision == "NEEDS_CONFIRMATION"


def test_unknown_relative_expression_and_wrong_date_fail_closed() -> None:
    unsupported = _evaluate(_draft(sourceExpression="позавчера"))
    mismatch = _evaluate(_draft(occurredOn="2026-07-25"))

    assert unsupported.decision == "REJECT"
    assert [issue.code for issue in unsupported.issues] == [
        "UNSUPPORTED_DATE_EXPRESSION"
    ]
    assert mismatch.decision == "REJECT"
    assert [issue.code for issue in mismatch.issues] == ["RELATIVE_DATE_MISMATCH"]


def test_account_is_required_and_foreign_accounts_are_indistinguishable() -> None:
    required = _evaluate(_draft(accountId=None))
    foreign = _evaluate(
        _draft(accountId="55555555-5555-4555-8555-555555555555"),
        account=_account(),
    )

    assert [issue.code for issue in required.issues] == ["ACCOUNT_REQUIRED"]
    assert [issue.code for issue in foreign.issues] == ["ACCOUNT_UNAVAILABLE"]


def test_money_is_recorded_in_the_currency_its_own_wallet_holds() -> None:
    """A wallet holds one currency, and only that one (ADR 0029).

    The wallet is the authority, not a base currency: an expense in a hryvnia
    wallet is ordinary, and the same expense against a euro wallet is refused
    for the mismatch alone. Before ADR 0029 both were refused as unsupported,
    which made every wallet but the default one impossible to spend from.
    """

    foreign_wallet = _evaluate(
        _draft(currency="UAH"),
        account=_account(currency="UAH"),
    )
    assert foreign_wallet.decision == "NEEDS_CONFIRMATION"
    assert foreign_wallet.issues == ()

    mismatch = _evaluate(_draft(currency="USD"), account=_account(currency="EUR"))
    assert [issue.code for issue in mismatch.issues] == ["ACCOUNT_CURRENCY_MISMATCH"]

    # The ISO-4217 shape is a contract rule, so a malformed code never reaches
    # Finance Core at all.
    with pytest.raises(ValidationError):
        _draft(currency="eur")


def test_operation_cannot_precede_the_immutable_account_baseline() -> None:
    result = _evaluate(
        _draft(),
        account=_account(opening_balance_on=date(2026, 7, 27)),
    )
    assert [issue.code for issue in result.issues] == [
        "OPERATION_BEFORE_ACCOUNT_BASELINE"
    ]


def test_future_date_still_fails_with_a_valid_owned_account() -> None:
    result = _evaluate(
        _draft(sourceExpression=None, occurredOn="2026-07-28"),
    )
    assert [issue.code for issue in result.issues] == ["FUTURE_OCCURRED_DATE"]


def test_occurred_at_must_resolve_to_occurred_on_in_captured_timezone() -> None:
    result = _evaluate(_draft(occurredAt="2026-07-27T22:30:00Z"))
    assert result.decision == "REJECT"
    assert [issue.code for issue in result.issues] == ["OCCURRED_AT_DATE_MISMATCH"]


def test_draft_hash_is_canonical_and_changes_with_confirmed_content() -> None:
    original = _draft(merchant="Cafe\u0301")
    canonically_equal = _draft(merchant="Café")
    equivalent_scale = _draft(amount="35.0", merchant="Café")
    changed = _draft(amount="35.01")
    assert draft_hash(original) == draft_hash(canonically_equal)
    assert draft_hash(original) == draft_hash(equivalent_scale)
    assert draft_hash(original) != draft_hash(changed)


def test_confirmed_command_hash_binds_confirmation_timestamp() -> None:
    draft = _draft()
    evaluated_hash = draft_hash(draft)
    first = confirmed_command_hash(
        draft=draft,
        confirmed_at=datetime(2026, 7, 27, 18, 1, tzinfo=UTC),
        evaluated_draft_hash=evaluated_hash,
    )
    changed = confirmed_command_hash(
        draft=draft,
        confirmed_at=datetime(2026, 7, 27, 18, 2, tzinfo=UTC),
        evaluated_draft_hash=evaluated_hash,
    )
    assert first != changed


def test_commit_revalidates_hash_and_confirmation_order() -> None:
    async def scenario() -> None:
        core = FinanceCore(
            repository=_NoWriteRepository(),
            account_directory=_NeverCalledAccountDirectory(),
        )
        draft = _draft()
        with pytest.raises(ConfirmationMismatch):
            await core.commit(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash="0" * 64,
                confirmed_at=datetime(2026, 7, 27, 18, 1, tzinfo=UTC),
            )
        with pytest.raises(OperationRejected) as rejection:
            await core.commit(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash=draft_hash(draft),
                confirmed_at=datetime(2026, 7, 27, 17, 59, tzinfo=UTC),
            )
        assert [issue.code for issue in rejection.value.issues] == [
            "CONFIRMATION_BEFORE_CAPTURE"
        ]

    asyncio.run(scenario())


def test_occupied_command_conflict_precedes_confirmation_order_validation() -> None:
    async def scenario() -> None:
        draft = _draft()
        accepted_at = datetime(2026, 7, 27, 18, 1, tzinfo=UTC)
        stored_hash = bytes.fromhex(
            confirmed_command_hash(
                draft=draft,
                confirmed_at=accepted_at,
                evaluated_draft_hash=draft_hash(draft),
            )
        )
        repository = _ExactReplayRepository(
            expected_hash=stored_hash,
            result=OperationWriteResult(
                operation=_committed(
                    user_id=_USER_ID,
                    draft=draft,
                    created_at=accepted_at,
                ),
                idempotent_replay=True,
            ),
        )
        core = FinanceCore(
            repository=repository,
            account_directory=_NeverCalledAccountDirectory(),
        )

        # The draft hash is self-consistent, but confirmedAt changes the full
        # command hash and also predates capture. An occupied command identity
        # must conflict before current confirmation-order validation.
        with pytest.raises(OperationCommandConflict):
            await core.commit(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash=draft_hash(draft),
                confirmed_at=datetime(2026, 7, 27, 17, 59, tzinfo=UTC),
            )

    asyncio.run(scenario())


def test_commit_rechecks_account_inside_the_write_transaction() -> None:
    async def scenario() -> None:
        core = FinanceCore(
            repository=_AccountDisappearsRepository(),
            account_directory=_StaticAccountDirectory(_account()),
        )
        draft = _draft()
        with pytest.raises(OperationRejected) as rejection:
            await core.commit(
                user_id=_USER_ID,
                draft=draft,
                expected_draft_hash=draft_hash(draft),
                confirmed_at=datetime(2026, 7, 27, 18, 1, tzinfo=UTC),
            )
        assert [issue.code for issue in rejection.value.issues] == [
            "ACCOUNT_UNAVAILABLE"
        ]

    asyncio.run(scenario())


def test_legacy_exact_replay_precedes_new_account_validation() -> None:
    async def scenario() -> None:
        legacy_wire = _draft().model_dump(mode="json", by_alias=True)
        legacy_wire.pop("accountId")
        legacy = OperationDraft.model_validate(legacy_wire)
        assert legacy.account_id is None
        assert legacy.model_dump(mode="json", by_alias=True)["accountId"] is None
        confirmed_at = datetime(2026, 7, 27, 18, 1, tzinfo=UTC)
        expected_hash = bytes.fromhex(
            confirmed_command_hash(
                draft=legacy,
                confirmed_at=confirmed_at,
                evaluated_draft_hash=draft_hash(legacy),
            )
        )
        operation = _committed(
            user_id=_USER_ID,
            draft=legacy,
            created_at=confirmed_at,
        )
        repository = _ExactReplayRepository(
            expected_hash=expected_hash,
            result=OperationWriteResult(
                operation=operation,
                idempotent_replay=True,
            ),
        )
        core = FinanceCore(
            repository=repository,
            account_directory=_NeverCalledAccountDirectory(),
        )

        replay = await core.commit(
            user_id=_USER_ID,
            draft=legacy,
            expected_draft_hash=draft_hash(legacy),
            confirmed_at=confirmed_at,
        )
        assert replay.idempotent_replay is True
        assert replay.operation.account_id is None

        with pytest.raises(OperationCommandConflict):
            await core.commit(
                user_id=_USER_ID,
                draft=legacy,
                expected_draft_hash=draft_hash(legacy),
                confirmed_at=datetime(2026, 7, 27, 18, 2, tzinfo=UTC),
            )

    asyncio.run(scenario())


def test_operation_api_uses_authenticated_user_for_account_lookup() -> None:
    async def scenario() -> None:
        directory = _StaticAccountDirectory(_account())
        core = FinanceCore(
            repository=_NoWriteRepository(),
            account_directory=directory,
        )
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            finance_core=core,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": _draft().model_dump(mode="json", by_alias=True)},
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 200
        assert response.json()["decision"] == "NEEDS_CONFIRMATION"
        assert directory.calls == [(_USER_ID, _ACCOUNT_ID)]
        assert response.headers["cache-control"] == "no-store"

    asyncio.run(scenario())


def test_commit_unavailable_error_is_stable_and_redacted() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        draft = _draft()
        body = {
            "schemaVersion": "1",
            "draft": draft.model_dump(mode="json", by_alias=True),
            "draftHash": draft_hash(draft),
            "confirmedAt": "2026-07-27T18:01:00Z",
        }
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/operations/commit",
                json=body,
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 503
        assert response.headers["cache-control"] == "no-store"
        assert response.json() == {
            "detail": {
                "code": "FINANCE_PERSISTENCE_UNAVAILABLE",
                "issues": [],
            }
        }
        assert "Lidl" not in response.text
        assert "35" not in response.text

    asyncio.run(scenario())


def test_operation_auth_unavailable_error_matches_public_contract() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_FailingAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": _draft().model_dump(mode="json", by_alias=True)},
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 503
        assert response.headers["cache-control"] == "no-store"
        assert response.json() == {
            "detail": {"code": "AUTHENTICATION_UNAVAILABLE", "issues": []}
        }

    asyncio.run(scenario())


def test_checked_in_operation_contract_is_reproducible() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    checked_in = json.loads(
        (repository_root / "contracts/finance/v1/operation.schema.json").read_text(
            encoding="utf-8"
        )
    )
    assert checked_in == operation_contract_schema()


class _StaticAccountDirectory:
    def __init__(self, account: FinanceAccountSnapshot | None) -> None:
        self._account = account
        self.calls: list[tuple[UUID, UUID]] = []

    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        self.calls.append((user_id, account_id))
        account = self._account
        if (
            account is None
            or account.account_id != account_id
            or account.user_id != user_id
        ):
            return None
        return account


class _NeverCalledAccountDirectory:
    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        del user_id, account_id
        raise AssertionError("account directory must not be called")


class _NoWriteRepository:
    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationWriteResult | None:
        del user_id, command_id, payload_hash
        return None

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise AssertionError("repository commit must not be called")


class _NeverCalledRepository(_NoWriteRepository):
    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationWriteResult | None:
        del user_id, command_id, payload_hash
        raise AssertionError("repository must not be called")


class _AccountDisappearsRepository(_NoWriteRepository):
    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise OperationAccountUnavailable


class _ExactReplayRepository:
    def __init__(
        self,
        *,
        expected_hash: bytes,
        result: OperationWriteResult,
    ) -> None:
        self._expected_hash = expected_hash
        self._result = result

    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationWriteResult | None:
        assert user_id == _USER_ID
        assert command_id == self._result.operation.command_id
        if payload_hash != self._expected_hash:
            raise OperationCommandConflict
        return self._result

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise AssertionError("exact replay must not create a second operation")


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(
            subject=str(_USER_ID),
            display_name="Synthetic User",
        )


class _FailingAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        raise RuntimeError("synthetic authentication failure")


def _committed(
    *,
    user_id: UUID,
    draft: OperationDraft,
    created_at: datetime,
) -> CommittedOperation:
    return CommittedOperation(
        operationId=uuid4(),
        userId=user_id,
        commandId=draft.command_id,
        type=draft.operation_type,
        amount=draft.amount,
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
        confirmedAt=created_at,
        createdAt=created_at,
    )
