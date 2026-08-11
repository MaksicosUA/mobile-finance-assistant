from __future__ import annotations

import asyncio
import json
from datetime import UTC, date, datetime
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.account_core import FinanceAccountSnapshot
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.category_contracts import (
    SEEDED_CATEGORIES,
    Category,
    ListCategoriesResponse,
    category_contract_schema,
)
from mobile_finance_api.finance_core import (
    FinanceCategorySnapshot,
    FinanceCore,
    OperationWriteResult,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.operation_contracts import OperationDraft
from mobile_finance_api.postgres_category_repository import seeded_category_rows

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_ACCOUNT_ID = UUID("33333333-3333-4333-8333-333333333333")
_CATEGORY_ID = UUID("55555555-5555-4555-8555-555555555555")
_NOW = datetime(2026, 8, 11, 12, 0, tzinfo=UTC)


def _draft(**changes: object) -> OperationDraft:
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": "44444444-4444-4444-8444-444444444444",
        "type": "expense",
        "amount": "25.00",
        "currency": "EUR",
        "accountId": str(_ACCOUNT_ID),
        "category": "Продукты",
        "merchant": None,
        "capturedAt": "2026-08-11T12:00:00Z",
        "capturedTimezone": "Europe/Berlin",
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": "2026-08-11",
        "occurredAt": None,
        "source": "manual_text",
    }
    payload.update(changes)
    return OperationDraft.model_validate(payload)


def _account() -> FinanceAccountSnapshot:
    return FinanceAccountSnapshot(
        account_id=_ACCOUNT_ID,
        user_id=_USER_ID,
        currency="EUR",
        opening_balance_on=date(2026, 1, 1),
        status="active",
    )


def _category(
    *,
    direction: str = "expense",
    archived: bool = False,
) -> FinanceCategorySnapshot:
    return FinanceCategorySnapshot(
        category_id=_CATEGORY_ID,
        user_id=_USER_ID,
        direction=direction,
        archived=archived,
    )


# --- the seeded set ---------------------------------------------------------


def test_the_seeded_set_covers_both_directions_with_unique_names() -> None:
    directions = {seeded.direction for seeded in SEEDED_CATEGORIES}
    assert directions == {"expense", "income"}
    # A name may repeat across directions ("Подарки" is both), but never inside
    # one, or the picker would offer the same label twice.
    per_direction = [
        (seeded.direction, seeded.name.casefold()) for seeded in SEEDED_CATEGORIES
    ]
    assert len(per_direction) == len(set(per_direction))
    keys = [seeded.system_key for seeded in SEEDED_CATEGORIES]
    assert len(keys) == len(set(keys))


def test_seeded_rows_are_owned_and_carry_their_key() -> None:
    rows = seeded_category_rows(user_id=_USER_ID, created_at=_NOW)
    assert len(rows) == len(SEEDED_CATEGORIES)
    assert {row.user_id for row in rows} == {_USER_ID}
    assert all(row.system_key is not None for row in rows)
    assert all(row.archived_at is None for row in rows)
    # Distinct identifiers, so two users never share a row.
    assert len({row.id for row in rows}) == len(rows)


def test_seeding_twice_produces_distinct_rows_for_distinct_users() -> None:
    first = seeded_category_rows(user_id=_USER_ID, created_at=_NOW)
    second = seeded_category_rows(user_id=uuid4(), created_at=_NOW)
    assert not {row.id for row in first} & {row.id for row in second}


# --- contract rules ---------------------------------------------------------


def test_a_system_key_is_a_slug_never_user_text() -> None:
    base: dict[str, object] = {
        "categoryId": str(_CATEGORY_ID),
        "name": "Продукты",
        "direction": "expense",
        "systemKey": "groceries",
        "createdAt": "2026-08-11T12:00:00Z",
    }
    assert Category.model_validate(base).system_key == "groceries"
    # A renamed category carries no key, so no localized label overrides the
    # name the user chose.
    assert Category.model_validate({**base, "systemKey": None}).system_key is None
    for rejected in ("Продукты", "Groceries", "1groceries", "with space", "a" * 64):
        with pytest.raises(ValidationError):
            Category.model_validate({**base, "systemKey": rejected})


def test_a_category_name_is_bounded_and_control_free() -> None:
    base: dict[str, object] = {
        "categoryId": str(_CATEGORY_ID),
        "name": "Продукты",
        "direction": "expense",
        "systemKey": None,
        "createdAt": "2026-08-11T12:00:00Z",
    }
    assert Category.model_validate({**base, "name": "  Продукты  "}).name == "Продукты"
    for rejected in ("", "Продукты", "П" * 101):
        with pytest.raises(ValidationError):
            Category.model_validate({**base, "name": rejected})


def test_a_listing_cannot_repeat_a_name_inside_one_direction() -> None:
    def entry(name: str, direction: str) -> dict[str, object]:
        return {
            "categoryId": str(uuid4()),
            "name": name,
            "direction": direction,
            "systemKey": None,
            "createdAt": "2026-08-11T12:00:00Z",
        }

    # The same label in both directions is legitimate.
    ListCategoriesResponse.model_validate(
        {"categories": [entry("Подарки", "expense"), entry("Подарки", "income")]}
    )
    # Two spellings of one name in one direction is exactly what the catalogue
    # exists to prevent, so a listing that shows it is malformed.
    with pytest.raises(ValidationError):
        ListCategoriesResponse.model_validate(
            {"categories": [entry("Продукты", "expense"), entry("продукты", "expense")]}
        )


def test_a_category_cannot_be_mass_assigned() -> None:
    with pytest.raises(ValidationError):
        Category.model_validate(
            {
                "categoryId": str(_CATEGORY_ID),
                "userId": str(_USER_ID),
                "name": "Продукты",
                "direction": "expense",
                "systemKey": None,
                "createdAt": "2026-08-11T12:00:00Z",
            }
        )


