"""A password changed and a forgotten one reset — against real PostgreSQL.

ADR 0035.

Opt-in, like the other PostgreSQL scripts. Migrates itself and wants an empty
database:

    MFA_TEST_DATABASE_URL=postgresql+asyncpg://... \
        python tests/credentials_postgres_e2e.py

Everything goes through the production wiring. What only a real database can
prove is checked here: the digest column and its constraint, the row lock that
lets one code be used once, which sessions survive, and that the migration will
not take a code away from someone holding it.
"""

from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime

import account_admin_postgres_e2e as fixture
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient, Response
from sqlalchemy import select, update

from mobile_finance_api.db_models import AuthSessionRow, UserRow
from mobile_finance_api.recovery_codes import hash_recovery_code

OWNER = "owner-credentials-e2e@example.com"
OTHER = "other-credentials-e2e@example.com"
NOBODY = "nobody-credentials-e2e@example.com"
SECOND_PASSWORD = "synthetic-password-456"
THIRD_PASSWORD = "synthetic-password-789"
FOURTH_PASSWORD = "synthetic-password-abc"
FIFTH_PASSWORD = "synthetic-password-def"
RACE_PASSWORDS = ("synthetic-race-one-123", "synthetic-race-two-123")

_STATUS = "/api/v1/auth/recovery-code"
_CHANGE = "/api/v1/auth/password/change"
_RESET = "/api/v1/auth/password/reset"
_REJECTED = {"detail": {"code": "RECOVERY_REJECTED"}}


async def _login(client: AsyncClient, email: str, password: str) -> Response:
    return await client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )


async def _session(client: AsyncClient, email: str, password: str) -> dict[str, str]:
    response = await _login(client, email, password)
    assert response.status_code == 200, response.text
    body = response.json()
    return {"access": body["accessToken"], "refresh": body["refreshToken"]}


async def _issue(client: AsyncClient, token: str, password: str) -> Response:
    return await client.post(
        _STATUS,
        json={"schemaVersion": "1", "password": password},
        headers=fixture._bearer(token),
    )


async def _reset(
    client: AsyncClient, email: str, code: str, new_password: str
) -> Response:
    return await client.post(
        _RESET,
        json={
            "schemaVersion": "1",
            "email": email,
            "recoveryCode": code,
            "newPassword": new_password,
        },
    )


async def _change(client: AsyncClient, token: str, current: str, new: str) -> Response:
    return await client.post(
        _CHANGE,
        json={"schemaVersion": "1", "currentPassword": current, "newPassword": new},
        headers=fixture._bearer(token),
    )


async def _status(client: AsyncClient, token: str) -> Response:
    return await client.get(_STATUS, headers=fixture._bearer(token))


async def _user(session_factory, email: str) -> UserRow:  # type: ignore[no-untyped-def]
    async with session_factory() as session:
        user = await session.scalar(
            select(UserRow).where(UserRow.email_normalized == email)
        )
    assert user is not None
    return user  # type: ignore[no-any-return]


async def _sessions(session_factory, user_id) -> int:  # type: ignore[no-untyped-def]
    async with session_factory() as session:
        rows = await session.scalars(
            select(AuthSessionRow.id).where(AuthSessionRow.user_id == user_id)
        )
        return len(rows.all())


