from __future__ import annotations

import asyncio
import json
import os
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from uuid import UUID, uuid4

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select, text

from mobile_finance_api.account_core import FinanceAccountDirectory
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceAccountRow,
    FinanceOperationAuditRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    UserRow,
)
from mobile_finance_api.finance_core import (
    FinanceCore,
    confirmed_command_hash,
    draft_hash,
)
from mobile_finance_api.main import create_app
from mobile_finance_api.operation_contracts import OperationDraft
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.postgres_finance_repository import (
    PostgresFinanceOperationRepository,
)
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
API_ROOT = REPOSITORY_ROOT / "services" / "api"
JWT_SECRET = b"test-only-migration-compat-secret-32-bytes"
CONFIRMED_AT = datetime(2026, 7, 27, 18, 1, tzinfo=UTC)


@dataclass(frozen=True, slots=True)
class _LegacySeed:
    user_id: UUID
    operation_id: UUID
    token: str
    draft: dict[str, object]
    draft_hash: str
    payload_hash: bytes

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}

    @property
    def commit_body(self) -> dict[str, object]:
        return {
            "schemaVersion": "1",
            "draft": self.draft,
            "draftHash": self.draft_hash,
            "confirmedAt": CONFIRMED_AT.isoformat().replace("+00:00", "Z"),
        }


def _alembic_config() -> Config:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    return config


def _draft(*, command_id: UUID, merchant: str) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "commandId": str(command_id),
        "type": "expense",
        "amount": "35.00",
        "currency": "EUR",
        "category": "Synthetic category",
        "merchant": merchant,
        "capturedAt": "2026-07-27T18:00:00Z",
        "capturedTimezone": "Europe/Berlin",
        "sourceExpression": "вчера",
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": "2026-07-26",
        "occurredAt": None,
        "source": "manual_text",
    }


def _hashes(raw_draft: dict[str, object]) -> tuple[OperationDraft, str, bytes]:
    parsed = OperationDraft.model_validate(raw_draft)
    evaluated_hash = draft_hash(parsed)
    command_hash = confirmed_command_hash(
        draft=parsed,
        confirmed_at=CONFIRMED_AT,
        evaluated_draft_hash=evaluated_hash,
    )
    return parsed, evaluated_hash, bytes.fromhex(command_hash)


