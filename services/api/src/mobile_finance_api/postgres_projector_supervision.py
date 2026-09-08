"""PostgreSQL leadership, health, and retention for the Home projector."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine

from .database import AsyncSessionFactory
from .db_models import FinanceAccountRow, UserRow
from .projector_supervision import (
    ProjectorHealth,
    RevisionRetentionPolicy,
    classify_health,
)

_LOCK_NAMESPACE = 1_296_447_816  # ASCII-like stable namespace: MFAH
_LOCK_RESOURCE = 1_347_569_482  # ASCII-like stable resource: PROJ
_RUNTIME_SINGLETON_ID = 1
_LOGGER = logging.getLogger("mobile_finance_api.home_projector")


class ProjectorLeadershipLost(RuntimeError):
    """The dedicated PostgreSQL connection no longer owns leadership."""


class ProjectorLeaderLease:
    """Session-level advisory lease held by one dedicated connection."""

    def __init__(
        self,
        *,
        connection: AsyncConnection,
        lease_id: UUID,
        clock: Callable[[], datetime],
    ) -> None:
        self._connection = connection
        self._lease_id = lease_id
        self._clock = clock

    async def start(self) -> None:
        now = _aware_utc(self._clock())
        await self._connection.execute(
            text(
                "INSERT INTO home_projector_runtime_state ("
                "singleton_id, lease_id, started_at, heartbeat_at, "
                "last_cycle_status"
                ") VALUES ("
                ":singleton_id, :lease_id, :started_at, :heartbeat_at, "
                "'starting'"
                ") ON CONFLICT (singleton_id) DO UPDATE SET "
                "lease_id = EXCLUDED.lease_id, "
                "started_at = EXCLUDED.started_at, "
                "heartbeat_at = EXCLUDED.heartbeat_at, "
                "last_cycle_status = EXCLUDED.last_cycle_status"
            ),
            {
                "singleton_id": _RUNTIME_SINGLETON_ID,
                "lease_id": self._lease_id,
                "started_at": now,
                "heartbeat_at": now,
            },
        )
        await self._connection.commit()

    async def heartbeat(self, *, status: str) -> None:
        if status not in {
            "starting",
            "idle",
            "published",
            "retry_scheduled",
            "degraded",
        }:
            raise ValueError("unsupported projector cycle status")
        await self._connection.execute(text("SELECT 1"))
        result = await self._connection.execute(
            text(
                "UPDATE home_projector_runtime_state SET "
                "heartbeat_at = :heartbeat_at, last_cycle_status = :status "
                "WHERE singleton_id = :singleton_id AND lease_id = :lease_id"
            ),
            {
                "heartbeat_at": _aware_utc(self._clock()),
                "status": status,
                "singleton_id": _RUNTIME_SINGLETON_ID,
                "lease_id": self._lease_id,
            },
        )
        await self._connection.commit()
        if result.rowcount != 1:
            raise ProjectorLeadershipLost("projector leadership state was replaced")

    async def stop(self) -> None:
        result = await self._connection.execute(
            text(
                "UPDATE home_projector_runtime_state SET "
                "heartbeat_at = :heartbeat_at, last_cycle_status = 'stopped' "
                "WHERE singleton_id = :singleton_id AND lease_id = :lease_id"
            ),
            {
                "heartbeat_at": _aware_utc(self._clock()),
                "singleton_id": _RUNTIME_SINGLETON_ID,
                "lease_id": self._lease_id,
            },
        )
        await self._connection.commit()
        if result.rowcount not in {0, 1}:
            raise ProjectorLeadershipLost("projector leadership state is invalid")


@asynccontextmanager
async def acquire_projector_leadership(
    *,
    engine: AsyncEngine,
    clock: Callable[[], datetime] | None = None,
) -> AsyncIterator[ProjectorLeaderLease | None]:
    """Try to hold the global Home projector advisory lease."""

    connection = await engine.connect()
    acquired = False
    lease: ProjectorLeaderLease | None = None
    try:
        acquired = bool(
            await connection.scalar(
                text("SELECT pg_try_advisory_lock(:namespace, :resource)"),
                {"namespace": _LOCK_NAMESPACE, "resource": _LOCK_RESOURCE},
            )
        )
        await connection.commit()
        if not acquired:
            yield None
            return
        lease = ProjectorLeaderLease(
            connection=connection,
            lease_id=uuid4(),
            clock=clock or _utc_now,
        )
        await lease.start()
        yield lease
    finally:
        if acquired:
            try:
                if lease is not None:
                    await lease.stop()
                await connection.scalar(
                    text("SELECT pg_advisory_unlock(:namespace, :resource)"),
                    {"namespace": _LOCK_NAMESPACE, "resource": _LOCK_RESOURCE},
                )
                await connection.commit()
            except Exception as error:
                # Closing a broken dedicated connection releases its
                # session-level advisory lock. Never mask the work failure.
                _LOGGER.warning(
                    "Projector leadership cleanup failed error_type=%s",
                    type(error).__name__,
                )
        await connection.close()


async def read_projector_health(
    *,
    session_factory: AsyncSessionFactory,
    heartbeat_stale_seconds: float,
    maximum_lag_seconds: float,
    clock: Callable[[], datetime] | None = None,
) -> ProjectorHealth:
    """Return bounded, privacy-safe operational health dimensions."""

    checked_at = _aware_utc((clock or _utc_now)())
    async with session_factory() as database:
        leader_present = bool(
            await database.scalar(
                text(
                    "SELECT EXISTS ("
                    "SELECT 1 FROM pg_locks "
                    "WHERE locktype = 'advisory' AND granted "
                    "AND database = ("
                    "SELECT oid FROM pg_database WHERE datname = current_database()"
                    ") AND classid = CAST(:namespace AS oid) "
                    "AND objid = CAST(:resource AS oid) AND objsubid = 2"
                    ")"
                ),
                {"namespace": _LOCK_NAMESPACE, "resource": _LOCK_RESOURCE},
            )
        )
        runtime_state = (
            await database.execute(
                text(
                    "SELECT heartbeat_at, last_cycle_status "
                    "FROM home_projector_runtime_state "
                    "WHERE singleton_id = :singleton_id"
                ),
                {"singleton_id": _RUNTIME_SINGLETON_ID},
            )
        ).one_or_none()
        heartbeat_at = None if runtime_state is None else runtime_state.heartbeat_at
        last_cycle_degraded = (
            runtime_state is not None
            and runtime_state.last_cycle_status in {"retry_scheduled", "degraded"}
        )
        oldest_pending_at = await database.scalar(
            text(
                "SELECT min(created_at) FROM ("
                "SELECT created_at FROM finance_account_outbox_events "
                "WHERE published_at IS NULL AND dead_lettered_at IS NULL "
                "UNION ALL "
                "SELECT created_at FROM finance_outbox_events "
                "WHERE published_at IS NULL AND dead_lettered_at IS NULL"
                ") AS pending_events"
            )
        )
        dead_letters_present = bool(
            await database.scalar(
                text(
                    "SELECT EXISTS ("
                    "SELECT 1 FROM finance_account_outbox_events "
                    "WHERE published_at IS NULL AND dead_lettered_at IS NOT NULL "
                    "UNION ALL "
                    "SELECT 1 FROM finance_outbox_events "
                    "WHERE published_at IS NULL AND dead_lettered_at IS NOT NULL"
                    ")"
                )
            )
        )
    return classify_health(
        leader_present=leader_present,
        heartbeat_at=None if heartbeat_at is None else _aware_utc(heartbeat_at),
        oldest_pending_at=(
            None if oldest_pending_at is None else _aware_utc(oldest_pending_at)
        ),
        dead_letters_present=dead_letters_present,
        last_cycle_degraded=last_cycle_degraded,
        checked_at=checked_at,
        heartbeat_stale_seconds=heartbeat_stale_seconds,
        maximum_lag_seconds=maximum_lag_seconds,
    )


async def prune_home_revisions(
    *,
    session_factory: AsyncSessionFactory,
    policy: RevisionRetentionPolicy,
    clock: Callable[[], datetime] | None = None,
) -> int:
    """Delete bounded superseded roots while preserving immutable survivors."""

    cutoff = _aware_utc((clock or _utc_now)()) - timedelta(days=policy.grace_days)
    async with session_factory() as database:
        user_ids = tuple(
            (
                await database.scalars(
                    text(
                        "WITH ranked AS MATERIALIZED ("
                        "SELECT user_id, generated_at, "
                        "row_number() OVER ("
                        "PARTITION BY user_id, account_id, timezone_name, period_start "
                        "ORDER BY revision DESC, id DESC"
                        ") AS ordinal "
                        "FROM home_projection_snapshots"
                        ") SELECT DISTINCT user_id FROM ranked "
                        "WHERE ordinal > :minimum AND generated_at < :cutoff "
                        "ORDER BY user_id LIMIT :limit"
                    ),
                    {
                        "minimum": policy.minimum_per_series,
                        "cutoff": cutoff,
                        "limit": policy.maximum_per_cycle,
                    },
                )
            ).all()
        )

    deleted = 0
    for user_id in user_ids:
        remaining = policy.maximum_per_cycle - deleted
        if remaining <= 0:
            break
        async with session_factory() as database, database.begin():
            user = await database.scalar(
                select(UserRow).where(UserRow.id == user_id).with_for_update()
            )
            if user is None:
                continue
            tuple(
                (
                    await database.scalars(
                        select(FinanceAccountRow)
                        .where(FinanceAccountRow.user_id == user_id)
                        .order_by(
                            FinanceAccountRow.created_at.asc(),
                            FinanceAccountRow.id.asc(),
                        )
                        .with_for_update()
                    )
                ).all()
            )
            removed = await database.scalar(
                text(
                    "WITH ranked AS MATERIALIZED ("
                    "SELECT id, generated_at, revision, "
                    "row_number() OVER ("
                    "PARTITION BY user_id, account_id, timezone_name, period_start "
                    "ORDER BY revision DESC, id DESC"
                    ") AS ordinal "
                    "FROM home_projection_snapshots WHERE user_id = :user_id"
                    "), candidates AS MATERIALIZED ("
                    "SELECT id FROM ranked "
                    "WHERE ordinal > :minimum AND generated_at < :cutoff "
                    "ORDER BY generated_at ASC, revision ASC, id ASC "
                    "LIMIT :limit"
                    "), removed AS ("
                    "DELETE FROM home_projection_snapshots AS snapshots "
                    "USING candidates WHERE snapshots.id = candidates.id "
                    "RETURNING 1"
                    ") SELECT count(*) FROM removed"
                ),
                {
                    "user_id": user_id,
                    "minimum": policy.minimum_per_series,
                    "cutoff": cutoff,
                    "limit": remaining,
                },
            )
            deleted += int(removed or 0)
    return deleted


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("projector operational clock must be timezone-aware")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