async def main() -> None:
    from mobile_finance_api import runtime

    session_factory = runtime.session_factory
    try:
        async with AsyncClient(
            transport=ASGITransport(app=runtime.app),
            base_url="http://credentials-e2e.test",
        ) as client:
            owner = await fixture._register(client, OWNER)
            other = await fixture._register(client, OTHER)

            # Nobody has a code until they ask for one.
            status = await _status(client, owner["access"])
            assert status.status_code == 200, status.text
            assert status.json() == {
                "schemaVersion": "1",
                "exists": False,
                "createdAt": None,
            }

            # The password is what lets a session mint a code.
            refused = await _issue(client, owner["access"], "not-the-password-123")
            assert refused.status_code == 403, refused.text
            assert (await _user(session_factory, OWNER)).recovery_code_hash is None

            issued = await _issue(client, owner["access"], fixture.PASSWORD)
            assert issued.status_code == 201, issued.text
            first_code = issued.json()["recoveryCode"]
            stored = await _user(session_factory, OWNER)
            # A digest is stored, and it is the digest of what was shown.
            assert stored.recovery_code_hash == hash_recovery_code(first_code)
            assert len(stored.recovery_code_hash) == 32
            assert stored.recovery_code_created_at is not None
            status = await _status(client, owner["access"])
            assert status.json()["exists"] is True
            assert first_code not in status.text

            # Asking again replaces it: the one before stops working.
            reissued = await _issue(client, owner["access"], fixture.PASSWORD)
            second_code = reissued.json()["recoveryCode"]
            assert second_code != first_code
            stale = await _reset(client, OWNER, first_code, SECOND_PASSWORD)
            assert (stale.status_code, stale.json()) == (403, _REJECTED)

            # One refusal for every reason, so nothing says who has an account.
            unknown = await _reset(client, NOBODY, second_code, SECOND_PASSWORD)
            codeless = await _reset(client, OTHER, second_code, SECOND_PASSWORD)
            garbled = await _reset(client, OWNER, "not a code", SECOND_PASSWORD)
            not_an_address = await _reset(
                client, "not an address", second_code, SECOND_PASSWORD
            )
            for response in (unknown, codeless, garbled, not_an_address):
                assert (response.status_code, response.json()) == (403, _REJECTED)
            # A refused reset changed nothing.
            assert (await _login(client, OWNER, fixture.PASSWORD)).status_code == 200

            # A new password the server would not take is said to be that, and
            # the code is not spent on it.
            weak = await _reset(client, OWNER, second_code, "short")
            assert weak.status_code == 400, weak.text
            assert weak.json() == {"detail": {"code": "NEW_PASSWORD_REJECTED"}}

            # The reset itself, with the address and the code typed loosely.
            second_device = await _session(client, OWNER, fixture.PASSWORD)
            assert await _sessions(session_factory, stored.id) >= 2
            done = await _reset(
                client,
                "Owner-Credentials-E2E@Example.COM",
                second_code.replace("-", " ").lower(),
                SECOND_PASSWORD,
            )
            assert done.status_code == 200, done.text
            third_code = done.json()["recoveryCode"]
            assert third_code not in {first_code, second_code}
            after = await _user(session_factory, OWNER)
            assert after.recovery_code_hash == hash_recovery_code(third_code)
            assert after.password_hash != stored.password_hash
            # Everyone who was signed in with the forgotten password is out.
            assert await _sessions(session_factory, stored.id) == 0
            for token in (owner["access"], second_device["access"]):
                assert (await _status(client, token)).status_code == 401
            replay = await client.post(
                "/api/v1/auth/refresh", json={"refreshToken": owner["refresh"]}
            )
            assert replay.status_code == 401, replay.text
            assert (await _login(client, OWNER, fixture.PASSWORD)).status_code == 401
            # The code that was used is spent.
            spent = await _reset(client, OWNER, second_code, THIRD_PASSWORD)
            assert (spent.status_code, spent.json()) == (403, _REJECTED)
            assert (await _login(client, OWNER, SECOND_PASSWORD)).status_code == 200
            # Nobody else was touched.
            assert (await _status(client, other["access"])).status_code == 200

            # Changing the password keeps this device and signs out the others.
            here = await _session(client, OWNER, SECOND_PASSWORD)
            elsewhere = await _session(client, OWNER, SECOND_PASSWORD)
            wrong = await _change(
                client, here["access"], "not-the-password-123", THIRD_PASSWORD
            )
            assert wrong.status_code == 403, wrong.text
            unacceptable = await _change(
                client, here["access"], SECOND_PASSWORD, "short"
            )
            assert unacceptable.status_code == 400, unacceptable.text
            assert (await _status(client, elsewhere["access"])).status_code == 200
            changed = await _change(
                client, here["access"], SECOND_PASSWORD, THIRD_PASSWORD
            )
            assert changed.status_code == 204, changed.text
            assert (await _status(client, here["access"])).status_code == 200
            assert (await _status(client, elsewhere["access"])).status_code == 401
            kept = await client.post(
                "/api/v1/auth/refresh", json={"refreshToken": here["refresh"]}
            )
            assert kept.status_code == 200, kept.text
            assert (await _login(client, OWNER, SECOND_PASSWORD)).status_code == 401
            assert (await _login(client, OWNER, THIRD_PASSWORD)).status_code == 200
            # The recovery code is a second key and was left alone.
            unchanged = await _user(session_factory, OWNER)
            assert unchanged.recovery_code_hash == hash_recovery_code(third_code)

            # An account the operator blocked is not let back in by its code.
            async with session_factory() as session, session.begin():
                await session.execute(
                    update(UserRow)
                    .where(UserRow.email_normalized == OWNER)
                    .values(disabled_at=datetime.now(UTC))
                )
            blocked = await _reset(client, OWNER, third_code, FOURTH_PASSWORD)
            assert (blocked.status_code, blocked.json()) == (403, _REJECTED)
            async with session_factory() as session, session.begin():
                await session.execute(
                    update(UserRow)
                    .where(UserRow.email_normalized == OWNER)
                    .values(disabled_at=None)
                )
            assert (await _login(client, OWNER, THIRD_PASSWORD)).status_code == 200

            # A reset does not cancel a requested erasure; signing in does.
            closing = await _session(client, OWNER, THIRD_PASSWORD)
            scheduled = await client.post(
                "/api/v1/account/deletion",
                json={"schemaVersion": "1", "password": THIRD_PASSWORD},
                headers=fixture._bearer(closing["access"]),
            )
            assert scheduled.status_code == 202, scheduled.text
            recovered = await _reset(client, OWNER, third_code, FOURTH_PASSWORD)
            assert recovered.status_code == 200, recovered.text
            fourth_code = recovered.json()["recoveryCode"]
            assert (await _user(session_factory, OWNER)).deletion_due_at is not None
            back = await _login(client, OWNER, FOURTH_PASSWORD)
            assert back.status_code == 200, back.text
            assert back.json()["deletionCancelled"] is True
            assert (await _user(session_factory, OWNER)).deletion_due_at is None

            # One code, used twice at the same moment, opens the account once.
            race = await asyncio.gather(
                *(_reset(client, OWNER, fourth_code, word) for word in RACE_PASSWORDS)
            )
            assert sorted(response.status_code for response in race) == [200, 403]
            winner = RACE_PASSWORDS[
                [response.status_code for response in race].index(200)
            ]
            loser = next(word for word in RACE_PASSWORDS if word != winner)
            assert (await _login(client, OWNER, winner)).status_code == 200
            assert (await _login(client, OWNER, loser)).status_code == 401
            fifth_code = next(
                response.json()["recoveryCode"]
                for response in race
                if response.status_code == 200
            )
            assert (await _user(session_factory, OWNER)).recovery_code_hash == (
                hash_recovery_code(fifth_code)
            )

            # The export says a code exists and since when, and never its digest.
            final = await _session(client, OWNER, winner)
            export = await client.get(
                "/api/v1/account/export", headers=fixture._bearer(final["access"])
            )
            assert export.status_code == 200, export.text
            (row,) = export.json()["tables"]["users"]
            assert "recovery_code_created_at" in row
            assert "recovery_code_hash" not in row
            assert "password_hash" not in row
            assert fifth_code not in export.text

            # The operator's reset still works, and leaves the code alone.
            code, out, err = await fixture._admin(
                session_factory, "set-password", OWNER, password=FIFTH_PASSWORD
            )
            assert code == 0, err
            assert (await _login(client, OWNER, FIFTH_PASSWORD)).status_code == 200
            assert (await _user(session_factory, OWNER)).recovery_code_hash == (
                hash_recovery_code(fifth_code)
            )
    finally:
        await runtime.engine.dispose()


