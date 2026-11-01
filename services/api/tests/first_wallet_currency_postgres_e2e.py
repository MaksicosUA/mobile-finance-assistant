"""A whole profile whose default wallet is not euro (issue 0013).

Every wallet slice so far found its defects in somebody else's read path, and
only with a second wallet present. This walks each write and each read a person
reaches with a dollar wallet as their first and default one, and a euro wallet
beside it, so a leftover euro assumption has nowhere to hide.

Runs the production wiring from ``mobile_finance_api.runtime`` and migrates its
own database: point ``MFA_TEST_DATABASE_URL`` at an empty one.
"""

from __future__ import annotations

import asyncio
import json
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
TIMEZONE = "America/New_York"
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


def _operation(*, account_id: str, currency: str, amount: str) -> dict[str, object]:
    return {
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


async def _commit(
    client: AsyncClient, token: str, kind: str, draft: dict[str, object]
) -> dict[str, object]:
    evaluation = await client.post(
        f"/api/v1/{kind}/evaluate", json={"draft": draft}, headers=_bearer(token)
    )
    assert evaluation.status_code == 200, evaluation.text
    assert evaluation.json()["decision"] != "REJECT", evaluation.text
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
    body: dict[str, object] = commit.json()
    return body


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


async def _read_as_a_new_american(client: AsyncClient, token: str) -> None:
    profile = await client.get("/api/v1/profile", headers=_bearer(token))
    assert profile.status_code == 200, profile.text
    assert profile.json()["account"]["currency"] == "USD", profile.text


async def _sentences(client: AsyncClient, token: str) -> None:
    async def parsed(text: str, **extra: str) -> dict[str, object]:
        response = await client.post(
            "/api/v1/operations/parse",
            json={
                "text": text,
                "capturedAt": _now(),
                "capturedTimezone": TIMEZONE,
                **extra,
            },
            headers=_bearer(token),
        )
        assert response.status_code == 200, response.text
        proposal: dict[str, object] = response.json()["proposal"]
        return proposal

    # Nobody said a currency: the wallet being recorded into is the answer.
    silent = await parsed("coffee 50", accountCurrency="USD")
    assert (silent["amount"], silent["currency"]) == ("50", "USD"), silent
    # Somebody said one: what was said wins, and the client reports the mismatch.
    said = await parsed("coffee 50 euros", accountCurrency="USD")
    assert (said["amount"], said["currency"]) == ("50", "EUR"), said
    # An installed client names no wallet and reads exactly as it did.
    installed = await parsed("coffee 50")
    assert installed["currency"] == "EUR", installed


async def _home(client: AsyncClient, token: str) -> dict[str, object]:
    home = await client.get(
        f"/api/v2/home?period=current_month&timezone={quote(TIMEZONE, safe='')}",
        headers=_bearer(token),
    )
    assert home.status_code == 200, home.text
    body: dict[str, object] = home.json()
    return body


async def _scenario(client: AsyncClient, projector: object) -> None:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": f"dollar-{uuid4().hex}@example.com",
            "password": PASSWORD,
            "displayName": "Synthetic",
        },
        headers={"Accept-Language": "en-US"},
    )
    assert response.status_code == 201, response.text
    token = str(response.json()["accessToken"])

    # --- the first wallet settles the profile ------------------------------
    dollar = await _open_wallet(client, token, "USD")
    euro = await _open_wallet(client, token, "EUR")
    listed = await client.get("/api/v1/accounts", headers=_bearer(token))
    defaults = [item for item in listed.json()["accounts"] if item["isDefault"]]
    assert [item["currency"] for item in defaults] == ["USD"], listed.text
    await _read_as_a_new_american(client, token)
    await _sentences(client, token)

    categories = await client.get("/api/v1/categories", headers=_bearer(token))
    assert categories.status_code == 200, categories.text
    groceries = next(
        item
        for item in categories.json()["categories"]
        if item["direction"] == "expense"
    )

    # --- money in the default wallet ---------------------------------------
    kept = await _commit(
        client,
        token,
        "operations",
        {
            **_operation(account_id=dollar, currency="USD", amount="20.00"),
            "categoryId": groceries["categoryId"],
        },
    )
    corrected = await _commit(
        client,
        token,
        "operations",
        _operation(account_id=dollar, currency="USD", amount="7.00"),
    )
    removed = await _commit(
        client,
        token,
        "operations",
        _operation(account_id=dollar, currency="USD", amount="3.00"),
    )

    replacement = _operation(account_id=dollar, currency="USD", amount="5.00")
    evaluation = await client.post(
        "/api/v1/operations/evaluate",
        json={"draft": replacement},
        headers=_bearer(token),
    )
    assert evaluation.status_code == 200, evaluation.text
    correction = await client.post(
        "/api/v1/operations/correction",
        json={
            "schemaVersion": "1",
            "targetOperationId": corrected["operation"]["operationId"],  # type: ignore[index]
            "draft": replacement,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert correction.status_code == 201, correction.text
    removal = await client.post(
        "/api/v1/operations/removal",
        json={
            "schemaVersion": "1",
            "targetOperationId": removed["operation"]["operationId"],  # type: ignore[index]
            "commandId": str(uuid4()),
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert removal.status_code == 201, removal.text

    # --- a plan, a rule, a ceiling and a goal in dollars --------------------
    today = datetime.now(ZoneInfo(TIMEZONE)).date()
    plan = await client.post(
        "/api/v1/planned-costs",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": dollar,
            "amount": "30.00",
            "currency": "USD",
            "title": "Synthetic plan",
            "plannedOn": today.isoformat(),
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert plan.status_code == 201, plan.text
    rule = await client.post(
        "/api/v1/planned-cost-recurrences",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": dollar,
            "amount": "40.00",
            "currency": "USD",
            "title": "Synthetic rent",
            "frequency": "monthly",
            "dayOfMonth": 28,
            "startsOn": (today + timedelta(days=30)).isoformat(),
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert rule.status_code == 201, rule.text

    for category_id, limit in ((None, "500.00"), (groceries["categoryId"], "100.00")):
        ceiling = await client.put(
            "/api/v1/budgets",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "accountId": dollar,
                "categoryId": category_id,
                "limit": limit,
                "currency": "USD",
                "requestedAt": _now(),
            },
            headers=_bearer(token),
        )
        assert ceiling.status_code in (200, 201), ceiling.text

    goal = await client.post(
        "/api/v1/goals",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": dollar,
            "title": "Synthetic goal",
            "targetAmount": "3000.00",
            "currency": "USD",
            "targetOn": (today + timedelta(days=300)).isoformat(),
            "monthlyContribution": "250.00",
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert goal.status_code == 201, goal.text
    goal_id = goal.json()["goal"]["goalId"]
    for direction, amount in (("deposit", "60.00"), ("withdrawal", "10.00")):
        entry = await client.post(
            f"/api/v1/goals/{goal_id}/contributions",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "direction": direction,
                "amount": amount,
                "requestedAt": _now(),
            },
            headers=_bearer(token),
        )
        assert entry.status_code == 201, entry.text

    # A goal on the other wallet is that wallet's: it must neither stall the
    # projection nor take the primary slot from the default wallet's.
    other_goal = await client.post(
        "/api/v1/goals",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": euro,
            "title": "Synthetic euro goal",
            "targetAmount": "500.00",
            "currency": "EUR",
            "targetOn": (today + timedelta(days=30)).isoformat(),
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert other_goal.status_code == 201, other_goal.text

    # --- a transfer from the default wallet to euros ------------------------
    await _commit(
        client,
        token,
        "transfers",
        {
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "fromAccountId": dollar,
            "fromAmount": "100.00",
            "fromCurrency": "USD",
            "toAccountId": euro,
            "toAmount": "90.00",
            "toCurrency": "EUR",
            "capturedAt": _now(),
            "capturedTimezone": TIMEZONE,
            "occurredOn": _today(),
        },
    )

    # --- corrections to the account itself ----------------------------------
    baseline = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "accountId": dollar,
        "openingBalanceOn": (datetime.now(UTC) - timedelta(days=40)).date().isoformat(),
    }
    evaluation = await client.post(
        "/api/v1/accounts/baseline/evaluate",
        json={"draft": baseline},
        headers=_bearer(token),
    )
    assert evaluation.status_code == 200, evaluation.text
    moved = await client.post(
        "/api/v1/accounts/baseline/commit",
        json={
            "schemaVersion": "1",
            "draft": baseline,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert moved.status_code in (200, 201), moved.text

    # --- reports ---------------------------------------------------------
    spent = Decimal("25.00")
    await projector.drain_available(max_candidates=20)  # type: ignore[attr-defined]
    home = await _home(client, token)
    closing = OPENING - spent - Decimal("100.00")
    assert home["baseCurrency"] == "USD", home
    balance = home["balance"]
    assert Decimal(balance["amount"]) == closing, balance  # type: ignore[index]
    wallets = {item["currency"]: item for item in home["wallets"]}  # type: ignore[attr-defined]
    assert Decimal(wallets["USD"]["balance"]) == closing, wallets
    assert Decimal(wallets["EUR"]["balance"]) == OPENING + Decimal("90.00"), wallets
    assert wallets["USD"]["isDefault"] is True, wallets
    assert home["primaryGoal"]["currency"] == "USD", home  # type: ignore[index]
    payments = home["upcomingPayments"]
    assert {item["currency"] for item in payments} == {"USD"}, payments  # type: ignore[attr-defined]

    legacy = await client.get(
        f"/api/v1/analytics?timezone={quote(TIMEZONE, safe='')}",
        headers=_bearer(token),
    )
    assert legacy.status_code == 200, legacy.text
    assert legacy.json()["baseCurrency"] == "USD", legacy.text
    assert Decimal(legacy.json()["totals"]["expense"]) == spent, legacy.text

    for query in ("", f"&accountId={dollar}"):
        report = await client.get(
            f"/api/v1/analytics/v2?period=month{query}", headers=_bearer(token)
        )
        assert report.status_code == 200, report.text
        assert report.json()["baseCurrency"] == "USD", report.text
        assert Decimal(report.json()["balance"]["closing"]) == closing, report.text

    budgets = await client.get("/api/v1/budgets", headers=_bearer(token))
    assert budgets.status_code == 200, budgets.text
    assert budgets.json()["currency"] == "USD", budgets.text
    overall = budgets.json()["overall"]
    assert Decimal(overall["spent"]) == spent, overall
    assert Decimal(overall["planned"]) == Decimal("30.00"), overall
    lines = budgets.json()["categories"]
    assert [Decimal(line["spent"]) for line in lines] == [Decimal("20.00")], lines

    goals = await client.get("/api/v1/goals", headers=_bearer(token))
    assert goals.status_code == 200, goals.text
    amounts = {item["goalId"]: item["currentAmount"] for item in goals.json()["goals"]}
    assert Decimal(amounts[goal_id]) == Decimal("50.00"), amounts

    history = await client.get("/api/v1/operations", headers=_bearer(token))
    assert history.status_code == 200, history.text
    assert {item["currency"] for item in history.json()["operations"]} == {"USD"}
    assert kept["operation"]["operationId"] in {  # type: ignore[index]
        item["operationId"] for item in history.json()["operations"]
    }

    export = await client.get("/api/v1/account/export", headers=_bearer(token))
    assert export.status_code == 200, export.text
    exported = json.dumps(export.json())
    assert '"USD"' in exported, exported[:200]
    table = await client.get(
        "/api/v1/account/export/operations.csv", headers=_bearer(token)
    )
    assert table.status_code == 200, table.text
    assert "USD" in table.text, table.text[:200]

    # --- a timezone correction moves both wallets, the default not first ----
    moved_zone = await client.post(
        "/api/v1/accounts/timezone",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": euro,
            "canonicalTimezone": "America/Chicago",
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert moved_zone.status_code == 200, moved_zone.text
    await projector.drain_available(max_candidates=20)  # type: ignore[attr-defined]
    await _read_as_a_new_american(client, token)


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
        "MFA_AUTH_JWT_SECRET", "synthetic-first-wallet-secret-32-bytes!!!"
    )
    _migrate()
    asyncio.run(_exercise())
    print("first wallet currency E2E passed")


if __name__ == "__main__":
    main()
