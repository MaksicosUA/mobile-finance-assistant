"""Deterministic boundary for savings goals and contributions (ADR 0019).

This module never computes or touches an authoritative money total. It validates
intent, delegates the single authoritative write transaction, and derives the
read-time figures a goal exposes: its balance, its progress, and whether it is
achieved.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .goal_contracts import (
    CancelGoalCommand,
    CancelGoalResponse,
    CreateGoalCommand,
    CreateGoalResponse,
    Goal,
    GoalContribution,
    GoalIssue,
    ListGoalContributionsResponse,
    ListGoalsResponse,
    RecordGoalContributionCommand,
    RecordGoalContributionResponse,
    cancel_goal_command_hash,
    contribution_command_hash,
    create_goal_command_hash,
    derive_achieved,
    derive_progress_percent,
)


class GoalPersistenceUnavailable(Exception):
    """The authoritative store could not safely read or commit a goal."""


class GoalCommandConflict(Exception):
    """A command ID is already bound to different confirmed content."""


class GoalNotFound(Exception):
    """No such goal exists inside the authenticated user's scope."""


class GoalAccountUnavailable(Exception):
    """The account disappeared or is outside the authenticated user scope."""


class GoalTargetBeforeAccountBaseline(Exception):
    """The goal target date precedes the account opening baseline."""


class GoalNotActive(Exception):
    """The goal already reached a terminal status."""


class GoalWithdrawalExceedsBalance(Exception):
    """A withdrawal would drive the goal balance below zero."""


class GoalRejected(Exception):
    def __init__(self, issues: tuple[GoalIssue, ...]) -> None:
        super().__init__("goal rejected")
        self.issues = issues


@dataclass(frozen=True, slots=True)
class GoalAccountContext:
    """Owned-account facts a goal is validated against."""

    account_id: UUID
    user_id: UUID
    currency: str
    opening_balance_on: date
    canonical_timezone: str


@dataclass(frozen=True, slots=True)
class StoredGoal:
    """Authoritative goal row plus the ledger sum derived for it.

    ``progress`` and ``achieved`` are deliberately absent: both follow from
    ``current_amount`` and ``target_amount`` and are computed at read time, so
    no stored copy can contradict the ledger (ADR 0019).
    """

    goal_id: UUID
    user_id: UUID
    account_id: UUID
    command_id: UUID
    title: str
    target_amount: Decimal
    monthly_contribution: Decimal
    current_amount: Decimal
    currency: str
    target_on: date
    status: str
    created_at: datetime
    updated_at: datetime
    canonical_timezone: str


@dataclass(frozen=True, slots=True)
class StoredGoalContribution:
    """Immutable ledger entry as persisted."""

    contribution_id: UUID
    goal_id: UUID
    user_id: UUID
    command_id: UUID
    direction: str
    amount: Decimal
    currency: str
    occurred_on: date
    created_at: datetime


@dataclass(frozen=True, slots=True)
class GoalWriteResult:
    goal: StoredGoal
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class ContributionWriteResult:
    contribution: StoredGoalContribution
    goal: StoredGoal
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class GoalListSnapshot:
    canonical_timezone: str | None
    goals: tuple[StoredGoal, ...]


@dataclass(frozen=True, slots=True)
class GoalLedgerSnapshot:
    goal: StoredGoal
    contributions: tuple[StoredGoalContribution, ...]


