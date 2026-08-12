"""The profile read: who is signed in, and the durable facts of the account.

One request answers the whole screen. The identity deliberately does not come
from the authentication response: that lives in memory and is gone after an app
restart, while this survives it.
"""

from __future__ import annotations

import asyncio
from datetime import date
from uuid import UUID

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app
from mobile_finance_api.postgres_profile_repository import ProfileUnavailable
from mobile_finance_api.profile_contracts import (
    ProfileAccount,
    ProfileResponse,
    ProfileUser,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_AUTH = {"Authorization": "Bearer synthetic-token"}


def _profile(*, account: bool = True) -> ProfileResponse:
    return ProfileResponse(
        user=ProfileUser(
            id=_USER_ID,
            display_name="Синтетический Пользователь",
            email="owner@example.com",
        ),
        account=ProfileAccount(
            id=_ACCOUNT_ID,
            currency="EUR",
            canonical_timezone="Europe/Berlin",
            opening_balance_on=date(2026, 6, 1),
        )
        if account
        else None,
    )


# --- contract rules ---------------------------------------------------------


def test_an_account_is_optional_because_registering_precedes_it() -> None:
    """A registered user without an account is a real state, not an error."""

    assert _profile(account=False).account is None


def test_the_profile_reports_no_money() -> None:
    """A balance belongs on Home.

    A second surface reporting it is a second thing that can disagree with the
    authoritative projection.
    """

    payload = _profile().model_dump(mode="json", by_alias=True)
    assert set(payload["account"]) == {
        "id",
        "currency",
        "canonicalTimezone",
        "openingBalanceOn",
    }
    assert "balance" not in payload["account"]


def test_a_malformed_identity_is_refused() -> None:
    for invalid in ({"email": "not-an-email"}, {"displayName": ""}):
        with pytest.raises(ValidationError):
            ProfileUser.model_validate(
                {
                    "id": str(_USER_ID),
                    "displayName": "Имя",
                    "email": "owner@example.com",
                    **invalid,
                }
            )


def test_the_profile_cannot_be_mass_assigned() -> None:
    with pytest.raises(ValidationError):
        ProfileResponse.model_validate(
            {
                "user": {
                    "id": str(_USER_ID),
                    "displayName": "Имя",
                    "email": "owner@example.com",
                    "passwordHash": "leaked",
                },
                "account": None,
            }
        )


# --- transport --------------------------------------------------------------


def test_reading_a_profile_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/profile")
        assert response.status_code == 401

    asyncio.run(scenario())


def test_the_route_takes_no_identifier_so_another_profile_is_unreachable() -> None:
    """Not merely rejected — there is no way to ask for someone else's."""

    async def scenario() -> None:
        repository = _FakeProfile()
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            profile_repository=repository,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/v1/profile",
                params={"userId": "33333333-3333-4333-8333-333333333333"},
                headers=_AUTH,
            )
        assert response.status_code == 200, response.text
        # The query parameter is ignored: the caller is the subject.
        assert repository.requested == [_USER_ID]

    asyncio.run(scenario())


def test_a_profile_crosses_the_api_with_its_identity_and_account() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            profile_repository=_FakeProfile(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/profile", headers=_AUTH)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["user"]["email"] == "owner@example.com"
        assert body["user"]["displayName"] == "Синтетический Пользователь"
        assert body["account"]["currency"] == "EUR"
        assert body["account"]["canonicalTimezone"] == "Europe/Berlin"
        assert body["account"]["openingBalanceOn"] == "2026-06-01"

    asyncio.run(scenario())


def test_an_unwired_store_fails_closed() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/profile", headers=_AUTH)
        assert response.status_code == 503, response.text
        assert response.json() == {"detail": {"code": "PROFILE_UNAVAILABLE"}}

    asyncio.run(scenario())


def test_an_unexpected_failure_never_carries_the_email() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            profile_repository=_ExplodingProfile(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/profile", headers=_AUTH)
        assert response.status_code == 503, response.text
        assert "owner@example.com" not in response.text

    asyncio.run(scenario())


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


class _FakeProfile:
    def __init__(self) -> None:
        self.requested: list[UUID] = []

    async def read_profile(self, *, user_id: UUID) -> ProfileResponse:
        self.requested.append(user_id)
        return _profile()


class _ExplodingProfile:
    async def read_profile(self, *, user_id: UUID) -> ProfileResponse:
        del user_id
        raise ProfileUnavailable("owner@example.com leaked through an exception")
