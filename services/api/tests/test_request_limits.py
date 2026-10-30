"""How often anyone may ask, and how many expensive answers run at once."""

from __future__ import annotations

import asyncio
from collections.abc import Sequence
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient, Response

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.auth_service import AuthenticationRejected, AuthGrant
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService, PasswordServiceBusy
from mobile_finance_api.request_limits import Limit, RequestLimits, SlidingWindow

_ADDRESS = "synthetic@example.com"
_PASSWORD = "synthetic-password-123"
_WRONG = "wrong-password-1234"
_USER_ID = "11111111-1111-4111-8111-111111111111"


class _Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class _Service:
    """Rejects everything except the one password that works."""

    async def login(self, *, email: str, password: str) -> object:
        del email
        if password != _PASSWORD:
            raise AuthenticationRejected
        return AuthGrant(
            access_token="synthetic-access",  # noqa: S106
            refresh_token="synthetic-refresh",  # noqa: S106
            access_expires_in=600,
            refresh_expires_in=3600,
            user_id=UUID(_USER_ID),
            display_name="Synthetic User",
        )

    async def register(self, *, email: str, password: str, display_name: str) -> object:
        del email, password, display_name
        raise AuthenticationRejected


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=_USER_ID, display_name="Synthetic User")


def _application():  # type: ignore[no-untyped-def]
    application = create_app(
        authentication_service=_Service(),  # type: ignore[arg-type]
        current_user_authenticator=_StaticAuthenticator(),
    )
    return application


def _send(
    application: object, calls: Sequence[tuple[str, str, object]]
) -> list[Response]:
    async def run() -> list[Response]:
        async with AsyncClient(
            transport=ASGITransport(app=application),  # type: ignore[arg-type]
            base_url="http://test",
        ) as client:
            return [
                await client.request(
                    method,
                    path,
                    json=body,
                    headers={"Authorization": "Bearer synthetic"},
                )
                for method, path, body in calls
            ]

    return asyncio.run(run())


def _login(address: str = _ADDRESS, secret: str = _WRONG):  # type: ignore[no-untyped-def]
    return ("POST", "/api/v1/auth/login", {"email": address, "password": secret})


# --- the window ---------------------------------------------------------------


def test_a_window_refuses_only_once_it_is_full() -> None:
    clock = _Clock()
    window = SlidingWindow(Limit(attempts=2, seconds=60), clock=clock)

    assert window.retry_after("key") is None
    window.record("key")
    assert window.retry_after("key") is None
    window.record("key")
    assert window.retry_after("key") == 60


def test_a_window_frees_up_as_old_attempts_age_out() -> None:
    clock = _Clock()
    window = SlidingWindow(Limit(attempts=2, seconds=60), clock=clock)
    window.record("key")
    clock.now += 40
    window.record("key")

    clock.now += 19
    assert window.retry_after("key") == 1
    clock.now += 2
    assert window.retry_after("key") is None


def test_clearing_forgets_the_attempts() -> None:
    window = SlidingWindow(Limit(attempts=1, seconds=60), clock=_Clock())
    window.record("key")
    window.clear("key")

    assert window.retry_after("key") is None


def test_a_flood_of_new_keys_cannot_grow_the_memory_without_end() -> None:
    window = SlidingWindow(Limit(attempts=1, seconds=60), clock=_Clock(), capacity=100)

    for _ in range(1000):
        window.record(uuid4().hex)

    assert window.tracked_keys() == 100


# --- signing in ---------------------------------------------------------------


def test_guessing_one_address_stops_at_the_limit() -> None:
    limit = RequestLimits().login_by_address.limit.attempts
    responses = _send(_application(), [_login()] * (limit + 1))

    assert [response.status_code for response in responses[:limit]] == [401] * limit
    assert responses[-1].status_code == 429
    assert int(responses[-1].headers["retry-after"]) > 0


def test_the_refusal_is_the_same_for_an_address_nobody_owns() -> None:
    """A limit that only applied to real accounts would reveal which they are."""

    limit = RequestLimits().login_by_address.limit.attempts
    responses = _send(_application(), [_login("nobody@example.com")] * (limit + 1))

    assert responses[-1].status_code == 429


