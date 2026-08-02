from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from decimal import Decimal
from uuid import UUID, uuid4

from httpx import (
    ASGITransport,
    AsyncBaseTransport,
    AsyncClient,
    ReadTimeout,
    Request,
    Response,
)
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from starlette.types import ASGIApp

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import (
    FinanceOperationAuditRow,
    FinanceOperationRow,
    FinanceOutboxEventRow,
    HomeProjectionSnapshotRow,
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
JWT_SECRET = "test-only-finance-operation-secret-32-bytes-minimum"


@dataclass(frozen=True, slots=True)
class _Identity:
    user_id: UUID
    token: str

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


class _LoseCommitResponseTransport(AsyncBaseTransport):
    """Let the API finish one commit, then hide its response from the client."""

    def __init__(self, *, app: ASGIApp) -> None:
        self._inner = ASGITransport(app=app)
        self.lost_status_code: int | None = None

    async def handle_async_request(self, request: Request) -> Response:
        response = await self._inner.handle_async_request(request)
        if request.method == "POST" and request.url.path == (
            "/api/v1/operations/commit"
        ):
            self.lost_status_code = response.status_code
            await response.aclose()
            raise ReadTimeout("synthetic response loss", request=request)
        return response

    async def aclose(self) -> None:
        await self._inner.aclose()


def _account_draft(
    *,
    command_id: str = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "commandId": command_id,
        "name": "Synthetic operation account",
        "currency": "EUR",
        "openingBalance": "1000.00",
        "openingBalanceOn": "2026-07-20",
        "canonicalTimezone": "Europe/Berlin",
    }


def _draft(
    *,
    account_id: str | None,
    merchant: str = "Synthetic grocery",
    command_id: str = "11111111-1111-4111-8111-111111111111",
    occurred_on: str = "2026-07-26",
    source_expression: str | None = "вчера",
) -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "commandId": command_id,
        "type": "expense",
        "amount": "35.00",
        "currency": "EUR",
        "accountId": account_id,
        "category": "Synthetic category",
        "merchant": merchant,
        "capturedAt": "2026-07-27T18:00:00Z",
        "capturedTimezone": "Europe/Berlin",
        "sourceExpression": source_expression,
        "dateResolverVersion": "calendar-relative-v1",
        "occurredOn": occurred_on,
        "occurredAt": None,
        "source": "manual_text",
    }


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


async def _login(client: AsyncClient, *, email: str) -> _Identity:
    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": email,
            "password": "synthetic-password-123",
        },
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    return _Identity(
        user_id=UUID(payload["user"]["id"]),
        token=str(payload["accessToken"]),
    )


async def _bootstrap_account(
    client: AsyncClient,
    *,
    identity: _Identity,
    command_id: str = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
) -> str:
    draft = _account_draft(command_id=command_id)
    evaluation = await client.post(
        "/api/v1/accounts/evaluate",
        json={"draft": draft},
        headers=identity.headers,
    )
    assert evaluation.status_code == 200, evaluation.text
    response = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": "2026-07-27T17:59:00Z",
        },
        headers=identity.headers,
    )
    assert response.status_code == 201, response.text
    return str(response.json()["account"]["accountId"])


def _application(
    *,
    session_factory: AsyncSessionFactory,
    tokens: AccessTokenCodec,
):
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


async def _assert_composite_ownership_fk(
    *,
    session_factory: AsyncSessionFactory,
    first_user_id: UUID,
    second_user_id: UUID,
) -> None:
    statement = text(
        "INSERT INTO finance_operations ("
        "id, user_id, command_id, command_payload_hash, schema_version, "
        "operation_type, amount, currency, account_id, category, merchant, "
        "captured_at, captured_timezone, source_expression, "
        "date_resolver_version, occurred_on, occurred_at, source, status, "
        "confirmed_at, created_at"
        ") SELECT "
        ":new_id, :second_user_id, :new_command_id, command_payload_hash, "
        "schema_version, operation_type, amount, currency, account_id, category, "
        "merchant, captured_at, captured_timezone, source_expression, "
        "date_resolver_version, occurred_on, occurred_at, source, status, "
        "confirmed_at, created_at FROM finance_operations "
        "WHERE user_id = :first_user_id LIMIT 1"
    )
    try:
        async with session_factory() as database, database.begin():
            await database.execute(
                statement,
                {
                    "new_id": uuid4(),
                    "second_user_id": second_user_id,
                    "new_command_id": uuid4(),
                    "first_user_id": first_user_id,
                },
            )
    except IntegrityError:
        return
    raise AssertionError("cross-user account allocation bypassed the composite FK")


