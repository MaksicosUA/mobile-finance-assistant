"""What a watcher is told about this service, and how little else."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any, cast

from httpx import ASGITransport, AsyncClient, Response

from mobile_finance_api.database import AsyncSessionFactory
from mobile_finance_api.main import create_app
from mobile_finance_api.service_health import (
    DatabaseServiceHealth,
    UnavailableServiceHealth,
)


class _Session:
    def __init__(self, owner: _Database) -> None:
        self._owner = owner

    async def execute(self, statement: Any) -> None:
        self._owner.statements.append(str(statement))
        if self._owner.delay:
            await asyncio.sleep(self._owner.delay)
        if self._owner.failure is not None:
            raise self._owner.failure


class _Database:
    """A session factory that answers, fails, or takes its time."""

    def __init__(self) -> None:
        self.statements: list[str] = []
        self.failure: Exception | None = None
        self.delay = 0.0
        self.opened = 0

    def factory(self) -> AsyncSessionFactory:
        return cast(AsyncSessionFactory, self._open)

    @asynccontextmanager
    async def _open(self) -> AsyncIterator[_Session]:
        self.opened += 1
        yield _Session(self)


class _Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class _Answers:
    def __init__(self, *, serving: bool) -> None:
        self._serving = serving
        self.asked = 0

    async def serving(self) -> bool:
        self.asked += 1
        return self._serving


def _get(health: object | None, path: str = "/api/v1/health") -> Response:
    app = create_app(service_health=cast(Any, health))

    async def scenario() -> Response:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="https://api.test"
        ) as client:
            return await client.get(path)

    return asyncio.run(scenario())


# --- the route ---------------------------------------------------------------


def test_a_serving_service_says_ok_to_anyone() -> None:
    response = _get(_Answers(serving=True))

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_a_service_that_cannot_reach_its_database_is_503() -> None:
    response = _get(_Answers(serving=False))

    assert response.status_code == 503
    # Up or down. No cause, no version, no count: the route has no door.
    assert response.json() == {"status": "unavailable"}


def test_neither_answer_may_be_kept_by_a_cache() -> None:
    # A cached "ok" in front of a dead service is the one wrong answer. The
    # header comes from the rule every route under /api/ gets.
    for serving in (True, False):
        response = _get(_Answers(serving=serving))
        assert response.headers["cache-control"] == "no-store"


def test_an_app_with_no_database_wired_is_down_not_ok() -> None:
    assert _get(None).status_code == 503
    assert asyncio.run(UnavailableServiceHealth().serving()) is False


def test_the_route_is_only_read() -> None:
    app = create_app(service_health=cast(Any, _Answers(serving=True)))

    async def scenario() -> Response:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="https://api.test"
        ) as client:
            return await client.post("/api/v1/health", json={})

    assert asyncio.run(scenario()).status_code == 405


# --- the probe ---------------------------------------------------------------


def test_one_trivial_query_goes_through_the_request_pool() -> None:
    database = _Database()
    health = DatabaseServiceHealth(session_factory=database.factory())

    assert asyncio.run(health.serving()) is True
    assert database.statements == ["SELECT 1"]


def test_a_database_that_refuses_is_down_and_nothing_is_raised() -> None:
    database = _Database()
    database.failure = RuntimeError("postgresql://someone:secret@host/db refused")
    health = DatabaseServiceHealth(session_factory=database.factory())

    assert asyncio.run(health.serving()) is False


def test_the_refusal_is_logged_by_kind_never_by_text(caplog: Any) -> None:
    database = _Database()
    database.failure = RuntimeError("postgresql://someone:secret@host/db refused")
    health = DatabaseServiceHealth(session_factory=database.factory())

    with caplog.at_level("WARNING"):
        asyncio.run(health.serving())

    assert "RuntimeError" in caplog.text
    assert "secret" not in caplog.text


def test_a_database_that_does_not_answer_in_time_is_down() -> None:
    database = _Database()
    database.delay = 5.0
    health = DatabaseServiceHealth(
        session_factory=database.factory(), timeout_seconds=0.05
    )

    assert asyncio.run(health.serving()) is False


def test_an_answer_is_reused_for_a_few_seconds_then_asked_again() -> None:
    database = _Database()
    clock = _Clock()
    health = DatabaseServiceHealth(
        session_factory=database.factory(), clock=clock, cache_seconds=5.0
    )

    async def scenario() -> None:
        assert await health.serving() is True
        clock.now += 4.9
        assert await health.serving() is True
        assert database.opened == 1
        clock.now += 0.2
        assert await health.serving() is True
        assert database.opened == 2

    asyncio.run(scenario())


def test_a_failure_is_not_remembered_longer_than_a_success() -> None:
    database = _Database()
    clock = _Clock()
    health = DatabaseServiceHealth(
        session_factory=database.factory(), clock=clock, cache_seconds=5.0
    )

    async def scenario() -> None:
        database.failure = RuntimeError("down")
        assert await health.serving() is False
        database.failure = None
        clock.now += 1.0
        # Still the cached answer: a flood during an outage asks once too.
        assert await health.serving() is False
        clock.now += 5.0
        assert await health.serving() is True

    asyncio.run(scenario())


def test_a_crowd_arriving_together_costs_one_query() -> None:
    database = _Database()
    database.delay = 0.02
    health = DatabaseServiceHealth(session_factory=database.factory())

    async def scenario() -> list[bool]:
        return list(await asyncio.gather(*(health.serving() for _ in range(25))))

    assert asyncio.run(scenario()) == [True] * 25
    assert database.opened == 1
