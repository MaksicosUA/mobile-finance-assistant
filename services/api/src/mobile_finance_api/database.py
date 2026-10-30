"""Async PostgreSQL engine and session construction."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

type AsyncSessionFactory = async_sessionmaker[AsyncSession]


def create_database(database_url: str) -> tuple[AsyncEngine, AsyncSessionFactory]:
    """Create a bounded async engine without opening a connection eagerly."""

    if not database_url.startswith("postgresql+asyncpg://"):
        raise ValueError("MFA_DATABASE_URL must use postgresql+asyncpg")
    engine = create_async_engine(
        database_url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        pool_recycle=1800,
        # One slow statement must not hold a connection from everyone else. The
        # pool above is small, and every request shares it.
        connect_args={"server_settings": {"statement_timeout": "30000"}},
    )
    return engine, async_sessionmaker(engine, expire_on_commit=False)


@asynccontextmanager
async def database_session(
    session_factory: AsyncSessionFactory,
) -> AsyncIterator[AsyncSession]:
    """Yield one session and guarantee it is closed."""

    async with session_factory() as session:
        yield session
