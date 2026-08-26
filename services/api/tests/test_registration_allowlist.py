"""Who may create an account once the API is reachable from the internet.

While the API answered only on localhost, open registration cost nothing. On a
public address it means anyone who finds the host can put their data in this
database and their transcriptions on these two cores.

Accounts stay isolated either way — that is enforced elsewhere and tested
elsewhere. This is about who gets one at all.
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import Iterator
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient

from mobile_finance_api.auth_service import AuthGrant
from mobile_finance_api.config import load_registration_allowlist
from mobile_finance_api.main import create_app

_REFUSAL = {"detail": "Account could not be created"}


def _grant() -> AuthGrant:
    return AuthGrant(
        access_token="synthetic-access",
        refresh_token="synthetic-refresh",
        access_expires_in=900,
        refresh_expires_in=2_592_000,
        user_id=UUID("11111111-1111-4111-8111-111111111111"),
        display_name="Synthetic Owner",
    )


class _RecordingAuthService:
    def __init__(self) -> None:
        self.registered: list[str] = []

    async def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str,
    ) -> AuthGrant:
        del password, display_name
        self.registered.append(email)
        return _grant()

    def __getattr__(self, name: str) -> object:  # pragma: no cover - unused
        raise AttributeError(name)


async def _register(app: object, email: str) -> tuple[int, dict[str, object]]:
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        response = await client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "synthetic-password-123",
                "displayName": "Synthetic Owner",
            },
        )
    return response.status_code, response.json()


@pytest.fixture
def clean_environment() -> Iterator[None]:
    previous = os.environ.pop("MFA_AUTH_REGISTRATION_ALLOWLIST", None)
    try:
        yield
    finally:
        if previous is not None:
            os.environ["MFA_AUTH_REGISTRATION_ALLOWLIST"] = previous


# --- the three states of the setting ------------------------------------------


def test_unset_means_open(clean_environment: None) -> None:
    """A local run and every other test depend on this staying the default."""

    del clean_environment
    assert load_registration_allowlist() is None


def test_an_empty_setting_closes_registration_rather_than_opening_it(
    clean_environment: None,
) -> None:
    """The dangerous reading of an empty value would be "allow everyone"."""

    del clean_environment
    os.environ["MFA_AUTH_REGISTRATION_ALLOWLIST"] = ""
    assert load_registration_allowlist() == frozenset()


def test_addresses_are_trimmed_and_case_folded(clean_environment: None) -> None:
    del clean_environment
    os.environ["MFA_AUTH_REGISTRATION_ALLOWLIST"] = " Owner@Example.com , b@e.com "
    assert load_registration_allowlist() == frozenset({"owner@example.com", "b@e.com"})


# --- what the endpoint does ---------------------------------------------------


def test_an_invited_address_registers() -> None:
    async def scenario() -> None:
        service = _RecordingAuthService()
        app = create_app(
            authentication_service=service,
            registration_allowlist=frozenset({"owner@example.com"}),
        )
        # The invite was written with capitals; it is the same invite.
        status_code, _ = await _register(app, "Owner@Example.com")
        assert status_code == 201
        assert service.registered == ["Owner@Example.com"]

    asyncio.run(scenario())


def test_an_uninvited_address_is_refused_before_the_service_is_asked() -> None:
    async def scenario() -> None:
        service = _RecordingAuthService()
        app = create_app(
            authentication_service=service,
            registration_allowlist=frozenset({"owner@example.com"}),
        )
        status_code, body = await _register(app, "stranger@example.com")

        assert status_code == 409
        # Byte for byte what a taken address gets: telling the two apart would
        # turn this endpoint into an oracle for who is invited.
        assert body == _REFUSAL
        assert service.registered == []

    asyncio.run(scenario())


def test_an_empty_allowlist_refuses_everyone() -> None:
    async def scenario() -> None:
        service = _RecordingAuthService()
        app = create_app(
            authentication_service=service,
            registration_allowlist=frozenset(),
        )
        status_code, body = await _register(app, "owner@example.com")

        assert status_code == 409
        assert body == _REFUSAL
        assert service.registered == []

    asyncio.run(scenario())


def test_no_allowlist_leaves_registration_open() -> None:
    async def scenario() -> None:
        service = _RecordingAuthService()
        app = create_app(authentication_service=service)
        status_code, _ = await _register(app, "anyone@example.com")

        assert status_code == 201
        assert service.registered == ["anyone@example.com"]

    asyncio.run(scenario())
