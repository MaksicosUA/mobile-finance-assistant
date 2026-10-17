"""A person takes their data along, then erases it — against real PostgreSQL.

ADR 0030.

Opt-in, like the other PostgreSQL scripts. Migrates itself:

    MFA_TEST_DATABASE_URL=postgresql+asyncpg://... \
        python tests/account_data_postgres_e2e.py

It reuses the erasure E2E's fixture, which fills the owner's account through the
production wiring, and adds one removed operation so the spreadsheet has
something withdrawn to show. What only a real database can prove is checked
here: the queries run, padding from NUMERIC(38, 18) is gone, the correlated
"still counts" predicate does not turn into a cross join, and nothing of anyone
else's arrives.
"""

from __future__ import annotations

import asyncio
import csv
import io
import os
import re
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import account_admin_postgres_e2e as fixture
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, update

from mobile_finance_api.account_data import (
    DELETION_GRACE,
    EXPORTED_TABLES,
    OPERATIONS_CSV_COLUMNS,
    erase_due_accounts,
)
from mobile_finance_api.db_models import UserRow

OWNER = "owner-export-e2e@example.com"
OTHER = "other-export-e2e@example.com"

#: Eighteen digits of padding is what a NUMERIC(38, 18) column returns.
_PADDED = re.compile(r"^-?\d+\.\d*0{6,}$")


async def _expense_id(client: AsyncClient, token: str, *, account_id: str) -> str:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": "expense",
        "amount": "7.25",
        "currency": "EUR",
        "accountId": account_id,
        "category": "Synthetic withdrawn",
        "merchant": None,
        "capturedAt": fixture._now(),
        "capturedTimezone": fixture.TIMEZONE,
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": fixture._today(),
        "occurredAt": None,
        "source": "manual_text",
    }
    evaluation = await client.post(
        "/api/v1/operations/evaluate",
        json={"draft": draft},
        headers=fixture._bearer(token),
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/operations/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": fixture._now(),
        },
        headers=fixture._bearer(token),
    )
    assert commit.status_code == 201, commit.text
    return str(commit.json()["operation"]["operationId"])


def _keys(value: object) -> set[str]:
    if isinstance(value, dict):
        return set(value) | {key for item in value.values() for key in _keys(item)}
    if isinstance(value, list):
        return {key for item in value for key in _keys(item)}
    return set()


def _strings(value: object) -> list[str]:
    if isinstance(value, dict):
        return [text for item in value.values() for text in _strings(item)]
    if isinstance(value, list):
        return [text for item in value for text in _strings(item)]
    return [value] if isinstance(value, str) else []


