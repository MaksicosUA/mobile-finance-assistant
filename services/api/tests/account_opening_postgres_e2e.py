from __future__ import annotations

import asyncio
import calendar
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncEngine

from mobile_finance_api.account_contracts import AccountDraft, account_draft_hash
from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceAccountAuditRow,
    FinanceAccountOutboxEventRow,
    FinanceAccountRow,
    HomeProjectionSnapshotRow,
    UserRow,
)
from mobile_finance_api.finance_core import FinanceCore
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.postgres_home_repository import PostgresHomeRepository
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-account-opening-secret-32-bytes-minimum"
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
OPENING_ON = (datetime.now(UTC) - timedelta(days=10)).date().isoformat()


@dataclass(frozen=True, slots=True)
class _Identity:
    user_id: UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


def _account_draft(
    *,
    command_id: str = "11111111-1111-4111-8111-111111111111",
    name: str = "Synthetic primary account",
) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "commandId": command_id,
        "name": name,
        "currency": "EUR",
        "openingBalance": "-125.50",
        "openingBalanceOn": OPENING_ON,
        "canonicalTimezone": "Europe/Berlin",
    }


def _account_commit(
    *,
    draft: dict[str, object],
    draft_hash: str,
    confirmed_at: str,
) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "draft": draft,
        "draftHash": draft_hash,
        "confirmedAt": confirmed_at,
    }


def _alembic_config() -> Config:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    return config


def _empty_migration_round_trip() -> None:
    config = _alembic_config()
    command.upgrade(config, "head")
    command.downgrade(config, "0003_finance_operations")
    command.upgrade(config, "head")


async def _register(
    client: AsyncClient,
    *,
    email: str,
    name: str,
) -> _Identity:
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


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):
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
    )