def _the_database_refuses_a_malformed_digest() -> None:
    async def scenario() -> None:
        from sqlalchemy.exc import IntegrityError

        from mobile_finance_api.database import create_database

        engine, session_factory = create_database(fixture.DATABASE_URL)
        try:
            for values in (
                {"recovery_code_hash": b"short"},
                {"recovery_code_hash": None},
                {"recovery_code_created_at": None},
            ):
                try:
                    async with session_factory() as session, session.begin():
                        await session.execute(
                            update(UserRow)
                            .where(UserRow.email_normalized == OWNER)
                            .values(**values)
                        )
                except IntegrityError as error:
                    assert "ck_users_recovery_code" in str(error)
                else:
                    raise AssertionError(f"the database accepted {sorted(values)}")
        finally:
            await engine.dispose()

    asyncio.run(scenario())


def _downgrade_refuses_while_someone_holds_a_code() -> None:
    """Dropping the column would leave a person with a code that no longer works."""

    config = Config(str(fixture.API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(fixture.API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", fixture.DATABASE_URL)
    try:
        command.downgrade(config, "0021_scheduled_account_erasure")
    except RuntimeError as error:
        assert "recovery code" in str(error)
    else:
        raise AssertionError("the downgrade dropped a code someone holds")

    async def forget_all() -> None:
        from mobile_finance_api.database import create_database

        engine, session_factory = create_database(fixture.DATABASE_URL)
        try:
            async with session_factory() as session, session.begin():
                await session.execute(
                    update(UserRow).values(
                        recovery_code_hash=None, recovery_code_created_at=None
                    )
                )
        finally:
            await engine.dispose()

    asyncio.run(forget_all())
    command.downgrade(config, "0021_scheduled_account_erasure")
    command.upgrade(config, "head")


if __name__ == "__main__":
    fixture._migrate()
    os.environ["MFA_AUTH_JWT_SECRET"] = "test-only-credentials-e2e-secret-32-bytes!!"
    for name in (
        "MFA_AUTH_REGISTRATION_ALLOWLIST",
        "MFA_RELEASE_DIR",
        "MFA_APP_DOWNLOAD_LINK_SECRET",
    ):
        os.environ.pop(name, None)
    asyncio.run(main())
    # Outside the event loop: Alembic's environment starts one of its own.
    _the_database_refuses_a_malformed_digest()
    _downgrade_refuses_while_someone_holds_a_code()
    print("credentials PostgreSQL E2E: pass")
