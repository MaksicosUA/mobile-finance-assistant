"""Operational runtime for the deterministic PostgreSQL Home projector."""

from __future__ import annotations

import argparse
import asyncio
import logging
import math
import time
from collections.abc import Awaitable, Callable, Sequence
from datetime import UTC, datetime

from .account_data import erase_due_accounts
from .config import require_database_url
from .database import AsyncSessionFactory, create_database
from .postgres_home_projector import PostgresHomeProjector
from .postgres_planned_cost_recurrence_repository import (
    PostgresPlannedCostRecurrenceRepository,
)
from .postgres_projector_supervision import (
    ProjectorLeaderLease,
    acquire_projector_leadership,
    prune_home_revisions,
    read_projector_health,
)
from .projector_supervision import (
    BoundedRuntimeBackoff,
    EventRetryPolicy,
    ProjectorHealth,
    RevisionRetentionPolicy,
)

_LOGGER = logging.getLogger("mobile_finance_api.home_projector")
_EX_TEMPFAIL = 75


class _ProjectionCycleFailed(RuntimeError):
    """One or more isolated projection streams failed in a bounded cycle."""


class _LeaseHeartbeat:
    """Serialize lease heartbeats independently from projector work."""

    def __init__(
        self,
        *,
        lease: ProjectorLeaderLease,
        heartbeat_stale_seconds: float,
    ) -> None:
        if not math.isfinite(heartbeat_stale_seconds) or heartbeat_stale_seconds <= 0:
            raise ValueError("heartbeat stale interval must be positive")
        # A stalled write is detected and work is cancelled before the last
        # successful heartbeat can become stale. Both the wait between writes
        # and the per-write timeout are one third of the stale threshold.
        self._interval_seconds = heartbeat_stale_seconds / 3
        self._lease = lease
        self._status = "starting"
        self._status_changed = asyncio.Event()
        self._ready = asyncio.Event()
        self._stop_requested = False

    def set_status(self, status: str) -> None:
        self._status = status
        self._status_changed.set()

    async def wait_until_ready(self) -> None:
        await self._ready.wait()

    def request_stop(self) -> None:
        self._stop_requested = True
        self._status_changed.set()

    async def run(self) -> None:
        while not self._stop_requested:
            # Clear before reading so an update concurrent with the database
            # call remains set and triggers an immediate serialized follow-up.
            self._status_changed.clear()
            if self._stop_requested:
                return
            status = self._status
            await asyncio.wait_for(
                self._lease.heartbeat(status=status),
                timeout=self._interval_seconds,
            )
            self._ready.set()
            if self._stop_requested:
                return
            try:
                await asyncio.wait_for(
                    self._status_changed.wait(),
                    timeout=self._interval_seconds,
                )
            except TimeoutError:
                pass


async def _run_guarded_leader_work[WorkResult](
    *,
    lease: ProjectorLeaderLease,
    heartbeat_stale_seconds: float,
    work: Callable[[Callable[[str], None]], Awaitable[WorkResult]],
) -> WorkResult:
    """Run work only while a dedicated background lease heartbeat is healthy."""

    heartbeat = _LeaseHeartbeat(
        lease=lease,
        heartbeat_stale_seconds=heartbeat_stale_seconds,
    )
    heartbeat_task = asyncio.create_task(
        heartbeat.run(),
        name="home-projector-lease-heartbeat",
    )
    ready_task = asyncio.create_task(
        heartbeat.wait_until_ready(),
        name="home-projector-lease-heartbeat-ready",
    )
    work_task: asyncio.Future[WorkResult] | None = None

    async def shutdown() -> None:
        # Never cancel a healthy heartbeat while SQLAlchemy is using the
        # dedicated lease connection: doing so can leave it in pending
        # rollback and break the context manager's stop/unlock cleanup.
        heartbeat.request_stop()
        for task in (work_task, ready_task):
            if task is not None and not task.done():
                task.cancel()
        await asyncio.gather(
            *(task for task in (work_task, ready_task, heartbeat_task) if task),
            return_exceptions=True,
        )

    try:
        ready_or_failed, _ = await asyncio.wait(
            {heartbeat_task, ready_task},
            return_when=asyncio.FIRST_COMPLETED,
        )
        if heartbeat_task in ready_or_failed:
            await heartbeat_task
            raise RuntimeError("projector lease heartbeat stopped unexpectedly")
        await ready_task

        work_task = asyncio.ensure_future(work(heartbeat.set_status))
        completed, _ = await asyncio.wait(
            {heartbeat_task, work_task},
            return_when=asyncio.FIRST_COMPLETED,
        )
        if heartbeat_task in completed:
            # The finally block cancels and awaits work before the leadership
            # context can stop/unlock the dedicated lease connection.
            await heartbeat_task
            raise RuntimeError("projector lease heartbeat stopped unexpectedly")
        result = await work_task
    except BaseException:
        await shutdown()
        raise

    await shutdown()
    if heartbeat_task.cancelled():
        raise RuntimeError("projector lease heartbeat was cancelled unexpectedly")
    heartbeat_error = heartbeat_task.exception()
    if heartbeat_error is not None:
        raise heartbeat_error
    return result


