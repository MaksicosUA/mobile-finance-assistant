"""Managing the catalogue: create, rename, hide, restore (ADR 0020, step 2b).

Removal is always archiving. A category is never deleted, so no historical
operation can lose its grouping — see `test_hiding_keeps_the_row`.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import ValidationError

from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.category_contracts import (
    Category,
    CreateCategoryCommand,
    ListCategoriesResponse,
    ManagedCategory,
    ManagedCategoryListResponse,
    RenameCategoryCommand,
)
from mobile_finance_api.db_models import (
    FinanceCategoryOutboxEventRow,
    FinanceCategoryRow,
    FinanceOperationRow,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.postgres_category_repository import (
    CategoryArchived,
    CategoryNameTaken,
    CategoryNotFound,
    _outbox_payload,
)
from mobile_finance_api.postgres_home_projector import (
    _category_label,
    _OutboxContractError,
    _validate_category_events,
)

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_GROCERIES = UUID("55555555-5555-4555-8555-555555555555")
_HIDDEN = UUID("66666666-6666-4666-8666-666666666666")
_MISSING = UUID("77777777-7777-4777-8777-777777777777")
_NOW = datetime(2026, 8, 12, 12, 0, tzinfo=UTC)
_AUTH = {"Authorization": "Bearer synthetic-token"}


# --- the invalidation a rename needs ----------------------------------------


def test_the_rename_event_carries_identifiers_and_no_name() -> None:
    """A published projection stores the label, so a rename makes it stale.

    The event says only which category changed. Carrying the new name would let
    a replayed event write a fact the projector did not read from the database.
    """

    command_id = uuid4()
    payload = _outbox_payload(
        category_id=_GROCERIES,
        user_id=_USER_ID,
        command_id=command_id,
    )
    assert payload == {
        "schemaVersion": "1",
        "categoryId": str(_GROCERIES),
        "userId": str(_USER_ID),
        "commandId": str(command_id),
    }


def test_a_report_reads_the_link_and_falls_back_to_the_written_text() -> None:
    """ADR 0020: reports read the link, never the stored text.

    This is what makes a rename visible. Before it, Home showed the label as it
    was written at the time, so renaming a category changed nothing a user
    could see and looked broken.
    """

    names = {_GROCERIES: "Еда"}
    linked = _operation_row(category_id=_GROCERIES, category="Продукты")
    assert _category_label(linked, category_names=names) == "Еда"

    # Recorded before the catalogue existed: there is no link to follow, and
    # the text the user wrote is all there is.
    unlinked = _operation_row(category_id=None, category="Продукты")
    assert _category_label(unlinked, category_names=names) == "Продукты"
    assert _category_label(_operation_row(), category_names=names) is None

    # A hidden category keeps its name, so hiding one never blanks the label on
    # a transaction that already happened.
    assert (
        _category_label(
            _operation_row(category_id=_HIDDEN, category="Аренда"),
            category_names={_HIDDEN: "Аренда"},
        )
        == "Аренда"
    )


def test_a_rename_event_that_cannot_be_trusted_is_refused() -> None:
    """A malformed event must dead-letter rather than rebuild from a payload."""

    category = _category_row()
    valid = _rename_event(category)
    _validate_category_events([valid], categories_by_id={_GROCERIES: category})

    foreign = _category_row(user_id=uuid4())
    for event, catalogue in (
        (valid, {}),
        (_rename_event(category), {_GROCERIES: foreign}),
        (
            _rename_event(category, aggregate_type="finance_goal"),
            {_GROCERIES: category},
        ),
        (
            _rename_event(category, event_type="finance.category.archived.v1"),
            {_GROCERIES: category},
        ),
        # A payload carrying the new name would let a replay write a label the
        # projector never read from the database.
        (
            _rename_event(category, extra={"name": "Еда"}),
            {_GROCERIES: category},
        ),
    ):
        with pytest.raises(_OutboxContractError):
            _validate_category_events([event], categories_by_id=catalogue)


# --- contract rules ---------------------------------------------------------


def test_a_hidden_category_reports_when_it_was_hidden() -> None:
    managed = ManagedCategory.model_validate(
        {
            "categoryId": str(_HIDDEN),
            "name": "Аренда",
            "direction": "expense",
            "systemKey": None,
            "createdAt": "2026-08-11T12:00:00Z",
            "archivedAt": "2026-08-12T12:00:00Z",
        }
    )
    assert managed.archived_at == _NOW
    # Absent means offered, so an older row needs no migration to read.
    assert (
        ManagedCategory.model_validate(
            {
                "categoryId": str(_GROCERIES),
                "name": "Продукты",
                "direction": "expense",
                "systemKey": "groceries",
                "createdAt": "2026-08-11T12:00:00Z",
            }
        ).archived_at
        is None
    )


def test_only_offered_names_must_be_unique() -> None:
    def entry(name: str, *, archived: bool) -> dict[str, object]:
        return {
            "categoryId": str(uuid4()),
            "name": name,
            "direction": "expense",
            "systemKey": None,
            "createdAt": "2026-08-11T12:00:00Z",
            "archivedAt": "2026-08-12T12:00:00Z" if archived else None,
        }

    # A hidden name may repeat an offered one: the database's uniqueness
    # excludes archived rows, so a listing showing both is correct.
    ManagedCategoryListResponse.model_validate(
        {
            "categories": [
                entry("Продукты", archived=False),
                entry("Продукты", archived=True),
                entry("продукты", archived=True),
            ]
        }
    )
    with pytest.raises(ValidationError):
        ManagedCategoryListResponse.model_validate(
            {
                "categories": [
                    entry("Продукты", archived=False),
                    entry("продукты", archived=False),
                ]
            }
        )


def test_a_command_cannot_smuggle_extra_fields() -> None:
    for payload in (
        {"name": "Кофе", "direction": "expense", "userId": str(_USER_ID)},
        {"name": "Кофе", "direction": "expense", "systemKey": "coffee"},
        {"name": "Кофе", "direction": "expense", "archivedAt": None},
    ):
        with pytest.raises(ValidationError):
            CreateCategoryCommand.model_validate(payload)
    # A user-authored category never claims a seeded key.
    assert (
        CreateCategoryCommand.model_validate(
            {"name": "  Кофе  ", "direction": "expense"}
        ).name
        == "Кофе"
    )


def test_a_rename_rejects_an_empty_or_oversized_name() -> None:
    # The control character is written as an escape on purpose: a literal
    # one in a source file is invisible in review and in most editors.
    for rejected in ("", "   ", "П" * 101, "Ко\u0007фе"):
        with pytest.raises(ValidationError):
            RenameCategoryCommand.model_validate({"name": rejected})


# --- transport --------------------------------------------------------------


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/api/v1/categories/managed"),
        ("POST", "/api/v1/categories"),
        ("PATCH", f"/api/v1/categories/{_GROCERIES}"),
        ("POST", f"/api/v1/categories/{_GROCERIES}/archive"),
        ("POST", f"/api/v1/categories/{_GROCERIES}/restore"),
    ],
)
def test_every_management_route_requires_authentication(
    method: str,
    path: str,
) -> None:
    async def scenario() -> None:
        app = create_app()
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.request(method, path, json={"name": "Кофе"})
        assert response.status_code == 401

    asyncio.run(scenario())


def test_the_picker_response_is_unchanged_by_this_slice() -> None:
    """The installed client parses that response with a closed key set.

    Both the envelope and each item are exact matches there, so an additive
    field would not degrade the picker — it would stop it from loading. The
    management view is a separate representation for exactly this reason.
    """

    async def scenario() -> None:
        catalogue = _FakeCatalogue()
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=catalogue,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/categories", headers=_AUTH)
        assert response.status_code == 200
        body = response.json()
        assert set(body) == {"schemaVersion", "categories"}
        assert set(body["categories"][0]) == {
            "categoryId",
            "name",
            "direction",
            "systemKey",
            "createdAt",
        }
        # And the hidden row never reaches the picker at all.
        assert [item["name"] for item in body["categories"]] == ["Продукты"]

    asyncio.run(scenario())


def test_the_management_view_shows_hidden_rows_with_their_date() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.get("/api/v1/categories/managed", headers=_AUTH)
        assert response.status_code == 200
        body = response.json()
        assert [(item["name"], item["archivedAt"]) for item in body["categories"]] == [
            ("Продукты", None),
            ("Аренда", "2026-08-12T12:00:00Z"),
        ]

    asyncio.run(scenario())


def test_creating_a_category_returns_it_as_offered() -> None:
    async def scenario() -> None:
        catalogue = _FakeCatalogue()
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=catalogue,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                "/api/v1/categories",
                headers=_AUTH,
                json={"name": "Кофе", "direction": "expense"},
            )
        assert response.status_code == 201
        body = response.json()
        assert body["category"]["name"] == "Кофе"
        assert body["category"]["archivedAt"] is None
        # A category the user named carries no key, so no translation overrides
        # the name they chose.
        assert body["category"]["systemKey"] is None
        assert catalogue.created == ["Кофе"]

    asyncio.run(scenario())


@pytest.mark.parametrize(
    ("failure", "status", "code"),
    [
        (CategoryNotFound(), 404, "CATEGORY_NOT_FOUND"),
        (CategoryNameTaken(), 409, "CATEGORY_NAME_TAKEN"),
        (CategoryArchived(), 409, "CATEGORY_ARCHIVED"),
    ],
)
def test_a_refused_rename_is_a_typed_code(
    failure: Exception,
    status: int,
    code: str,
) -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(failure=failure),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.patch(
                f"/api/v1/categories/{_GROCERIES}",
                headers=_AUTH,
                json={"name": "Еда"},
            )
        assert response.status_code == status
        assert response.json() == {"detail": {"code": code}}

    asyncio.run(scenario())


def test_an_unexpected_failure_is_redacted() -> None:
    """A category name must never reach a client through an exception."""

    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(
                failure=RuntimeError("Аренда квартиры on the wire")
            ),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                f"/api/v1/categories/{_GROCERIES}/archive",
                headers=_AUTH,
            )
        assert response.status_code == 503
        assert response.json() == {
            "detail": {"code": "CATEGORY_PERSISTENCE_UNAVAILABLE"}
        }
        assert "Аренда" not in response.text

    asyncio.run(scenario())


def test_a_repeated_write_succeeds_and_says_nothing_changed() -> None:
    """This is what a retry looks like, not a failure.

    Hiding a hidden category, or renaming one to the name it already has,
    already satisfies the caller's intent. Answering with an error would push a
    client into undoing work that was already correct.
    """

    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(changed=False),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                f"/api/v1/categories/{_GROCERIES}/archive",
                headers=_AUTH,
            )
        assert response.status_code == 200
        assert response.headers["X-Category-Unchanged"] == "1"
        assert response.json()["category"]["categoryId"] == str(_GROCERIES)

    asyncio.run(scenario())


def test_hiding_keeps_the_row() -> None:
    """The decision this slice is built on: removal is never deletion.

    Hiding answers with the same category identifier it was given, so whatever
    an operation points at still exists afterwards.
    """

    async def scenario() -> None:
        catalogue = _FakeCatalogue()
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=catalogue,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            hidden = await client.post(
                f"/api/v1/categories/{_GROCERIES}/archive",
                headers=_AUTH,
            )
            listing = await client.get("/api/v1/categories/managed", headers=_AUTH)
        assert hidden.status_code == 200
        assert hidden.json()["category"]["archivedAt"] is not None
        identifiers = {item["categoryId"] for item in listing.json()["categories"]}
        assert str(_GROCERIES) in identifiers
        assert catalogue.deletions == 0

    asyncio.run(scenario())


def test_restoring_a_category_offers_it_again() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                f"/api/v1/categories/{_HIDDEN}/restore",
                headers=_AUTH,
            )
        assert response.status_code == 200
        assert response.json()["category"]["archivedAt"] is None

    asyncio.run(scenario())


def test_an_unknown_category_is_not_found_rather_than_created() -> None:
    async def scenario() -> None:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            category_repository=_FakeCatalogue(failure=CategoryNotFound()),
        )
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            response = await client.post(
                f"/api/v1/categories/{_MISSING}/restore",
                headers=_AUTH,
            )
        assert response.status_code == 404

    asyncio.run(scenario())


def _operation_row(
    *,
    category_id: UUID | None = None,
    category: str | None = None,
) -> FinanceOperationRow:
    return FinanceOperationRow(
        id=uuid4(),
        user_id=_USER_ID,
        category_id=category_id,
        category=category,
    )


def _category_row(*, user_id: UUID | None = None) -> FinanceCategoryRow:
    return FinanceCategoryRow(
        id=_GROCERIES,
        user_id=user_id if user_id is not None else _USER_ID,
        name="Продукты",
        direction="expense",
        system_key=None,
        created_at=_NOW,
        archived_at=None,
    )


def _rename_event(
    category: FinanceCategoryRow,
    *,
    aggregate_type: str = "finance_category",
    event_type: str = "finance.category.renamed.v1",
    extra: dict[str, object] | None = None,
) -> FinanceCategoryOutboxEventRow:
    command_id = uuid4()
    payload: dict[str, object] = {
        "schemaVersion": "1",
        "categoryId": str(category.id),
        "userId": str(_USER_ID),
        "commandId": str(command_id),
    }
    payload.update(extra or {})
    return FinanceCategoryOutboxEventRow(
        id=uuid4(),
        aggregate_type=aggregate_type,
        aggregate_id=category.id,
        user_id=_USER_ID,
        command_id=command_id,
        event_type=event_type,
        payload=payload,
        created_at=_NOW,
        published_at=None,
        attempt_count=0,
        validation_failure_count=0,
        next_attempt_at=_NOW,
        last_failed_at=None,
        failure_code=None,
        dead_lettered_at=None,
    )


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic User")


class _FakeCatalogue:
    """In-memory stand-in for the PostgreSQL adapter.

    Locking, the partial unique index, and the audit/outbox rows are exercised
    against a real database in `tests/category_postgres_e2e.py`; this double
    covers the HTTP contract those failures are translated into.
    """

    def __init__(
        self,
        *,
        failure: Exception | None = None,
        changed: bool = True,
    ) -> None:
        self._failure = failure
        self._changed = changed
        self.created: list[str] = []
        self.deletions = 0

    def _raise_if_configured(self) -> None:
        if self._failure is not None:
            raise self._failure

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        del user_id
        return ListCategoriesResponse(
            categories=(
                Category(
                    category_id=_GROCERIES,
                    name="Продукты",
                    direction="expense",
                    system_key="groceries",
                    created_at=_NOW,
                ),
            )
        )

    async def list_managed_categories(
        self,
        *,
        user_id: UUID,
    ) -> ManagedCategoryListResponse:
        del user_id
        return ManagedCategoryListResponse(
            categories=(
                _managed(_GROCERIES, "Продукты", key="groceries"),
                _managed(_HIDDEN, "Аренда", archived_at=_NOW),
            )
        )

    async def create_category(
        self,
        *,
        user_id: UUID,
        command: CreateCategoryCommand,
    ) -> ManagedCategory:
        del user_id
        self._raise_if_configured()
        self.created.append(command.name)
        return _managed(uuid4(), command.name)

    async def rename_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
        command: RenameCategoryCommand,
    ) -> tuple[ManagedCategory, bool]:
        del user_id
        self._raise_if_configured()
        return _managed(category_id, command.name), self._changed

    async def archive_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        del user_id
        self._raise_if_configured()
        return _managed(category_id, "Продукты", archived_at=_NOW), self._changed

    async def restore_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        del user_id
        self._raise_if_configured()
        return _managed(category_id, "Аренда"), self._changed


def _managed(
    category_id: UUID,
    name: str,
    *,
    key: str | None = None,
    archived_at: datetime | None = None,
) -> ManagedCategory:
    return ManagedCategory(
        category_id=category_id,
        name=name,
        direction="expense",
        system_key=key,
        created_at=_NOW,
        archived_at=archived_at,
    )
