"""Opt-in PostgreSQL E2E for recurring planned costs (ADR 0025).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/planned_cost_recurrence_postgres_e2e.py

Not collected by pytest: `testpaths` only picks up `test_*.py`, so this stays
opt-in and never blocks CI, which provisions no database.

The claims that only a real database can settle:

- materialisation is idempotent because of a partial unique index, not because
  the generator is careful;
- a generated instance publishes an ordinary planned-cost invalidation, so Home
  redraws with no new event type;
- `skipped` is finally reachable and means something different from `cancelled`;
- ending a series withdraws untouched future instances and leaves acted-on ones
  exactly as they were;
- and a planned amount still never reaches the balance.
"""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    PlannedCostAuditRow,
    PlannedCostOutboxEventRow,
    PlannedCostRecurrenceAuditRow,
    PlannedCostRecurrenceRow,
    PlannedCostRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.planned_cost_core import PlannedCostCore
from mobile_finance_api.planned_cost_recurrence import clamp_day_into_month
from mobile_finance_api.planned_cost_recurrence_core import PlannedCostRecurrenceCore
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_projector import PostgresHomeProjector
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.postgres_planned_cost_recurrence_repository import (
    PostgresPlannedCostRecurrenceRepository,
)
from mobile_finance_api.postgres_planned_cost_repository import (
    PostgresPlannedCostRepository,
)
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-recurrence-secret-32-bytes-minimum"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
TIMEZONE = "Europe/Berlin"
OPENING_ON = (datetime.now(UTC) - timedelta(days=400)).date()
#: Anchored on the 31st on purpose: February is the case the whole design is
#: about, and a three-month horizon from any date crosses a short month often
#: enough that the assertions below stay meaningful all year.
ANCHOR_DAY = 31


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
    command.downgrade(config, "0014_operation_reversals")
    command.upgrade(config, "head")


def _assert_lossy_downgrade_refused() -> None:
    config = _alembic_config()
    try:
        command.downgrade(config, "0014_operation_reversals")
    except RuntimeError as error:
        assert "Refusing lossy downgrade" in str(error), str(error)
    else:
        raise AssertionError("downgrade past existing recurrence rules was allowed")


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):  # type: ignore[no-untyped-def]
    accounts = PostgresFinanceAccountRepository(session_factory=session_factory)
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
        ),
        planned_cost_core=PlannedCostCore(
            repository=PostgresPlannedCostRepository(session_factory=session_factory),
        ),
        planned_cost_recurrence_core=PlannedCostRecurrenceCore(
            repository=PostgresPlannedCostRecurrenceRepository(
                session_factory=session_factory,
            ),
        ),
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
    evaluated = evaluation.json()
    commit = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluated["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        },
        headers=identity.headers,
    )
    assert commit.status_code == 201, commit.text
    return UUID(commit.json()["account"]["accountId"])


def _rule_body(*, account_id: UUID, **changes: object) -> dict[str, object]:
    body: dict[str, object] = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "accountId": str(account_id),
        "amount": "800.00",
        "currency": "EUR",
        "title": "Аренда",
        "frequency": "monthly",
        "dayOfMonth": ANCHOR_DAY,
        "startsOn": (datetime.now(UTC) - timedelta(days=1)).date().isoformat(),
        "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    body.update(changes)
    return body


async def _count(session_factory: AsyncSessionFactory, statement: object) -> int:
    async with session_factory() as database:
        return int(await database.scalar(statement) or 0)


async def _exercise() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-test",
        audience="mfa-test-client",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    recurrences = PostgresPlannedCostRecurrenceRepository(
        session_factory=session_factory,
    )
    projector = PostgresHomeProjector(session_factory=session_factory)

    try:
        await _scenario(
            app=app,
            session_factory=session_factory,
            recurrences=recurrences,
            projector=projector,
        )
    finally:
        # Disposed on this loop: closing the pool from a second asyncio.run()
        # tears connections down against a loop that is already gone.
        await engine.dispose()