async def _run_once(
    *,
    max_cycles: int,
    heartbeat_stale_seconds: float,
    retry_policy: EventRetryPolicy,
    retention_policy: RevisionRetentionPolicy,
) -> bool:
    engine, session_factory = create_database(require_database_url())
    projector = PostgresHomeProjector(
        session_factory=session_factory,
        retry_policy=retry_policy,
    )
    recurrences = PostgresPlannedCostRecurrenceRepository(
        session_factory=session_factory,
    )
    try:
        async with acquire_projector_leadership(engine=engine) as lease:
            if lease is None:
                return False

            async def one_shot_work(
                set_status: Callable[[str], None],
            ) -> None:
                # Extend repeating plans first: the instances it writes publish
                # their own invalidations, which the same cycle then consumes.
                materialised = await recurrences.materialise_active_rules()
                # Accounts whose week has run out go before anything is built
                # for them (ADR 0030).
                erased = await erase_due_accounts(
                    session_factory, now=datetime.now(UTC)
                )
                # Reconcile healthy users before processing event streams.
                reconciliation = await projector.reconcile_all()
                projection = await projector.drain_available(max_candidates=max_cycles)
                pruned = await prune_home_revisions(
                    session_factory=session_factory,
                    policy=retention_policy,
                )
                failures_present = (
                    reconciliation.failures_present or projection.failures_present
                )
                if failures_present:
                    set_status("degraded")
                elif reconciliation.published or projection.published:
                    set_status("published")
                else:
                    set_status("idle")
                _LOGGER.info(
                    "Home projector cycle complete consumed=%d "
                    "reconciled=%d materialised=%d erased=%d pruned=%d failures=%s",
                    projection.published,
                    reconciliation.published,
                    materialised,
                    erased,
                    pruned,
                    failures_present,
                )
                if failures_present:
                    raise _ProjectionCycleFailed(
                        "one or more projection streams failed"
                    )

            await _run_guarded_leader_work(
                lease=lease,
                heartbeat_stale_seconds=heartbeat_stale_seconds,
                work=one_shot_work,
            )
            return True
    finally:
        await engine.dispose()


