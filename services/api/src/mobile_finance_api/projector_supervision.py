"""Pure operational policies for the deterministic Home projector."""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Literal

type ProjectorFailureCode = Literal["invalid_outbox_contract"]
type HeartbeatBucket = Literal["none", "fresh", "stale"]
type PendingLagBucket = Literal[
    "none",
    "lt_30s",
    "lt_2m",
    "lt_10m",
    "gte_10m",
]
type ProjectorHealthStatus = Literal["healthy", "degraded"]
type CycleHealth = Literal["ok", "degraded"]


@dataclass(frozen=True, slots=True)
class EventRetryPolicy:
    """Durable retry limits for a structurally invalid outbox event."""

    max_attempts: int = 8
    initial_seconds: float = 2.0
    maximum_seconds: float = 300.0

    def __post_init__(self) -> None:
        if self.max_attempts <= 0 or self.max_attempts > 32767:
            raise ValueError("max_attempts must be between 1 and 32767")
        _positive_finite(self.initial_seconds, name="initial_seconds")
        _positive_finite(self.maximum_seconds, name="maximum_seconds")
        if self.initial_seconds > self.maximum_seconds:
            raise ValueError("initial_seconds must not exceed maximum_seconds")

    def delay_for_attempt(self, attempt_count: int) -> timedelta:
        if attempt_count <= 0:
            raise ValueError("attempt_count must be positive")
        exponent = min(attempt_count - 1, 62)
        seconds = min(
            self.initial_seconds * (2**exponent),
            self.maximum_seconds,
        )
        return timedelta(seconds=seconds)


@dataclass(frozen=True, slots=True)
class EventRetryDecision:
    validation_failure_count: int
    next_attempt_at: datetime | None
    last_failed_at: datetime
    failure_code: ProjectorFailureCode
    dead_lettered_at: datetime | None


def event_retry_decision(
    *,
    previous_validation_failure_count: int,
    failed_at: datetime,
    failure_code: ProjectorFailureCode,
    policy: EventRetryPolicy,
) -> EventRetryDecision:
    """Schedule a bounded retry or move one poison event to in-place DLQ."""

    if (
        previous_validation_failure_count < 0
        or previous_validation_failure_count >= 32767
    ):
        raise ValueError(
            "previous_validation_failure_count is outside the supported range"
        )
    if failed_at.tzinfo is None or failed_at.utcoffset() is None:
        raise ValueError("failed_at must be timezone-aware")
    validation_failure_count = previous_validation_failure_count + 1
    if validation_failure_count >= policy.max_attempts:
        return EventRetryDecision(
            validation_failure_count=validation_failure_count,
            next_attempt_at=None,
            last_failed_at=failed_at,
            failure_code=failure_code,
            dead_lettered_at=failed_at,
        )
    return EventRetryDecision(
        validation_failure_count=validation_failure_count,
        next_attempt_at=(
            failed_at + policy.delay_for_attempt(validation_failure_count)
        ),
        last_failed_at=failed_at,
        failure_code=failure_code,
        dead_lettered_at=None,
    )


@dataclass(slots=True)
class BoundedRuntimeBackoff:
    """Process-local backoff for database or unexpected worker failures."""

    initial_seconds: float = 1.0
    maximum_seconds: float = 30.0
    _next_seconds: float | None = None

    def __post_init__(self) -> None:
        _positive_finite(self.initial_seconds, name="initial_seconds")
        _positive_finite(self.maximum_seconds, name="maximum_seconds")
        if self.initial_seconds > self.maximum_seconds:
            raise ValueError("initial_seconds must not exceed maximum_seconds")

    def after_failure(self) -> float:
        delay = (
            self.initial_seconds if self._next_seconds is None else self._next_seconds
        )
        self._next_seconds = min(delay * 2, self.maximum_seconds)
        return delay

    def reset(self) -> None:
        self._next_seconds = None


@dataclass(frozen=True, slots=True)
class ProjectorHealth:
    status: ProjectorHealthStatus
    leader: Literal["present", "absent"]
    heartbeat_age: HeartbeatBucket
    pending_lag: PendingLagBucket
    dead_letters: Literal["none", "present"]
    last_cycle: CycleHealth


def classify_health(
    *,
    leader_present: bool,
    heartbeat_at: datetime | None,
    oldest_pending_at: datetime | None,
    dead_letters_present: bool,
    last_cycle_degraded: bool,
    checked_at: datetime,
    heartbeat_stale_seconds: float,
    maximum_lag_seconds: float,
) -> ProjectorHealth:
    _positive_finite(heartbeat_stale_seconds, name="heartbeat_stale_seconds")
    _positive_finite(maximum_lag_seconds, name="maximum_lag_seconds")
    if checked_at.tzinfo is None or checked_at.utcoffset() is None:
        raise ValueError("checked_at must be timezone-aware")

    heartbeat_age: HeartbeatBucket
    if heartbeat_at is None:
        heartbeat_age = "none"
    else:
        heartbeat_age = (
            "stale"
            if _age_seconds(checked_at, heartbeat_at) > heartbeat_stale_seconds
            else "fresh"
        )

    pending_lag = pending_lag_bucket(
        checked_at=checked_at,
        oldest_pending_at=oldest_pending_at,
    )
    lag_is_healthy = (
        oldest_pending_at is None
        or _age_seconds(checked_at, oldest_pending_at) <= maximum_lag_seconds
    )
    healthy = (
        leader_present
        and heartbeat_age == "fresh"
        and lag_is_healthy
        and not dead_letters_present
        and not last_cycle_degraded
    )
    return ProjectorHealth(
        status="healthy" if healthy else "degraded",
        leader="present" if leader_present else "absent",
        heartbeat_age=heartbeat_age,
        pending_lag=pending_lag,
        dead_letters="present" if dead_letters_present else "none",
        last_cycle="degraded" if last_cycle_degraded else "ok",
    )


def pending_lag_bucket(
    *,
    checked_at: datetime,
    oldest_pending_at: datetime | None,
) -> PendingLagBucket:
    if oldest_pending_at is None:
        return "none"
    age = _age_seconds(checked_at, oldest_pending_at)
    if age < 30:
        return "lt_30s"
    if age < 120:
        return "lt_2m"
    if age < 600:
        return "lt_10m"
    return "gte_10m"


@dataclass(frozen=True, slots=True)
class RevisionRetentionPolicy:
    minimum_per_series: int = 2
    grace_days: int = 30
    maximum_per_cycle: int = 100

    def __post_init__(self) -> None:
        if self.minimum_per_series < 2:
            raise ValueError("minimum_per_series must be at least 2")
        if self.grace_days < 1:
            raise ValueError("grace_days must be positive")
        if self.maximum_per_cycle < 1 or self.maximum_per_cycle > 1000:
            raise ValueError("maximum_per_cycle must be between 1 and 1000")


def _age_seconds(checked_at: datetime, value: datetime) -> float:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("health timestamps must be timezone-aware")
    return max(0.0, (checked_at - value).total_seconds())


def _positive_finite(value: float, *, name: str) -> None:
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be positive and finite")
