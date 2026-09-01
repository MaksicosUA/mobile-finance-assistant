"""Deterministic boundary for monthly budgets (ADR 0027).

A ceiling is a declaration. What has been spent against it is derived from
committed operations at read time and never stored, so no copy can disagree
with the operations it claims to summarise.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol
from uuid import UUID

from .budget_contracts import (
    BudgetIssue,
    BudgetsResponse,
    RemoveBudgetCommand,
    RemoveBudgetResponse,
    SetBudgetCommand,
    SetBudgetResponse,
    remove_budget_command_hash,
    set_budget_command_hash,
)

#: A ceiling limits spending, so only an expense category can carry one.
BUDGET_DIRECTION = "expense"


class BudgetPersistenceUnavailable(Exception):
    """The authoritative store could not safely read or commit a ceiling."""


class BudgetCommandConflict(Exception):
    """A command ID is already bound to different content."""


class BudgetNotFound(Exception):
    """No such budget exists inside the authenticated user's scope."""


class BudgetAccountUnavailable(Exception):
    """The account disappeared or is outside the authenticated user scope."""


class BudgetAlreadyRemoved(Exception):
    """The ceiling was already withdrawn."""


class BudgetRejected(Exception):
    def __init__(self, issues: tuple[BudgetIssue, ...]) -> None:
        super().__init__("budget rejected")
        self.issues = issues


@dataclass(frozen=True, slots=True)
class BudgetAccountContext:
    account_id: UUID
    user_id: UUID
    currency: str


@dataclass(frozen=True, slots=True)
class BudgetWriteResult:
    budget_id: UUID
    category_id: UUID | None
    limit: Decimal
    idempotent_replay: bool


class BudgetRepository(Protocol):
    async def get_account_context(
        self,
        *,
        user_id: UUID,
    ) -> BudgetAccountContext | None:
        """Return the owned active account a ceiling would belong to."""

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        """Return an owned non-archived category's direction, or None."""

    async def replay_existing_set(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        """Return an exact prior write or reject command identity reuse."""

    async def set_budget(
        self,
        *,
        user_id: UUID,
        command: SetBudgetCommand,
        payload_hash: bytes,
    ) -> BudgetWriteResult:
        """Declare or change one ceiling, with its audit row, atomically."""

    async def replay_existing_removal(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        """Return an exact prior removal or reject command identity reuse."""

    async def remove_budget(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command: RemoveBudgetCommand,
        payload_hash: bytes,
    ) -> BudgetWriteResult:
        """Withdraw one ceiling, keeping its audit trail intact."""

    async def read_budgets(self, *, user_id: UUID) -> BudgetsResponse:
        """Report every live ceiling and how the current month stands."""


class UnavailableBudgetRepository:
    async def get_account_context(
        self,
        *,
        user_id: UUID,
    ) -> BudgetAccountContext | None:
        del user_id
        raise BudgetPersistenceUnavailable

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        del user_id, category_id
        raise BudgetPersistenceUnavailable

    async def replay_existing_set(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        del user_id, command_id, payload_hash
        raise BudgetPersistenceUnavailable

    async def set_budget(
        self,
        *,
        user_id: UUID,
        command: SetBudgetCommand,
        payload_hash: bytes,
    ) -> BudgetWriteResult:
        del user_id, command, payload_hash
        raise BudgetPersistenceUnavailable

    async def replay_existing_removal(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        del user_id, budget_id, command_id, payload_hash
        raise BudgetPersistenceUnavailable

    async def remove_budget(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command: RemoveBudgetCommand,
        payload_hash: bytes,
    ) -> BudgetWriteResult:
        del user_id, budget_id, command, payload_hash
        raise BudgetPersistenceUnavailable

    async def read_budgets(self, *, user_id: UUID) -> BudgetsResponse:
        del user_id
        raise BudgetPersistenceUnavailable


class BudgetCore:
    """Validate and commit monthly ceilings."""

    def __init__(self, *, repository: BudgetRepository) -> None:
        self._repository = repository

    async def set_budget(
        self,
        *,
        user_id: UUID,
        command: SetBudgetCommand,
    ) -> SetBudgetResponse:
        payload_hash = bytes.fromhex(set_budget_command_hash(command))
        existing = await self._repository.replay_existing_set(
            user_id=user_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return _set_response(existing)

        context = await self._repository.get_account_context(user_id=user_id)
        direction = (
            await self._repository.get_category_direction(
                user_id=user_id,
                category_id=command.category_id,
            )
            if command.category_id is not None
            else None
        )
        issues = _issues(
            command=command,
            context=context,
            category_direction=direction,
        )
        if issues:
            raise BudgetRejected(issues)

        try:
            result = await self._repository.set_budget(
                user_id=user_id,
                command=command,
                payload_hash=payload_hash,
            )
        except BudgetAccountUnavailable:
            raise BudgetRejected(
                (BudgetIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"),)
            ) from None
        return _set_response(result)

    async def remove_budget(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command: RemoveBudgetCommand,
    ) -> RemoveBudgetResponse:
        payload_hash = bytes.fromhex(
            remove_budget_command_hash(budget_id=budget_id, command=command)
        )
        existing = await self._repository.replay_existing_removal(
            user_id=user_id,
            budget_id=budget_id,
            command_id=command.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            return RemoveBudgetResponse(
                idempotent_replay=True,
                budget_id=existing.budget_id,
            )

        try:
            result = await self._repository.remove_budget(
                user_id=user_id,
                budget_id=budget_id,
                command=command,
                payload_hash=payload_hash,
            )
        except BudgetAlreadyRemoved:
            raise BudgetRejected(
                (BudgetIssue(code="BUDGET_ALREADY_REMOVED", field="status"),)
            ) from None
        return RemoveBudgetResponse(
            idempotent_replay=result.idempotent_replay,
            budget_id=result.budget_id,
        )

    async def read_budgets(self, *, user_id: UUID) -> BudgetsResponse:
        return await self._repository.read_budgets(user_id=user_id)


def _issues(
    *,
    command: SetBudgetCommand,
    context: BudgetAccountContext | None,
    category_direction: str | None,
) -> tuple[BudgetIssue, ...]:
    issues: list[BudgetIssue] = []
    if context is None:
        issues.append(BudgetIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    elif context.account_id != command.account_id:
        issues.append(BudgetIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    elif context.currency != command.currency:
        issues.append(BudgetIssue(code="ACCOUNT_CURRENCY_MISMATCH", field="currency"))
    if command.currency != "EUR":
        issues.append(BudgetIssue(code="UNSUPPORTED_CURRENCY", field="currency"))
    if command.category_id is not None:
        if category_direction is None:
            issues.append(BudgetIssue(code="CATEGORY_UNAVAILABLE", field="categoryId"))
        elif category_direction != BUDGET_DIRECTION:
            # Budgeting income is not a thing anyone means.
            issues.append(
                BudgetIssue(code="CATEGORY_DIRECTION_MISMATCH", field="categoryId")
            )
    return tuple(issues)


def _set_response(result: BudgetWriteResult) -> SetBudgetResponse:
    return SetBudgetResponse(
        idempotent_replay=result.idempotent_replay,
        budget_id=result.budget_id,
        category_id=result.category_id,
        limit=result.limit,
    )