async def _run_forever(
    *,
    poll_seconds: float,
    reconcile_seconds: float,
    max_cycles: int,
    leader_retry_seconds: float,
    runtime_backoff_initial_seconds: float,
    runtime_backoff_maximum_seconds: float,
    health_seconds: float,
    heartbeat_stale_seconds: float,
    maximum_lag_seconds: float,
    retention_seconds: float,
    materialise_seconds: float,
    erasure_seconds: float,
    retry_policy: EventRetryPolicy,
    retention_policy: RevisionRetentionPolicy,
) -> None:
    engine, session_factory = create_database(require_database_url())
    projector = PostgresHomeProjector(
        session_factory=session_factory,
        retry_policy=retry_policy,
    )
    recurrences = PostgresPlannedCostRecurrenceRepository(
        session_factory=session_factory,
    )
    leadership_backoff = BoundedRuntimeBackoff(
        initial_seconds=runtime_backoff_initial_seconds,
        maximum_seconds=runtime_backoff_maximum_seconds,
    )
    try:
        while True:
            try:
                async with acquire_projector_leadership(engine=engine) as lease:
                    if lease is None:
                        leadership_backoff.reset()
                        _LOGGER.info("Home projector leadership unavailable")
                        await asyncio.sleep(leader_retry_seconds)
                        continue
                    leadership_backoff.reset()
                    _LOGGER.info("Home projector leadership acquired")

                    async def leader_work(
                        set_status: Callable[[str], None],
                    ) -> None:
                        await _run_leader_loop(
                            set_status=set_status,
                            projector=projector,
                            poll_seconds=poll_seconds,
                            reconcile_seconds=reconcile_seconds,
                            max_cycles=max_cycles,
                            runtime_backoff_initial_seconds=(
                                runtime_backoff_initial_seconds
                            ),
                            runtime_backoff_maximum_seconds=(
                                runtime_backoff_maximum_seconds
                            ),
                            health_seconds=health_seconds,
                            heartbeat_stale_seconds=heartbeat_stale_seconds,
                            maximum_lag_seconds=maximum_lag_seconds,
                            retention_seconds=retention_seconds,
                            materialise_seconds=materialise_seconds,
                            erasure_seconds=erasure_seconds,
                            session_factory=session_factory,
                            recurrences=recurrences,
                            retention_policy=retention_policy,
                        )

                    await _run_guarded_leader_work(
                        lease=lease,
                        heartbeat_stale_seconds=heartbeat_stale_seconds,
                        work=leader_work,
                    )
            except asyncio.CancelledError:
                raise
            except Exception as error:
                delay = leadership_backoff.after_failure()
                _LOGGER.error(
                    "Home projector leadership cycle failed error_type=%s",
                    type(error).__name__,
                )
                await asyncio.sleep(delay)
    finally:
        await engine.dispose()


async def _run_leader_loop(
    *,
    set_status: Callable[[str], None],
    projector: PostgresHomeProjector,
    poll_seconds: float,
    reconcile_seconds: float,
    max_cycles: int,
    runtime_backoff_initial_seconds: float,
    runtime_backoff_maximum_seconds: float,
    health_seconds: float,
    heartbeat_stale_seconds: float,
    maximum_lag_seconds: float,
    retention_seconds: float,
    materialise_seconds: float,
    erasure_seconds: float,
    session_factory: AsyncSessionFactory,
    recurrences: PostgresPlannedCostRecurrenceRepository,
    retention_policy: RevisionRetentionPolicy,
) -> None:
    event_backoff = BoundedRuntimeBackoff(
        initial_seconds=runtime_backoff_initial_seconds,
        maximum_seconds=runtime_backoff_maximum_seconds,
    )
    next_reconciliation = 0.0
    next_health = 0.0
    next_retention = 0.0
    next_materialisation = 0.0
    next_erasure = 0.0
    while True:
        consumed = 0
        reconciled = 0
        cycle_failed = False
        try:
            projection = await projector.drain_available(max_candidates=max_cycles)
            consumed = projection.published
            cycle_failed = projection.failures_present
        except asyncio.CancelledError:
            raise
        except Exception as error:
            cycle_failed = True
            _LOGGER.error(
                "Home projector event cycle failed error_type=%s",
                type(error).__name__,
            )

        now = time.monotonic()
        if now >= next_reconciliation:
            try:
                reconciliation = await projector.reconcile_all()
                reconciled = reconciliation.published
                cycle_failed = cycle_failed or reconciliation.failures_present
                next_reconciliation = now + reconcile_seconds
                _LOGGER.info(
                    "Home projector reconciliation complete published=%d",
                    reconciled,
                )
            except asyncio.CancelledError:
                raise
            except Exception as error:
                cycle_failed = True
                _LOGGER.error(
                    "Home projector reconciliation failed error_type=%s",
                    type(error).__name__,
                )

        if now >= next_materialisation:
            try:
                # Repeating plans grow their next few months here. The write is
                # idempotent by a database index, so a missed or repeated run
                # costs nothing but a query (ADR 0025).
                materialised = await recurrences.materialise_active_rules()
                next_materialisation = now + materialise_seconds
                if materialised:
                    _LOGGER.info(
                        "Planned cost recurrence materialisation wrote=%d",
                        materialised,
                    )
            except asyncio.CancelledError:
                raise
            except Exception as error:
                cycle_failed = True
                _LOGGER.error(
                    "Planned cost recurrence materialisation failed error_type=%s",
                    type(error).__name__,
                )

        if now >= next_erasure:
            try:
                # People who asked to be erased and did not come back within
                # the week (ADR 0030). Counted, never named: the log learns how
                # many, not who.
                erased = await erase_due_accounts(
                    session_factory, now=datetime.now(UTC)
                )
                next_erasure = now + erasure_seconds
                if erased:
                    _LOGGER.info("Scheduled account erasure erased=%d", erased)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                cycle_failed = True
                _LOGGER.error(
                    "Scheduled account erasure failed error_type=%s",
                    type(error).__name__,
                )

        if now >= next_retention:
            try:
                pruned = await prune_home_revisions(
                    session_factory=session_factory,
                    policy=retention_policy,
                )
                next_retention = now + retention_seconds
                _LOGGER.info("Home projector retention complete pruned=%d", pruned)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                cycle_failed = True
                _LOGGER.error(
                    "Home projector retention failed error_type=%s",
                    type(error).__name__,
                )

        health: ProjectorHealth | None = None
        if now >= next_health:
            try:
                health = await read_projector_health(
                    session_factory=session_factory,
                    heartbeat_stale_seconds=heartbeat_stale_seconds,
                    maximum_lag_seconds=maximum_lag_seconds,
                )
                next_health = now + health_seconds
                _log_health(health)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                cycle_failed = True
                _LOGGER.error(
                    "Home projector health query failed error_type=%s",
                    type(error).__name__,
                )

        status = "degraded" if cycle_failed else "idle"
        if not cycle_failed and (consumed or reconciled):
            status = "published"
        set_status(status)

        if cycle_failed:
            await asyncio.sleep(event_backoff.after_failure())
        elif consumed == 0:
            event_backoff.reset()
            await asyncio.sleep(poll_seconds)
        else:
            event_backoff.reset()