async def _bootstrap_account(
    client: AsyncClient,
    *,
    identity: _Identity,
    draft: dict[str, object],
    confirmed_at: str,
) -> tuple[dict[str, object], dict[str, object]]:
    evaluation = await client.post(
        "/api/v1/accounts/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    evaluated = evaluation.json()
    assert evaluated["decision"] == "NEEDS_CONFIRMATION"
    assert evaluated["issues"] == []
    commit_body = _account_commit(
        draft=draft,
        draft_hash=str(evaluated["draftHash"]),
        confirmed_at=confirmed_at,
    )
    response = await client.post(
        "/api/v1/accounts/commit",
        json=commit_body,
        headers=identity.headers,
    )
    assert response.status_code == 201, response.text
    return response.json(), commit_body


async def _seed_stale_current_home_snapshot(
    *,
    session_factory: AsyncSessionFactory,
    user_id: UUID,
) -> None:
    generated_at = datetime.now(UTC) - timedelta(minutes=1)
    local_date = generated_at.astimezone(ZoneInfo("Europe/Berlin")).date()
    period_start = local_date.replace(day=1)
    period_end = local_date.replace(
        day=calendar.monthrange(local_date.year, local_date.month)[1]
    )
    zero = Decimal(0)
    async with session_factory() as database, database.begin():
        database.add(
            HomeProjectionSnapshotRow(
                id=uuid4(),
                user_id=user_id,
                timezone_name="Europe/Berlin",
                period_start=period_start,
                period_end=period_end,
                revision=1,
                generated_at=generated_at,
                data_as_of=generated_at,
                base_currency="EUR",
                balance_amount=zero,
                balance_delta_amount=zero,
                balance_delta_percent=zero,
                month_income=zero,
                month_expense=zero,
                month_net_flow=zero,
                trend_metric="expense",
                trend_period="7d",
                trend_total=zero,
            )
        )


async def _assert_unsafe_timezone_constraints(
    *,
    session_factory: AsyncSessionFactory,
    user_id: UUID,
    account_id: UUID,
) -> None:
    attempts = (
        (
            (
                "UPDATE users SET canonical_timezone = 'Factory', "
                "timezone_revision = 1 WHERE id = :row_id"
            ),
            user_id,
            "ck_users_canonical_timezone_revision",
        ),
        (
            (
                "UPDATE finance_accounts SET opening_timezone = 'localtime' "
                "WHERE id = :row_id"
            ),
            account_id,
            "ck_finance_accounts_opening_timezone",
        ),
    )
    for statement, row_id, constraint_name in attempts:
        try:
            async with session_factory() as database, database.begin():
                await database.execute(text(statement), {"row_id": row_id})
        except IntegrityError as error:
            assert constraint_name in str(error.orig)
        else:
            raise AssertionError(f"{constraint_name} accepted an unsafe timezone")

    async with session_factory() as database:
        profile = await database.scalar(select(UserRow).where(UserRow.id == user_id))
        account = await database.scalar(
            select(FinanceAccountRow).where(FinanceAccountRow.id == account_id)
        )
        assert profile is not None
        assert profile.canonical_timezone == "Europe/Berlin"
        assert profile.timezone_revision == 1
        assert account is not None
        assert account.opening_timezone == "Europe/Berlin"


async def _exercise_http() -> tuple[
    AsyncEngine,
    AsyncSessionFactory,
    AccessTokenCodec,
    _Identity,
    dict[str, object],
    str,
]:
    engine, session_factory = create_database(DATABASE_URL)
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-account-test",
        audience="mfa-account-test-mobile",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    confirmed_at = datetime.now(UTC).isoformat().replace("+00:00", "Z")

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        unauthenticated = await client.get("/api/v1/accounts")
        assert unauthenticated.status_code == 401
        assert unauthenticated.headers["cache-control"] == "no-store"

        first = await _register(
            client,
            email="first-account@example.com",
            name="Synthetic First",
        )
        first_before = await client.get(
            "/api/v1/accounts",
            headers=first.headers,
        )
        assert first_before.status_code == 200, first_before.text
        assert first_before.headers["cache-control"] == "no-store"
        assert first_before.json() == {
            "schemaVersion": "1",
            "canonicalTimezone": None,
            "timezoneRevision": 0,
            "accounts": [],
        }

        home_before = await client.get(
            "/api/v1/home",
            params={"period": "current_month", "timezone": "Europe/Berlin"},
            headers=first.headers,
        )
        assert home_before.status_code == 200
        assert home_before.json()["homeState"] == "first_use_empty"

        await _seed_stale_current_home_snapshot(
            session_factory=session_factory,
            user_id=first.user_id,
        )
        stale_home_before_account = await client.get(
            "/api/v1/home",
            params={"period": "current_month", "timezone": "Europe/Berlin"},
            headers=first.headers,
        )
        assert stale_home_before_account.status_code == 503
        assert stale_home_before_account.json() == {
            "detail": "Home temporarily unavailable"
        }

        marker = "sensitive-account-marker"
        malformed = _account_draft(name=marker)
        malformed["openingBalance"] = -125.5
        redacted = await client.post(
            "/api/v1/accounts/evaluate",
            json={"draft": malformed},
            headers=first.headers,
        )
        assert redacted.status_code == 422
        assert redacted.headers["cache-control"] == "no-store"
        assert redacted.json() == {
            "detail": {"code": "MALFORMED_ACCOUNT", "issues": []}
        }
        assert marker not in redacted.text
        assert "125.5" not in redacted.text

        draft = _account_draft()
        evaluation = await client.post(
            "/api/v1/accounts/evaluate",
            json={"draft": draft},
            headers=first.headers,
        )
        assert evaluation.status_code == 200, evaluation.text
        evaluated = evaluation.json()
        assert evaluated["decision"] == "NEEDS_CONFIRMATION"
        commit_body = _account_commit(
            draft=draft,
            draft_hash=str(evaluated["draftHash"]),
            confirmed_at=confirmed_at,
        )
        accepted, replay = await asyncio.gather(
            client.post(
                "/api/v1/accounts/commit",
                json=commit_body,
                headers=first.headers,
            ),
            client.post(
                "/api/v1/accounts/commit",
                json=commit_body,
                headers=first.headers,
            ),
        )
        assert sorted((accepted.status_code, replay.status_code)) == [200, 201]
        payloads = (accepted.json(), replay.json())
        assert sorted(payload["idempotentReplay"] for payload in payloads) == [
            False,
            True,
        ]
        assert payloads[0]["account"] == payloads[1]["account"]
        assert payloads[0]["account"]["openingBalance"] == "-125.5"
        first_account_id = str(payloads[0]["account"]["accountId"])
        assert first_account_id == str(payloads[1]["account"]["accountId"])
        assert payloads[0]["canonicalTimezone"] == "Europe/Berlin"
        assert payloads[0]["timezoneRevision"] == 1

        listed = await client.get("/api/v1/accounts", headers=first.headers)
        assert listed.status_code == 200
        assert listed.json()["accounts"] == [payloads[0]["account"]]

        await _assert_unsafe_timezone_constraints(
            session_factory=session_factory,
            user_id=first.user_id,
            account_id=UUID(first_account_id),
        )

        confirmation_mismatch = await client.post(
            "/api/v1/accounts/commit",
            json={**commit_body, "draftHash": "0" * 64},
            headers=first.headers,
        )
        assert confirmation_mismatch.status_code == 409
        assert confirmation_mismatch.json()["detail"] == {
            "code": "CONFIRMATION_MISMATCH",
            "issues": [],
        }

        changed_confirmation = await client.post(
            "/api/v1/accounts/commit",
            json={
                **commit_body,
                "confirmedAt": (datetime.now(UTC) + timedelta(seconds=1))
                .isoformat()
                .replace("+00:00", "Z"),
            },
            headers=first.headers,
        )
        assert changed_confirmation.status_code == 409
        assert changed_confirmation.json()["detail"] == {
            "code": "COMMAND_CONFLICT",
            "issues": [],
        }

        invalid_changed_draft = {**draft, "currency": "USD"}
        invalid_changed = await client.post(
            "/api/v1/accounts/commit",
            json=_account_commit(
                draft=invalid_changed_draft,
                draft_hash=account_draft_hash(
                    AccountDraft.model_validate(invalid_changed_draft)
                ),
                confirmed_at=confirmed_at,
            ),
            headers=first.headers,
        )
        assert invalid_changed.status_code == 409
        assert invalid_changed.json()["detail"] == {
            "code": "COMMAND_CONFLICT",
            "issues": [],
        }

        exact_after_invalid = await client.post(
            "/api/v1/accounts/commit",
            json=commit_body,
            headers=first.headers,
        )
        assert exact_after_invalid.status_code == 200
        assert exact_after_invalid.json()["idempotentReplay"] is True
        assert exact_after_invalid.json()["account"]["accountId"] == first_account_id

        second_command = _account_draft(
            command_id="22222222-2222-4222-8222-222222222222",
        )
        second_command_hash = account_draft_hash(
            AccountDraft.model_validate(second_command)
        )
        second_attempt = await client.post(
            "/api/v1/accounts/commit",
            json=_account_commit(
                draft=second_command,
                draft_hash=second_command_hash,
                confirmed_at=confirmed_at,
            ),
            headers=first.headers,
        )
        assert second_attempt.status_code == 409
        assert second_attempt.json()["detail"] == {
            "code": "ACCOUNT_ALREADY_INITIALIZED",
            "issues": [],
        }

        mismatch_home = await client.get(
            "/api/v1/home",
            params={"period": "current_month", "timezone": "UTC"},
            headers=first.headers,
        )
        assert mismatch_home.status_code == 409
        # The refusal names the zone the profile actually reports, so a client
        # left behind by a correction can adopt it and retry (ADR 0028).
        assert mismatch_home.json() == {
            "detail": {
                "code": "CANONICAL_TIMEZONE_MISMATCH",
                "canonicalTimezone": "Europe/Berlin",
            }
        }
        canonical_home = await client.get(
            "/api/v1/home",
            params={"period": "current_month", "timezone": "Europe/Berlin"},
            headers=first.headers,
        )
        assert canonical_home.status_code == 503

        second = await _register(
            client,
            email="second-account@example.com",
            name="Synthetic Second",
        )
        second_before = await client.get("/api/v1/accounts", headers=second.headers)
        assert second_before.status_code == 200
        assert second_before.json()["accounts"] == []
        second_payload, _ = await _bootstrap_account(
            client,
            identity=second,
            draft=draft,
            confirmed_at=confirmed_at,
        )
        assert second_payload["account"]["accountId"] != first_account_id
        assert second_payload["account"]["userId"] != str(first.user_id)

        rollback_user = await _register(
            client,
            email="rollback-account@example.com",
            name="Synthetic Rollback",
        )
        async with session_factory() as database:
            await database.execute(
                text(
                    "CREATE FUNCTION reject_synthetic_account_outbox() "
                    "RETURNS trigger LANGUAGE plpgsql AS $$ "
                    "BEGIN RAISE EXCEPTION 'synthetic account outbox failure'; END $$"
                )
            )
            await database.execute(
                text(
                    "CREATE TRIGGER reject_synthetic_account_outbox "
                    "BEFORE INSERT ON finance_account_outbox_events "
                    "FOR EACH ROW EXECUTE FUNCTION "
                    "reject_synthetic_account_outbox()"
                )
            )
            await database.commit()
        rollback_draft = _account_draft(
            command_id="33333333-3333-4333-8333-333333333333",
            name="Synthetic rollback account",
        )
        rollback_evaluation = await client.post(
            "/api/v1/accounts/evaluate",
            json={"draft": rollback_draft},
            headers=rollback_user.headers,
        )
        rollback_response = await client.post(
            "/api/v1/accounts/commit",
            json=_account_commit(
                draft=rollback_draft,
                draft_hash=str(rollback_evaluation.json()["draftHash"]),
                confirmed_at=confirmed_at,
            ),
            headers=rollback_user.headers,
        )
        assert rollback_response.status_code == 503
        assert rollback_response.json()["detail"] == {
            "code": "FINANCE_PERSISTENCE_UNAVAILABLE",
            "issues": [],
        }
        async with session_factory() as database:
            await database.execute(
                text(
                    "DROP TRIGGER reject_synthetic_account_outbox "
                    "ON finance_account_outbox_events"
                )
            )
            await database.execute(
                text("DROP FUNCTION reject_synthetic_account_outbox()")
            )
            await database.commit()
            assert (
                await database.scalar(
                    select(func.count())
                    .select_from(FinanceAccountRow)
                    .where(FinanceAccountRow.user_id == rollback_user.user_id)
                )
                == 0
            )
            profile = await database.scalar(
                select(UserRow).where(UserRow.id == rollback_user.user_id)
            )
            assert profile is not None
            assert profile.canonical_timezone is None
            assert profile.timezone_revision == 0

        async with session_factory() as database:
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceAccountRow)
                )
                == 2
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceAccountAuditRow)
                )
                == 2
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceAccountOutboxEventRow)
                )
                == 2
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(HomeProjectionSnapshotRow)
                )
                == 1
            )
            outbox = tuple(
                (await database.scalars(select(FinanceAccountOutboxEventRow))).all()
            )
            assert all(
                set(event.payload)
                == {"schemaVersion", "accountId", "userId", "commandId"}
                for event in outbox
            )
            assert all(
                "name" not in event.payload and "openingBalance" not in event.payload
                for event in outbox
            )

    return engine, session_factory, tokens, first, commit_body, first_account_id


