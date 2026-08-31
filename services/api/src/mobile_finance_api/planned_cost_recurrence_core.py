"""Deterministic boundary for recurring planned costs (ADR 0025).

This module validates intent and delegates one authoritative write transaction.
It never computes or touches an authoritative money total: a rule generates
forecasts, and a forecast is not money that moved.

The calendar itself lives in :mod:`planned_cost_recurrence`, deliberately apart
from anything that writes, so the dates a rule implies stay a pure function of
the rule and the day it is evaluated on.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .planned_cost_recurrence import horizon_end
from .planned_cost_recurrence_contracts import (
    CreatePlannedCostRecurrenceCommand,
    CreatePlannedCostRecurrenceResponse,
    EndPlannedCostRecurrenceCommand,
    EndPlannedCostRecurrenceResponse,
    ListPlannedCostRecurrencesResponse,
    PlannedCostRecurrence,
    PlannedCostRecurrenceListItem,
    RecurrenceInstance,
    RecurrenceIssue,
    create_recurrence_command_hash,
    end_recurrence_command_hash,
)

#: A plan is an expense (ADR 0018), so only an expense category can label one.
PLANNED_COST_DIRECTION = "expense"


class RecurrencePersistenceUnavailable(Exception):
    """The authoritative store could not safely read or commit a rule."""


class RecurrenceCommandConflict(Exception):
    """A command ID is already bound to different confirmed content."""


class RecurrenceNotFound(Exception):
    """No such rule exists inside the authenticated user's scope."""


class RecurrenceAccountUnavailable(Exception):
    """The account disappeared or is outside the authenticated user scope."""


class RecurrenceBeforeAccountBaseline(Exception):
    """The series would start before the account opening baseline."""


class RecurrenceAlreadyEnded(Exception):
    """The rule already reached its terminal status."""


class RecurrenceRejected(Exception):
    def __init__(self, issues: tuple[RecurrenceIssue, ...]) -> None:
        super().__init__("recurrence rejected")
        self.issues = issues


@dataclass(frozen=True, slots=True)
class RecurrenceAccountContext:
    """Owned-account facts a rule is validated against."""

    account_id: UUID
    user_id: UUID
    currency: str
    opening_balance_on: date
    canonical_timezone: str


@dataclass(frozen=True, slots=True)
class StoredRecurrence:
    """Authoritative rule row as the store holds it."""

    recurrence_id: UUID
    user_id: UUID
    account_id: UUID
    command_id: UUID
    amount: Decimal
    currency: str
    title: str
    category: str | None
    category_id: UUID | None
    frequency: str
    day_of_month: int
    starts_on: date
    ends_on: date | None
    status: str
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True, slots=True)
class RecurrenceWriteResult:
    recurrence: StoredRecurrence
    #: The dates materialised as part of this write, oldest first.
    occurrences: tuple[date, ...]
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class StoredRecurrenceInstance:
    """One outstanding instance, as the list needs it."""

    planned_cost_id: UUID
    planned_on: date


@dataclass(frozen=True, slots=True)
class RecurrenceListing:
    recurrence: StoredRecurrence
    upcoming: tuple[StoredRecurrenceInstance, ...]


@dataclass(frozen=True, slots=True)
class RecurrenceEndResult:
    recurrence: StoredRecurrence
    #: Future instances nobody had acted on, withdrawn along with the rule.
    cancelled_occurrences: int
    idempotent_replay: bool


class PlannedCostRecurrenceRepository(Protocol):
    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> RecurrenceAccountContext | None:
        """Return an owned active account without exposing foreign accounts."""

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        """Return an owned non-archived category's direction, or None."""

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceWriteResult | None:
        """Return an exact prior creation or reject command identity reuse."""

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostRecurrenceCommand,
        payload_hash: bytes,
        through: date,
    ) -> RecurrenceWriteResult:
        """Write the rule, its audit row, and its first instances atomically."""

    async def replay_existing_end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceEndResult | None:
        """Return an exact prior ending or reject command identity reuse."""

    async def end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command: EndPlannedCostRecurrenceCommand,
        payload_hash: bytes,
    ) -> RecurrenceEndResult:
        """End one rule and withdraw its untouched future instances."""

    async def list_recurrences(
        self,
        *,
        user_id: UUID,
    ) -> tuple[RecurrenceListing, ...]:
        """Return the user's rules, each with its outstanding instances."""


