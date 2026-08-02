from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from mobile_finance_api.projector_supervision import (
    BoundedRuntimeBackoff,
    EventRetryPolicy,
    RevisionRetentionPolicy,
    classify_health,
    event_retry_decision,
    pending_lag_bucket,
)

_NOW = datetime(2026, 7, 29, 20, tzinfo=UTC)


def test_event_retry_is_exponential_capped_and_then_dead_lettered() -> None:
    policy = EventRetryPolicy(
        max_attempts=4,
        initial_seconds=2,
        maximum_seconds=5,
    )

    first = event_retry_decision(
        previous_validation_failure_count=0,
        failed_at=_NOW,
        failure_code="invalid_outbox_contract",
        policy=policy,
    )
    second = event_retry_decision(
        previous_validation_failure_count=1,
        failed_at=_NOW,
        failure_code="invalid_outbox_contract",
        policy=policy,
    )
    third = event_retry_decision(
        previous_validation_failure_count=2,
        failed_at=_NOW,
        failure_code="invalid_outbox_contract",
        policy=policy,
    )
    dead = event_retry_decision(
        previous_validation_failure_count=3,
        failed_at=_NOW,
        failure_code="invalid_outbox_contract",
        policy=policy,
    )

    assert first.next_attempt_at == _NOW + timedelta(seconds=2)
    assert second.next_attempt_at == _NOW + timedelta(seconds=4)
    assert third.next_attempt_at == _NOW + timedelta(seconds=5)
    assert dead.next_attempt_at is None
    assert dead.dead_lettered_at == _NOW
    assert dead.validation_failure_count == 4


def test_runtime_backoff_resets_after_success() -> None:
    backoff = BoundedRuntimeBackoff(initial_seconds=1, maximum_seconds=3)

    assert [backoff.after_failure() for _ in range(4)] == [1, 2, 3, 3]
    backoff.reset()
    assert backoff.after_failure() == 1


@pytest.mark.parametrize(
    ("age", "expected"),
    [
        (None, "none"),
        (29, "lt_30s"),
        (30, "lt_2m"),
        (119, "lt_2m"),
        (120, "lt_10m"),
        (599, "lt_10m"),
        (600, "gte_10m"),
    ],
)
def test_pending_lag_buckets_are_low_cardinality(
    age: int | None,
    expected: str,
) -> None:
    oldest = None if age is None else _NOW - timedelta(seconds=age)
    assert pending_lag_bucket(checked_at=_NOW, oldest_pending_at=oldest) == expected


def test_health_requires_live_leader_fresh_heartbeat_and_no_dlq() -> None:
    healthy = classify_health(
        leader_present=True,
        heartbeat_at=_NOW - timedelta(seconds=5),
        oldest_pending_at=_NOW - timedelta(seconds=10),
        dead_letters_present=False,
        last_cycle_degraded=False,
        checked_at=_NOW,
        heartbeat_stale_seconds=30,
        maximum_lag_seconds=120,
    )
    degraded = classify_health(
        leader_present=True,
        heartbeat_at=_NOW - timedelta(seconds=5),
        oldest_pending_at=None,
        dead_letters_present=True,
        last_cycle_degraded=False,
        checked_at=_NOW,
        heartbeat_stale_seconds=30,
        maximum_lag_seconds=120,
    )

    assert healthy.status == "healthy"
    assert healthy.pending_lag == "lt_30s"
    assert degraded.status == "degraded"
    assert degraded.dead_letters == "present"


def test_health_is_degraded_after_a_failed_cycle() -> None:
    health = classify_health(
        leader_present=True,
        heartbeat_at=_NOW,
        oldest_pending_at=None,
        dead_letters_present=False,
        last_cycle_degraded=True,
        checked_at=_NOW,
        heartbeat_stale_seconds=30,
        maximum_lag_seconds=120,
    )

    assert health.status == "degraded"
    assert health.last_cycle == "degraded"


@pytest.mark.parametrize(
    "factory",
    [
        lambda: EventRetryPolicy(max_attempts=0),
        lambda: EventRetryPolicy(initial_seconds=0),
        lambda: EventRetryPolicy(initial_seconds=3, maximum_seconds=2),
        lambda: RevisionRetentionPolicy(minimum_per_series=1),
        lambda: RevisionRetentionPolicy(grace_days=0),
        lambda: RevisionRetentionPolicy(maximum_per_cycle=1001),
    ],
)
def test_operational_policy_rejects_unsafe_bounds(factory) -> None:
    with pytest.raises(ValueError):
        factory()
