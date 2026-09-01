"""Correcting where an account's months are drawn (ADR 0028).

Nothing here re-files history: an operation keeps the local date it was
captured with. What these tests hold is the shape of the change — both copies
of the timezone move together, and a correction that would hide a recorded
operation is refused rather than allowed to self-heal overnight.
"""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.account_contracts import (
    AccountErrorDetail,
    CorrectTimezoneCommand,
    TimezoneIssue,
    correct_timezone_command_hash,
)
from mobile_finance_api.account_core import (
    AccountCommandConflict,
    AccountCore,
    AccountPersistenceUnavailable,
    TimezoneRejected,
    TimezoneWriteResult,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_COMMAND_ID = UUID("33333333-3333-4333-8333-333333333333")


def _command(**changes: object) -> CorrectTimezoneCommand:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(_COMMAND_ID),
        "accountId": str(_ACCOUNT_ID),
        "canonicalTimezone": "Europe/Lisbon",
        "requestedAt": "2026-09-01T12:00:00Z",
    }
    payload.update(changes)
    return CorrectTimezoneCommand.model_validate(payload)


class _Repository:
    def __init__(
        self,
        *,
        raises: Exception | None = None,
        revision: int = 2,
        replay: bool = False,
    ) -> None:
        self._raises = raises
        self._revision = revision
        self._replay = replay
        self.written: list[CorrectTimezoneCommand] = []

    async def correct_timezone(
        self,
        *,
        user_id: UUID,
        command: CorrectTimezoneCommand,
        payload_hash: bytes,
    ) -> TimezoneWriteResult:
        del user_id
        if self._raises is not None:
            raise self._raises
        assert len(payload_hash) == 32
        self.written.append(command)
        return TimezoneWriteResult(
            account_id=command.account_id,
            canonical_timezone=command.canonical_timezone,
            timezone_revision=self._revision,
            idempotent_replay=self._replay,
        )

    def __getattr__(self, name: str) -> object:  # pragma: no cover - unused
        raise AttributeError(name)


def _core(repository: _Repository) -> AccountCore:
    return AccountCore(repository=repository)  # type: ignore[arg-type]


# --- the contract -------------------------------------------------------------


def test_an_unknown_key_is_refused_rather_than_ignored() -> None:
    with pytest.raises(ValidationError):
        _command(reFileHistory=True)


def test_an_unusable_timezone_is_refused() -> None:
    for unusable in ("", "  ", "Factory", "localtime", "posixrules", "Not/AZone"):
        with pytest.raises(ValidationError):
            _command(canonicalTimezone=unusable)


def test_the_command_hash_binds_the_zone_and_the_account() -> None:
    baseline = correct_timezone_command_hash(_command())

    assert correct_timezone_command_hash(_command(canonicalTimezone="UTC")) != baseline
    assert correct_timezone_command_hash(_command(accountId=str(uuid4()))) != baseline
    assert correct_timezone_command_hash(_command()) == baseline


def test_a_revision_below_one_is_not_a_settled_timezone() -> None:
    from mobile_finance_api.account_contracts import CorrectTimezoneResponse

    with pytest.raises(ValidationError):
        CorrectTimezoneResponse(
            idempotent_replay=False,
            account_id=_ACCOUNT_ID,
            canonical_timezone="Europe/Lisbon",
            timezone_revision=0,
        )


def test_an_error_without_timezone_issues_keeps_the_old_wire_shape() -> None:
    """Installed clients parse this strictly, so the new field must not appear
    on errors that never had one.

    Asserted on the response rather than the model: the route is where the
    empty list is dropped, and the route is what a phone reads.
    """

    async def scenario() -> None:
        core = _core(_Repository(raises=AccountPersistenceUnavailable()))
        response = await _post(_application(core), _body())

        assert "timezoneIssues" not in response.json()["detail"]

    asyncio.run(scenario())


def test_only_a_timezone_rejection_may_carry_timezone_issues() -> None:
    with pytest.raises(ValidationError):
        AccountErrorDetail(
            code="ACCOUNT_UNAVAILABLE",
            timezone_issues=(
                TimezoneIssue(code="TIMEZONE_UNCHANGED", field="canonicalTimezone"),
            ),
        )
    with pytest.raises(ValidationError):
        AccountErrorDetail(code="TIMEZONE_REJECTED")


# --- the core -----------------------------------------------------------------