class GoalRepository(Protocol):
    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> GoalAccountContext | None:
        """Return an owned active account without exposing foreign accounts."""

    async def get_goal_context(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> tuple[StoredGoal, GoalAccountContext] | None:
        """Return an owned goal and the account facts it is bound to."""

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        """Return an exact prior creation or reject command identity reuse."""

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreateGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        """Atomically write the goal, its audit row, and its invalidation."""

    async def replay_existing_goal_command(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        """Return an exact prior cancellation or reject identity reuse."""

    async def cancel(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: CancelGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        """Atomically cancel one goal under a row lock, keeping its ledger."""

    async def replay_existing_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> ContributionWriteResult | None:
        """Return an exact prior ledger entry or reject identity reuse."""

    async def record_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: RecordGoalContributionCommand,
        occurred_on: date,
        payload_hash: bytes,
    ) -> ContributionWriteResult:
        """Append one ledger entry under the goal's row lock."""

    async def list_goals(self, *, user_id: UUID) -> GoalListSnapshot:
        """Return the user's goals in a stable order."""

    async def list_contributions(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> GoalLedgerSnapshot:
        """Return one goal with its full ledger in a stable order."""


class UnavailableGoalRepository:
    async def get_account_context(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> GoalAccountContext | None:
        del user_id, account_id
        raise GoalPersistenceUnavailable

    async def get_goal_context(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> tuple[StoredGoal, GoalAccountContext] | None:
        del user_id, goal_id
        raise GoalPersistenceUnavailable

    async def replay_existing_create(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        del user_id, command_id, payload_hash
        raise GoalPersistenceUnavailable

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreateGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        del user_id, command, payload_hash
        raise GoalPersistenceUnavailable

    async def replay_existing_goal_command(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> GoalWriteResult | None:
        del user_id, goal_id, command_id, payload_hash
        raise GoalPersistenceUnavailable

    async def cancel(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: CancelGoalCommand,
        payload_hash: bytes,
    ) -> GoalWriteResult:
        del user_id, goal_id, command, payload_hash
        raise GoalPersistenceUnavailable

    async def replay_existing_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> ContributionWriteResult | None:
        del user_id, goal_id, command_id, payload_hash
        raise GoalPersistenceUnavailable

    async def record_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: RecordGoalContributionCommand,
        occurred_on: date,
        payload_hash: bytes,
    ) -> ContributionWriteResult:
        del user_id, goal_id, command, occurred_on, payload_hash
        raise GoalPersistenceUnavailable

    async def list_goals(self, *, user_id: UUID) -> GoalListSnapshot:
        del user_id
        raise GoalPersistenceUnavailable

    async def list_contributions(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> GoalLedgerSnapshot:
        del user_id, goal_id
        raise GoalPersistenceUnavailable


class GoalCore:
    """Validate and commit the goal and contribution lifecycle."""

    def __init__(
        self,
        *,
        repository: GoalRepository,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._clock = clock or _utc_now

    async def create(
        self,
        *,
        user_id: UUID,
        command: CreateGoalCommand,
    ) -> CreateGoalResponse:
        payload_hash = bytes.fromhex(create_goal_command_hash(command))
        existing = await self._repository.replay_existing_create(
            user_id=user_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return CreateGoalResponse(
                idempotent_replay=True,
                goal=_to_contract(existing.goal),
            )

        context = await self._repository.get_account_context(
            user_id=user_id,
            account_id=command.account_id,
        )
        issues = _creation_issues(command=command, context=context)
        if issues:
            raise GoalRejected(issues)

        try:
            result = await self._repository.create(
                user_id=user_id,
                command=command,
                payload_hash=payload_hash,
            )
        except GoalAccountUnavailable:
            raise GoalRejected(
                (GoalIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"),)
            ) from None
        except GoalTargetBeforeAccountBaseline:
            raise GoalRejected(
                (
                    GoalIssue(
                        code="TARGET_BEFORE_ACCOUNT_BASELINE",
                        field="targetOn",
                    ),
                )
            ) from None
        _validate_owner(goal=result.goal, user_id=user_id)
        return CreateGoalResponse(
            idempotent_replay=result.idempotent_replay,
            goal=_to_contract(result.goal),
        )

    async def cancel(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: CancelGoalCommand,
    ) -> CancelGoalResponse:
        payload_hash = bytes.fromhex(
            cancel_goal_command_hash(goal_id=goal_id, command=command)
        )
        existing = await self._repository.replay_existing_goal_command(
            user_id=user_id,
            goal_id=goal_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return CancelGoalResponse(
                idempotent_replay=True,
                goal=_to_contract(existing.goal),
            )

        try:
            result = await self._repository.cancel(
                user_id=user_id,
                goal_id=goal_id,
                command=command,
                payload_hash=payload_hash,
            )
        except GoalNotActive:
            raise GoalRejected(
                (GoalIssue(code="GOAL_NOT_ACTIVE", field="status"),)
            ) from None
        _validate_owner(goal=result.goal, user_id=user_id)
        return CancelGoalResponse(
            idempotent_replay=result.idempotent_replay,
            goal=_to_contract(result.goal),
        )

    async def record_contribution(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
        command: RecordGoalContributionCommand,
    ) -> RecordGoalContributionResponse:
        payload_hash = bytes.fromhex(
            contribution_command_hash(goal_id=goal_id, command=command)
        )
        existing = await self._repository.replay_existing_contribution(
            user_id=user_id,
            goal_id=goal_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return RecordGoalContributionResponse(
                idempotent_replay=True,
                contribution=_to_contribution_contract(existing.contribution),
                goal=_to_contract(existing.goal),
            )

        found = await self._repository.get_goal_context(
            user_id=user_id,
            goal_id=goal_id,
        )
        if found is None:
            raise GoalNotFound
        goal, account = found
        today = _local_today(now_utc=_aware_utc(self._clock()), account=account)
        # Resolved once here so the value written, the value validated, and the
        # value returned are the same date even across a local midnight.
        occurred_on = command.occurred_on if command.occurred_on is not None else today
        issues = _contribution_issues(
            command=command,
            goal=goal,
            account=account,
            occurred_on=occurred_on,
            today=today,
        )
        if issues:
            raise GoalRejected(issues)

        try:
            result = await self._repository.record_contribution(
                user_id=user_id,
                goal_id=goal_id,
                command=command,
                occurred_on=occurred_on,
                payload_hash=payload_hash,
            )
        except GoalNotActive:
            raise GoalRejected(
                (GoalIssue(code="GOAL_NOT_ACTIVE", field="status"),)
            ) from None
        except GoalWithdrawalExceedsBalance:
            # Re-checked under the row lock, so two concurrent withdrawals
            # cannot both pass a check that each saw as satisfied.
            raise GoalRejected(
                (
                    GoalIssue(
                        code="WITHDRAWAL_EXCEEDS_GOAL_BALANCE",
                        field="amount",
                    ),
                )
            ) from None
        _validate_owner(goal=result.goal, user_id=user_id)
        if result.contribution.user_id != user_id:
            raise GoalPersistenceUnavailable
        return RecordGoalContributionResponse(
            idempotent_replay=result.idempotent_replay,
            contribution=_to_contribution_contract(result.contribution),
            goal=_to_contract(result.goal),
        )

    async def list_goals(self, *, user_id: UUID) -> ListGoalsResponse:
        snapshot = await self._repository.list_goals(user_id=user_id)
        for goal in snapshot.goals:
            _validate_owner(goal=goal, user_id=user_id)
        now_utc = _aware_utc(self._clock())
        # Without a canonical timezone the user has no account and therefore no
        # goals; UTC is then only a well-formed placeholder for `evaluatedOn`.
        timezone = (
            ZoneInfo(snapshot.canonical_timezone)
            if snapshot.canonical_timezone is not None
            else UTC
        )
        return ListGoalsResponse(
            evaluated_on=now_utc.astimezone(timezone).date(),
            goals=tuple(_to_contract(goal) for goal in snapshot.goals),
        )

    async def list_contributions(
        self,
        *,
        user_id: UUID,
        goal_id: UUID,
    ) -> ListGoalContributionsResponse:
        snapshot = await self._repository.list_contributions(
            user_id=user_id,
            goal_id=goal_id,
        )
        _validate_owner(goal=snapshot.goal, user_id=user_id)
        if any(entry.user_id != user_id for entry in snapshot.contributions):
            raise GoalPersistenceUnavailable
        return ListGoalContributionsResponse(
            goal=_to_contract(snapshot.goal),
            contributions=tuple(
                _to_contribution_contract(entry) for entry in snapshot.contributions
            ),
        )


def _to_contract(goal: StoredGoal) -> Goal:
    return Goal(
        goal_id=goal.goal_id,
        user_id=goal.user_id,
        account_id=goal.account_id,
        command_id=goal.command_id,
        title=goal.title,
        target_amount=goal.target_amount,
        current_amount=goal.current_amount,
        monthly_contribution=goal.monthly_contribution,
        currency=goal.currency,
        target_on=goal.target_on,
        status=goal.status,  # type: ignore[arg-type]
        achieved=derive_achieved(
            current=goal.current_amount,
            target=goal.target_amount,
        ),
        progress_percent=derive_progress_percent(
            current=goal.current_amount,
            target=goal.target_amount,
        ),
        created_at=goal.created_at,
        updated_at=goal.updated_at,
    )


def _to_contribution_contract(entry: StoredGoalContribution) -> GoalContribution:
    return GoalContribution(
        contribution_id=entry.contribution_id,
        goal_id=entry.goal_id,
        user_id=entry.user_id,
        command_id=entry.command_id,
        direction=entry.direction,  # type: ignore[arg-type]
        amount=entry.amount,
        currency=entry.currency,
        occurred_on=entry.occurred_on,
        created_at=entry.created_at,
    )


def _creation_issues(
    *,
    command: CreateGoalCommand,
    context: GoalAccountContext | None,
) -> tuple[GoalIssue, ...]:
    """Apply the ADR 0019 creation bounds in a fixed, deterministic order."""

    issues: list[GoalIssue] = []
    if context is None:
        issues.append(GoalIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    elif context.currency != command.currency:
        issues.append(GoalIssue(code="ACCOUNT_CURRENCY_MISMATCH", field="currency"))
    # No verified currency registry or rate provenance exists yet, so anything
    # outside the account base currency fails closed exactly as operations do.
    if command.currency != "EUR":
        issues.append(GoalIssue(code="UNSUPPORTED_CURRENCY", field="currency"))
    # A target before the baseline describes a deadline the account did not yet
    # exist for. Corrections only move the baseline earlier (ADR 0016), so this
    # bound can widen later but never invalidates an accepted goal.
    if context is not None and command.target_on < context.opening_balance_on:
        issues.append(
            GoalIssue(code="TARGET_BEFORE_ACCOUNT_BASELINE", field="targetOn")
        )
    return tuple(issues)


def _contribution_issues(
    *,
    command: RecordGoalContributionCommand,
    goal: StoredGoal,
    account: GoalAccountContext,
    occurred_on: date,
    today: date,
) -> tuple[GoalIssue, ...]:
    """Apply the ADR 0019 ledger bounds in a fixed, deterministic order."""

    issues: list[GoalIssue] = []
    if goal.status != "active":
        issues.append(GoalIssue(code="GOAL_NOT_ACTIVE", field="status"))
    # Unlike a plan, a contribution is something that already happened, so a
    # future date is refused exactly as it is for an operation.
    if occurred_on > today:
        issues.append(GoalIssue(code="FUTURE_CONTRIBUTION_DATE", field="occurredOn"))
    if occurred_on < account.opening_balance_on:
        issues.append(
            GoalIssue(
                code="CONTRIBUTION_BEFORE_ACCOUNT_BASELINE",
                field="occurredOn",
            )
        )
    if command.direction == "withdrawal" and command.amount > goal.current_amount:
        issues.append(GoalIssue(code="WITHDRAWAL_EXCEEDS_GOAL_BALANCE", field="amount"))
    return tuple(issues)


def _validate_owner(*, goal: StoredGoal, user_id: UUID) -> None:
    if goal.user_id != user_id:
        raise GoalPersistenceUnavailable


def _local_today(*, now_utc: datetime, account: GoalAccountContext) -> date:
    return now_utc.astimezone(ZoneInfo(account.canonical_timezone)).date()


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
