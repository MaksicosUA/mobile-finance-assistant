"""What the API keeps to itself, on every route rather than on most of them.

Each of these was true for some paths and not for others, because the rule was
a list of prefixes that grew by hand. A route added later fell outside it in
silence. These tests name routes that were outside.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient, Response

from mobile_finance_api.app_download_link import verify_download_link
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app

_USER_ID = "11111111-1111-4111-8111-111111111111"
_SECRET = b"synthetic-download-link-secret-32-bytes"
_WRITTEN_BY_THE_PERSON = "synthetic words nobody should get back"


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=_USER_ID, display_name="Synthetic User")


def _call(method: str, path: str, body: object = None) -> Response:
    application = create_app(current_user_authenticator=_StaticAuthenticator())

    async def run() -> Response:
        async with AsyncClient(
            transport=ASGITransport(app=application),
            base_url="http://test",
        ) as client:
            return await client.request(
                method,
                path,
                json=body,
                headers={"Authorization": "Bearer synthetic"},
            )

    return asyncio.run(run())


@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json"])
def test_the_api_does_not_describe_itself_to_strangers(path: str) -> None:
    assert _call("GET", path).status_code == 404


def test_the_contract_can_still_be_generated_in_process() -> None:
    """Hiding the route must not cost the schema a contract check relies on."""

    schema = create_app().openapi()

    assert "/api/v2/home" in schema["paths"]


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/goals",
        "/api/v1/categories",
        "/api/v1/profile",
        "/api/v1/analytics",
        "/api/v1/analytics/v2",
        "/api/v1/planned-cost-recurrences",
        "/api/v1/not-a-route",
    ],
)
def test_nothing_under_the_api_may_be_stored_on_the_way(path: str) -> None:
    response = _call("GET", path)

    assert response.headers["cache-control"] == "no-store"


def test_home_keeps_its_own_revalidation_rule() -> None:
    """Home is the one read a client may keep: it revalidates with an ETag."""

    assert _call("GET", "/api/v2/home").headers["cache-control"] == "private, no-cache"


def test_a_refused_body_is_not_echoed_back() -> None:
    response = _call("PUT", "/api/v1/budgets", {"limit": _WRITTEN_BY_THE_PERSON})

    assert response.status_code == 422
    assert _WRITTEN_BY_THE_PERSON not in response.text


@pytest.mark.parametrize(
    "link",
    ["1893456000.подпись", "1893456000.signäture", "١٨٩٣٤٥٦٠٠٠.signature"],
)
def test_a_link_that_is_not_ascii_is_an_ordinary_refusal(link: str) -> None:
    """It used to raise, which answered 500 and only when a secret was set."""

    now = datetime(2026, 9, 11, 12, tzinfo=UTC)

    assert not verify_download_link(secret=_SECRET, link=link, now=now)
