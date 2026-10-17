from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

import pytest

from mobile_finance_api import projector_runtime
from mobile_finance_api.postgres_home_projector import ProjectionCycleResult
from mobile_finance_api.projector_supervision import (
    EventRetryPolicy,
    ProjectorHealth,
    RevisionRetentionPolicy,
)


class _FailingHeartbeatLease:
    def __init__(self) -> None:
        self.calls = 0
        self.active_calls = 0
        self.maximum_active_calls = 0
        self.failure_requested = asyncio.Event()
        self.failure_call_started = asyncio.Event()

    async def heartbeat(self, *, status: str) -> None:
        del status
        self.calls += 1
        self.active_calls += 1
        self.maximum_active_calls = max(
            self.maximum_active_calls,
            self.active_calls,
        )
        try:
            if self.calls == 1:
                return
            self.failure_call_started.set()
            await self.failure_requested.wait()
            raise RuntimeError("private value must not reach logs")
        finally:
            self.active_calls -= 1


class _StubRecurrences:
    """Stands in for the materialiser the projector leader now also runs.

    Recurrence has its own tests; here it only has to be present and quiet, so
    a cycle's shape can still be asserted without a database.
    """

    def __init__(self, **kwargs: object) -> None:
        del kwargs

    async def materialise_active_rules(self, **kwargs: object) -> int:
        del kwargs
        return 0


async def _no_due_erasures(session_factory: object, **kwargs: object) -> int:
    """Stands in for the scheduled erasure the leader also runs (ADR 0030).

    Erasure has its own tests against PostgreSQL; here it only has to be
    present and quiet, like the materialiser above.
    """

    del session_factory, kwargs
    return 0