def test_a_correction_reports_the_new_zone_and_revision() -> None:
    repository = _Repository()
    result = asyncio.run(
        _core(repository).correct_timezone(user_id=_USER_ID, command=_command())
    )

    assert result.canonical_timezone == "Europe/Lisbon"
    assert result.timezone_revision == 2
    assert repository.written == [_command()]


def test_a_replay_reports_itself_as_one() -> None:
    result = asyncio.run(
        _core(_Repository(replay=True)).correct_timezone(
            user_id=_USER_ID,
            command=_command(),
        )
    )

    assert result.idempotent_replay is True


def test_the_same_zone_is_refused() -> None:
    repository = _Repository(
        raises=TimezoneRejected(
            (TimezoneIssue(code="TIMEZONE_UNCHANGED", field="canonicalTimezone"),)
        )
    )
    with pytest.raises(TimezoneRejected) as rejection:
        asyncio.run(
            _core(repository).correct_timezone(user_id=_USER_ID, command=_command())
        )

    assert [issue.code for issue in rejection.value.issues] == ["TIMEZONE_UNCHANGED"]


def test_a_zone_that_would_hide_an_operation_is_refused() -> None:
    """A future-dated operation is excluded from the balance until the day
    catches up, so the correction is refused rather than letting a confirmed
    amount vanish for hours."""

    repository = _Repository(
        raises=TimezoneRejected(
            (
                TimezoneIssue(
                    code="TIMEZONE_BEHIND_RECORDED_OPERATIONS",
                    field="canonicalTimezone",
                ),
            )
        )
    )
    with pytest.raises(TimezoneRejected) as rejection:
        asyncio.run(
            _core(repository).correct_timezone(user_id=_USER_ID, command=_command())
        )

    assert [issue.code for issue in rejection.value.issues] == [
        "TIMEZONE_BEHIND_RECORDED_OPERATIONS"
    ]


# --- over HTTP ----------------------------------------------------------------


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


async def _post(app: object, body: dict[str, object], *, authenticated: bool = True):  # type: ignore[no-untyped-def]
    headers = {"Authorization": "Bearer synthetic"} if authenticated else {}
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        return await client.post(
            "/api/v1/accounts/timezone", json=body, headers=headers
        )


def _body(**changes: object) -> dict[str, object]:
    return _command(**changes).model_dump(mode="json", by_alias=True)


def _application(core: AccountCore | None = None):  # type: ignore[no-untyped-def]
    return create_app(
        account_core=core,
        current_user_authenticator=_StaticAuthenticator(),
    )


def test_a_correction_answers_200() -> None:
    async def scenario() -> None:
        response = await _post(_application(_core(_Repository())), _body())

        assert response.status_code == 200
        payload = response.json()
        assert payload["canonicalTimezone"] == "Europe/Lisbon"
        assert payload["timezoneRevision"] == 2

    asyncio.run(scenario())


def test_a_rejection_is_typed_and_names_the_field() -> None:
    async def scenario() -> None:
        core = _core(
            _Repository(
                raises=TimezoneRejected(
                    (
                        TimezoneIssue(
                            code="TIMEZONE_UNCHANGED",
                            field="canonicalTimezone",
                        ),
                    )
                )
            )
        )
        response = await _post(_application(core), _body())

        assert response.status_code == 422
        detail = response.json()["detail"]
        assert detail["code"] == "TIMEZONE_REJECTED"
        assert detail["timezoneIssues"] == [
            {"code": "TIMEZONE_UNCHANGED", "field": "canonicalTimezone"}
        ]

    asyncio.run(scenario())


def test_a_reused_command_with_other_content_is_a_conflict() -> None:
    async def scenario() -> None:
        core = _core(_Repository(raises=AccountCommandConflict()))
        response = await _post(_application(core), _body())

        assert response.status_code == 409

    asyncio.run(scenario())


def test_persistence_failure_is_redacted() -> None:
    async def scenario() -> None:
        core = _core(_Repository(raises=AccountPersistenceUnavailable()))
        response = await _post(_application(core), _body())

        assert response.status_code == 503

    asyncio.run(scenario())


def test_an_anonymous_caller_is_refused() -> None:
    async def scenario() -> None:
        response = await _post(create_app(), _body(), authenticated=False)

        assert response.status_code == 401

    asyncio.run(scenario())