async def _seed_prior_v1() -> _LegacySeed:
    engine, _ = create_database(DATABASE_URL)
    user_id = uuid4()
    session_id = uuid4()
    operation_id = uuid4()
    command_id = uuid4()
    audit_id = uuid4()
    outbox_id = uuid4()
    now = datetime.now(UTC)
    raw_draft = _draft(
        command_id=command_id,
        merchant="Synthetic legacy merchant",
    )
    assert "accountId" not in raw_draft
    parsed, evaluated_hash, payload_hash = _hashes(raw_draft)
    explicit_null = OperationDraft.model_validate({**raw_draft, "accountId": None})
    assert parsed.account_id is None
    assert draft_hash(explicit_null) == evaluated_hash

    try:
        async with engine.begin() as connection:
            revision = await connection.scalar(
                text("SELECT version_num FROM alembic_version")
            )
            assert revision == "0003_finance_operations"
            await connection.execute(
                text(
                    "INSERT INTO users ("
                    "id, email_normalized, password_hash, display_name, "
                    "base_currency, created_at, updated_at, disabled_at"
                    ") VALUES ("
                    ":id, :email, :password_hash, :display_name, 'EUR', "
                    ":created_at, :updated_at, NULL"
                    ")"
                ),
                {
                    "id": user_id,
                    "email": "migration-compat@example.com",
                    "password_hash": "synthetic-password-hash-not-used",
                    "display_name": "Synthetic Migration User",
                    "created_at": now,
                    "updated_at": now,
                },
            )
            await connection.execute(
                text(
                    "INSERT INTO auth_sessions ("
                    "id, user_id, created_at, last_seen_at, absolute_expires_at, "
                    "revoked_at, revocation_reason"
                    ") VALUES ("
                    ":id, :user_id, :created_at, :last_seen_at, "
                    ":absolute_expires_at, NULL, NULL"
                    ")"
                ),
                {
                    "id": session_id,
                    "user_id": user_id,
                    "created_at": now,
                    "last_seen_at": now,
                    "absolute_expires_at": now + timedelta(hours=1),
                },
            )
            await connection.execute(
                text(
                    "INSERT INTO finance_operations ("
                    "id, user_id, command_id, command_payload_hash, "
                    "schema_version, operation_type, amount, currency, "
                    "account_id, category, merchant, captured_at, "
                    "captured_timezone, source_expression, "
                    "date_resolver_version, occurred_on, occurred_at, source, "
                    "status, confirmed_at, created_at"
                    ") VALUES ("
                    ":id, :user_id, :command_id, :payload_hash, '1', 'expense', "
                    ":amount, 'EUR', NULL, :category, :merchant, :captured_at, "
                    ":captured_timezone, :source_expression, "
                    ":date_resolver_version, :occurred_on, NULL, :source, "
                    "'confirmed', :confirmed_at, :created_at"
                    ")"
                ),
                {
                    "id": operation_id,
                    "user_id": user_id,
                    "command_id": command_id,
                    "payload_hash": payload_hash,
                    "amount": Decimal("35.00"),
                    "category": parsed.category,
                    "merchant": parsed.merchant,
                    "captured_at": parsed.captured_at,
                    "captured_timezone": parsed.captured_timezone,
                    "source_expression": parsed.source_expression,
                    "date_resolver_version": parsed.date_resolver_version,
                    "occurred_on": parsed.occurred_on,
                    "source": parsed.source,
                    "confirmed_at": CONFIRMED_AT,
                    "created_at": CONFIRMED_AT,
                },
            )
            await connection.execute(
                text(
                    "INSERT INTO finance_operation_audit_events ("
                    "id, operation_id, user_id, command_id, event_type, "
                    "actor_type, payload_hash, created_at"
                    ") VALUES ("
                    ":id, :operation_id, :user_id, :command_id, "
                    "'operation_accepted', 'user', :payload_hash, :created_at"
                    ")"
                ),
                {
                    "id": audit_id,
                    "operation_id": operation_id,
                    "user_id": user_id,
                    "command_id": command_id,
                    "payload_hash": payload_hash,
                    "created_at": CONFIRMED_AT,
                },
            )
            await connection.execute(
                text(
                    "INSERT INTO finance_outbox_events ("
                    "id, aggregate_type, aggregate_id, event_type, payload, "
                    "created_at, published_at, attempt_count"
                    ") VALUES ("
                    ":id, 'finance_operation', :operation_id, "
                    "'finance.operation.accepted.v1', CAST(:payload AS JSONB), "
                    ":created_at, NULL, 32767"
                    ")"
                ),
                {
                    "id": outbox_id,
                    "operation_id": operation_id,
                    "payload": json.dumps(
                        {
                            "schemaVersion": "1",
                            "operationId": str(operation_id),
                            "userId": str(user_id),
                            "commandId": str(command_id),
                        }
                    ),
                    "created_at": CONFIRMED_AT,
                },
            )
    finally:
        await engine.dispose()

    token_codec = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-migration-compat-test",
        audience="mfa-migration-compat-mobile",
    )
    return _LegacySeed(
        user_id=user_id,
        operation_id=operation_id,
        token=token_codec.issue(user_id=user_id, session_id=session_id, now=now),
        draft=raw_draft,
        draft_hash=evaluated_hash,
        payload_hash=payload_hash,
    )


def _application(
    *,
    session_factory: AsyncSessionFactory,
    tokens: AccessTokenCodec,
):
    accounts: FinanceAccountDirectory = PostgresFinanceAccountRepository(
        session_factory=session_factory
    )
    return create_app(
        current_user_authenticator=PostgresCurrentUserAuthenticator(
            session_factory=session_factory,
            access_tokens=tokens,
        ),
        finance_core=FinanceCore(
            repository=PostgresFinanceOperationRepository(
                session_factory=session_factory
            ),
            account_directory=accounts,
        ),
    )