async def _check_health(
    *,
    heartbeat_stale_seconds: float,
    maximum_lag_seconds: float,
) -> int:
    engine, session_factory = create_database(require_database_url())
    try:
        try:
            health = await read_projector_health(
                session_factory=session_factory,
                heartbeat_stale_seconds=heartbeat_stale_seconds,
                maximum_lag_seconds=maximum_lag_seconds,
            )
        except Exception as error:
            _LOGGER.error(
                "Home projector health unavailable error_type=%s",
                type(error).__name__,
            )
            return 2
        _log_health(health)
        return 0 if health.status == "healthy" else 1
    finally:
        await engine.dispose()


def _log_health(health: ProjectorHealth) -> None:
    log = _LOGGER.info if health.status == "healthy" else _LOGGER.error
    log(
        "Home projector health status=%s leader=%s heartbeat_age=%s "
        "pending_lag=%s dead_letters=%s last_cycle=%s",
        health.status,
        health.leader,
        health.heartbeat_age,
        health.pending_lag,
        health.dead_letters,
        health.last_cycle,
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Consume Finance outboxes into immutable Home revisions.",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--once",
        action="store_true",
        help="Run one leader-protected projection and retention cycle.",
    )
    mode.add_argument(
        "--check-health",
        action="store_true",
        help="Report privacy-safe worker health and exit 0/1/2.",
    )
    parser.add_argument("--max-cycles", type=int, default=100)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("--reconcile-seconds", type=float, default=300.0)
    parser.add_argument("--leader-retry-seconds", type=float, default=5.0)
    parser.add_argument("--runtime-backoff-initial-seconds", type=float, default=1.0)
    parser.add_argument("--runtime-backoff-maximum-seconds", type=float, default=30.0)
    parser.add_argument("--event-max-attempts", type=int, default=8)
    parser.add_argument("--event-backoff-initial-seconds", type=float, default=2.0)
    parser.add_argument("--event-backoff-maximum-seconds", type=float, default=300.0)
    parser.add_argument("--health-seconds", type=float, default=60.0)
    parser.add_argument("--heartbeat-stale-seconds", type=float, default=30.0)
    parser.add_argument("--maximum-lag-seconds", type=float, default=120.0)
    parser.add_argument("--retention-seconds", type=float, default=86400.0)
    # Hourly: a plan's next months are never urgent, and creating a rule
    # materialises its own instances immediately anyway.
    parser.add_argument("--materialise-seconds", type=float, default=3600.0)
    # Hourly too: a week's grace has no need of a tighter clock (ADR 0030).
    parser.add_argument("--erasure-seconds", type=float, default=3600.0)
    parser.add_argument("--retention-minimum-revisions", type=int, default=2)
    parser.add_argument("--retention-grace-days", type=int, default=30)
    parser.add_argument("--retention-maximum-per-cycle", type=int, default=100)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    retry_policy, retention_policy = _validated_policies(args)
    logging.basicConfig(level=logging.INFO)
    if args.check_health:
        try:
            return asyncio.run(
                _check_health(
                    heartbeat_stale_seconds=args.heartbeat_stale_seconds,
                    maximum_lag_seconds=args.maximum_lag_seconds,
                )
            )
        except Exception as error:
            _LOGGER.error(
                "Home projector health unavailable error_type=%s",
                type(error).__name__,
            )
            return 2
    if args.once:
        try:
            acquired = asyncio.run(
                _run_once(
                    max_cycles=args.max_cycles,
                    heartbeat_stale_seconds=args.heartbeat_stale_seconds,
                    retry_policy=retry_policy,
                    retention_policy=retention_policy,
                )
            )
        except Exception as error:
            _LOGGER.error(
                "Home projector one-shot failed error_type=%s",
                type(error).__name__,
            )
            return 1
        if not acquired:
            _LOGGER.warning("Home projector one-shot leadership unavailable")
            return _EX_TEMPFAIL
        return 0
    try:
        asyncio.run(
            _run_forever(
                poll_seconds=args.poll_seconds,
                reconcile_seconds=args.reconcile_seconds,
                max_cycles=args.max_cycles,
                leader_retry_seconds=args.leader_retry_seconds,
                runtime_backoff_initial_seconds=(args.runtime_backoff_initial_seconds),
                runtime_backoff_maximum_seconds=(args.runtime_backoff_maximum_seconds),
                health_seconds=args.health_seconds,
                heartbeat_stale_seconds=args.heartbeat_stale_seconds,
                maximum_lag_seconds=args.maximum_lag_seconds,
                retention_seconds=args.retention_seconds,
                materialise_seconds=args.materialise_seconds,
                erasure_seconds=args.erasure_seconds,
                retry_policy=retry_policy,
                retention_policy=retention_policy,
            )
        )
    except KeyboardInterrupt:
        return 0
    except Exception as error:
        _LOGGER.error(
            "Home projector startup failed error_type=%s",
            type(error).__name__,
        )
        return 1
    return 0


