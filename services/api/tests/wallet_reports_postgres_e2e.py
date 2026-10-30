"""What each report says when a person holds more than one wallet (ADR 0029).

A wallet's figures are its own. Nothing here is visible to the unit suite: the
filters under test are SQL, and every one of them looks right with one wallet.

Runs the production wiring from ``mobile_finance_api.runtime`` and migrates its
own database: point ``MFA_TEST_DATABASE_URL`` at an empty one.
"""

from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from urllib.parse import quote
from uuid import uuid4
from zoneinfo import ZoneInfo

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
API_ROOT = Path(__file__).resolve().parents[1]
TIMEZONE = "Europe/Berlin"
PASSWORD = "synthetic-password-123"
OPENING = Decimal("1000.00")


def _now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _today() -> str:
    return datetime.now(ZoneInfo(TIMEZONE)).date().isoformat()


def _migrate() -> None:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    command.upgrade(config, "head")


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _commit(
    client: AsyncClient, token: str, kind: str, draft: dict[str, object]
) -> None:
    evaluation = await client.post(
        f"/api/v1/{kind}/evaluate", json={"draft": draft}, headers=_bearer(token)
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        f"/api/v1/{kind}/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert commit.status_code == 201, commit.text


async def _open_wallet(client: AsyncClient, token: str, currency: str) -> str:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": f"Synthetic {currency}",
        "currency": currency,
        "openingBalance": str(OPENING),
        "openingBalanceOn": (datetime.now(UTC) - timedelta(days=10)).date().isoformat(),
        "canonicalTimezone": TIMEZONE,
    }
    await _commit(client, token, "accounts", draft)
    listed = await client.get("/api/v1/accounts", headers=_bearer(token))
    assert listed.status_code == 200, listed.text
    return next(
        str(item["accountId"])
        for item in listed.json()["accounts"]
        if item["currency"] == currency
    )


async def _expense(
    client: AsyncClient, token: str, *, account_id: str, currency: str, amount: str
) -> None:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": "expense",
        "amount": amount,
        "currency": currency,
        "accountId": account_id,
        "category": "Synthetic category",
        "merchant": "Synthetic merchant",
        "capturedAt": _now(),
        "capturedTimezone": TIMEZONE,
        "sourceExpression": None,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": _today(),
        "occurredAt": None,
        "source": "manual_text",
    }
    await _commit(client, token, "operations", draft)


async def _transfer(
    client: AsyncClient, token: str, *, euro: str, hryvnia: str
) -> None:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "fromAccountId": euro,
        "fromAmount": "100.00",
        "fromCurrency": "EUR",
        "toAccountId": hryvnia,
        "toAmount": "4800.00",
        "toCurrency": "UAH",
        "capturedAt": _now(),
        "capturedTimezone": TIMEZONE,
        "occurredOn": _today(),
    }
    await _commit(client, token, "transfers", draft)


async def _plan(
    client: AsyncClient, token: str, *, account_id: str, currency: str, amount: str
) -> None:
    # The last day of this month: a budget reads plans inside the month.
    today = datetime.now(ZoneInfo(TIMEZONE)).date()
    plan = await client.post(
        "/api/v1/planned-costs",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": account_id,
            "amount": amount,
            "currency": currency,
            "title": "Synthetic plan",
            "plannedOn": today.isoformat(),
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert plan.status_code == 201, plan.text


async def _scenario(client: AsyncClient, projector: object) -> None:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": f"wallets-{uuid4().hex}@example.com",
            "password": PASSWORD,
            "displayName": "Synthetic",
        },
    )
    assert response.status_code == 201, response.text
    token = str(response.json()["accessToken"])

    euro = await _open_wallet(client, token, "EUR")
    hryvnia = await _open_wallet(client, token, "UAH")

    ceiling = await client.put(
        "/api/v1/budgets",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": euro,
            "categoryId": None,
            "limit": "500.00",
            "currency": "EUR",
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert ceiling.status_code in (200, 201), ceiling.text

    await _expense(client, token, account_id=euro, currency="EUR", amount="20.00")
    await _expense(client, token, account_id=hryvnia, currency="UAH", amount="5200.00")
    await _plan(client, token, account_id=euro, currency="EUR", amount="30.00")
    await _plan(client, token, account_id=hryvnia, currency="UAH", amount="7000.00")
    await _transfer(client, token, euro=euro, hryvnia=hryvnia)

    # --- a ceiling in euros counts euros ----------------------------------
    budgets = await client.get("/api/v1/budgets", headers=_bearer(token))
    assert budgets.status_code == 200, budgets.text
    overall = budgets.json()["overall"]
    assert Decimal(overall["spent"]) == Decimal("20.00"), overall
    assert Decimal(overall["planned"]) == Decimal("30.00"), overall

    # --- the balance line and Home agree, for each wallet ------------------
    await projector.drain_available(max_candidates=10)  # type: ignore[attr-defined]
    home = await client.get(
        f"/api/v2/home?period=current_month&timezone={quote(TIMEZONE, safe='')}",
        headers=_bearer(token),
    )
    assert home.status_code == 200, home.text
    wallets = {item["accountId"]: item for item in home.json()["wallets"]}

    expected = {
        euro: OPENING - Decimal("20.00") - Decimal("100.00"),
        hryvnia: OPENING - Decimal("5200.00") + Decimal("4800.00"),
    }
    for account_id, closing in expected.items():
        report = await client.get(
            f"/api/v1/analytics/v2?period=month&accountId={account_id}",
            headers=_bearer(token),
        )
        assert report.status_code == 200, report.text
        line = report.json()["balance"]
        assert Decimal(line["closing"]) == closing, (account_id, line)
        assert Decimal(line["points"][-1]["amount"]) == closing, (account_id, line)
        assert Decimal(wallets[account_id]["balance"]) == closing

    # A transfer stays out of the month: only the expense counts.
    report = await client.get(
        f"/api/v1/analytics/v2?period=month&accountId={euro}",
        headers=_bearer(token),
    )
    totals = report.json()["totals"]
    assert Decimal(totals["expense"]) == Decimal("20.00"), totals
    assert Decimal(totals["income"]) == Decimal(0), totals


async def _exercise() -> None:
    from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
    from mobile_finance_api.runtime import app, engine, session_factory

    projector = PostgresHomeProjector(session_factory=session_factory)
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            await _scenario(client, projector)
    finally:
        await engine.dispose()


def main() -> None:
    os.environ.setdefault(
        "MFA_AUTH_JWT_SECRET", "synthetic-wallet-reports-secret-32-bytes!"
    )
    _migrate()
    asyncio.run(_exercise())
    print("wallet reports E2E passed")


if __name__ == "__main__":
    main()
