"""Ended sessions leave the database (run against a disposable PostgreSQL).

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/session_pruning_postgres_e2e.py

Migrates its own database: point it at an empty one.
"""

from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import func, select

from mobile_finance_api.auth_service import prune_ended_sessions
from mobile_finance_api.database import create_database
from mobile_finance_api.db_models import AuthRefreshTokenRow, AuthSessionRow, UserRow

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
API_ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 10, 30, 12, tzinfo=UTC)


def _migrate() -> None:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    command.upgrade(config, "head")


def _session(user_id, *, expires, revoked=None):  # type: ignore[no-untyped-def]
    return AuthSessionRow(
        id=uuid4(),
        user_id=user_id,
        created_at=expires - timedelta(days=90),
        last_seen_at=expires - timedelta(days=90),
        absolute_expires_at=expires,
        revoked_at=revoked,
        revocation_reason=None if revoked is None else "logout",
    )


async def _exercise() -> None:
    engine, session_factory = create_database(DATABASE_URL)
    try:
        user = UserRow(
            id=uuid4(),
            email_normalized=f"sessions-{uuid4().hex}@example.com",
            password_hash="synthetic",
            display_name="Synthetic",
            created_at=NOW,
            updated_at=NOW,
        )
        expired = _session(user.id, expires=NOW - timedelta(days=31))
        revoked = _session(
            user.id,
            expires=NOW + timedelta(days=30),
            revoked=NOW - timedelta(days=31),
        )
        recently_ended = _session(user.id, expires=NOW - timedelta(days=1))
        recently_revoked = _session(
            user.id,
            expires=NOW + timedelta(days=30),
            revoked=NOW - timedelta(days=1),
        )
        live = _session(user.id, expires=NOW + timedelta(days=30))
        token = AuthRefreshTokenRow(
            id=uuid4(),
            session_id=expired.id,
            token_hash=os.urandom(32),
            created_at=expired.created_at,
            expires_at=expired.absolute_expires_at,
        )
        async with session_factory() as database, database.begin():
            database.add(user)
            await database.flush()
            database.add_all([expired, revoked, recently_ended, recently_revoked, live])
            await database.flush()
            database.add(token)

        assert await prune_ended_sessions(session_factory, now=NOW) == 2

        async with session_factory() as database:
            left = set(await database.scalars(select(AuthSessionRow.id)))
            tokens = await database.scalar(
                select(func.count()).select_from(AuthRefreshTokenRow)
            )
        assert left == {recently_ended.id, recently_revoked.id, live.id}
        assert tokens == 0

        assert await prune_ended_sessions(session_factory, now=NOW) == 0
    finally:
        await engine.dispose()


def main() -> None:
    _migrate()
    asyncio.run(_exercise())
    print("session pruning E2E passed")


if __name__ == "__main__":
    main()