def _validated_policies(
    args: argparse.Namespace,
) -> tuple[EventRetryPolicy, RevisionRetentionPolicy]:
    if args.max_cycles <= 0:
        raise SystemExit("--max-cycles must be positive")
    for name in (
        "poll_seconds",
        "reconcile_seconds",
        "leader_retry_seconds",
        "runtime_backoff_initial_seconds",
        "runtime_backoff_maximum_seconds",
        "health_seconds",
        "heartbeat_stale_seconds",
        "maximum_lag_seconds",
        "retention_seconds",
    ):
        value = getattr(args, name)
        if not math.isfinite(value) or value <= 0:
            raise SystemExit(f"--{name.replace('_', '-')} must be positive")
    try:
        retry_policy = EventRetryPolicy(
            max_attempts=args.event_max_attempts,
            initial_seconds=args.event_backoff_initial_seconds,
            maximum_seconds=args.event_backoff_maximum_seconds,
        )
        retention_policy = RevisionRetentionPolicy(
            minimum_per_series=args.retention_minimum_revisions,
            grace_days=args.retention_grace_days,
            maximum_per_cycle=args.retention_maximum_per_cycle,
        )
        BoundedRuntimeBackoff(
            initial_seconds=args.runtime_backoff_initial_seconds,
            maximum_seconds=args.runtime_backoff_maximum_seconds,
        )
    except ValueError as error:
        raise SystemExit(str(error)) from error
    return retry_policy, retention_policy


if __name__ == "__main__":
    raise SystemExit(main())