async def _single_command_operation_id(
    *,
    session_factory: AsyncSessionFactory,
    user_id: UUID,
    command_id: UUID,
) -> UUID:
    async with session_factory() as database:
        operation_id = await database.scalar(
            select(FinanceOperationRow.id).where(
                FinanceOperationRow.user_id == user_id,
                FinanceOperationRow.command_id == command_id,
            )
        )
        assert operation_id is not None
        operation_count = await database.scalar(
            select(func.count())
            .select_from(FinanceOperationRow)
            .where(
                FinanceOperationRow.user_id == user_id,
                FinanceOperationRow.command_id == command_id,
            )
        )
        audit_count = await database.scalar(
            select(func.count())
            .select_from(FinanceOperationAuditRow)
            .where(
                FinanceOperationAuditRow.user_id == user_id,
                FinanceOperationAuditRow.command_id == command_id,
            )
        )
        outbox_count = await database.scalar(
            select(func.count())
            .select_from(FinanceOutboxEventRow)
            .where(FinanceOutboxEventRow.aggregate_id == operation_id)
        )
    assert operation_count == audit_count == outbox_count == 1
    return operation_id


async def main() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    tokens = AccessTokenCodec(
        secret=JWT_SECRET,
        issuer="mfa-operation-test",
        audience="mfa-operation-test-mobile",
    )
    app = _application(session_factory=session_factory, tokens=tokens)

    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            first = await _register(
                client,
                email="first-operation@example.com",
                name="Synthetic First",
            )
            home_before = await client.get(
                "/api/v1/home",
                params={"period": "current_month", "timezone": "Europe/Berlin"},
                headers=first.headers,
            )
            assert home_before.status_code == 200
            assert home_before.json()["homeState"] == "first_use_empty"

            first_account_id = await _bootstrap_account(client, identity=first)

            unauthenticated = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": _draft(account_id=first_account_id)},
            )
            assert unauthenticated.status_code == 401
            assert unauthenticated.headers["cache-control"] == "no-store"

            unallocated = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": _draft(account_id=None)},
                headers=first.headers,
            )
            assert unallocated.status_code == 200
            assert unallocated.json()["decision"] == "REJECT"
            assert unallocated.json()["issues"] == [
                {"code": "ACCOUNT_REQUIRED", "field": "accountId"}
            ]

            marker = "sensitive-operation-marker"
            malformed = _draft(account_id=first_account_id, merchant=marker)
            malformed["amount"] = 35.0
            redacted = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": malformed},
                headers=first.headers,
            )
            assert redacted.status_code == 422
            assert redacted.json() == {
                "detail": {"code": "MALFORMED_OPERATION", "issues": []}
            }
            assert marker not in redacted.text
            assert "35.0" not in redacted.text

            before_baseline = await client.post(
                "/api/v1/operations/evaluate",
                json={
                    "draft": _draft(
                        account_id=first_account_id,
                        occurred_on="2026-07-19",
                        source_expression=None,
                    )
                },
                headers=first.headers,
            )
            assert before_baseline.status_code == 200
            assert before_baseline.json()["decision"] == "REJECT"
            assert before_baseline.json()["issues"] == [
                {
                    "code": "OPERATION_BEFORE_ACCOUNT_BASELINE",
                    "field": "occurredOn",
                }
            ]

            draft = _draft(account_id=first_account_id)
            evaluation = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": draft},
                headers=first.headers,
            )
            assert evaluation.status_code == 200, evaluation.text
            assert evaluation.json()["decision"] == "NEEDS_CONFIRMATION"
            commit_body = {
                "schemaVersion": "1",
                "draft": draft,
                "draftHash": evaluation.json()["draftHash"],
                "confirmedAt": "2026-07-27T18:01:00Z",
            }
            accepted, replay = await asyncio.gather(
                client.post(
                    "/api/v1/operations/commit",
                    json=commit_body,
                    headers=first.headers,
                ),
                client.post(
                    "/api/v1/operations/commit",
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
            assert payloads[0]["operation"] == payloads[1]["operation"]
            assert payloads[0]["operation"]["accountId"] == first_account_id
            assert payloads[0]["operation"]["amount"] == "35"
            operation_id = str(payloads[0]["operation"]["operationId"])

            confirmation_mismatch = await client.post(
                "/api/v1/operations/commit",
                json={**commit_body, "draftHash": "0" * 64},
                headers=first.headers,
            )
            assert confirmation_mismatch.status_code == 409
            assert confirmation_mismatch.json()["detail"]["code"] == (
                "CONFIRMATION_MISMATCH"
            )

            changed_confirmation = await client.post(
                "/api/v1/operations/commit",
                json={**commit_body, "confirmedAt": "2026-07-27T18:02:00Z"},
                headers=first.headers,
            )
            assert changed_confirmation.status_code == 409
            assert changed_confirmation.json()["detail"]["code"] == ("COMMAND_CONFLICT")

            changed = _draft(
                account_id=first_account_id,
                merchant="Changed synthetic merchant",
            )
            changed_evaluation = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": changed},
                headers=first.headers,
            )
            conflict = await client.post(
                "/api/v1/operations/commit",
                json={
                    "schemaVersion": "1",
                    "draft": changed,
                    "draftHash": changed_evaluation.json()["draftHash"],
                    "confirmedAt": "2026-07-27T18:02:00Z",
                },
                headers=first.headers,
            )
            assert conflict.status_code == 409
            assert conflict.json()["detail"]["code"] == "COMMAND_CONFLICT"
            assert "Changed synthetic merchant" not in conflict.text

            lost_response_command_id = UUID("55555555-5555-4555-8555-555555555555")
            lost_response_draft = _draft(
                account_id=first_account_id,
                command_id=str(lost_response_command_id),
                merchant="Synthetic reconnect delivery",
            )
            lost_response_evaluation = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": lost_response_draft},
                headers=first.headers,
            )
            assert lost_response_evaluation.status_code == 200
            lost_response_body = {
                "schemaVersion": "1",
                "draft": lost_response_draft,
                "draftHash": lost_response_evaluation.json()["draftHash"],
                "confirmedAt": "2026-07-27T18:04:00Z",
            }

            lossy_transport = _LoseCommitResponseTransport(app=app)
            async with AsyncClient(
                transport=lossy_transport,
                base_url="http://test",
            ) as lossy_client:
                try:
                    await lossy_client.post(
                        "/api/v1/operations/commit",
                        json=lost_response_body,
                        headers=first.headers,
                    )
                except ReadTimeout:
                    pass
                else:
                    raise AssertionError("synthetic commit response was not lost")
            assert lossy_transport.lost_status_code == 201

            lost_operation_id = await _single_command_operation_id(
                session_factory=session_factory,
                user_id=first.user_id,
                command_id=lost_response_command_id,
            )
            replacement = await _login(
                client,
                email="first-operation@example.com",
            )
            assert replacement.user_id == first.user_id
            assert replacement.token != first.token

            recovered = await client.post(
                "/api/v1/operations/commit",
                json=lost_response_body,
                headers=replacement.headers,
            )
            assert recovered.status_code == 200, recovered.text
            assert recovered.json()["idempotentReplay"] is True
            assert UUID(recovered.json()["operation"]["operationId"]) == (
                lost_operation_id
            )
            assert (
                await _single_command_operation_id(
                    session_factory=session_factory,
                    user_id=first.user_id,
                    command_id=lost_response_command_id,
                )
                == lost_operation_id
            )

            second = await _register(
                client,
                email="second-operation@example.com",
                name="Synthetic Second",
            )
            second_account_id = await _bootstrap_account(
                client,
                identity=second,
            )
            foreign = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": _draft(account_id=first_account_id)},
                headers=second.headers,
            )
            missing = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": _draft(account_id=str(uuid4()))},
                headers=second.headers,
            )
            assert foreign.status_code == missing.status_code == 200
            assert (
                foreign.json()["issues"]
                == missing.json()["issues"]
                == [{"code": "ACCOUNT_UNAVAILABLE", "field": "accountId"}]
            )

            second_draft = _draft(account_id=second_account_id)
            second_evaluation = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": second_draft},
                headers=second.headers,
            )
            second_commit = await client.post(
                "/api/v1/operations/commit",
                json={
                    "schemaVersion": "1",
                    "draft": second_draft,
                    "draftHash": second_evaluation.json()["draftHash"],
                    "confirmedAt": "2026-07-27T18:01:00Z",
                },
                headers=second.headers,
            )
            assert second_commit.status_code == 201, second_commit.text
            assert second_commit.json()["operation"]["accountId"] == (second_account_id)

            await _assert_composite_ownership_fk(
                session_factory=session_factory,
                first_user_id=first.user_id,
                second_user_id=second.user_id,
            )

            rollback_command_id = "44444444-4444-4444-8444-444444444444"
            async with session_factory() as database:
                await database.execute(
                    text(
                        "CREATE FUNCTION reject_synthetic_finance_outbox() "
                        "RETURNS trigger LANGUAGE plpgsql AS $$ "
                        "BEGIN RAISE EXCEPTION 'synthetic outbox failure'; END $$"
                    )
                )
                await database.execute(
                    text(
                        "CREATE TRIGGER reject_synthetic_finance_outbox "
                        "BEFORE INSERT ON finance_outbox_events "
                        "FOR EACH ROW EXECUTE FUNCTION "
                        "reject_synthetic_finance_outbox()"
                    )
                )
                await database.commit()
            rollback_draft = _draft(
                account_id=first_account_id,
                command_id=rollback_command_id,
            )
            rollback_evaluation = await client.post(
                "/api/v1/operations/evaluate",
                json={"draft": rollback_draft},
                headers=first.headers,
            )
            rollback_response = await client.post(
                "/api/v1/operations/commit",
                json={
                    "schemaVersion": "1",
                    "draft": rollback_draft,
                    "draftHash": rollback_evaluation.json()["draftHash"],
                    "confirmedAt": "2026-07-27T18:03:00Z",
                },
                headers=first.headers,
            )
            assert rollback_response.status_code == 503
            async with session_factory() as database:
                await database.execute(
                    text(
                        "DROP TRIGGER reject_synthetic_finance_outbox "
                        "ON finance_outbox_events"
                    )
                )
                await database.execute(
                    text("DROP FUNCTION reject_synthetic_finance_outbox()")
                )
                await database.commit()
                assert (
                    await database.scalar(
                        select(func.count())
                        .select_from(FinanceOperationRow)
                        .where(
                            FinanceOperationRow.command_id == UUID(rollback_command_id)
                        )
                    )
                    == 0
                )

            home_after = await client.get(
                "/api/v1/home",
                params={"period": "current_month", "timezone": "Europe/Berlin"},
                headers=first.headers,
            )
            assert home_after.status_code == 503

        async with session_factory() as database:
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceOperationRow)
                )
                == 3
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceOperationAuditRow)
                )
                == 3
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(FinanceOutboxEventRow)
                )
                == 3
            )
            assert (
                await database.scalar(
                    select(func.count()).select_from(HomeProjectionSnapshotRow)
                )
                == 0
            )
            operations = tuple(
                (await database.scalars(select(FinanceOperationRow))).all()
            )
            assert all(operation.amount == Decimal("35.00") for operation in operations)
            assert all(operation.account_id is not None for operation in operations)
            outbox = tuple(
                (await database.scalars(select(FinanceOutboxEventRow))).all()
            )
            assert all(
                set(event.payload)
                == {"schemaVersion", "operationId", "userId", "commandId"}
                for event in outbox
            )

        restarted_app = _application(session_factory=session_factory, tokens=tokens)
        async with AsyncClient(
            transport=ASGITransport(app=restarted_app),
            base_url="http://test",
        ) as restarted:
            persisted_replay = await restarted.post(
                "/api/v1/operations/commit",
                json=commit_body,
                headers=first.headers,
            )
            assert persisted_replay.status_code == 200
            assert persisted_replay.json()["idempotentReplay"] is True
            assert persisted_replay.json()["operation"]["operationId"] == operation_id
    finally:
        await engine.dispose()

    print("allocated finance operation PostgreSQL E2E: pass")


if __name__ == "__main__":
    asyncio.run(main())
