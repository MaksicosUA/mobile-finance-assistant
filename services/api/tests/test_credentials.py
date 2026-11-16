"""A password changed, and a forgotten one replaced with a recovery code (ADR 0035).

What only a real database can prove (the lock, the sessions, the digest column)
is in `credentials_postgres_e2e.py`. Here: the code itself, and what the routes
say and refuse to say.
"""

from __future__ import annotations

import asyncio
import re
from datetime import UTC, datetime
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient, Response

from mobile_finance_api.account_data import WITHHELD_COLUMNS
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.credentials import (
    CredentialsUnavailable,
    CurrentPasswordRejected,
    IssuedRecoveryCode,
    NewPasswordRejected,
    RecoveryRejected,
)
from mobile_finance_api.db_models import Base
from mobile_finance_api.main import create_app
from mobile_finance_api.recovery_codes import (
    DIGEST_BYTES,
    InvalidRecoveryCode,
    hash_recovery_code,
    new_recovery_code,
    same_digest,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_SESSION_ID = UUID("22222222-2222-4222-8222-222222222222")
_AUTH = {"Authorization": "Bearer synthetic-token"}
_PASSWORD = "synthetic-password-123"
_NEW_PASSWORD = "synthetic-password-456"
_ADDRESS = "synthetic@example.com"
_ISSUED_AT = datetime(2026, 11, 16, 9, 30, tzinfo=UTC)
_CODE = "ABCDE-FGHJK-MNPQR-STVWX"
_NEXT_CODE = "01234-56789-ABCDE-FGHJK"
_SHAPE = re.compile(r"^[0-9A-HJKMNP-TV-Z]{5}(-[0-9A-HJKMNP-TV-Z]{5}){3}$")


# --- the code ----------------------------------------------------------------


def test_a_code_is_four_groups_from_an_alphabet_nothing_is_misread_in() -> None:
    for _ in range(200):
        code = new_recovery_code()
        assert _SHAPE.fullmatch(code.value), code.value
        assert len(code.digest) == DIGEST_BYTES
        assert hash_recovery_code(code.value) == code.digest


def test_no_two_codes_are_the_same() -> None:
    assert len({new_recovery_code().value for _ in range(500)}) == 500


@pytest.mark.parametrize(
    "typed",
    [
        "abcde-fghjk-mnpqr-stvwx",
        "ABCDEFGHJKMNPQRSTVWX",
        "ABCDE FGHJK MNPQR STVWX",
        "  ABCDE-FGHJK-MNPQR-STVWX\t",
        "ABCDE\u2013FGHJK\u2014MNPQR\u2212STVWX",  # an en dash, an em dash, a minus
        "abcde fghjk-mnpqrstvwx",
    ],
)
def test_a_code_reads_the_same_however_it_was_typed(typed: str) -> None:
    assert hash_recovery_code(typed) == hash_recovery_code(_CODE)


def test_a_letter_the_alphabet_leaves_out_is_read_as_the_digit_it_looks_like() -> None:
    assert hash_recovery_code("OIL00-00000-00000-00000") == hash_recovery_code(
        "01100-00000-00000-00000"
    )
    assert hash_recovery_code("oil00-00000-00000-00000") == hash_recovery_code(
        "01100-00000-00000-00000"
    )


@pytest.mark.parametrize(
    "text",
    [
        "",
        "ABCDE-FGHJK-MNPQR-STVW",
        "ABCDE-FGHJK-MNPQR-STVWX-0",
        "ABCDE-FGHJK-MNPQR-STVWU",
        "ABCDE-FGHJK-MNPQR-STVW!",
        "\u0410\u0412\u0421DE-FGHJK-MNPQR-STVWX",  # Cyrillic А, В, С are not the code
        "A" * 65,
    ],
)
def test_text_that_is_not_a_code_is_refused_before_anything_is_compared(
    text: str,
) -> None:
    with pytest.raises(InvalidRecoveryCode):
        hash_recovery_code(text)


def test_one_wrong_character_is_a_different_code() -> None:
    assert hash_recovery_code("ABCDE-FGHJK-MNPQR-STVWY") != hash_recovery_code(_CODE)


def test_an_account_with_no_code_matches_nothing() -> None:
    digest = hash_recovery_code(_CODE)

    assert same_digest(digest, digest)
    assert not same_digest(None, digest)
    assert not same_digest(digest, None)
    # Neither side present is compared against the same filler, and must still
    # be a refusal: this is the case of an unknown address and garbled text.
    assert not same_digest(None, None)
    assert not same_digest(None, bytes(DIGEST_BYTES))


def test_the_digest_of_the_code_never_leaves_in_an_export() -> None:
    users = Base.metadata.tables["users"]

    assert "recovery_code_hash" in users.c
    assert "recovery_code_hash" in WITHHELD_COLUMNS["users"]


# --- the routes ----------------------------------------------------------------


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(
            subject=str(_USER_ID),
            display_name="Synthetic",
            session_id=_SESSION_ID,
        )


class _FakeCredentials:
    def __init__(
        self,
        *,
        created_at: datetime | None = None,
        error: Exception | None = None,
    ) -> None:
        self.created_at = created_at
        self.error = error
        self.calls: list[tuple[object, ...]] = []

    async def recovery_code_created_at(self, *, user_id: UUID) -> datetime | None:
        self.calls.append(("status", user_id))
        if self.error is not None:
            raise self.error
        return self.created_at

    async def issue_recovery_code(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> IssuedRecoveryCode:
        del now
        self.calls.append(("issue", user_id, password))
        if self.error is not None:
            raise self.error
        return IssuedRecoveryCode(value=_CODE, created_at=_ISSUED_AT)

    async def change_password(
        self,
        *,
        user_id: UUID,
        session_id: UUID | None,
        current_password: str,
        new_password: str,
        now: datetime,
    ) -> None:
        del now
        self.calls.append(
            ("change", user_id, session_id, current_password, new_password)
        )
        if self.error is not None:
            raise self.error

    async def reset_password(
        self,
        *,
        email: str,
        recovery_code: str,
        new_password: str,
        now: datetime,
    ) -> IssuedRecoveryCode:
        del now
        self.calls.append(("reset", email, recovery_code, new_password))
        if self.error is not None:
            raise self.error
        return IssuedRecoveryCode(value=_NEXT_CODE, created_at=_ISSUED_AT)


Step = tuple[str, str, object | None, bool]


def _run(store: _FakeCredentials, steps: list[Step]) -> list[Response]:
    """Send every step to one application, so its counters carry across them."""

    async def scenario() -> list[Response]:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            credential_repository=store,
        )
        responses = []
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            for method, path, body, authenticated in steps:
                responses.append(
                    await client.request(
                        method,
                        path,
                        json=body,
                        headers=_AUTH if authenticated else {},
                    )
                )
        return responses

    return asyncio.run(scenario())


def _one(
    store: _FakeCredentials,
    method: str,
    path: str,
    body: object | None = None,
    *,
    authenticated: bool = True,
) -> Response:
    return _run(store, [(method, path, body, authenticated)])[0]


_STATUS = "/api/v1/auth/recovery-code"
_CHANGE = "/api/v1/auth/password/change"
_RESET = "/api/v1/auth/password/reset"
_ISSUE_BODY = {"schemaVersion": "1", "password": _PASSWORD}
_CHANGE_BODY = {
    "schemaVersion": "1",
    "currentPassword": _PASSWORD,
    "newPassword": _NEW_PASSWORD,
}
_RESET_BODY = {
    "schemaVersion": "1",
    "email": _ADDRESS,
    "recoveryCode": _CODE,
    "newPassword": _NEW_PASSWORD,
}


def test_the_status_says_whether_there_is_a_code_and_never_what_it_is() -> None:
    store = _FakeCredentials(created_at=_ISSUED_AT)
    response = _one(store, "GET", _STATUS)

    assert response.status_code == 200, response.text
    assert response.json() == {
        "schemaVersion": "1",
        "exists": True,
        "createdAt": "2026-11-16T09:30:00Z",
    }
    assert store.calls == [("status", _USER_ID)]
    assert response.headers["cache-control"] == "no-store"


def test_an_account_that_never_asked_has_no_code() -> None:
    response = _one(_FakeCredentials(), "GET", _STATUS)

    assert response.json() == {"schemaVersion": "1", "exists": False, "createdAt": None}


def test_a_code_is_issued_once_to_the_caller_who_knows_the_password() -> None:
    store = _FakeCredentials()
    response = _one(store, "POST", _STATUS, _ISSUE_BODY)

    assert response.status_code == 201, response.text
    assert response.json() == {
        "schemaVersion": "1",
        "recoveryCode": _CODE,
        "createdAt": "2026-11-16T09:30:00Z",
    }
    assert store.calls == [("issue", _USER_ID, _PASSWORD)]
    assert response.headers["cache-control"] == "no-store"


def test_a_wrong_password_is_forbidden_never_unauthorized() -> None:
    """A 401 would tell the app its session expired and sign the person out."""

    for path, body in ((_STATUS, _ISSUE_BODY), (_CHANGE, _CHANGE_BODY)):
        response = _one(
            _FakeCredentials(error=CurrentPasswordRejected()), "POST", path, body
        )
        assert response.status_code == 403, path
        assert response.json() == {"detail": {"code": "PASSWORD_REJECTED"}}


def test_a_stolen_session_cannot_keep_guessing_the_password() -> None:
    store = _FakeCredentials(error=CurrentPasswordRejected())
    # One count for both routes: they guard the same secret.
    steps: list[Step] = [("POST", _STATUS, _ISSUE_BODY, True)] * 3
    steps += [("POST", _CHANGE, _CHANGE_BODY, True)] * 3
    responses = _run(store, steps)

    assert [response.status_code for response in responses] == [403] * 5 + [429]
    assert int(responses[-1].headers["retry-after"]) > 0
    assert len(store.calls) == 5


def test_changing_the_password_keeps_the_session_that_asked() -> None:
    store = _FakeCredentials()
    response = _one(store, "POST", _CHANGE, _CHANGE_BODY)

    assert response.status_code == 204, response.text
    assert response.content == b""
    assert store.calls == [("change", _USER_ID, _SESSION_ID, _PASSWORD, _NEW_PASSWORD)]


def test_a_new_password_the_server_would_not_accept_is_said_to_be_that() -> None:
    for path, body in ((_CHANGE, _CHANGE_BODY), (_RESET, _RESET_BODY)):
        response = _one(
            _FakeCredentials(error=NewPasswordRejected()),
            "POST",
            path,
            body,
            authenticated=path == _CHANGE,
        )
        assert response.status_code == 400, path
        assert response.json() == {"detail": {"code": "NEW_PASSWORD_REJECTED"}}


def test_nothing_about_a_credential_is_reachable_without_signing_in() -> None:
    store = _FakeCredentials()
    responses = _run(
        store,
        [
            ("GET", _STATUS, None, False),
            ("POST", _STATUS, _ISSUE_BODY, False),
            ("POST", _CHANGE, _CHANGE_BODY, False),
        ],
    )

    assert [response.status_code for response in responses] == [401, 401, 401]
    assert store.calls == []


def test_a_forgotten_password_is_replaced_without_a_session() -> None:
    store = _FakeCredentials()
    response = _one(store, "POST", _RESET, _RESET_BODY, authenticated=False)

    assert response.status_code == 200, response.text
    # The code that was used is spent; the answer is the one to keep next.
    assert response.json() == {
        "schemaVersion": "1",
        "recoveryCode": _NEXT_CODE,
        "createdAt": "2026-11-16T09:30:00Z",
    }
    assert store.calls == [("reset", _ADDRESS, _CODE, _NEW_PASSWORD)]
    assert response.headers["cache-control"] == "no-store"
    # No session is opened by a reset: signing in is the ordinary sign-in.
    assert "accessToken" not in response.text


def test_a_refused_reset_does_not_say_what_was_wrong() -> None:
    response = _one(
        _FakeCredentials(error=RecoveryRejected()),
        "POST",
        _RESET,
        _RESET_BODY,
        authenticated=False,
    )

    assert response.status_code == 403
    assert response.json() == {"detail": {"code": "RECOVERY_REJECTED"}}
    assert _ADDRESS not in response.text
    assert _CODE not in response.text


def test_one_address_cannot_be_tried_without_end() -> None:
    store = _FakeCredentials(error=RecoveryRejected())
    responses = _run(store, [("POST", _RESET, _RESET_BODY, False)] * 12)

    assert [response.status_code for response in responses] == [403] * 10 + [429] * 2
    assert int(responses[-1].headers["retry-after"]) > 0
    # Refused before the store is asked: the limit is not a second oracle.
    assert len(store.calls) == 10


def test_the_limit_counts_an_address_however_it_is_spelled() -> None:
    store = _FakeCredentials(error=RecoveryRejected())
    spelled = dict(_RESET_BODY, email="  Synthetic@Example.COM ")
    responses = _run(
        store,
        [("POST", _RESET, _RESET_BODY, False)] * 10
        + [("POST", _RESET, spelled, False)],
    )

    assert responses[-1].status_code == 429


def test_another_address_is_not_held_back_by_the_first() -> None:
    store = _FakeCredentials(error=RecoveryRejected())
    other = dict(_RESET_BODY, email="another@example.com")
    responses = _run(
        store,
        [("POST", _RESET, _RESET_BODY, False)] * 11 + [("POST", _RESET, other, False)],
    )

    assert responses[-2].status_code == 429
    assert responses[-1].status_code == 403


def test_one_origin_cannot_walk_through_every_address() -> None:
    store = _FakeCredentials(error=RecoveryRejected())
    steps: list[Step] = [
        ("POST", _RESET, dict(_RESET_BODY, email=f"walk-{index}@example.com"), False)
        for index in range(31)
    ]
    responses = _run(store, steps)

    assert [response.status_code for response in responses] == [403] * 30 + [429]


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("POST", _STATUS, {"schemaVersion": "1", "password": "p" * 200}),
        ("POST", _STATUS, {"schemaVersion": "2", "password": _PASSWORD}),
        ("POST", _CHANGE, dict(_CHANGE_BODY, newPassword="n" * 200)),
        ("POST", _CHANGE, dict(_CHANGE_BODY, extra="unknown")),
        ("POST", _RESET, dict(_RESET_BODY, recoveryCode="C" * 65)),
        ("POST", _RESET, dict(_RESET_BODY, newPassword="n" * 200)),
        ("POST", _RESET, {"schemaVersion": "1", "email": _ADDRESS}),
    ],
)
def test_a_malformed_request_is_refused_without_echoing_a_secret(
    method: str, path: str, body: dict[str, str]
) -> None:
    store = _FakeCredentials()
    response = _one(store, method, path, body)

    assert response.status_code == 422, response.text
    assert response.json() == {"detail": {"code": "MALFORMED_CREDENTIAL_REQUEST"}}
    for secret in ("p" * 200, "n" * 200, "C" * 65, _PASSWORD, _NEW_PASSWORD, _CODE):
        assert secret not in response.text
    assert store.calls == []


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("GET", _STATUS, None),
        ("POST", _STATUS, _ISSUE_BODY),
        ("POST", _CHANGE, _CHANGE_BODY),
        ("POST", _RESET, _RESET_BODY),
    ],
)
def test_a_failing_store_says_so_and_nothing_more(
    method: str, path: str, body: dict[str, str] | None
) -> None:
    store = _FakeCredentials(error=CredentialsUnavailable("secret-detail"))
    response = _one(store, method, path, body)

    assert response.status_code == 503
    assert response.json() == {"detail": {"code": "CREDENTIALS_UNAVAILABLE"}}
    assert "secret-detail" not in response.text


def test_an_application_built_without_a_store_fails_closed() -> None:
    async def scenario() -> Response:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            return await client.post(_RESET, json=_RESET_BODY)

    response = asyncio.run(scenario())

    assert response.status_code == 503
    assert response.json() == {"detail": {"code": "CREDENTIALS_UNAVAILABLE"}}
