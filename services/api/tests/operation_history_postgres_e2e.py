"""Opt-in PostgreSQL E2E for the operation history read (ADR 0020, step 4).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/operation_history_postgres_e2e.py

It is not collected by pytest: `testpaths` only picks up `test_*.py`, so this
script stays opt-in and never blocks CI, which provisions no database.

It proves what the in-memory fake cannot: that the keyset cursor walks every
row exactly once even when several share one date, that the join resolves a
category's current name while the operation keeps the text the user wrote, and
that an unlinked operation still appears in its own history.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

from httpx import ASGITransport, AsyncClient
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncEngine

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import FinanceOperationRow
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_category_repository import PostgresCategoryRepository
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-operation-history-secret-32-bytes"
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


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):
    accounts = PostgresFinanceAccountRepository(session_factory=session_factory)
    categories = PostgresCategoryRepository(session_factory=session_factory)
    operations = PostgresFinanceOperationRepository(session_factory=session_factory)
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
            repository=operations,
            account_directory=accounts,
            category_directory=categories,
        ),
        category_repository=categories,
        finance_operation_repository=operations,
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
        "openingBalance": "5000.00",
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
    occurred_on: date,
    amount: str,
    category_id: UUID | None,
    category_text: str | None,
) -> UUID:
    draft: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": "expense",
        "amount": amount,
        "currency": "EUR",
        "accountId": str(account_id),
        "category": category_text,
        "merchant": None,
        "capturedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "capturedTimezone": TIMEZONE,
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": occurred_on.isoformat(),
        "occurredAt": None,
        "source": "manual_text",
    }
    if category_id is not None:
        draft["categoryId"] = str(category_id)
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
    return UUID(commit.json()["operation"]["operationId"])


async def _walk_every_page(
    client: AsyncClient,
    *,
    identity: _Identity,
    limit: int,
) -> list[dict[str, object]]:
    collected: list[dict[str, object]] = []
    cursor: str | None = None
    for _ in range(20):
        params: dict[str, object] = {"limit": limit}
        if cursor is not None:
            params["cursor"] = cursor
        page = await client.get(
            "/api/v1/operations",
            params=params,
            headers=identity.headers,
        )
        assert page.status_code == 200, page.text
        body = page.json()
        assert len(body["operations"]) <= limit, body
        collected.extend(body["operations"])
        cursor = body["nextCursor"]
        if cursor is None:
            return collected
    raise AssertionError("paging did not terminate")


async def _scenario(engine: AsyncEngine, session_factory: AsyncSessionFactory) -> None:
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-test",
        audience="mfa-test-clients",
    )
    app = _application(session_factory=session_factory, tokens=tokens)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        identity = await _register(
            client,
            email=f"history-{uuid4().hex[:12]}@example.com",
            name="Synthetic Owner",
        )
        account_id = await _bootstrap_account(client, identity=identity)

        catalogue = await client.get("/api/v1/categories", headers=identity.headers)
        assert catalogue.status_code == 200, catalogue.text
        groceries = next(
            item
            for item in catalogue.json()["categories"]
            if item["systemKey"] == "groceries"
        )
        groceries_id = UUID(groceries["categoryId"])
        groceries_name = str(groceries["name"])

        today = datetime.now(UTC).date()
        # Three operations share one date on purpose: that is where an ordering
        # by date alone would repeat or skip a row while paging.
        same_day = today - timedelta(days=1)
        expected: list[UUID] = []
        for index in range(3):
            expected.append(
                await _commit_operation(
                    client,
                    identity=identity,
                    account_id=account_id,
                    occurred_on=same_day,
                    amount=f"{10 + index}.00",
                    category_id=groceries_id,
                    category_text=groceries_name,
                )
            )
        for offset in range(1, 5):
            expected.append(
                await _commit_operation(
                    client,
                    identity=identity,
                    account_id=account_id,
                    occurred_on=today - timedelta(days=offset + 1),
                    amount=f"{20 + offset}.00",
                    category_id=groceries_id,
                    category_text=groceries_name,
                )
            )
        # One recorded the way operations were before the catalogue: free text
        # and no link at all.
        unlinked = await _commit_operation(
            client,
            identity=identity,
            account_id=account_id,
            occurred_on=today,
            amount="99.00",
            category_id=None,
            category_text="Наличными",
        )
        expected.append(unlinked)

        # --- one page holds everything, newest first -----------------------
        everything = await client.get(
            "/api/v1/operations",
            params={"limit": 100},
            headers=identity.headers,
        )
        assert everything.status_code == 200, everything.text
        assert everything.json()["nextCursor"] is None, everything.text
        rows = everything.json()["operations"]
        assert len(rows) == len(expected), (len(rows), len(expected))
        dates = [item["occurredOn"] for item in rows]
        assert dates == sorted(dates, reverse=True), dates

        # --- paging covers every row exactly once --------------------------
        for limit in (1, 2, 3):
            walked = await _walk_every_page(client, identity=identity, limit=limit)
            identifiers = [item["operationId"] for item in walked]
            assert len(identifiers) == len(expected), (limit, len(identifiers))
            assert len(set(identifiers)) == len(expected), limit
            assert identifiers == [item["operationId"] for item in rows], (
                f"paging at limit {limit} changed the order"
            )

        # --- an unlinked operation is still its own history ----------------
        orphan = next(item for item in rows if item["operationId"] == str(unlinked))
        assert orphan["categoryId"] is None, orphan
        # With no link to follow, the text the user wrote is all there is.
        assert orphan["category"] == "Наличными", orphan
        assert orphan["categoryText"] == "Наличными", orphan

        # --- a rename moves the name but never the written text ------------
        renamed = await client.patch(
            f"/api/v1/categories/{groceries_id}",
            json={"name": "Еда и напитки"},
            headers=identity.headers,
        )
        assert renamed.status_code == 200, renamed.text
        after_rename = await client.get(
            "/api/v1/operations",
            params={"limit": 100},
            headers=identity.headers,
        )
        linked = [
            item
            for item in after_rename.json()["operations"]
            if item["categoryId"] == str(groceries_id)
        ]
        assert len(linked) == 7, len(linked)
        assert {item["category"] for item in linked} == {"Еда и напитки"}, linked
        # This is the pair the screen exists to show side by side.
        assert {item["categoryText"] for item in linked} == {groceries_name}, linked

        # --- hiding a category does not hide its operations ----------------
        hidden = await client.post(
            f"/api/v1/categories/{groceries_id}/archive",
            headers=identity.headers,
        )
        assert hidden.status_code == 200, hidden.text
        after_hide = await client.get(
            "/api/v1/operations",
            params={"limit": 100},
            headers=identity.headers,
        )
        still_named = [
            item
            for item in after_hide.json()["operations"]
            if item["categoryId"] == str(groceries_id)
        ]
        assert len(still_named) == 7, len(still_named)
        assert {item["category"] for item in still_named} == {"Еда и напитки"}

        # --- ordering is stable when created_at ties too -------------------
        await _force_identical_timestamps(session_factory, operation_ids=expected[:3])
        tied = await _walk_every_page(client, identity=identity, limit=1)
        tied_ids = [item["operationId"] for item in tied]
        assert len(tied_ids) == len(set(tied_ids)) == len(expected), tied_ids

        # --- another user sees none of it ----------------------------------
        stranger = await _register(
            client,
            email=f"stranger-{uuid4().hex[:12]}@example.com",
            name="Synthetic Stranger",
        )
        foreign = await client.get(
            "/api/v1/operations",
            params={"limit": 100},
            headers=stranger.headers,
        )
        assert foreign.status_code == 200, foreign.text
        assert foreign.json()["operations"] == [], foreign.text
        assert "Наличными" not in foreign.text

        # --- a forged cursor is refused ------------------------------------
        forged = await client.get(
            "/api/v1/operations",
            params={"cursor": "bm90LWEtY3Vyc29y"},
            headers=identity.headers,
        )
        assert forged.status_code == 400, forged.text
        assert forged.json()["detail"]["code"] == "MALFORMED_OPERATION"

    await engine.dispose()


async def _force_identical_timestamps(
    session_factory: AsyncSessionFactory,
    *,
    operation_ids: list[UUID],
) -> None:
    """Collapse `created_at` so only the identifier can break the tie.

    Three operations on one date, recorded in one transaction, would carry the
    same timestamp in production; forcing it here makes the last tiebreaker the
    only thing keeping the page boundary stable.
    """

    shared = datetime.now(UTC).replace(microsecond=0)
    async with session_factory() as database, database.begin():
        await database.execute(
            update(FinanceOperationRow)
            .where(FinanceOperationRow.id.in_(operation_ids))
            .values(created_at=shared)
        )


def main() -> None:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    from alembic import command
    from alembic.config import Config

    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    command.upgrade(config, "head")

    engine, session_factory = create_database(DATABASE_URL)
    asyncio.run(_scenario(engine, session_factory))
    print("operation history PostgreSQL E2E passed")


if __name__ == "__main__":
    main()