@pytest.fixture(autouse=True)
def _quiet_erasure(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(projector_runtime, "erase_due_accounts", _no_due_erasures)


class _HealthyBlockingLease:
    def __init__(self) -> None:
        self.calls = 0
        self.active_calls = 0
        self.maximum_active_calls = 0
        self.call_cancelled = False
        self.cleanup_succeeded = False
        self.blocking_call_started = asyncio.Event()
        self.release_blocking_call = asyncio.Event()

    async def heartbeat(self, *, status: str) -> None:
        del status
        self.calls += 1
        self.active_calls += 1
        self.maximum_active_calls = max(
            self.maximum_active_calls,
            self.active_calls,
        )
        try:
            if self.calls > 1:
                self.blocking_call_started.set()
                await self.release_blocking_call.wait()
        except asyncio.CancelledError:
            self.call_cancelled = True
            raise
        finally:
            self.active_calls -= 1

    async def stop_and_unlock(self) -> None:
        if self.active_calls or self.call_cancelled:
            raise RuntimeError("lease connection requires rollback")
        self.cleanup_succeeded = True


def test_heartbeat_loss_cancels_guarded_work_without_concurrent_lease_calls() -> None:
    async def scenario() -> tuple[_FailingHeartbeatLease, bool]:
        lease = _FailingHeartbeatLease()
        work_started = asyncio.Event()
        work_cancelled = asyncio.Event()

        async def work(set_status):  # type: ignore[no-untyped-def]
            set_status("published")
            work_started.set()
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                work_cancelled.set()
                raise

        guarded = asyncio.create_task(
            projector_runtime._run_guarded_leader_work(
                lease=lease,  # type: ignore[arg-type]
                heartbeat_stale_seconds=0.3,
                work=work,
            )
        )
        await asyncio.wait_for(work_started.wait(), timeout=1)
        await asyncio.wait_for(lease.failure_call_started.wait(), timeout=1)
        lease.failure_requested.set()
        with pytest.raises(RuntimeError, match="private value"):
            await asyncio.wait_for(guarded, timeout=1)
        return lease, work_cancelled.is_set()

    lease, work_cancelled = asyncio.run(scenario())

    assert work_cancelled is True
    assert lease.maximum_active_calls == 1


def test_successful_one_shot_cooperatively_stops_heartbeat_before_lease_cleanup(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    lease = _HealthyBlockingLease()
    calls: list[str] = []

    class _Engine:
        async def dispose(self) -> None:
            calls.append("dispose")

    class _Projector:
        def __init__(self, **kwargs) -> None:  # type: ignore[no-untyped-def]
            del kwargs

        async def reconcile_all(self) -> ProjectionCycleResult:
            await lease.blocking_call_started.wait()
            return ProjectionCycleResult(0, 1, False)

        async def drain_available(
            self,
            *,
            max_candidates: int,
        ) -> ProjectionCycleResult:
            assert max_candidates == 1
            return ProjectionCycleResult(1, 1, False)

    async def prune(**kwargs) -> int:  # type: ignore[no-untyped-def]
        del kwargs
        asyncio.get_running_loop().call_later(
            0.01,
            lease.release_blocking_call.set,
        )
        return 0

    @asynccontextmanager
    async def leadership(**kwargs):  # type: ignore[no-untyped-def]
        del kwargs
        try:
            yield lease
        finally:
            await lease.stop_and_unlock()
            calls.append("stop_and_unlock")

    monkeypatch.setattr(
        projector_runtime,
        "create_database",
        lambda database_url: (_Engine(), object()),
    )
    monkeypatch.setattr(projector_runtime, "require_database_url", lambda: "unused")
    monkeypatch.setattr(projector_runtime, "PostgresHomeProjector", _Projector)
    monkeypatch.setattr(
        projector_runtime,
        "PostgresPlannedCostRecurrenceRepository",
        _StubRecurrences,
    )
    monkeypatch.setattr(projector_runtime, "prune_home_revisions", prune)
    monkeypatch.setattr(
        projector_runtime,
        "acquire_projector_leadership",
        leadership,
    )

    acquired = asyncio.run(
        projector_runtime._run_once(
            max_cycles=1,
            heartbeat_stale_seconds=0.3,
            retry_policy=EventRetryPolicy(),
            retention_policy=RevisionRetentionPolicy(),
        )
    )

    assert acquired is True
    assert lease.cleanup_succeeded is True
    assert lease.call_cancelled is False
    assert lease.maximum_active_calls == 1
    assert calls == ["stop_and_unlock", "dispose"]


def test_one_shot_heartbeat_loss_cancels_projection_before_dispose(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[str] = []
    lease: _FailingHeartbeatLease | None = None

    class _Engine:
        async def dispose(self) -> None:
            calls.append("dispose")

    class _Projector:
        def __init__(self, **kwargs) -> None:  # type: ignore[no-untyped-def]
            del kwargs

        async def reconcile_all(self) -> ProjectionCycleResult:
            calls.append("reconcile")
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                calls.append("cancelled")
                raise

        async def drain_available(
            self,
            *,
            max_candidates: int,
        ) -> ProjectionCycleResult:
            raise AssertionError(max_candidates)

    @asynccontextmanager
    async def leadership(**kwargs):  # type: ignore[no-untyped-def]
        nonlocal lease
        del kwargs
        lease = _FailingHeartbeatLease()

        async def request_failure() -> None:
            await lease.failure_call_started.wait()
            lease.failure_requested.set()

        failure_task = asyncio.create_task(request_failure())
        try:
            yield lease
        finally:
            await failure_task

    monkeypatch.setattr(
        projector_runtime,
        "create_database",
        lambda database_url: (_Engine(), object()),
    )
    monkeypatch.setattr(projector_runtime, "require_database_url", lambda: "unused")
    monkeypatch.setattr(projector_runtime, "PostgresHomeProjector", _Projector)
    monkeypatch.setattr(
        projector_runtime,
        "PostgresPlannedCostRecurrenceRepository",
        _StubRecurrences,
    )
    monkeypatch.setattr(
        projector_runtime,
        "acquire_projector_leadership",
        leadership,
    )

    with pytest.raises(RuntimeError, match="private value"):
        asyncio.run(
            projector_runtime._run_once(
                max_cycles=1,
                heartbeat_stale_seconds=0.03,
                retry_policy=EventRetryPolicy(),
                retention_policy=RevisionRetentionPolicy(),
            )
        )

    assert lease is not None
    assert lease.maximum_active_calls == 1
    assert calls == ["reconcile", "cancelled", "dispose"]


def test_continuous_runtime_reacquires_after_heartbeat_loss(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    async def scenario() -> tuple[int, list[str], int]:
        calls: list[str] = []
        acquisitions = 0
        reacquired = asyncio.Event()
        first_lease = _FailingHeartbeatLease()

        class _Engine:
            async def dispose(self) -> None:
                calls.append("dispose")

        class _Projector:
            def __init__(self, **kwargs) -> None:  # type: ignore[no-untyped-def]
                del kwargs

            async def drain_available(
                self,
                *,
                max_candidates: int,
            ) -> ProjectionCycleResult:
                del max_candidates
                calls.append("drain")
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    calls.append("cancelled")
                    raise

            async def reconcile_all(self) -> ProjectionCycleResult:
                raise AssertionError("reconciliation must not start")

        @asynccontextmanager
        async def leadership(**kwargs):  # type: ignore[no-untyped-def]
            nonlocal acquisitions
            del kwargs
            acquisitions += 1
            if acquisitions == 1:

                async def request_failure() -> None:
                    await first_lease.failure_call_started.wait()
                    first_lease.failure_requested.set()

                failure_task = asyncio.create_task(request_failure())
                try:
                    yield first_lease
                finally:
                    await failure_task
                return
            reacquired.set()
            yield None

        monkeypatch.setattr(
            projector_runtime,
            "create_database",
            lambda database_url: (_Engine(), object()),
        )
        monkeypatch.setattr(
            projector_runtime,
            "require_database_url",
            lambda: "unused",
        )
        monkeypatch.setattr(projector_runtime, "PostgresHomeProjector", _Projector)
        monkeypatch.setattr(
            projector_runtime,
            "PostgresPlannedCostRecurrenceRepository",
            _StubRecurrences,
        )
        monkeypatch.setattr(
            projector_runtime,
            "acquire_projector_leadership",
            leadership,
        )

        runtime = asyncio.create_task(
            projector_runtime._run_forever(
                poll_seconds=10,
                reconcile_seconds=10,
                max_cycles=1,
                leader_retry_seconds=10,
                runtime_backoff_initial_seconds=0.001,
                runtime_backoff_maximum_seconds=0.001,
                health_seconds=10,
                heartbeat_stale_seconds=0.03,
                maximum_lag_seconds=10,
                retention_seconds=10,
                materialise_seconds=10,
                erasure_seconds=10,
                retry_policy=EventRetryPolicy(),
                retention_policy=RevisionRetentionPolicy(),
            )
        )
        await asyncio.wait_for(reacquired.wait(), timeout=1)
        runtime.cancel()
        with pytest.raises(asyncio.CancelledError):
            await runtime
        return acquisitions, calls, first_lease.maximum_active_calls

    with caplog.at_level(
        logging.ERROR,
        logger="mobile_finance_api.home_projector",
    ):
        acquisitions, calls, maximum_active_calls = asyncio.run(scenario())

    assert acquisitions >= 2
    assert calls == ["drain", "cancelled", "dispose"]
    assert maximum_active_calls == 1
    assert "RuntimeError" in caplog.text
    assert "private value" not in caplog.text


def test_health_check_construction_error_returns_two_without_sensitive_log(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setattr(
        projector_runtime,
        "_check_health",
        lambda **kwargs: (_ for _ in ()).throw(
            RuntimeError("private value must not reach logs")
        ),
    )

    with caplog.at_level(
        "ERROR",
        logger="mobile_finance_api.home_projector",
    ):
        exit_code = projector_runtime.main(["--check-health"])

    assert exit_code == 2
    assert "RuntimeError" in caplog.text
    assert "private value" not in caplog.text


def test_failed_continuous_cycle_advances_backoff_exactly_once(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    after_failure_calls = 0
    reset_calls = 0
    statuses: list[str] = []

    class _Backoff:
        def __init__(self, **kwargs) -> None:  # type: ignore[no-untyped-def]
            del kwargs

        def after_failure(self) -> float:
            nonlocal after_failure_calls
            after_failure_calls += 1
            return 0.001

        def reset(self) -> None:
            nonlocal reset_calls
            reset_calls += 1

    class _Projector:
        async def drain_available(
            self,
            *,
            max_candidates: int,
        ) -> ProjectionCycleResult:
            del max_candidates
            return ProjectionCycleResult(
                published=1,
                inspected=2,
                failures_present=True,
            )

        async def reconcile_all(self) -> ProjectionCycleResult:
            return ProjectionCycleResult(
                published=1,
                inspected=2,
                failures_present=True,
            )

    async def failing_retention(**kwargs) -> int:  # type: ignore[no-untyped-def]
        del kwargs
        raise RuntimeError("synthetic retention failure")

    async def healthy(**kwargs) -> ProjectorHealth:  # type: ignore[no-untyped-def]
        del kwargs
        return ProjectorHealth(
            status="healthy",
            leader="present",
            heartbeat_age="fresh",
            pending_lag="none",
            dead_letters="none",
            last_cycle="ok",
        )

    async def stop_after_delay(delay: float) -> None:
        assert delay == 0.001
        raise asyncio.CancelledError

    monkeypatch.setattr(projector_runtime, "BoundedRuntimeBackoff", _Backoff)
    monkeypatch.setattr(
        projector_runtime,
        "prune_home_revisions",
        failing_retention,
    )
    monkeypatch.setattr(projector_runtime, "read_projector_health", healthy)
    monkeypatch.setattr(projector_runtime.asyncio, "sleep", stop_after_delay)

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(
            projector_runtime._run_leader_loop(
                set_status=statuses.append,
                projector=_Projector(),  # type: ignore[arg-type]
                poll_seconds=1,
                reconcile_seconds=1,
                max_cycles=5,
                runtime_backoff_initial_seconds=0.001,
                runtime_backoff_maximum_seconds=1,
                health_seconds=1,
                heartbeat_stale_seconds=1,
                maximum_lag_seconds=1,
                retention_seconds=1,
                materialise_seconds=1,
                erasure_seconds=1,
                session_factory=object(),  # type: ignore[arg-type]
                recurrences=_StubRecurrences(),  # type: ignore[arg-type]
                retention_policy=RevisionRetentionPolicy(),
            )
        )

    assert after_failure_calls == 1
    assert reset_calls == 0
    assert statuses == ["degraded"]
