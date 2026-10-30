"""How often anyone may ask.

Counted in the process, which is one uvicorn worker on one host: a restart
forgets the counts, and nothing here is a fact worth a table. What it protects is
the password check and everyone else's share of two cores.

Addresses are held only as digests, so the counters are not a list of who tried.
"""

from __future__ import annotations

import hashlib
import math
import time
from collections import OrderedDict, deque
from collections.abc import Callable
from dataclasses import dataclass, field

from fastapi import HTTPException, Request, status

_MINUTE = 60
_QUARTER_HOUR = 15 * _MINUTE
_HOUR = 60 * _MINUTE
_TRACKED_KEYS = 50_000


@dataclass(frozen=True, slots=True)
class Limit:
    attempts: int
    seconds: int


class SlidingWindow:
    """At most `limit.attempts` events per key in any `limit.seconds`."""

    def __init__(
        self,
        limit: Limit,
        *,
        clock: Callable[[], float] = time.monotonic,
        capacity: int = _TRACKED_KEYS,
    ) -> None:
        self.limit = limit
        self._clock = clock
        self._capacity = capacity
        self._events: OrderedDict[str, deque[float]] = OrderedDict()

    def retry_after(self, key: str) -> int | None:
        """Seconds until `key` may try again, or None when it may try now."""

        events = self._events.get(key)
        if events is None:
            return None
        cutoff = self._clock() - self.limit.seconds
        while events and events[0] <= cutoff:
            events.popleft()
        if not events:
            del self._events[key]
            return None
        if len(events) < self.limit.attempts:
            return None
        return max(1, math.ceil(events[0] - cutoff))

    def record(self, key: str) -> None:
        events = self._events.get(key)
        if events is None:
            events = deque(maxlen=self.limit.attempts)
            self._events[key] = events
            # The oldest key goes first: a flood of new ones cannot grow this,
            # and an active key moves to the end below.
            while len(self._events) > self._capacity:
                self._events.popitem(last=False)
        self._events.move_to_end(key)
        events.append(self._clock())

    def clear(self, key: str) -> None:
        self._events.pop(key, None)

    def tracked_keys(self) -> int:
        return len(self._events)


def _login_by_address() -> SlidingWindow:
    return SlidingWindow(Limit(attempts=20, seconds=_QUARTER_HOUR))


def _login_by_ip() -> SlidingWindow:
    # Many people can share one address behind a mobile carrier, so this is the
    # coarse limit. The one on the address is what stops guessing.
    return SlidingWindow(Limit(attempts=100, seconds=_QUARTER_HOUR))


def _registration_by_ip() -> SlidingWindow:
    return SlidingWindow(Limit(attempts=10, seconds=_HOUR))


def _password_by_user() -> SlidingWindow:
    return SlidingWindow(Limit(attempts=5, seconds=_QUARTER_HOUR))


def _reads_by_user() -> SlidingWindow:
    return SlidingWindow(Limit(attempts=600, seconds=_MINUTE))


def _writes_by_user() -> SlidingWindow:
    return SlidingWindow(Limit(attempts=120, seconds=_MINUTE))


@dataclass(slots=True)
class RequestLimits:
    login_by_address: SlidingWindow = field(default_factory=_login_by_address)
    login_by_ip: SlidingWindow = field(default_factory=_login_by_ip)
    registration_by_ip: SlidingWindow = field(default_factory=_registration_by_ip)
    password_by_user: SlidingWindow = field(default_factory=_password_by_user)
    reads_by_user: SlidingWindow = field(default_factory=_reads_by_user)
    writes_by_user: SlidingWindow = field(default_factory=_writes_by_user)


def request_limits(request: Request) -> RequestLimits:
    limits: RequestLimits = request.app.state.request_limits
    return limits


def address_key(email: str) -> str:
    """One key for every spelling of an address the store treats as the same."""

    return hashlib.sha256(email.strip().casefold().encode("utf-8")).hexdigest()


def client_key(request: Request) -> str:
    """Where a request came from, as Caddy reported it to uvicorn."""

    return "unknown" if request.client is None else request.client.host


def refuse_if_exhausted(*windows: tuple[SlidingWindow, str]) -> None:
    waits = [window.retry_after(key) for window, key in windows]
    longest = max((wait for wait in waits if wait is not None), default=None)
    if longest is not None:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts",
            headers={"Retry-After": str(longest)},
        )
