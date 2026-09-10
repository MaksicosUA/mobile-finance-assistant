"""Deterministic boundary for forecast-only planned costs (ADR 0018).

This module never computes or touches an authoritative money total. It validates
intent, delegates the single authoritative write transaction, and derives the
read-time `is_due` flag.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .planned_cost_contracts import (
    CreatePlannedCostCommand,
    CreatePlannedCostResponse,
    ListPlannedCostsResponse,
    PlannedCost,
    PlannedCostIssue,
    PlannedCostStatus,
    TransitionPlannedCostCommand,
    TransitionPlannedCostResponse,
    create_planned_cost_command_hash,
    derive_is_due,
    local_today,
    transition_planned_cost_command_hash,
    transition_target_status,
)


class PlannedCostPersistenceUnavailable(Exception):
    """The authoritative store could not safely read or commit a plan."""


class PlannedCostCommandConflict(Exception):
    """A command ID is already bound to different confirmed content."""


class PlannedCostNotFound(Exception):
    """No such plan exists inside the authenticated user's scope."""


class PlannedCostAccountUnavailable(Exception):
    """The account disappeared or is outside the authenticated user scope."""


class PlannedCostBeforeAccountBaseline(Exception):
    """The plan precedes the account opening baseline."""


class PlannedCostInvalidTransition(Exception):
    """The plan already reached a terminal status."""


class PlannedCostConfirmingOperationMissing(Exception):
    """No committed operation exists for the supplied operation command."""


class PlannedCostRejected(Exception):
    def __init__(self, issues: tuple[PlannedCostIssue, ...]) -> None:
        super().__init__("planned cost rejected")
        self.issues = issues


@dataclass(frozen=True, slots=True)
class PlannedCostAccountContext:
    """Owned-account facts a planned cost is validated against."""

    account_id: UUID
    user_id: UUID
    currency: str
    opening_balance_on: date
    canonical_timezone: str


@dataclass(frozen=True, slots=True)
class StoredPlannedCost:
    """Authoritative plan row plus the timezone `is_due` is derived in.

    `is_due` is deliberately absent: it is a read-time function of the local
    date, never a stored fact (ADR 0018).
    """

    planned_cost_id: UUID
    user_id: UUID
    account_id: UUID
    command_id: UUID
    amount: Decimal
    currency: str
    title: str
    category: str | None
    planned_on: date
    status: str
    confirmed_operation_id: UUID | None
    created_at: datetime
    updated_at: datetime
    canonical_timezone: str


@dataclass(frozen=True, slots=True)
class PlannedCostWriteResult:
    plan: StoredPlannedCost
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class PlannedCostListSnapshot:
    canonical_timezone: str | None
    plans: tuple[StoredPlannedCost, ...]


class PlannedCostRepository(Protocol):
    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> PlannedCostAccountContext | None:
        """Return an owned active account without exposing foreign accounts."""

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        """Return an exact prior creation or reject command identity reuse."""

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostCommand,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult:
        """Atomically write the plan, its audit row, and its invalidation."""

    async def replay_existing_transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        """Return an exact prior transition or reject command identity reuse."""

    async def transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command: TransitionPlannedCostCommand,
        payload_hash: bytes,
        target_status: PlannedCostStatus,
    ) -> PlannedCostWriteResult:
        """Atomically move one plan to a terminal status under a row lock."""

    async def list_plans(
        self,
        *,
        user_id: UUID,
        planned_from: date | None,
        planned_to: date | None,
    ) -> PlannedCostListSnapshot:
        """Return the user's plans in a stable order."""


class UnavailablePlannedCostRepository:
    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> PlannedCostAccountContext | None:
        del user_id, account_id
        raise PlannedCostPersistenceUnavailable

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        del user_id, command_id, payload_hash
        raise PlannedCostPersistenceUnavailable

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostCommand,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult:
        del user_id, command, payload_hash
        raise PlannedCostPersistenceUnavailable

    async def replay_existing_transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> PlannedCostWriteResult | None:
        del user_id, planned_cost_id, command_id, payload_hash
        raise PlannedCostPersistenceUnavailable

    async def transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command: TransitionPlannedCostCommand,
        payload_hash: bytes,
        target_status: PlannedCostStatus,
    ) -> PlannedCostWriteResult:
        del user_id, planned_cost_id, command, payload_hash, target_status
        raise PlannedCostPersistenceUnavailable

    async def list_plans(
        self,
        *,
        user_id: UUID,
        planned_from: date | None,
        planned_to: date | None,
    ) -> PlannedCostListSnapshot:
        del user_id, planned_from, planned_to
        raise PlannedCostPersistenceUnavailable


