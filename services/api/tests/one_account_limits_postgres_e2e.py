"""What one account can do to itself, and what it cannot do to anybody else.

Runs the production wiring from ``mobile_finance_api.runtime`` and migrates its
own database: point ``MFA_TEST_DATABASE_URL`` at an empty one.

The claims a real database has to settle:

- every list an account holds has an end, and reaching it is an ordinary refusal;
- a rule that fails to materialise costs only itself, and all of them are reached;
- a timezone correction refuses to date a baseline or a transfer in the future.
"""

from __future__ import annotations

import asyncio
import os
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
API_ROOT = Path(__file__).resolve().parents[1]
PASSWORD = "synthetic-password-123"
TIMEZONE = "Europe/Berlin"
AHEAD = "Pacific/Kiritimati"
BEHIND = "Pacific/Pago_Pago"


def _now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _today(zone: str = TIMEZONE) -> date:
    return datetime.now(ZoneInfo(zone)).date()


def _migrate() -> None:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    command.upgrade(config, "head")


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _register(client: AsyncClient) -> str:
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": f"limits-{uuid4().hex}@example.com",
            "password": PASSWORD,
            "displayName": "Synthetic",
        },
    )
    assert response.status_code == 201, response.text
    return str(response.json()["accessToken"])


async def _commit(
    client: AsyncClient,
    token: str,
    kind: str,
    draft: dict[str, object],
) -> object:
    evaluation = await client.post(
        f"/api/v1/{kind}/evaluate", json={"draft": draft}, headers=_bearer(token)
    )
    assert evaluation.status_code == 200, evaluation.text
    return await client.post(
        f"/api/v1/{kind}/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )


def _wallet(currency: str, *, on: date, zone: str) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": f"Synthetic {currency}",
        "currency": currency,
        "openingBalance": "1000.00",
        "openingBalanceOn": on.isoformat(),
        "canonicalTimezone": zone,
    }


async def _open(
    client: AsyncClient, token: str, currency: str, *, on: date, zone: str
) -> str:
    created = await _commit(
        client, token, "accounts", _wallet(currency, on=on, zone=zone)
    )
    assert created.status_code == 201, created.text  # type: ignore[attr-defined]
    return str(created.json()["account"]["accountId"])  # type: ignore[attr-defined]


async def _correct_timezone(
    client: AsyncClient, token: str, account_id: str, zone: str
):  # type: ignore[no-untyped-def]
    return await client.post(
        "/api/v1/accounts/timezone",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": account_id,
            "canonicalTimezone": zone,
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )


async def _limits(client: AsyncClient, modules: dict[str, object]) -> None:
    quotas = modules["quotas"]
    token = await _register(client)
    euro = await _open(client, token, "EUR", on=_today(), zone=TIMEZONE)

    # Written straight to the table: creating 500 plans over HTTP proves nothing
    # more than creating the one that is refused.
    plan = {
        "schemaVersion": "1",
        "accountId": euro,
        "amount": "1.00",
        "currency": "EUR",
        "title": "Synthetic plan",
        "plannedOn": (_today() + timedelta(days=5)).isoformat(),
        "requestedAt": _now(),
    }
    async with modules["session_factory"]() as database, database.begin():  # type: ignore[operator]
        await _fill_plans(
            database, modules, token_account=euro, how_many=quotas.MAX_OPEN_PLANS
        )  # type: ignore[attr-defined]
    refused = await client.post(
        "/api/v1/planned-costs",
        json={**plan, "commandId": str(uuid4())},
        headers=_bearer(token),
    )
    assert refused.status_code == 422, refused.text
    assert refused.json()["detail"]["code"] == "LIMIT_REACHED", refused.text

    # A limit is per account: somebody else writes as before.
    other = await _register(client)
    other_euro = await _open(client, other, "EUR", on=_today(), zone=TIMEZONE)
    allowed = await client.post(
        "/api/v1/planned-costs",
        json={**plan, "commandId": str(uuid4()), "accountId": other_euro},
        headers=_bearer(other),
    )
    assert allowed.status_code == 201, allowed.text


async def _fill_plans(database, modules, *, token_account: str, how_many: int) -> None:  # type: ignore[no-untyped-def]
    db_models = modules["db_models"]
    row = await database.scalar(
        select(db_models.FinanceAccountRow).where(
            db_models.FinanceAccountRow.id == token_account
        )
    )
    now = datetime.now(UTC)
    for _ in range(how_many):
        database.add(
            db_models.PlannedCostRow(
                id=uuid4(),
                user_id=row.user_id,
                account_id=row.id,
                command_id=uuid4(),
                command_payload_hash=os.urandom(32),
                schema_version="1",
                amount="1.00",
                currency="EUR",
                title="Synthetic plan",
                category=None,
                category_id=None,
                recurrence_id=None,
                planned_on=_today() + timedelta(days=5),
                status="planned",
                confirmed_operation_id=None,
                confirmed_operation_command_id=None,
                created_at=now,
                updated_at=now,
            )
        )