async def main() -> None:
    from mobile_finance_api import runtime
    from mobile_finance_api.postgres_home_projector import PostgresHomeProjector

    session_factory = runtime.session_factory
    try:
        async with AsyncClient(
            transport=ASGITransport(app=runtime.app), base_url="http://export-e2e.test"
        ) as client:
            owner = await fixture._register(client, OWNER)
            other = await fixture._register(client, OTHER)
            await fixture._fill_owner(client, owner["access"])
            wallets = await client.get(
                "/api/v1/accounts", headers=fixture._bearer(owner["access"])
            )
            assert wallets.status_code == 200, wallets.text
            euro = next(
                wallet["accountId"]
                for wallet in wallets.json()["accounts"]
                if wallet["currency"] == "EUR"
            )
            withdrawn = await _expense_id(client, owner["access"], account_id=euro)
            removal = await client.post(
                "/api/v1/operations/removal",
                json={
                    "schemaVersion": "1",
                    "targetOperationId": withdrawn,
                    "commandId": str(uuid4()),
                    "confirmedAt": fixture._now(),
                },
                headers=fixture._bearer(owner["access"]),
            )
            assert removal.status_code in {200, 201}, removal.text

            other_wallet = await fixture._open_wallet(
                client, other["access"], currency="EUR", name="Other euro"
            )
            await fixture._record_expense(
                client, other["access"], account_id=other_wallet, currency="EUR"
            )
            await PostgresHomeProjector(session_factory=session_factory).drain_pending()

            # --- nothing without signing in ---------------------------------
            assert (await client.get("/api/v1/account/export")).status_code == 401

            # --- the JSON -----------------------------------------------------
            response = await client.get(
                "/api/v1/account/export", headers=fixture._bearer(owner["access"])
            )
            assert response.status_code == 200, response.text
            assert response.headers["cache-control"] == "no-store"
            document = response.json()
            tables = document["tables"]
            assert tuple(tables) == EXPORTED_TABLES

            assert [row["id"] for row in tables["users"]] == [owner["user_id"]]
            for name, rows in tables.items():
                owner_column = "id" if name == "users" else "user_id"
                assert all(row[owner_column] == owner["user_id"] for row in rows), name

            # The owner's facts, all of them, and the credential none of them.
            for name, at_least in {
                "finance_accounts": 2,
                "finance_operations": 2,
                "finance_operation_reversals": 1,
                "finance_transfers": 1,
                "finance_categories": 1,
                "finance_category_keywords": 1,
                "planned_costs": 1,
                "finance_goals": 1,
            }.items():
                assert len(tables[name]) >= at_least, (name, len(tables[name]))
            assert "password_hash" not in _keys(document)
            text = response.text
            assert "$argon2" not in text
            assert "Other euro" not in text
            assert other["user_id"] not in text

            padded = [value for value in _strings(document) if _PADDED.match(value)]
            assert padded == [], padded[:3]

            # --- the spreadsheet ---------------------------------------------
            sheet = await client.get(
                "/api/v1/account/export/operations.csv",
                headers=fixture._bearer(owner["access"]),
            )
            assert sheet.status_code == 200, sheet.text
            assert sheet.headers["content-type"].startswith("text/csv")
            body = sheet.content.decode("utf-8")
            assert body.startswith("﻿")
            rows = list(csv.reader(io.StringIO(body.removeprefix("﻿")), delimiter=";"))
            header, *operations = rows
            assert tuple(header) == OPERATIONS_CSV_COLUMNS
            assert len(operations) == len(tables["finance_operations"])
            status = {row[2]: row[7] for row in operations}
            # Exactly the removed one is withdrawn: an uncorrelated "still
            # counts" subquery would have marked every operation withdrawn.
            assert status == {"12,50": "active", "7,25": "withdrawn"}, status
            assert {row[4] for row in operations} == {"Synthetic euro"}
            assert "Other euro" not in body

            # --- and the stranger sees only their own -------------------------
            theirs = await client.get(
                "/api/v1/account/export", headers=fixture._bearer(other["access"])
            )
            assert theirs.status_code == 200, theirs.text
            assert "Synthetic euro" not in theirs.text
            assert owner["user_id"] not in theirs.text

            await _erasure_lifecycle(client, session_factory, owner=owner, other=other)
    finally:
        await runtime.engine.dispose()


async def _deletion(
    client: AsyncClient, token: str, password: str
) -> tuple[int, dict[str, object]]:
    response = await client.post(
        "/api/v1/account/deletion",
        json={"schemaVersion": "1", "password": password},
        headers=fixture._bearer(token),
    )
    return response.status_code, response.json()


async def _schedule(session_factory, user_id: str) -> tuple[object, object]:  # type: ignore[no-untyped-def]
    async with session_factory() as session:
        row = (
            await session.execute(
                select(UserRow.deletion_requested_at, UserRow.deletion_due_at).where(
                    UserRow.id == UUID(user_id)
                )
            )
        ).one()
    return row[0], row[1]