async def _scenario(
    *,
    app: object,
    session_factory: AsyncSessionFactory,
    recurrences: PostgresPlannedCostRecurrenceRepository,
    projector: PostgresHomeProjector,
) -> None:
    async with AsyncClient(
        transport=ASGITransport(app=app),  # type: ignore[arg-type]
        base_url="http://test",
    ) as client:
        identity = await _register(
            client,
            email=f"recurrence-{uuid4().hex}@example.com",
            name="Synthetic Owner",
        )
        account_id = await _bootstrap_account(client, identity=identity)

        # --- creating a rule materialises its own first instances -------------
        body = _rule_body(account_id=account_id)
        created = await client.post(
            "/api/v1/planned-cost-recurrences",
            json=body,
            headers=identity.headers,
        )
        assert created.status_code == 201, created.text
        payload = created.json()
        recurrence_id = UUID(payload["recurrence"]["recurrenceId"])
        occurrences = [datetime.fromisoformat(d).date() for d in payload["occurrences"]]
        assert occurrences, payload
        assert occurrences == sorted(occurrences)

        # Every date is the anchor clamped into its own month — the answer to
        # "the 31st of February" this ADR chose.
        for occurrence in occurrences:
            assert occurrence == clamp_day_into_month(
                year=occurrence.year,
                month=occurrence.month,
                day_of_month=ANCHOR_DAY,
            )
        # A short month proves the clamp actually fired rather than never being
        # asked; a three-month horizon does not always cross one, so this is
        # only asserted when it does.
        short_months = [o for o in occurrences if o.day < ANCHOR_DAY]
        for occurrence in short_months:
            assert occurrence.day in (28, 29, 30), occurrence

        instances = await _count(
            session_factory,
            select(func.count())
            .select_from(PlannedCostRow)
            .where(PlannedCostRow.recurrence_id == recurrence_id),
        )
        assert instances == len(occurrences), instances

        # The audit says a rule wrote these, not a person.
        generated_audit = await _count(
            session_factory,
            select(func.count())
            .select_from(PlannedCostAuditRow)
            .where(
                PlannedCostAuditRow.user_id == identity.user_id,
                PlannedCostAuditRow.actor_type == "recurrence",
                PlannedCostAuditRow.event_type == "planned_cost_created",
            ),
        )
        assert generated_audit == len(occurrences), generated_audit

        # --- replaying the exact command changes nothing ----------------------
        replayed = await client.post(
            "/api/v1/planned-cost-recurrences",
            json=body,
            headers=identity.headers,
        )
        assert replayed.status_code == 200, replayed.text
        assert replayed.json()["idempotentReplay"] is True

        # --- the same command id with different content is a conflict ---------
        conflicting = await client.post(
            "/api/v1/planned-cost-recurrences",
            json={**body, "amount": "900.00"},
            headers=identity.headers,
        )
        assert conflicting.status_code == 409, conflicting.text
        assert conflicting.json()["detail"]["code"] == "COMMAND_CONFLICT"

        # --- materialising again writes nothing -------------------------------
        # Not because the generator remembers: because the partial unique index
        # refuses a second live instance for a date the rule already covers.
        assert await recurrences.materialise_active_rules() == 0
        assert await recurrences.materialise_active_rules() == 0
        still = await _count(
            session_factory,
            select(func.count())
            .select_from(PlannedCostRow)
            .where(PlannedCostRow.recurrence_id == recurrence_id),
        )
        assert still == instances, (still, instances)

        # --- Home redraws from ordinary planned-cost invalidations ------------
        published = await projector.drain_available(max_candidates=50)
        assert published.failures_present is False, published
        dead = await _count(
            session_factory,
            select(func.count())
            .select_from(PlannedCostOutboxEventRow)
            .where(PlannedCostOutboxEventRow.dead_lettered_at.is_not(None)),
        )
        assert dead == 0, dead
        unpublished = await _count(
            session_factory,
            select(func.count())
            .select_from(PlannedCostOutboxEventRow)
            .where(PlannedCostOutboxEventRow.published_at.is_(None)),
        )
        assert unpublished == 0, unpublished

        home = await client.get(
            "/api/v2/home",
            params={"period": "current_month", "timezone": TIMEZONE},
            headers=identity.headers,
        )
        assert home.status_code == 200, home.text
        snapshot = home.json()
        # A forecast is not money that moved: the balance is still the opening
        # balance, and nothing the rule wrote reached a monthly total.
        assert Decimal(snapshot["balance"]["amount"]) == Decimal("1000.00")
        assert Decimal(snapshot["monthSummary"]["expense"]) == Decimal("0")
        assert Decimal(snapshot["monthSummary"]["netFlow"]) == Decimal("0")
        assert snapshot["upcomingPayments"], snapshot

        # --- skipping one instance, at last -----------------------------------
        # `skipped` has existed in the schema since ADR 0018 and has never been
        # reachable: without recurrence it means the same as `cancelled`.
        first_instance = await _first_planned_instance(
            session_factory,
            recurrence_id=recurrence_id,
        )
        skipped = await client.post(
            f"/api/v1/planned-costs/{first_instance}/transition",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "transition": "skip",
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert skipped.status_code == 200, skipped.text
        assert skipped.json()["plannedCost"]["status"] == "skipped"

        # Skipping one does not stop the series: the rule still fills that date
        # back in only when the horizon moves, never retroactively.
        assert await recurrences.materialise_active_rules() == 0

        # --- ending the series -------------------------------------------------
        ended = await client.post(
            f"/api/v1/planned-cost-recurrences/{recurrence_id}/end",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert ended.status_code == 200, ended.text
        end_payload = ended.json()
        assert end_payload["recurrence"]["status"] == "ended"
        assert end_payload["cancelledOccurrences"] >= 1, end_payload

        statuses = await _instance_statuses(
            session_factory,
            recurrence_id=recurrence_id,
        )
        # The skipped instance survives untouched: the user acted on it, and
        # ending a rule must not rewrite what already happened.
        assert statuses["skipped"] == 1, statuses
        assert statuses.get("cancelled", 0) == end_payload["cancelledOccurrences"]

        # --- an ended rule generates nothing ever again -------------------------
        assert await recurrences.materialise_active_rules() == 0
        again = await client.post(
            f"/api/v1/planned-cost-recurrences/{recurrence_id}/end",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=identity.headers,
        )
        assert again.status_code == 422, again.text
        assert again.json()["detail"]["issues"][0]["code"] == (
            "INVALID_LIFECYCLE_TRANSITION"
        )

        # --- another user can never see or end this rule ------------------------
        stranger = await _register(
            client,
            email=f"stranger-{uuid4().hex}@example.com",
            name="Synthetic Stranger",
        )
        listed = await client.get(
            "/api/v1/planned-cost-recurrences",
            headers=stranger.headers,
        )
        assert listed.status_code == 200, listed.text
        assert listed.json()["recurrences"] == []
        forbidden = await client.post(
            f"/api/v1/planned-cost-recurrences/{recurrence_id}/end",
            json={
                "schemaVersion": "1",
                "commandId": str(uuid4()),
                "requestedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            headers=stranger.headers,
        )
        assert forbidden.status_code == 404, forbidden.text

        rules = await _count(
            session_factory,
            select(func.count()).select_from(PlannedCostRecurrenceRow),
        )
        assert rules == 1, rules
        rule_audit = await _count(
            session_factory,
            select(func.count()).select_from(PlannedCostRecurrenceAuditRow),
        )
        assert rule_audit == 2, rule_audit


async def _first_planned_instance(
    session_factory: AsyncSessionFactory,
    *,
    recurrence_id: UUID,
) -> UUID:
    async with session_factory() as database:
        found = await database.scalar(
            select(PlannedCostRow.id)
            .where(
                PlannedCostRow.recurrence_id == recurrence_id,
                PlannedCostRow.status == "planned",
            )
            .order_by(PlannedCostRow.planned_on.asc())
        )
    assert found is not None
    return found


async def _instance_statuses(
    session_factory: AsyncSessionFactory,
    *,
    recurrence_id: UUID,
) -> dict[str, int]:
    async with session_factory() as database:
        rows = (
            await database.execute(
                select(PlannedCostRow.status, func.count())
                .where(PlannedCostRow.recurrence_id == recurrence_id)
                .group_by(PlannedCostRow.status)
            )
        ).all()
    return {status: int(count) for status, count in rows}


def main() -> int:
    _empty_migration_round_trip()
    asyncio.run(_exercise())
    _assert_lossy_downgrade_refused()
    print("planned cost recurrence PostgreSQL E2E passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