# --- the draft link ---------------------------------------------------------


def test_a_draft_without_a_category_link_stays_valid() -> None:
    """Uncategorized is a real state, not a gap to guess at."""

    draft = _draft()
    assert draft.category_id is None
    assert draft.category == "Продукты"


def test_the_written_text_and_the_link_are_separate_fields() -> None:
    draft = _draft(categoryId=str(_CATEGORY_ID))
    assert draft.category_id == _CATEGORY_ID
    # The text is evidence of what the user wrote and is never replaced by the
    # link (ADR 0020).
    assert draft.category == "Продукты"


def test_an_owned_matching_category_is_accepted() -> None:
    core = FinanceCore(
        repository=_FakeRepository(),
        account_directory=_FakeAccounts(),
        category_directory=_FakeCategories(_category()),
    )
    response = asyncio.run(
        core.evaluate(user_id=_USER_ID, draft=_draft(categoryId=str(_CATEGORY_ID)))
    )
    assert response.decision == "NEEDS_CONFIRMATION"
    assert response.issues == ()
    assert response.draft_hash is not None


@pytest.mark.parametrize(
    ("category", "expected"),
    [
        (None, "CATEGORY_UNAVAILABLE"),
        (_category(archived=True), "CATEGORY_UNAVAILABLE"),
        (_category(direction="income"), "CATEGORY_DIRECTION_MISMATCH"),
    ],
)
def test_an_unusable_category_is_rejected_with_a_typed_issue(
    category: FinanceCategorySnapshot | None,
    expected: str,
) -> None:
    core = FinanceCore(
        repository=_FakeRepository(),
        account_directory=_FakeAccounts(),
        category_directory=_FakeCategories(category),
    )
    response = asyncio.run(
        core.evaluate(user_id=_USER_ID, draft=_draft(categoryId=str(_CATEGORY_ID)))
    )
    assert response.decision == "REJECT"
    assert [(issue.code, issue.field) for issue in response.issues] == [
        (expected, "categoryId")
    ]


def test_a_draft_with_no_link_never_consults_the_catalogue() -> None:
    directory = _FakeCategories(None)
    core = FinanceCore(
        repository=_FakeRepository(),
        account_directory=_FakeAccounts(),
        category_directory=directory,
    )
    response = asyncio.run(core.evaluate(user_id=_USER_ID, draft=_draft()))
    assert response.decision == "NEEDS_CONFIRMATION"
    assert directory.lookups == 0


def test_a_core_without_a_catalogue_refuses_a_linked_draft() -> None:
    """Fail closed: an unwired catalogue must not silently accept any link."""

    core = FinanceCore(
        repository=_FakeRepository(),
        account_directory=_FakeAccounts(),
    )
    response = asyncio.run(
        core.evaluate(user_id=_USER_ID, draft=_draft(categoryId=str(_CATEGORY_ID)))
    )
    assert response.decision == "REJECT"
    assert [issue.code for issue in response.issues] == ["CATEGORY_UNAVAILABLE"]


def test_the_link_changes_the_draft_hash() -> None:
    """Two drafts that differ in grouping are not the same command."""

    from mobile_finance_api.finance_core import draft_hash

    assert draft_hash(_draft()) != draft_hash(_draft(categoryId=str(_CATEGORY_ID)))


# --- transport --------------------------------------------------------------


def test_listing_requires_authentication() -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/categories")
        assert response.status_code == 401

    asyncio.run(scenario())


def test_an_unavailable_catalogue_is_redacted_to_a_typed_code() -> None:
    async def scenario() -> None:
        app = create_app(current_user_authenticator=_StaticAuthenticator())
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/v1/categories",
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 503
        assert response.json() == {
            "detail": {"code": "CATEGORY_PERSISTENCE_UNAVAILABLE"}
        }

    asyncio.run(scenario())


def test_a_listing_crosses_the_api_with_its_keys() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get(
                "/api/v1/categories",
                headers={"Authorization": "Bearer synthetic-token"},
            )
        assert response.status_code == 200
        body = response.json()
        assert body["schemaVersion"] == "1"
        assert body["categories"][0]["systemKey"] == "groceries"
        # The owner is never echoed back: the caller already is the owner.
        assert "userId" not in body["categories"][0]

    asyncio.run(scenario())


def test_checked_in_category_contract_is_reproducible() -> None:
    repository_root = Path(__file__).resolve().parents[3]
    checked_in = json.loads(
        (repository_root / "contracts/finance/v1/category.schema.json").read_text(
            encoding="utf-8"
        )
    )
    assert checked_in == category_contract_schema()


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic User")


class _FakeCatalogue:
    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        del user_id
        return ListCategoriesResponse(
            categories=(
                Category(
                    category_id=_CATEGORY_ID,
                    name="Продукты",
                    direction="expense",
                    system_key="groceries",
                    created_at=_NOW,
                ),
            )
        )


class _FakeAccounts:
    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        del user_id, account_id
        return _account()


class _FakeCategories:
    def __init__(self, category: FinanceCategorySnapshot | None) -> None:
        self._category = category
        self.lookups = 0

    async def get_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> FinanceCategorySnapshot | None:
        del user_id, category_id
        self.lookups += 1
        return self._category


class _FakeRepository:
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
        raise AssertionError("commit is not exercised by these tests")


def test_money_is_untouched_by_the_catalogue() -> None:
    """A category is a label; nothing here may influence an amount."""

    linked = _draft(categoryId=str(_CATEGORY_ID))
    assert linked.amount == Decimal("25.00")
    assert _draft().amount == linked.amount
