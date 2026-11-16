"""Whether this process can serve a request that needs the database.

Every other route answers 401 before it looks at PostgreSQL, so a watcher that
only asks "does the API answer" keeps hearing yes while every signed-in request
fails. This asks the question a phone would: can a query get through the same
pool the requests use.

It says up or down and nothing else. The route is open to anyone, so it names
no cause, counts nothing, and reaches the database at most once every few
seconds however often it is asked.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable
from typing import Protocol

from sqlalchemy import text

from .database import AsyncSessionFactory

_logger = logging.getLogger(__name__)

#: How long one answer is reused. Short enough that a watcher asking every few
#: minutes always gets a fresh one; long enough that a flood asks once.
DEFAULT_CACHE_SECONDS = 5.0

#: Far below the statement timeout: a database that takes this long to say
#: `1` is not serving anyone.
DEFAULT_TIMEOUT_SECONDS = 3.0


class ServiceHealth(Protocol):
    async def serving(self) -> bool:
        """Whether a request that needs the database would be answered."""


class UnavailableServiceHealth:
    """Fail closed when no database is wired."""

    async def serving(self) -> bool:
        return False


class DatabaseServiceHealth:
    """Runs one trivial query through the pool the requests share."""

    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], float] = time.monotonic,
        cache_seconds: float = DEFAULT_CACHE_SECONDS,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock
        self._cache_seconds = cache_seconds
        self._timeout_seconds = timeout_seconds
        self._lock = asyncio.Lock()
        self._answer: bool | None = None
        self._answered_at = 0.0

    async def serving(self) -> bool:
        # One caller asks the database; the ones that arrive meanwhile wait for
        # that answer instead of each taking a connection.
        async with self._lock:
            now = self._clock()
            if (
                self._answer is not None
                and now - self._answered_at < self._cache_seconds
            ):
                return self._answer
            answer = await self._ask()
            self._answer = answer
            self._answered_at = self._clock()
            return answer

    async def _ask(self) -> bool:
        try:
            async with asyncio.timeout(self._timeout_seconds):
                async with self._session_factory() as session:
                    await session.execute(text("SELECT 1"))
        except Exception as error:
            # The kind of failure, never its text: a driver error can carry
            # the connection string.
            _logger.warning(
                "Service health: the database did not answer (%s)",
                type(error).__name__,
            )
            return False
        return True
