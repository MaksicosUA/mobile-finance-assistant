"""A person takes their own data along, against a real PostgreSQL (ADR 0030).

Opt-in, like the other PostgreSQL scripts. Migrates itself:

    MFA_TEST_DATABASE_URL=postgresql+asyncpg://... python tests/account_data_postgres_e2e.py

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
from uuid import uuid4

import account_admin_postgres_e2e as fixture
from httpx import ASGITransport, AsyncClient

from mobile_finance_api.account_data import EXPORTED_TABLES, OPERATIONS_CSV_COLUMNS

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
    finally:
        await runtime.engine.dispose()

    print("account data PostgreSQL E2E: pass")


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