class PlannedCostCore:
    """Validate and commit the planned-cost lifecycle."""

    def __init__(
        self,
        *,
        repository: PlannedCostRepository,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._clock = clock or _utc_now

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreatePlannedCostCommand,
    ) -> CreatePlannedCostResponse:
        payload_hash = bytes.fromhex(create_planned_cost_command_hash(command))
        existing = await self._repository.replay_existing_create(
            user_id=user_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return CreatePlannedCostResponse(
                idempotent_replay=True,
                planned_cost=self._to_contract(existing.plan),
            )

        context = await self._repository.get_account_context(
            user_id=user_id,
            account_id=command.account_id,
        )
        issues = _creation_issues(command=command, context=context)
        if issues:
            raise PlannedCostRejected(issues)

        try:
            result = await self._repository.create(
                user_id=user_id,
                command=command,
                payload_hash=payload_hash,
            )
        except PlannedCostAccountUnavailable:
            raise PlannedCostRejected(
                (PlannedCostIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"),)
            ) from None
        except PlannedCostBeforeAccountBaseline:
            raise PlannedCostRejected(
                (
                    PlannedCostIssue(
                        code="PLAN_BEFORE_ACCOUNT_BASELINE",
                        field="plannedOn",
                    ),
                )
            ) from None
        _validate_result(result=result, user_id=user_id)
        return CreatePlannedCostResponse(
            idempotent_replay=result.idempotent_replay,
            planned_cost=self._to_contract(result.plan),
        )

    async def transition(
        self,
        *,
        user_id: UUID,
        planned_cost_id: UUID,
        command: TransitionPlannedCostCommand,
    ) -> TransitionPlannedCostResponse:
        payload_hash = bytes.fromhex(
            transition_planned_cost_command_hash(
                planned_cost_id=planned_cost_id,
                command=command,
            )
        )
        existing = await self._repository.replay_existing_transition(
            user_id=user_id,
            planned_cost_id=planned_cost_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return TransitionPlannedCostResponse(
                idempotent_replay=True,
                planned_cost=self._to_contract(existing.plan),
            )

        try:
            result = await self._repository.transition(
                user_id=user_id,
                planned_cost_id=planned_cost_id,
                command=command,
                payload_hash=payload_hash,
                target_status=transition_target_status(command.transition),
            )
        except PlannedCostInvalidTransition:
            raise PlannedCostRejected(
                (
                    PlannedCostIssue(
                        code="INVALID_LIFECYCLE_TRANSITION",
                        field="transition",
                    ),
                )
            ) from None
        except PlannedCostConfirmingOperationMissing:
            # Fail closed: marking a plan confirmed without the operation that
            # settled it would silently lose a real payment.
            raise PlannedCostRejected(
                (
                    PlannedCostIssue(
                        code="CONFIRMING_OPERATION_MISSING",
                        field="operationCommandId",
                    ),
                )
            ) from None
        _validate_result(result=result, user_id=user_id)
        return TransitionPlannedCostResponse(
            idempotent_replay=result.idempotent_replay,
            planned_cost=self._to_contract(result.plan),
        )

    async def list_plans(
        self,
        *,
        user_id: UUID,
        planned_from: date | None = None,
        planned_to: date | None = None,
    ) -> ListPlannedCostsResponse:
        snapshot = await self._repository.list_plans(
            user_id=user_id,
            planned_from=planned_from,
            planned_to=planned_to,
        )
        if any(plan.user_id != user_id for plan in snapshot.plans):
            raise PlannedCostPersistenceUnavailable
        now_utc = _aware_utc(self._clock())
        # Without a canonical timezone the user has no account and therefore no
        # plans; UTC is then only a well-formed placeholder for `evaluatedOn`.
        timezone = (
            ZoneInfo(snapshot.canonical_timezone)
            if snapshot.canonical_timezone is not None
            else UTC
        )
        evaluated_on = now_utc.astimezone(timezone).date()
        return ListPlannedCostsResponse(
            evaluated_on=evaluated_on,
            planned_costs=tuple(
                self._to_contract(plan, now_utc=now_utc) for plan in snapshot.plans
            ),
        )

    def _to_contract(
        self,
        plan: StoredPlannedCost,
        *,
        now_utc: datetime | None = None,
    ) -> PlannedCost:
        instant = now_utc if now_utc is not None else _aware_utc(self._clock())
        today = local_today(
            now_utc=instant,
            timezone=ZoneInfo(plan.canonical_timezone),
        )
        return PlannedCost(
            planned_cost_id=plan.planned_cost_id,
            user_id=plan.user_id,
            account_id=plan.account_id,
            command_id=plan.command_id,
            amount=plan.amount,
            currency=plan.currency,
            title=plan.title,
            category=plan.category,
            planned_on=plan.planned_on,
            status=plan.status,  # type: ignore[arg-type]
            is_due=derive_is_due(
                planned_on=plan.planned_on,
                status=plan.status,
                today_local=today,
            ),
            confirmed_operation_id=plan.confirmed_operation_id,
            created_at=plan.created_at,
            updated_at=plan.updated_at,
        )


def _creation_issues(
    *,
    command: CreatePlannedCostCommand,
    context: PlannedCostAccountContext | None,
) -> tuple[PlannedCostIssue, ...]:
    """Apply the ADR 0018 creation bounds in a fixed, deterministic order.

    There is deliberately no future-date rule here: a future date is the entire
    point of a forecast.
    """

    issues: list[PlannedCostIssue] = []
    if context is None:
        issues.append(PlannedCostIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    elif context.currency != command.currency:
        issues.append(
            PlannedCostIssue(code="ACCOUNT_CURRENCY_MISMATCH", field="currency")
        )
    # A plan is denominated by the wallet it will be paid from, which the
    # mismatch check above already enforces. There is no base currency left to
    # measure it against and nothing converts anything (ADR 0029).
    # `UNSUPPORTED_CURRENCY` stays in the contract for installed clients.
    # A plan before the baseline could never be confirmed into a legal
    # operation. Corrections only move the baseline earlier (ADR 0016), so this
    # bound can widen later but never invalidates an accepted plan.
    if context is not None and command.planned_on < context.opening_balance_on:
        issues.append(
            PlannedCostIssue(
                code="PLAN_BEFORE_ACCOUNT_BASELINE",
                field="plannedOn",
            )
        )
    return tuple(issues)


def _validate_result(*, result: PlannedCostWriteResult, user_id: UUID) -> None:
    if result.plan.user_id != user_id:
        raise PlannedCostPersistenceUnavailable


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
