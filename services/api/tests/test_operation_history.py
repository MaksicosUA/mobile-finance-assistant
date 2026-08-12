"""Reading confirmed operations back (ADR 0020, step 4).

Home shows three recent transactions; everything older had no surface at all.
This is that surface, and it is also the only place the original free text a
user wrote can be shown next to the category it was linked to.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.main import create_app
from mobile_finance_api.operation_contracts import (
    ListOperationsResponse,
    OperationHistoryItem,
)
from mobile_finance_api.postgres_finance_repository import InvalidOperationCursor

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("22222222-2222-4222-8222-222222222222")
_CATEGORY_ID = UUID("55555555-5555-4555-8555-555555555555")
_NOW = datetime(2026, 8, 12, 12, 0, tzinfo=UTC)
_AUTH = {"Authorization": "Bearer synthetic-token"}


def _item(**changes: object) -> OperationHistoryItem:
    values: dict[str, object] = {
        "operationId": str(uuid4()),
        "type": "expense",
        "amount": "42.00",
        "currency": "EUR",
        "accountId": str(_ACCOUNT_ID),
        "category": "Кофе и чай",
        "categoryId": str(_CATEGORY_ID),
        "categoryText": "Кофе",
        "merchant": None,
        "occurredOn": "2026-08-12",
        "occurredAt": None,
        "source": "manual_text",
        "status": "confirmed",
        "createdAt": "2026-08-12T12:00:00Z",
    }
    values.update(changes)
    return OperationHistoryItem.model_validate(values)


# --- contract rules ---------------------------------------------------------


def test_the_current_name_and_the_written_text_are_separate_fields() -> None:
    """After a rename they differ, and that difference is the point.

    The name comes from the link and follows a rename; the text is what the
    user actually wrote and never changes. Showing both is what makes a wrong
    link visible instead of permanent (ADR 0020).
    """

    item = _item()
    assert item.category == "Кофе и чай"
    assert item.category_text == "Кофе"
    assert item.category_id == _CATEGORY_ID


def test_an_uncategorized_operation_is_representable() -> None:
    item = _item(category=None, categoryId=None, categoryText=None)
    assert item.category is None
    assert item.category_id is None
    # Uncategorized is a real state, not a gap to guess at.
    assert item.category_text is None


def test_money_crosses_as_a_decimal_string_and_stays_exact() -> None:
    item = _item(amount="1234.567890123456789")
    assert item.amount == Decimal("1234.567890123456789")
    dumped = item.model_dump(mode="json", by_alias=True)
    assert dumped["amount"] == "1234.567890123456789"
    assert isinstance(dumped["amount"], str)


def test_a_history_item_cannot_be_mass_assigned() -> None:
    with pytest.raises(ValidationError):
        _item(userId=str(_USER_ID))
    with pytest.raises(ValidationError):
        _item(commandId=str(uuid4()))


def test_a_page_cursor_is_opaque_and_bounded() -> None:
    ListOperationsResponse.model_validate(
        {"operations": [], "nextCursor": "MjAyNi0wOC0xMg"}
    )
    # Absent on the last page rather than an empty string, which a client could
    # mistake for "there is more".
    assert ListOperationsResponse.model_validate({"operations": []}).next_cursor is None
    for rejected in ("has space", "has/slash", "a" * 257, ""):
        with pytest.raises(ValidationError):
            ListOperationsResponse.model_validate(
                {"operations": [], "nextCursor": rejected}
            )


# --- paging -----------------------------------------------------------------


def test_a_full_page_reports_a_cursor_and_the_last_page_does_not() -> None:
    async def scenario() -> None:
        repository = _FakeHistory(count=5)
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            finance_operation_repository=repository,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            first = await client.get(
                "/api/v1/operations",
                params={"limit": 2},
                headers=_AUTH,
            )
            assert first.status_code == 200, first.text
            cursor = first.json()["nextCursor"]
            assert cursor is not None
            assert len(first.json()["operations"]) == 2

            second = await client.get(
                "/api/v1/operations",
                params={"limit": 2, "cursor": cursor},
                headers=_AUTH,
            )
            assert second.status_code == 200, second.text
            last = await client.get(
                "/api/v1/operations",
                params={"limit": 2, "cursor": second.json()["nextCursor"]},
                headers=_AUTH,
            )
        # Five rows in pages of two: the third page holds one and ends.
        assert len(last.json()["operations"]) == 1
        assert last.json()["nextCursor"] is None
        # Every row appeared exactly once.
        seen = [
            item["operationId"]
            for page in (first, second, last)
            for item in page.json()["operations"]
        ]
        assert len(seen) == len(set(seen)) == 5

    asyncio.run(scenario())


def test_a_malformed_cursor_is_refused_rather_than_ignored() -> None:
    """Silently ignoring it would page from the top forever."""

    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            finance_operation_repository=_FakeHistory(count=1, reject_cursor=True),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/v1/operations",
                params={"cursor": "not-a-cursor"},
                headers=_AUTH,
            )
        assert response.status_code == 400, response.text
        assert response.json() == {
            "detail": {"code": "MALFORMED_OPERATION", "issues": []}
        }

    asyncio.run(scenario())


@pytest.mark.parametrize("limit", [0, -1, 101])
def test_an_out_of_range_limit_is_redacted_to_a_typed_code(limit: int) -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            finance_operation_repository=_FakeHistory(count=1),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/v1/operations",
                params={"limit": limit},
                headers=_AUTH,
            )
        assert response.status_code == 422, response.text
        # The collection path takes query parameters now, so its validation
        # errors are redacted like the rest of the operation boundary.
        assert response.json() == {
            "detail": {"code": "MALFORMED_OPERATION", "issues": []}
        }

    asyncio.run(scenario())


# --- transport --------------------------------------------------------------


def test_reading_history_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/operations")
        assert response.status_code == 401

    asyncio.run(scenario())


def test_an_unwired_store_fails_closed_without_leaking() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/operations", headers=_AUTH)
        assert response.status_code == 503, response.text
        assert response.json() == {
            "detail": {"code": "FINANCE_PERSISTENCE_UNAVAILABLE", "issues": []}
        }

    asyncio.run(scenario())


def test_an_unexpected_failure_never_carries_financial_text() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            finance_operation_repository=_ExplodingHistory(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/operations", headers=_AUTH)
        assert response.status_code == 503, response.text
        assert "Аренда" not in response.text
        assert "42.00" not in response.text

    asyncio.run(scenario())


def test_a_page_crosses_the_api_with_both_category_fields() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            finance_operation_repository=_FakeHistory(count=1),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/operations", headers=_AUTH)
        assert response.status_code == 200, response.text
        item = response.json()["operations"][0]
        assert item["category"] == "Кофе и чай"
        assert item["categoryText"] == "Кофе"
        # The owner is never echoed back: the caller already is the owner.
        assert "userId" not in item

    asyncio.run(scenario())


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic User")


class _FakeHistory:
    """In-memory stand-in that pages the way the SQL keyset does.

    The real ordering, the join, and the cursor encoding are exercised against
    PostgreSQL in `tests/operation_history_postgres_e2e.py`.
    """

    def __init__(self, *, count: int, reject_cursor: bool = False) -> None:
        self._items = [
            _item(
                operationId=str(UUID(int=index + 1)),
                occurredOn=date(2026, 8, 12 - index).isoformat(),
            )
            for index in range(count)
        ]
        self._reject_cursor = reject_cursor

    async def list_operations(
        self,
        *,
        user_id: UUID,
        limit: int,
        cursor: str | None,
    ) -> ListOperationsResponse:
        del user_id
        if cursor is not None and self._reject_cursor:
            raise InvalidOperationCursor
        start = 0 if cursor is None else int(cursor)
        page = self._items[start : start + limit]
        remaining = start + limit < len(self._items)
        return ListOperationsResponse(
            operations=tuple(page),
            next_cursor=str(start + limit) if remaining else None,
        )


class _ExplodingHistory:
    async def list_operations(
        self,
        *,
        user_id: UUID,
        limit: int,
        cursor: str | None,
    ) -> ListOperationsResponse:
        del user_id, limit, cursor
        raise RuntimeError("Аренда 42.00 leaked through an exception")