async def _wallet_limit(client: AsyncClient, modules: dict[str, object]) -> None:
    quotas = modules["quotas"]
    token = await _register(client)
    await _open(client, token, "EUR", on=_today(), zone=TIMEZONE)
    for _ in range(quotas.MAX_WALLETS - 1):  # type: ignore[attr-defined]
        await _open(client, token, "USD", on=_today(), zone=TIMEZONE)
    refused = await _commit(
        client, token, "accounts", _wallet("USD", on=_today(), zone=TIMEZONE)
    )
    assert refused.status_code == 422, refused.text  # type: ignore[attr-defined]
    assert refused.json()["detail"]["code"] == "LIMIT_REACHED"  # type: ignore[attr-defined]


async def _timezone(client: AsyncClient) -> None:
    # A baseline dated "today" far ahead of the new zone: a day that has not
    # happened there yet.
    token = await _register(client)
    baseline_today = _today(AHEAD)
    wallet = await _open(client, token, "EUR", on=baseline_today, zone=AHEAD)
    refused = await _correct_timezone(client, token, wallet, BEHIND)
    assert refused.status_code == 422, refused.text
    assert (
        refused.json()["detail"]["timezoneIssues"][0]["code"]
        == "TIMEZONE_BEHIND_RECORDED_OPERATIONS"
    ), refused.text

    # The same for a transfer dated today, with both baselines safely earlier.
    token = await _register(client)
    earlier = baseline_today - timedelta(days=30)
    euro = await _open(client, token, "EUR", on=earlier, zone=AHEAD)
    hryvnia = await _open(client, token, "UAH", on=earlier, zone=AHEAD)
    transfer = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "fromAccountId": euro,
        "fromAmount": "10.00",
        "fromCurrency": "EUR",
        "toAccountId": hryvnia,
        "toAmount": "480.00",
        "toCurrency": "UAH",
        "capturedAt": _now(),
        "capturedTimezone": AHEAD,
        "occurredOn": baseline_today.isoformat(),
    }
    moved = await _commit(client, token, "transfers", transfer)
    assert moved.status_code == 201, moved.text  # type: ignore[attr-defined]
    refused = await _correct_timezone(client, token, euro, BEHIND)
    assert refused.status_code == 422, refused.text
    assert (
        refused.json()["detail"]["timezoneIssues"][0]["code"]
        == "TIMEZONE_BEHIND_RECORDED_OPERATIONS"
    ), refused.text


async def _rules(client: AsyncClient, modules: dict[str, object]) -> None:
    db_models = modules["db_models"]
    session_factory = modules["session_factory"]
    recurrences = modules["recurrences"]

    async def rule(token: str, account_id: str, ends_on: str | None = None):  # type: ignore[no-untyped-def]
        created = await client.post(
            "/api/v1/planned-cost-recurrences",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "accountId": account_id,
                "amount": "10.00",
                "currency": "EUR",
                "title": "Synthetic rule",
                "frequency": "monthly",
                "dayOfMonth": 15,
                "startsOn": _today().isoformat(),
                "endsOn": ends_on,
                "requestedAt": _now(),
            },
            headers=_bearer(token),
        )
        assert created.status_code == 201, created.text
        return created.json()["recurrence"]["recurrenceId"]

    # Three accounts, and a page of one rule: every page has to be reached.
    tokens = [await _register(client) for _ in range(3)]
    ids = []
    for token in tokens:
        account = await _open(client, token, "EUR", on=_today(), zone=TIMEZONE)
        ids.append(await rule(token, account))

    async with session_factory() as database, database.begin():  # type: ignore[operator]
        before = await database.scalar(
            select(func.count()).select_from(db_models.PlannedCostRow)
        )
        # The newest instance of each rule goes, so a run has something to write.
        for rule_id in ids:
            newest = await database.scalar(
                select(db_models.PlannedCostRow)
                .where(db_models.PlannedCostRow.recurrence_id == rule_id)
                .order_by(db_models.PlannedCostRow.planned_on.desc())
                .limit(1)
            )
            await database.delete(newest)
    assert await recurrences.materialise_active_rules(limit=1) == 3  # type: ignore[attr-defined]
    async with session_factory() as database:  # type: ignore[operator]
        after = await database.scalar(
            select(func.count()).select_from(db_models.PlannedCostRow)
        )
    assert after == before


async def _exercise() -> None:
    from mobile_finance_api import db_models, quotas
    from mobile_finance_api.postgres_planned_cost_recurrence_repository import (
        PostgresPlannedCostRecurrenceRepository,
    )
    from mobile_finance_api.runtime import app, engine, session_factory

    modules: dict[str, object] = {
        "db_models": db_models,
        "quotas": quotas,
        "session_factory": session_factory,
        "recurrences": PostgresPlannedCostRecurrenceRepository(
            session_factory=session_factory
        ),
    }
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            await _limits(client, modules)
            await _wallet_limit(client, modules)
            await _timezone(client)
            await _rules(client, modules)
    finally:
        await engine.dispose()


def main() -> None:
    os.environ.setdefault(
        "MFA_AUTH_JWT_SECRET", "synthetic-limits-secret-of-32-bytes!!!!"
    )
    _migrate()
    asyncio.run(_exercise())
    print("one account limits E2E passed")


if __name__ == "__main__":
    main()
