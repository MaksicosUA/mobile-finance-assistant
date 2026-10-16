"""Blocking and erasing an account against a real PostgreSQL (ADR 0024).

Runs the production wiring from ``mobile_finance_api.runtime``, so every core
that writes a user's rows is the one that ships. Migrates its own database:
point ``MFA_TEST_DATABASE_URL`` at an empty one.
"""

from __future__ import annotations

import asyncio
import io
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
API_ROOT = Path(__file__).resolve().parents[1]
TIMEZONE = "Europe/Berlin"
PASSWORD = "synthetic-password-123"
OWNER = "owner-admin-e2e@example.com"
OTHER = "other-admin-e2e@example.com"
_FILLED_BY_FIXTURE = {
    "auth_sessions",
    "finance_account_audit_events",
    "finance_account_outbox_events",
    "finance_accounts",
    "finance_categories",
    "finance_category_keywords",
    "finance_goal_audit_events",
    "finance_goal_outbox_events",
    "finance_goals",
    "finance_operation_audit_events",
    "finance_operations",
    "finance_transfer_audit_events",
    "finance_transfer_outbox_events",
    "finance_transfers",
    "home_projection_snapshots",
    "planned_cost_audit_events",
    "planned_cost_outbox_events",
    "planned_costs",
}


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