class UnavailablePlannedCostRecurrenceRepository:
    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> RecurrenceAccountContext | None:
        del user_id, account_id
        raise RecurrencePersistenceUnavailable

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        del user_id, category_id
        raise RecurrencePersistenceUnavailable

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceWriteResult | None:
        del user_id, command_id, payload_hash
        raise RecurrencePersistenceUnavailable

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostRecurrenceCommand,
        payload_hash: bytes,
        through: date,
    ) -> RecurrenceWriteResult:
        del user_id, command, payload_hash, through
        raise RecurrencePersistenceUnavailable

    async def replay_existing_end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> RecurrenceEndResult | None:
        del user_id, recurrence_id, command_id, payload_hash
        raise RecurrencePersistenceUnavailable

    async def end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command: EndPlannedCostRecurrenceCommand,
        payload_hash: bytes,
    ) -> RecurrenceEndResult:
        del user_id, recurrence_id, command, payload_hash
        raise RecurrencePersistenceUnavailable

    async def list_recurrences(
        self,
        *,
        user_id: UUID,
    ) -> tuple[RecurrenceListing, ...]:
        del user_id
        raise RecurrencePersistenceUnavailable


class PlannedCostRecurrenceCore:
    """Validate and commit the lifecycle of a repeating planned cost."""

    def __init__(
        self,
        *,
        repository: PlannedCostRecurrenceRepository,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._clock = clock or _utc_now

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostRecurrenceCommand,
    ) -> CreatePlannedCostRecurrenceResponse:
        payload_hash = bytes.fromhex(create_recurrence_command_hash(command))
        existing = await self._repository.replay_existing_create(
            user_id=user_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return CreatePlannedCostRecurrenceResponse(
                idempotent_replay=True,
                recurrence=_to_contract(existing.recurrence),
                occurrences=existing.occurrences,
            )

        context = await self._repository.get_account_context(
            user_id=user_id,
            account_id=command.account_id,
        )
        direction = (
            await self._repository.get_category_direction(
                user_id=user_id,
                category_id=command.category_id,
            )
            if command.category_id is not None
            else None
        )
        issues = _creation_issues(
            command=command,
            context=context,
            category_direction=direction,
        )
        if issues:
            raise RecurrenceRejected(issues)
        if context is None:  # pragma: no cover - no issues implies an account
            raise RecurrencePersistenceUnavailable

        # The horizon is a local question: "three months from today" depends on
        # which day it already is where the account lives.
        today = _aware_utc(self._clock()).astimezone(
            ZoneInfo(context.canonical_timezone)
        )
        try:
            result = await self._repository.create(
                user_id=user_id,
                command=command,
                payload_hash=payload_hash,
                through=horizon_end(today=today.date()),
            )
        except RecurrenceAccountUnavailable:
            raise RecurrenceRejected(
                (RecurrenceIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"),)
            ) from None
        except RecurrenceBeforeAccountBaseline:
            raise RecurrenceRejected(
                (
                    RecurrenceIssue(
                        code="RECURRENCE_BEFORE_ACCOUNT_BASELINE",
                        field="startsOn",
                    ),
                )
            ) from None
        _validate_owner(recurrence=result.recurrence, user_id=user_id)
        return CreatePlannedCostRecurrenceResponse(
            idempotent_replay=result.idempotent_replay,
            recurrence=_to_contract(result.recurrence),
            occurrences=result.occurrences,
        )

    async def end(
        self,
        *,
        user_id: UUID,
        recurrence_id: UUID,
        command: EndPlannedCostRecurrenceCommand,
    ) -> EndPlannedCostRecurrenceResponse:
        payload_hash = bytes.fromhex(
            end_recurrence_command_hash(
                recurrence_id=recurrence_id,
                command=command,
            )
        )
        existing = await self._repository.replay_existing_end(
            user_id=user_id,
            recurrence_id=recurrence_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return EndPlannedCostRecurrenceResponse(
                idempotent_replay=True,
                recurrence=_to_contract(existing.recurrence),
                cancelled_occurrences=existing.cancelled_occurrences,
            )

        try:
            result = await self._repository.end(
                user_id=user_id,
                recurrence_id=recurrence_id,
                command=command,
                payload_hash=payload_hash,
            )
        except RecurrenceAlreadyEnded:
            raise RecurrenceRejected(
                (
                    RecurrenceIssue(
                        code="INVALID_LIFECYCLE_TRANSITION",
                        field="status",
                    ),
                )
            ) from None
        _validate_owner(recurrence=result.recurrence, user_id=user_id)
        return EndPlannedCostRecurrenceResponse(
            idempotent_replay=result.idempotent_replay,
            recurrence=_to_contract(result.recurrence),
            cancelled_occurrences=result.cancelled_occurrences,
        )

    async def list_recurrences(
        self,
        *,
        user_id: UUID,
    ) -> ListPlannedCostRecurrencesResponse:
        stored = await self._repository.list_recurrences(user_id=user_id)
        if any(listing.recurrence.user_id != user_id for listing in stored):
            raise RecurrencePersistenceUnavailable
        return ListPlannedCostRecurrencesResponse(
            recurrences=tuple(
                PlannedCostRecurrenceListItem(
                    recurrence=_to_contract(listing.recurrence),
                    upcoming=tuple(
                        RecurrenceInstance(
                            planned_cost_id=instance.planned_cost_id,
                            planned_on=instance.planned_on,
                        )
                        for instance in listing.upcoming
                    ),
                )
                for listing in stored
            ),
        )


def _creation_issues(
    *,
    command: CreatePlannedCostRecurrenceCommand,
    context: RecurrenceAccountContext | None,
    category_direction: str | None,
) -> tuple[RecurrenceIssue, ...]:
    """Apply the creation bounds in a fixed, deterministic order.

    There is no future-date rule: a series that begins in the future is the
    entire point. Nor is there a past-date rule — an obligation that has been
    running for a while is a legitimate thing to record, and the generator
    simply starts at the first occurrence inside the horizon.
    """

    issues: list[RecurrenceIssue] = []
    if context is None:
        issues.append(RecurrenceIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    elif context.currency != command.currency:
        issues.append(
            RecurrenceIssue(code="ACCOUNT_CURRENCY_MISMATCH", field="currency")
        )
    if command.currency != "EUR":
        issues.append(RecurrenceIssue(code="UNSUPPORTED_CURRENCY", field="currency"))
    # Corrections only move a baseline earlier (ADR 0016), so this bound can
    # widen later but never invalidates a rule that was already accepted.
    if context is not None and command.starts_on < context.opening_balance_on:
        issues.append(
            RecurrenceIssue(
                code="RECURRENCE_BEFORE_ACCOUNT_BASELINE",
                field="startsOn",
            )
        )
    if command.category_id is not None:
        if category_direction is None:
            issues.append(
                RecurrenceIssue(code="CATEGORY_UNAVAILABLE", field="categoryId")
            )
        elif category_direction != PLANNED_COST_DIRECTION:
            issues.append(
                RecurrenceIssue(
                    code="CATEGORY_DIRECTION_MISMATCH",
                    field="categoryId",
                )
            )
    return tuple(issues)


def _to_contract(recurrence: StoredRecurrence) -> PlannedCostRecurrence:
    return PlannedCostRecurrence(
        recurrence_id=recurrence.recurrence_id,
        user_id=recurrence.user_id,
        account_id=recurrence.account_id,
        command_id=recurrence.command_id,
        amount=recurrence.amount,
        currency=recurrence.currency,
        title=recurrence.title,
        category=recurrence.category,
        category_id=recurrence.category_id,
        frequency=recurrence.frequency,  # type: ignore[arg-type]
        day_of_month=recurrence.day_of_month,
        starts_on=recurrence.starts_on,
        ends_on=recurrence.ends_on,
        status=recurrence.status,  # type: ignore[arg-type]
        created_at=recurrence.created_at,
        updated_at=recurrence.updated_at,
    )


def _validate_owner(*, recurrence: StoredRecurrence, user_id: UUID) -> None:
    if recurrence.user_id != user_id:
        raise RecurrencePersistenceUnavailable


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