async def _restart_check(
    *,
    session_factory: AsyncSessionFactory,
    tokens: AccessTokenCodec,
    identity: _Identity,
    commit_body: dict[str, object],
    account_id: str,
) -> None:
    restarted_app = _application(session_factory=session_factory, tokens=tokens)
    async with AsyncClient(
        transport=ASGITransport(app=restarted_app),
        base_url="http://test",
    ) as restarted:
        listed = await restarted.get("/api/v1/accounts", headers=identity.headers)
        assert listed.status_code == 200
        assert listed.json()["accounts"][0]["accountId"] == account_id
        replay = await restarted.post(
            "/api/v1/accounts/commit",
            json=commit_body,
            headers=identity.headers,
        )
        assert replay.status_code == 200
        assert replay.json()["idempotentReplay"] is True
        assert replay.json()["account"]["accountId"] == account_id


async def _baseline_replay_check(
    *,
    session_factory: AsyncSessionFactory,
    tokens: AccessTokenCodec,
    identity: _Identity,
    opening_commit_body: dict[str, object],
    account_id: str,
) -> None:
    app = _application(session_factory=session_factory, tokens=tokens)
    opening_on = date.fromisoformat(OPENING_ON)
    first_on = opening_on - timedelta(days=10)
    second_on = opening_on - timedelta(days=20)
    first_draft = {
        "schemaVersion": "1",
        "commandId": "44444444-4444-4444-8444-444444444444",
        "accountId": account_id,
        "openingBalanceOn": first_on.isoformat(),
    }
    second_draft = {
        "schemaVersion": "1",
        "commandId": "55555555-5555-4555-8555-555555555555",
        "accountId": account_id,
        "openingBalanceOn": second_on.isoformat(),
    }

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        first_evaluation = await client.post(
            "/api/v1/accounts/baseline/evaluate",
            json={"draft": first_draft},
            headers=identity.headers,
        )
        assert first_evaluation.status_code == 200, first_evaluation.text
        assert first_evaluation.json()["decision"] == "NEEDS_CONFIRMATION"
        assert first_evaluation.json()["currentOpeningBalanceOn"] == OPENING_ON
        first_commit = {
            "schemaVersion": "1",
            "draft": first_draft,
            "draftHash": first_evaluation.json()["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        }
        first_responses = await asyncio.gather(
            client.post(
                "/api/v1/accounts/baseline/commit",
                json=first_commit,
                headers=identity.headers,
            ),
            client.post(
                "/api/v1/accounts/baseline/commit",
                json=first_commit,
                headers=identity.headers,
            ),
        )
        assert all(response.status_code == 200 for response in first_responses)
        first_payloads = tuple(response.json() for response in first_responses)
        assert sorted(payload["idempotentReplay"] for payload in first_payloads) == [
            False,
            True,
        ]
        assert all(
            payload["previousOpeningBalanceOn"] == OPENING_ON
            and payload["account"]["openingBalanceOn"] == first_on.isoformat()
            for payload in first_payloads
        )

        second_evaluation = await client.post(
            "/api/v1/accounts/baseline/evaluate",
            json={"draft": second_draft},
            headers=identity.headers,
        )
        assert second_evaluation.status_code == 200, second_evaluation.text
        assert second_evaluation.json()["currentOpeningBalanceOn"] == (
            first_on.isoformat()
        )
        second_commit = {
            "schemaVersion": "1",
            "draft": second_draft,
            "draftHash": second_evaluation.json()["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        }
        second_response = await client.post(
            "/api/v1/accounts/baseline/commit",
            json=second_commit,
            headers=identity.headers,
        )
        assert second_response.status_code == 200, second_response.text
        assert second_response.json()["idempotentReplay"] is False

        replayed_first = await client.post(
            "/api/v1/accounts/baseline/commit",
            json=first_commit,
            headers=identity.headers,
        )
        assert replayed_first.status_code == 200, replayed_first.text
        replayed_first_body = replayed_first.json()
        assert replayed_first_body["idempotentReplay"] is True
        assert replayed_first_body["previousOpeningBalanceOn"] == OPENING_ON
        assert replayed_first_body["account"]["openingBalanceOn"] == (
            first_on.isoformat()
        )

        replayed_opening = await client.post(
            "/api/v1/accounts/commit",
            json=opening_commit_body,
            headers=identity.headers,
        )
        assert replayed_opening.status_code == 200, replayed_opening.text
        replayed_opening_body = replayed_opening.json()
        assert replayed_opening_body["idempotentReplay"] is True
        assert replayed_opening_body["account"]["openingBalanceOn"] == OPENING_ON

        listed = await client.get("/api/v1/accounts", headers=identity.headers)
        assert listed.status_code == 200, listed.text
        live_account = listed.json()["accounts"][0]
        assert live_account["openingBalanceOn"] == second_on.isoformat()
        # Replayed receipts restore only their historical date. Every immutable
        # field still comes from the current authoritative account row.
        for key in (
            "accountId",
            "userId",
            "commandId",
            "name",
            "currency",
            "openingBalance",
            "openingTimezone",
            "status",
            "isDefault",
            "confirmedAt",
            "createdAt",
        ):
            assert replayed_first_body["account"][key] == live_account[key]
            assert replayed_opening_body["account"][key] == live_account[key]

    async with session_factory() as database:
        audits = tuple(
            (
                await database.scalars(
                    select(FinanceAccountAuditRow).where(
                        FinanceAccountAuditRow.account_id == UUID(account_id)
                    )
                )
            ).all()
        )
        outbox = tuple(
            (
                await database.scalars(
                    select(FinanceAccountOutboxEventRow).where(
                        FinanceAccountOutboxEventRow.aggregate_id == UUID(account_id)
                    )
                )
            ).all()
        )
    assert len(audits) == 3
    assert len(outbox) == 3
    assert sum(row.event_type == "account_baseline_corrected" for row in audits) == 2
    assert (
        sum(row.event_type == "finance.account.baseline_corrected.v1" for row in outbox)
        == 2
    )


def _assert_lossy_downgrade_refused() -> None:
    config = _alembic_config()
    try:
        command.downgrade(config, "0003_finance_operations")
    except RuntimeError as error:
        assert "Refusing lossy downgrade" in str(error)
    else:
        raise AssertionError("populated account downgrade was not refused")


async def main() -> None:
    engine, factory, tokens, identity, commit_body, account_id = await _exercise_http()
    try:
        await _restart_check(
            session_factory=factory,
            tokens=tokens,
            identity=identity,
            commit_body=commit_body,
            account_id=account_id,
        )
        await _baseline_replay_check(
            session_factory=factory,
            tokens=tokens,
            identity=identity,
            opening_commit_body=commit_body,
            account_id=account_id,
        )
    finally:
        await engine.dispose()


if __name__ == "__main__":
    _empty_migration_round_trip()
    asyncio.run(main())
    _assert_lossy_downgrade_refused()
    print("account opening PostgreSQL E2E: pass")