async def _erasure_lifecycle(  # type: ignore[no-untyped-def]
    client: AsyncClient,
    session_factory,
    *,
    owner: dict[str, str],
    other: dict[str, str],
) -> None:
    from mobile_finance_api.postgres_home_projector import PostgresHomeProjector

    # A wrong password changes nothing, and is 403 rather than 401 — a 401 would
    # sign the app out over a typo.
    status, body = await _deletion(client, owner["access"], "not-the-password")
    assert status == 403, body
    assert body == {"detail": {"code": "PASSWORD_REJECTED"}}
    assert (
        await client.get("/api/v1/profile", headers=fixture._bearer(owner["access"]))
    ).status_code == 200
    assert await _schedule(session_factory, owner["user_id"]) == (None, None)

    # The right one schedules erasure a week out ...
    before = datetime.now(UTC)
    status, body = await _deletion(client, owner["access"], fixture.PASSWORD)
    assert status == 202, body
    due = datetime.fromisoformat(str(body["deletionDueAt"]).replace("Z", "+00:00"))
    assert before + DELETION_GRACE <= due <= datetime.now(UTC) + DELETION_GRACE

    # ... and signs every device out at once: the access token and the refresh
    # token are both dead, because their session is gone.
    assert (
        await client.get("/api/v1/profile", headers=fixture._bearer(owner["access"]))
    ).status_code == 401
    refreshed = await client.post(
        "/api/v1/auth/refresh", json={"refreshToken": owner["refresh"]}
    )
    assert refreshed.status_code != 200, refreshed.text

    # Signing in within the week cancels it, and says so.
    status, body = await fixture._sign_in(client, OWNER)
    assert status == 200, body
    assert body["deletionCancelled"] is True
    assert await _schedule(session_factory, owner["user_id"]) == (None, None)
    status, body = await fixture._sign_in(client, OWNER)
    assert status == 200 and body["deletionCancelled"] is False, body

    # Asked again, and this time the week runs out.
    status, _ = await _deletion(client, str(body["accessToken"]), fixture.PASSWORD)
    assert status == 202
    now = datetime.now(UTC)
    async with session_factory() as session, session.begin():
        await session.execute(
            update(UserRow)
            .where(UserRow.id == UUID(owner["user_id"]))
            .values(
                deletion_requested_at=now - timedelta(days=8),
                deletion_due_at=now - timedelta(days=1),
            )
        )

    other_before = await fixture._counts(session_factory, other["user_id"])
    assert await erase_due_accounts(session_factory, now=now) == 1
    remaining = await fixture._counts(session_factory, owner["user_id"])
    assert sum(remaining.values()) == 0, {k: v for k, v in remaining.items() if v}
    async with session_factory() as session:
        assert (
            await session.scalar(
                select(UserRow.id).where(UserRow.id == UUID(owner["user_id"]))
            )
        ) is None
    # Nobody else lost a row, and a second sweep has nothing to do.
    assert await fixture._counts(session_factory, other["user_id"]) == other_before
    assert await erase_due_accounts(session_factory, now=now) == 0
    await PostgresHomeProjector(session_factory=session_factory).drain_pending()
    assert await fixture._dead_letters(session_factory) == 0
    status, _ = await fixture._sign_in(client, OWNER)
    assert status != 200

    # A pending request for the other account, left for the downgrade check.
    status, _ = await _deletion(client, other["access"], fixture.PASSWORD)
    assert status == 202


def _downgrade_refuses_a_pending_erasure() -> None:
    """Dropping the columns would silently cancel a request someone made."""

    config = Config(str(fixture.API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(fixture.API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", fixture.DATABASE_URL)
    try:
        command.downgrade(config, "0020_projection_per_wallet")
    except RuntimeError as error:
        assert "scheduled for erasure" in str(error)
    else:
        raise AssertionError("the downgrade dropped a pending erasure")

    async def cancel_all() -> None:
        from mobile_finance_api.database import create_database

        engine, session_factory = create_database(fixture.DATABASE_URL)
        try:
            async with session_factory() as session, session.begin():
                await session.execute(
                    update(UserRow).values(
                        deletion_requested_at=None, deletion_due_at=None
                    )
                )
        finally:
            await engine.dispose()

    asyncio.run(cancel_all())
    command.downgrade(config, "0020_projection_per_wallet")
    command.upgrade(config, "head")


if __name__ == "__main__":
    fixture._migrate()
    os.environ["MFA_AUTH_JWT_SECRET"] = "test-only-account-data-e2e-secret-32-bytes!"
    for name in (
        "MFA_AUTH_REGISTRATION_ALLOWLIST",
        "MFA_RELEASE_DIR",
        "MFA_APP_DOWNLOAD_LINK_SECRET",
    ):
        os.environ.pop(name, None)
    asyncio.run(main())
    # Outside the event loop: Alembic's environment starts one of its own.
    _downgrade_refuses_a_pending_erasure()
    print("account data PostgreSQL E2E: pass")
