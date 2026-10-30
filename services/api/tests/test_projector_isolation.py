"""One account's broken ledger is that account's problem.

The projector takes the oldest pending stream first, and a stream that cannot be
projected stays the oldest. Without a pause of its own it is tried first on every
cycle and uses up the cycle's budget, so enough of them starve everybody else.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from mobile_finance_api.home_projection import HomeProjectionInvariantError
from mobile_finance_api.postgres_home_projector import (
    PostgresHomeProjector,
    _OutboxCandidate,
    _ProjectionStreamBlocked,
)

_START = datetime(2026, 10, 30, 12, tzinfo=UTC)


class _ScriptedProjector(PostgresHomeProjector):
    """The drain loop over a queue of users, with no database underneath."""

    def __init__(self, *, broken: list[UUID], healthy: list[UUID]) -> None:
        self.now = _START
        super().__init__(
            session_factory=None,  # type: ignore[arg-type]
            clock=lambda: self.now,
        )
        self.broken = set(broken)
        self.queue = [*broken, *healthy]
        self.attempts: list[UUID] = []

    async def _next_candidate(
        self, *, excluded_user_ids: set[UUID]
    ) -> _OutboxCandidate | None:
        for user_id in self.queue:
            if user_id not in excluded_user_ids:
                return _OutboxCandidate(
                    kind="operation",
                    event_id=uuid4(),
                    user_id=user_id,
                    created_at=_START,
                )
        return None

    async def _project_user(
        self, user_id: UUID, *, require_pending: bool, allow_blocked: bool = False
    ) -> bool:
        del require_pending, allow_blocked
        self.attempts.append(user_id)
        if user_id in self.broken:
            raise HomeProjectionInvariantError("synthetic overflow")
        self.queue.remove(user_id)
        return True


def _users(count: int) -> list[UUID]:
    return [uuid4() for _ in range(count)]


def _drain(projector: _ScriptedProjector, *, max_candidates: int = 100):  # type: ignore[no-untyped-def]
    return asyncio.run(projector.drain_available(max_candidates=max_candidates))


def test_a_full_cycle_of_broken_accounts_does_not_starve_the_next_person() -> None:
    honest = _users(1)
    projector = _ScriptedProjector(broken=_users(100), healthy=honest)

    _drain(projector)
    projector.attempts.clear()
    result = _drain(projector)

    assert projector.attempts == honest
    assert result.published == 1


def test_a_broken_account_is_not_tried_again_on_every_cycle() -> None:
    broken = _users(1)
    projector = _ScriptedProjector(broken=broken, healthy=[])

    _drain(projector)
    _drain(projector)
    _drain(projector)

    assert projector.attempts == broken


def test_the_pause_ends_and_grows() -> None:
    broken = _users(1)
    projector = _ScriptedProjector(broken=broken, healthy=[])

    _drain(projector)
    projector.now += timedelta(seconds=61)
    _drain(projector)
    assert len(projector.attempts) == 2

    projector.now += timedelta(seconds=61)
    _drain(projector)
    assert len(projector.attempts) == 2, "the second pause is longer than the first"

    projector.now += timedelta(seconds=61)
    _drain(projector)
    assert len(projector.attempts) == 3


def test_the_pause_has_a_ceiling() -> None:
    broken = _users(1)
    projector = _ScriptedProjector(broken=broken, healthy=[])

    for _ in range(12):
        _drain(projector)
        projector.now += timedelta(hours=1, seconds=1)

    assert len(projector.attempts) == 12


def test_a_repaired_account_starts_from_the_first_pause_again() -> None:
    user = _users(1)
    projector = _ScriptedProjector(broken=user, healthy=[])

    _drain(projector)
    projector.now += timedelta(seconds=61)
    _drain(projector)
    projector.now += timedelta(seconds=121)
    projector.broken.clear()
    _drain(projector)

    assert projector._cooldowns == {}


def test_the_failure_is_still_reported() -> None:
    projector = _ScriptedProjector(broken=_users(1), healthy=[])

    assert _drain(projector).failures_present is True


def test_a_user_already_waiting_on_a_retry_is_not_a_failure() -> None:
    class _Blocked(_ScriptedProjector):
        async def _project_user(
            self, user_id: UUID, *, require_pending: bool, allow_blocked: bool = False
        ) -> bool:
            raise _ProjectionStreamBlocked

    projector = _Blocked(broken=_users(1), healthy=[])

    assert _drain(projector).failures_present is False
    assert projector._cooldowns == {}