async def _verify_after_upgrade(seed: _LegacySeed) -> None:
    engine, session_factory = create_database(DATABASE_URL)
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-migration-compat-test",
        audience="mfa-migration-compat-mobile",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    try:
        async with session_factory() as database:
            operation = await database.scalar(
                select(FinanceOperationRow).where(
                    FinanceOperationRow.id == seed.operation_id
                )
            )
            assert operation is not None
            assert operation.user_id == seed.user_id
            assert operation.account_id is None
            assert operation.command_payload_hash == seed.payload_hash
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceAccountRow)
                )
                == 0
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceOperationAuditRow)
                )
                == 1
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceOutboxEventRow)
                )
                == 1
            )
            outbox = await database.scalar(select(FinanceOutboxEventRow))
            assert outbox is not None
            assert outbox.attempt_count == 32767
            # Legacy delivery attempts were not strict validation failures and
            # must never consume the new bounded DLQ budget.
            assert outbox.validation_failure_count == 0
            assert outbox.next_attempt_at == outbox.created_at
            profile = await database.scalar(
                select(UserRow).where(UserRow.id == seed.user_id)
            )
            assert profile is not None
            assert profile.canonical_timezone is None
            assert profile.timezone_revision == 0

        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            exact = await client.post(
                "/api/v1/operations/commit",
                json=seed.commit_body,
                headers=seed.headers,
            )
            assert exact.status_code == 200, exact.text
            assert exact.json()["idempotentReplay"] is True
            assert exact.json()["operation"]["operationId"] == str(seed.operation_id)
            assert exact.json()["operation"]["accountId"] is None

            changed_draft = {
                **seed.draft,
                "merchant": "Changed synthetic legacy merchant",
            }
            _, changed_draft_hash, _ = _hashes(changed_draft)
            changed = await client.post(
                "/api/v1/operations/commit",
                json={
                    "schemaVersion": "1",
                    "draft": changed_draft,
                    "draftHash": changed_draft_hash,
                    "confirmedAt": seed.commit_body["confirmedAt"],
                },
                headers=seed.headers,
            )
            assert changed.status_code == 409
            assert changed.json() == {
                "detail": {"code": "COMMAND_CONFLICT", "issues": []}
            }

            new_draft = _draft(
                command_id=uuid4(),
                merchant="Synthetic new unallocated merchant",
            )
            assert "accountId" not in new_draft
            new_evaluation = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": new_draft},
                headers=seed.headers,
            )
            assert new_evaluation.status_code == 200
            assert new_evaluation.json()["decision"] == "REJECT"
            assert new_evaluation.json()["draft"]["accountId"] is None
            assert new_evaluation.json()["issues"] == [
                {"code": "ACCOUNT_REQUIRED", "field": "accountId"}
            ]

            _, new_draft_hash, _ = _hashes(new_draft)
            rejected = await client.post(
                "/api/v1/operations/commit",
                json={
                    "schemaVersion": "1",
                    "draft": new_draft,
                    "draftHash": new_draft_hash,
                    "confirmedAt": seed.commit_body["confirmedAt"],
                },
                headers=seed.headers,
            )
            assert rejected.status_code == 422
            assert rejected.json() == {
                "detail": {
                    "code": "OPERATION_REJECTED",
                    "issues": [{"code": "ACCOUNT_REQUIRED", "field": "accountId"}],
                }
            }

        async with session_factory() as database:
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceOperationRow)
                )
                == 1
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceAccountRow)
                )
                == 0
            )
    finally:
        await engine.dispose()


def main() -> None:
    config = _alembic_config()
    command.upgrade(config, "0003_finance_operations")
    seed = asyncio.run(_seed_prior_v1())
    command.upgrade(config, "head")
    asyncio.run(_verify_after_upgrade(seed))


if __name__ == "__main__":
    main()
    print("authoritative accounts migration compatibility PostgreSQL E2E: pass")
