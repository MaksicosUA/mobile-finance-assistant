"""Opt-in PostgreSQL E2E for category management (ADR 0020, step 2b).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/category_postgres_e2e.py

It is not collected by pytest: `testpaths` only picks up `test_*.py`, so this
script stays opt-in and never blocks CI, which provisions no database.

It proves what an in-memory fake cannot: that the partial unique index refuses
a duplicate offered name case-insensitively while leaving a hidden one free,
that hiding is not deletion and the operation foreign key survives it, that
audit and outbox rows are written in the same transaction as the state change,
and above all that renaming a category renames it on a rebuilt Home — the one
thing the whole slice exists for.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceCategoryAuditRow,
    FinanceCategoryOutboxEventRow,
    FinanceCategoryRow,
    FinanceOperationRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_category_repository import (
    PostgresCategoryRepository,
)
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-category-management-secret-32-bytes"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
TIMEZONE = "Europe/Berlin"
OPENING_ON = (datetime.now(UTC) - timedelta(days=60)).date()


@dataclass(frozen=True, slots=True)
class _Identity:
    user_id: UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


def _alembic_config() -> Config:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    return config


def _empty_migration_round_trip() -> None:
    config = _alembic_config()
    command.upgrade(config, "head")
    command.downgrade(config, "0011_category_catalogue")
    command.upgrade(config, "head")


def _assert_lossy_downgrade_refused() -> None:
    """An audit row is the only record of a name a rename replaced."""

    config = _alembic_config()
    try:
        command.downgrade(config, "0011_category_catalogue")
    except RuntimeError as error:
        assert "Refusing lossy downgrade" in str(error), str(error)
    else:
        raise AssertionError("populated category downgrade was not refused")


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):
    accounts = PostgresFinanceAccountRepository(session_factory=session_factory)
    categories = PostgresCategoryRepository(session_factory=session_factory)
    return create_app(
        home_repository=PostgresHomeRepository(session_factory=session_factory),
        current_user_authenticator=PostgresCurrentUserAuthenticator(
            session_factory=session_factory,
            access_tokens=tokens,
        ),
        authentication_service=PostgresAuthenticationService(
            session_factory=session_factory,
            password_service=PasswordService(),
            access_tokens=tokens,
        ),
        account_core=AccountCore(repository=accounts),
        finance_core=FinanceCore(
            repository=PostgresFinanceOperationRepository(
                session_factory=session_factory,
            ),
            account_directory=accounts,
            category_directory=categories,
        ),
        category_repository=categories,
    )


async def _register(client: AsyncClient, *, email: str, name: str) -> _Identity:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "synthetic-password-123",
            "displayName": name,
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()
    return _Identity(
        user_id=UUID(payload["user"]["id"]),
        token=str(payload["accessToken"]),
    )


async def _bootstrap_account(client: AsyncClient, *, identity: _Identity) -> UUID:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": "Synthetic primary account",
        "currency": "EUR",
        "openingBalance": "1000.00",
        "openingBalanceOn": OPENING_ON.isoformat(),
        "canonicalTimezone": TIMEZONE,
    }
    evaluation = await client.post(
        "/api/v1/accounts/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text
    return UUID(commit.json()["account"]["accountId"])


async def _commit_operation(
    client: AsyncClient,
    *,
    identity: _Identity,
    account_id: UUID,
    category_id: UUID,
    category_text: str,
) -> None:
    """Record real money against a category, through the untouched v1 path."""

    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": "expense",
        "amount": "42.00",
        "currency": "EUR",
        "accountId": str(account_id),
        "category": category_text,
        "categoryId": str(category_id),
        "merchant": None,
        "capturedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "capturedTimezone": TIMEZONE,
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": datetime.now(UTC)
        .astimezone(ZoneInfo(TIMEZONE))
        .date()
        .isoformat(),
        "occurredAt": None,
        "source": "manual_text",
    }
    evaluation = await client.post(
        "/api/v1/operations/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    evaluated = evaluation.json()
    assert evaluated["decision"] == "NEEDS_CONFIRMATION", evaluated
    commit = await client.post(
        "/api/v1/operations/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluated["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text


async def _scenario(engine: AsyncEngine, session_factory: AsyncSessionFactory) -> None:
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-test",
        audience="mfa-test-clients",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    projector = PostgresHomeProjector(session_factory=session_factory)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        identity = await _register(
            client,
            email=f"categories-{uuid4().hex[:12]}@example.com",
            name="Synthetic Owner",
        )
        account_id = await _bootstrap_account(client, identity=identity)

        # --- the picker contract is frozen ---------------------------------
        picker = await client.get("/api/v1/categories", headers=identity.headers)
        assert picker.status_code == 200, picker.text
        picker_body = picker.json()
        assert set(picker_body) == {"schemaVersion", "categories"}, picker_body
        assert set(picker_body["categories"][0]) == {
            "categoryId",
            "name",
            "direction",
            "systemKey",
            "createdAt",
        }, picker_body["categories"][0]
        seeded_count = len(picker_body["categories"])
        assert seeded_count == 16, seeded_count

        managed = await client.get(
            "/api/v1/categories/managed",
            headers=identity.headers,
        )
        assert managed.status_code == 200, managed.text
        assert len(managed.json()["categories"]) == seeded_count
        assert all(
            item["archivedAt"] is None for item in managed.json()["categories"]
        ), managed.text

        # --- creating ------------------------------------------------------
        created = await client.post(
            "/api/v1/categories",
            json={"name": "  Кофе  ", "direction": "expense"},
            headers=identity.headers,
        )
        assert created.status_code == 201, created.text
        coffee_id = UUID(created.json()["category"]["categoryId"])
        assert created.json()["category"]["name"] == "Кофе"
        # A user-authored category claims no seeded key.
        assert created.json()["category"]["systemKey"] is None, created.text

        for duplicate in ("Кофе", "кофе", "  КОФЕ  "):
            conflict = await client.post(
                "/api/v1/categories",
                json={"name": duplicate, "direction": "expense"},
                headers=identity.headers,
            )
            assert conflict.status_code == 409, (duplicate, conflict.text)
            assert conflict.json() == {"detail": {"code": "CATEGORY_NAME_TAKEN"}}

        # The same name in the other direction is legitimate.
        income = await client.post(
            "/api/v1/categories",
            json={"name": "Кофе", "direction": "income"},
            headers=identity.headers,
        )
        assert income.status_code == 201, income.text

        # --- an operation points at a category ------------------------------
        await _commit_operation(
            client,
            identity=identity,
            account_id=account_id,
            category_id=coffee_id,
            category_text="Кофе",
        )
        await projector.drain_pending()
        home = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home.status_code == 200, home.text
        assert home.json()["recentTransactions"][0]["category"] == "Кофе", home.text

        # --- renaming is what Home must follow ------------------------------
        renamed = await client.patch(
            f"/api/v1/categories/{coffee_id}",
            json={"name": "Кофе и чай"},
            headers=identity.headers,
        )
        assert renamed.status_code == 200, renamed.text
        assert renamed.json()["category"]["name"] == "Кофе и чай"
        assert "X-Category-Unchanged" not in renamed.headers

        await _assert_one_pending_rename(session_factory, category_id=coffee_id)
        await projector.drain_pending()
        home_after = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home_after.status_code == 200, home_after.text
        # The point of the slice: a report reads the link, so the rename shows.
        assert home_after.json()["recentTransactions"][0]["category"] == "Кофе и чай", (
            home_after.text
        )
        # And the operation's own text is untouched evidence of what was typed.
        async with session_factory() as database:
            stored_text = await database.scalar(
                select(FinanceOperationRow.category).where(
                    FinanceOperationRow.user_id == identity.user_id
                )
            )
        assert stored_text == "Кофе", stored_text

        # --- a repeated rename changes nothing and says so ------------------
        repeated = await client.patch(
            f"/api/v1/categories/{coffee_id}",
            json={"name": "Кофе и чай"},
            headers=identity.headers,
        )
        assert repeated.status_code == 200, repeated.text
        assert repeated.headers.get("X-Category-Unchanged") == "1"
        await _assert_audit_count(
            session_factory,
            category_id=coffee_id,
            event_type="category_renamed",
            expected=1,
        )

        # --- renaming a seeded category clears its key ----------------------
        seeded_id = UUID(
            next(
                item["categoryId"]
                for item in picker_body["categories"]
                if item["systemKey"] == "groceries"
            )
        )
        seeded_rename = await client.patch(
            f"/api/v1/categories/{seeded_id}",
            json={"name": "Еда"},
            headers=identity.headers,
        )
        assert seeded_rename.status_code == 200, seeded_rename.text
        # Once the user names it themselves, a translated label would
        # contradict them.
        assert seeded_rename.json()["category"]["systemKey"] is None

        # --- hiding is not deletion ----------------------------------------
        hidden = await client.post(
            f"/api/v1/categories/{coffee_id}/archive",
            headers=identity.headers,
        )
        assert hidden.status_code == 200, hidden.text
        assert hidden.json()["category"]["archivedAt"] is not None

        after_hide = await client.get(
            "/api/v1/categories",
            headers=identity.headers,
        )
        offered = {item["categoryId"] for item in after_hide.json()["categories"]}
        assert str(coffee_id) not in offered, after_hide.text
        managed_after = await client.get(
            "/api/v1/categories/managed",
            headers=identity.headers,
        )
        assert str(coffee_id) in {
            item["categoryId"] for item in managed_after.json()["categories"]
        }, managed_after.text

        async with session_factory() as database:
            still_linked = await database.scalar(
                select(func.count())
                .select_from(FinanceOperationRow)
                .where(FinanceOperationRow.category_id == coffee_id)
            )
        assert still_linked == 1, still_linked

        # A hidden category cannot be renamed: restoring it later could
        # resurrect a name collision the user cannot see.
        blocked = await client.patch(
            f"/api/v1/categories/{coffee_id}",
            json={"name": "Что-то ещё"},
            headers=identity.headers,
        )
        assert blocked.status_code == 409, blocked.text
        assert blocked.json() == {"detail": {"code": "CATEGORY_ARCHIVED"}}

        # Hiding it again is a no-op, not a failure.
        again = await client.post(
            f"/api/v1/categories/{coffee_id}/archive",
            headers=identity.headers,
        )
        assert again.status_code == 200, again.text
        assert again.headers.get("X-Category-Unchanged") == "1"

        # --- the freed name is reusable, and then blocks the restore --------
        reused = await client.post(
            "/api/v1/categories",
            json={"name": "Кофе и чай", "direction": "expense"},
            headers=identity.headers,
        )
        assert reused.status_code == 201, reused.text
        refused_restore = await client.post(
            f"/api/v1/categories/{coffee_id}/restore",
            headers=identity.headers,
        )
        assert refused_restore.status_code == 409, refused_restore.text
        assert refused_restore.json() == {"detail": {"code": "CATEGORY_NAME_TAKEN"}}

        # Free the name again and the restore succeeds.
        freed = await client.post(
            f"/api/v1/categories/{UUID(reused.json()['category']['categoryId'])}"
            "/archive",
            headers=identity.headers,
        )
        assert freed.status_code == 200, freed.text
        restored = await client.post(
            f"/api/v1/categories/{coffee_id}/restore",
            headers=identity.headers,
        )
        assert restored.status_code == 200, restored.text
        assert restored.json()["category"]["archivedAt"] is None

        # --- another user can never reach this catalogue --------------------
        stranger = await _register(
            client,
            email=f"stranger-{uuid4().hex[:12]}@example.com",
            name="Synthetic Stranger",
        )
        foreign = await client.patch(
            f"/api/v1/categories/{coffee_id}",
            json={"name": "Чужое"},
            headers=stranger.headers,
        )
        assert foreign.status_code == 404, foreign.text
        assert "Кофе" not in foreign.text

        missing = await client.post(
            f"/api/v1/categories/{uuid4()}/restore",
            headers=identity.headers,
        )
        assert missing.status_code == 404, missing.text

    await _assert_nothing_was_deleted(session_factory)
    await engine.dispose()


async def _assert_one_pending_rename(
    session_factory: AsyncSessionFactory,
    *,
    category_id: UUID,
) -> None:
    async with session_factory() as database:
        rows = (
            await database.scalars(
                select(FinanceCategoryOutboxEventRow).where(
                    FinanceCategoryOutboxEventRow.aggregate_id == category_id,
                    FinanceCategoryOutboxEventRow.published_at.is_(None),
                )
            )
        ).all()
    assert len(rows) == 1, len(rows)
    event = rows[0]
    assert event.event_type == "finance.category.renamed.v1", event.event_type
    # Identifier-only: a payload carrying the new name would let a replay write
    # a label the projector never read from the database.
    assert set(event.payload) == {
        "schemaVersion",
        "categoryId",
        "userId",
        "commandId",
    }, event.payload


async def _assert_audit_count(
    session_factory: AsyncSessionFactory,
    *,
    category_id: UUID,
    event_type: str,
    expected: int,
) -> None:
    async with session_factory() as database:
        count = await database.scalar(
            select(func.count())
            .select_from(FinanceCategoryAuditRow)
            .where(
                FinanceCategoryAuditRow.category_id == category_id,
                FinanceCategoryAuditRow.event_type == event_type,
            )
        )
    assert count == expected, (event_type, count)


async def _assert_nothing_was_deleted(
    session_factory: AsyncSessionFactory,
) -> None:
    """Removal is archiving, so every category ever created still exists."""

    async with session_factory() as database:
        total = await database.scalar(
            select(func.count()).select_from(FinanceCategoryRow)
        )
        archived = await database.scalar(
            select(func.count())
            .select_from(FinanceCategoryRow)
            .where(FinanceCategoryRow.archived_at.is_not(None))
        )
    # 16 seeded with the owner's account, plus the three they created. The
    # stranger never bootstrapped an account, and the starting set is written
    # with the account rather than at registration, so they own none.
    assert total == 19, total
    # Only the duplicate created to free a name stays hidden: the category an
    # operation points at was hidden and then restored, and neither step
    # removed a row.
    assert archived == 1, archived


def main() -> None:
    _empty_migration_round_trip()
    engine, session_factory = create_database(DATABASE_URL)
    asyncio.run(_scenario(engine, session_factory))
    _assert_lossy_downgrade_refused()
    print("category management PostgreSQL E2E passed")


if __name__ == "__main__":
    main()