def test_the_address_is_compared_the_way_it_is_stored() -> None:
    limit = RequestLimits().login_by_address.limit.attempts
    spellings = [_login(" Synthetic@Example.com ")] * limit + [_login()]
    responses = _send(_application(), spellings)

    assert responses[-1].status_code == 429


def test_one_address_being_guessed_does_not_lock_out_another() -> None:
    limit = RequestLimits().login_by_address.limit.attempts
    calls = [_login()] * limit + [_login("other@example.com")]

    assert _send(_application(), calls)[-1].status_code == 401


def test_a_right_password_clears_the_count() -> None:
    limit = RequestLimits().login_by_address.limit.attempts
    calls = [
        *[_login()] * (limit - 1),
        _login(secret=_PASSWORD),
        *[_login()] * (limit - 1),
    ]

    statuses = [response.status_code for response in _send(_application(), calls)]

    assert 429 not in statuses


def test_many_addresses_from_one_place_stop_too() -> None:
    limit = RequestLimits().login_by_ip.limit.attempts
    calls = [_login(f"person{index}@example.com") for index in range(limit + 1)]

    assert _send(_application(), calls)[-1].status_code == 429


# --- registering --------------------------------------------------------------


def test_registering_from_one_place_is_limited() -> None:
    limit = RequestLimits().registration_by_ip.limit.attempts
    body = {
        "email": _ADDRESS,
        "password": _PASSWORD,
        "displayName": "Synthetic",
    }
    responses = _send(
        _application(), [("POST", "/api/v1/auth/register", body)] * (limit + 1)
    )

    assert responses[-1].status_code == 429


# --- a signed-in person -------------------------------------------------------


def test_writes_are_budgeted_per_person() -> None:
    limit = RequestLimits().writes_by_user.limit.attempts
    responses = _send(_application(), [("POST", "/api/v1/goals", {})] * (limit + 1))

    assert responses[limit - 1].status_code != 429
    assert responses[-1].status_code == 429


def test_reads_are_budgeted_separately_from_writes() -> None:
    limits = RequestLimits()
    assert limits.reads_by_user.limit.attempts > limits.writes_by_user.limit.attempts

    calls = [("POST", "/api/v1/goals", {})] * (limits.writes_by_user.limit.attempts + 1)
    calls.append(("GET", "/api/v1/profile", None))

    assert _send(_application(), calls)[-1].status_code != 429


# --- the password, spent carefully --------------------------------------------


def test_a_queue_of_password_checks_is_refused_past_its_length(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    release = asyncio.Event()

    async def run() -> list[object]:
        service = PasswordService()

        async def blocked(*_: object) -> bool:
            await release.wait()
            return True

        monkeypatch.setattr("mobile_finance_api.passwords.run_in_threadpool", blocked)
        waiting = [
            asyncio.create_task(service.verify(_PASSWORD, None)) for _ in range(40)
        ]
        await asyncio.sleep(0)
        await asyncio.sleep(0)
        release.set()
        return await asyncio.gather(*waiting, return_exceptions=True)

    results = asyncio.run(run())

    assert any(isinstance(result, PasswordServiceBusy) for result in results)
    assert any(result is True for result in results)


def test_password_checks_run_a_few_at_a_time(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    running = 0
    most = 0

    async def run() -> None:
        service = PasswordService()

        async def counted(*_: object) -> bool:
            nonlocal running, most
            running += 1
            most = max(most, running)
            await asyncio.sleep(0)
            running -= 1
            return True

        monkeypatch.setattr("mobile_finance_api.passwords.run_in_threadpool", counted)
        await asyncio.gather(*(service.verify(_PASSWORD, None) for _ in range(8)))

    asyncio.run(run())

    assert most <= 2


def test_a_server_failure_does_not_clear_the_count() -> None:
    """Only a right password does, or a failure would reset the guessing."""

    class _Failing(_Service):
        async def login(self, *, email: str, password: str) -> object:
            if password == _PASSWORD:
                raise RuntimeError("synthetic outage")
            return await super().login(email=email, password=password)

    application = create_app(
        authentication_service=_Failing(),  # type: ignore[arg-type]
    )
    limit = RequestLimits().login_by_address.limit.attempts
    calls = [
        *[_login()] * (limit - 1),
        _login(secret=_PASSWORD),
        _login(),
        _login(),
    ]

    assert _send(application, calls)[-1].status_code == 429