async def _register(client: AsyncClient, email: str) -> dict[str, str]:
    response = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": PASSWORD, "displayName": "Synthetic"},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    return {
        "user_id": str(body["user"]["id"]),
        "access": str(body["accessToken"]),
        "refresh": str(body["refreshToken"]),
    }


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _open_wallet(
    client: AsyncClient, token: str, *, currency: str, name: str
) -> str:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": name,
        "currency": currency,
        "openingBalance": "1000.00",
        "openingBalanceOn": (datetime.now(UTC) - timedelta(days=10)).date().isoformat(),
        "canonicalTimezone": TIMEZONE,
    }
    evaluation = await client.post(
        "/api/v1/accounts/evaluate", json={"draft": draft}, headers=_bearer(token)
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert commit.status_code == 201, commit.text
    return str(commit.json()["account"]["accountId"])


async def _record_expense(
    client: AsyncClient, token: str, *, account_id: str, currency: str
) -> None:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "type": "expense",
        "amount": "12.50",
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
    evaluation = await client.post(
        "/api/v1/operations/evaluate", json={"draft": draft}, headers=_bearer(token)
    )
    assert evaluation.status_code == 200, evaluation.text
    assert evaluation.json()["issues"] == [], evaluation.text
    commit = await client.post(
        "/api/v1/operations/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert commit.status_code == 201, commit.text


async def _fill_owner(client: AsyncClient, token: str) -> None:
    euro = await _open_wallet(client, token, currency="EUR", name="Synthetic euro")
    hryvnia = await _open_wallet(
        client, token, currency="UAH", name="Synthetic hryvnia"
    )
    await _record_expense(client, token, account_id=euro, currency="EUR")

    future = (datetime.now(UTC) + timedelta(days=30)).date().isoformat()
    plan = await client.post(
        "/api/v1/planned-costs",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": euro,
            "amount": "80.00",
            "currency": "EUR",
            "title": "Synthetic plan",
            "plannedOn": future,
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert plan.status_code == 201, plan.text

    goal = await client.post(
        "/api/v1/goals",
        json={
            "schemaVersion": "1",
            "commandId": str(uuid4()),
            "accountId": euro,
            "title": "Synthetic goal",
            "targetAmount": "3000.00",
            "currency": "EUR",
            "targetOn": (datetime.now(UTC) + timedelta(days=365)).date().isoformat(),
            "monthlyContribution": "250.00",
            "requestedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert goal.status_code == 201, goal.text

    transfer = {
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
    evaluation = await client.post(
        "/api/v1/transfers/evaluate", json={"draft": transfer}, headers=_bearer(token)
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/transfers/commit",
        json={
            "schemaVersion": "1",
            "draft": transfer,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": _now(),
        },
        headers=_bearer(token),
    )
    assert commit.status_code == 201, commit.text


async def _counts(session_factory, user_id: str) -> dict[str, int]:  # type: ignore[no-untyped-def]
    from mobile_finance_api.account_data import user_tables

    counts: dict[str, int] = {}
    async with session_factory() as session:
        for table in user_tables():
            counts[table.name] = int(
                await session.scalar(
                    select(func.count())
                    .select_from(table)
                    .where(table.c.user_id == UUID(user_id))
                )
                or 0
            )
    return counts


def _without_sessions(counts: dict[str, int]) -> dict[str, int]:
    return {name: count for name, count in counts.items() if name != "auth_sessions"}


async def _dead_letters(session_factory) -> int:  # type: ignore[no-untyped-def]
    from mobile_finance_api.db_models import Base

    total = 0
    async with session_factory() as session:
        for table in Base.metadata.sorted_tables:
            if "dead_lettered_at" in table.c:
                total += int(
                    await session.scalar(
                        select(func.count())
                        .select_from(table)
                        .where(table.c.dead_lettered_at.is_not(None))
                    )
                    or 0
                )
    return total


async def _admin(  # type: ignore[no-untyped-def]
    session_factory, *argv: str, password: str | None = None
) -> tuple[int, str, str]:
    from mobile_finance_api import account_admin

    out, err = io.StringIO(), io.StringIO()
    args = account_admin.parse_arguments(list(argv))
    if password is not None:
        # What main() does after reading the hidden prompt.
        args.password = password
    code = await account_admin.execute(
        args,
        session_factory=session_factory,
        out=out,
        err=err,
        now=datetime.now(UTC),
    )
    return code, out.getvalue(), err.getvalue()


async def _sign_in(client: AsyncClient, email: str) -> tuple[int, dict[str, object]]:
    response = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": PASSWORD}
    )
    return response.status_code, response.json()


async def main() -> None:
    from mobile_finance_api import runtime
    from mobile_finance_api.postgres_home_projector import PostgresHomeProjector

    session_factory = runtime.session_factory
    try:
        async with AsyncClient(
            transport=ASGITransport(app=runtime.app), base_url="http://admin-e2e.test"
        ) as client:
            owner = await _register(client, OWNER)
            other = await _register(client, OTHER)
            await _fill_owner(client, owner["access"])
            other_wallet = await _open_wallet(
                client, other["access"], currency="EUR", name="Other euro"
            )
            await _record_expense(
                client, other["access"], account_id=other_wallet, currency="EUR"
            )
            await PostgresHomeProjector(session_factory=session_factory).drain_pending()

            owner_before = await _counts(session_factory, owner["user_id"])
            other_before = await _counts(session_factory, other["user_id"])
            filled = {name for name, count in owner_before.items() if count}
            assert owner_before["finance_accounts"] == 2, owner_before
            assert owner_before["finance_transfers"] == 1, owner_before
            assert owner_before["planned_costs"] == 1, owner_before
            assert owner_before["finance_goals"] == 1, owner_before
            assert owner_before["home_projection_snapshots"] >= 2, owner_before
            # Every table the fixture writes to, so the erasure below is proved
            # against real rows in each; the schema test covers the others.
            assert filled == _FILLED_BY_FIXTURE, sorted(filled)

            # --- list -----------------------------------------------------------
            code, out, _ = await _admin(session_factory, "list")
            assert code == 0
            assert OWNER in out and OTHER in out and "2 account(s)" in out, out

            # --- block ----------------------------------------------------------
            code, out, _ = await _admin(session_factory, "block", OWNER.upper())
            assert code == 0 and "blocked" in out, out
            status, body = await _sign_in(client, OWNER)
            assert status != 200 and "accessToken" not in body, (status, body)
            profile = await client.get(
                "/api/v1/profile", headers=_bearer(owner["access"])
            )
            assert profile.status_code == 401, profile.text
            refresh = await client.post(
                "/api/v1/auth/refresh", json={"refreshToken": owner["refresh"]}
            )
            assert refresh.status_code != 200, refresh.text
            unaffected = await client.get(
                "/api/v1/profile", headers=_bearer(other["access"])
            )
            assert unaffected.status_code == 200, unaffected.text
            code, out, _ = await _admin(session_factory, "block", OWNER)
            assert code == 0 and "already blocked" in out, out
            # Blocking removed nothing.
            assert await _counts(session_factory, owner["user_id"]) == owner_before

            # --- unblock --------------------------------------------------------
            code, out, _ = await _admin(session_factory, "unblock", OWNER)
            assert code == 0 and "active" in out, out
            status, body = await _sign_in(client, OWNER)
            assert status == 200 and "accessToken" in body, (status, body)

            # --- set a password -----------------------------------------------
            status, signed_in = await _sign_in(client, OWNER)
            assert status == 200, signed_in
            live_refresh = str(signed_in["refreshToken"])
            new_password = "synthetic-reset-password-42"
            code, out, _ = await _admin(
                session_factory, "set-password", OWNER, password=new_password
            )
            assert code == 0 and "session(s) signed out" in out, out
            # Every device is out: the refresh token went with its session.
            revoked = await client.post(
                "/api/v1/auth/refresh", json={"refreshToken": live_refresh}
            )
            assert revoked.status_code != 200, revoked.text
            status, _ = await _sign_in(client, OWNER)
            assert status != 200, "the old password still signs in"
            renewed = await client.post(
                "/api/v1/auth/login",
                json={"email": OWNER, "password": new_password},
            )
            assert renewed.status_code == 200, renewed.text
            assert "accessToken" in renewed.json()
            code, _, _ = await _admin(
                session_factory,
                "set-password",
                "nobody-admin-e2e@example.com",
                password=new_password,
            )
            assert code == 1
            untouched = await client.get(
                "/api/v1/profile", headers=_bearer(other["access"])
            )
            assert untouched.status_code == 200, untouched.text

            # --- erasure refusals -----------------------------------------------
            code, _, err = await _admin(
                session_factory, "delete", OWNER, "--confirm", OTHER
            )
            assert code == 2 and "Nothing was touched" in err, err
            code, _, _ = await _admin(
                session_factory,
                "delete",
                "nobody-admin-e2e@example.com",
                "--confirm",
                "nobody-admin-e2e@example.com",
            )
            assert code == 1
            after_refusals = await _counts(session_factory, owner["user_id"])
            # Sign-in above added a session; nothing else may have moved.
            assert _without_sessions(after_refusals) == _without_sessions(owner_before)

            # --- erasure --------------------------------------------------------
            code, out, err = await _admin(
                session_factory, "delete", OWNER, "--confirm", f"  {OWNER.upper()} "
            )
            assert code == 0, err
            assert "erased" in out, out

            owner_after = await _counts(session_factory, owner["user_id"])
            assert all(count == 0 for count in owner_after.values()), owner_after
            async with session_factory() as session:
                from mobile_finance_api.db_models import UserRow

                assert (
                    await session.scalar(
                        select(func.count())
                        .select_from(UserRow)
                        .where(UserRow.id == UUID(owner["user_id"]))
                    )
                ) == 0
            assert await _counts(session_factory, other["user_id"]) == other_before
            still_fine = await client.get(
                "/api/v1/profile", headers=_bearer(other["access"])
            )
            assert still_fine.status_code == 200, still_fine.text

            # The projector must not trip over a user that no longer exists.
            await PostgresHomeProjector(session_factory=session_factory).drain_pending()
            assert await _dead_letters(session_factory) == 0

            # Erasure frees the address.
            status, _ = await _sign_in(client, OWNER)
            assert status != 200
            again = await _register(client, OWNER)
            assert again["user_id"] != owner["user_id"]
    finally:
        await runtime.engine.dispose()

    print("account admin PostgreSQL E2E: pass")


if __name__ == "__main__":
    _migrate()
    os.environ["MFA_AUTH_JWT_SECRET"] = "test-only-account-admin-e2e-secret-32-bytes"
    for name in (
        "MFA_AUTH_REGISTRATION_ALLOWLIST",
        "MFA_RELEASE_DIR",
        "MFA_APP_DOWNLOAD_LINK_SECRET",
    ):
        os.environ.pop(name, None)
    asyncio.run(main())
