"""Deterministic Finance Core boundary for the first confirmed-operation slice."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .operation_contracts import (
    CommitOperationRequest,
    CommittedOperation,
    EvaluateOperationResponse,
    OperationDraft,
    OperationIssue,
)


class ConfirmationMismatch(Exception):
    """The committed draft differs from the explicitly evaluated draft."""


class OperationCommandConflict(Exception):
    """A command ID is already bound to a different immutable draft."""


class OperationRejected(Exception):
    def __init__(self, issues: tuple[OperationIssue, ...]) -> None:
        super().__init__("operation rejected")
        self.issues = issues


class FinancePersistenceUnavailable(Exception):
    """The authoritative store could not safely commit or replay a command."""


@dataclass(frozen=True, slots=True)
class OperationWriteResult:
    operation: CommittedOperation
    idempotent_replay: bool


class FinanceOperationRepository(Protocol):
    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult: ...


class UnavailableFinanceOperationRepository:
    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise FinancePersistenceUnavailable


class FinanceCore:
    """Validate drafts and delegate the sole authoritative write transaction."""

    def __init__(self, *, repository: FinanceOperationRepository) -> None:
        self._repository = repository

    def evaluate(self, draft: OperationDraft) -> EvaluateOperationResponse:
        issues = _evaluate_issues(draft)
        if issues:
            return EvaluateOperationResponse(
                decision="REJECT",
                draft=draft,
                draft_hash=None,
                issues=issues,
            )
        return EvaluateOperationResponse(
            decision="NEEDS_CONFIRMATION",
            draft=draft,
            draft_hash=draft_hash(draft),
            issues=(),
        )

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        expected_draft_hash: str,
        confirmed_at: datetime,
    ) -> OperationWriteResult:
        evaluation = self.evaluate(draft)
        if evaluation.decision == "REJECT":
            raise OperationRejected(evaluation.issues)
        actual_hash = draft_hash(draft)
        if actual_hash != expected_draft_hash:
            raise ConfirmationMismatch
        if confirmed_at < draft.captured_at:
            raise OperationRejected(
                (
                    OperationIssue(
                        code="CONFIRMATION_BEFORE_CAPTURE",
                        field="confirmedAt",
                    ),
                )
            )
        command_hash = confirmed_command_hash(
            draft=draft,
            confirmed_at=confirmed_at,
            evaluated_draft_hash=actual_hash,
        )
        return await self._repository.commit(
            user_id=user_id,
            draft=draft,
            payload_hash=bytes.fromhex(command_hash),
            confirmed_at=confirmed_at,
        )


def draft_hash(draft: OperationDraft) -> str:
    return _canonical_hash(draft.model_dump(mode="json", by_alias=True))


def confirmed_command_hash(
    *,
    draft: OperationDraft,
    confirmed_at: datetime,
    evaluated_draft_hash: str,
) -> str:
    command = CommitOperationRequest(
        schema_version="1",
        draft=draft,
        draft_hash=evaluated_draft_hash,
        confirmed_at=confirmed_at,
    )
    return _canonical_hash(command.model_dump(mode="json", by_alias=True))


def _canonical_hash(payload: object) -> str:
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _evaluate_issues(draft: OperationDraft) -> tuple[OperationIssue, ...]:
    issues: list[OperationIssue] = []
    timezone = ZoneInfo(draft.captured_timezone)
    captured_local_date = draft.captured_at.astimezone(timezone).date()

    # Account ownership cannot be verified until an account registry exists.
    # V1 accepts only explicitly unallocated operations and never trusts an
    # opaque client account identifier.
    if draft.account_id is not None:
        issues.append(OperationIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    # A versioned ISO currency registry and conversion provenance are not yet
    # available. V1 therefore fails closed outside the account base currency.
    if draft.currency != "EUR":
        issues.append(OperationIssue(code="UNSUPPORTED_CURRENCY", field="currency"))
    if draft.occurred_on > captured_local_date:
        issues.append(OperationIssue(code="FUTURE_OCCURRED_DATE", field="occurredOn"))
    if (
        draft.occurred_at is not None
        and draft.occurred_at.astimezone(timezone).date() != draft.occurred_on
    ):
        issues.append(
            OperationIssue(code="OCCURRED_AT_DATE_MISMATCH", field="occurredAt")
        )

    expected_date, expression_supported = _relative_date(
        expression=draft.source_expression,
        captured_local_date=captured_local_date,
    )
    if not expression_supported:
        issues.append(
            OperationIssue(
                code="UNSUPPORTED_DATE_EXPRESSION",
                field="sourceExpression",
            )
        )
    elif expected_date is not None and expected_date != draft.occurred_on:
        issues.append(OperationIssue(code="RELATIVE_DATE_MISMATCH", field="occurredOn"))
    return tuple(issues)


def _relative_date(
    *, expression: str | None, captured_local_date: date
) -> tuple[date | None, bool]:
    if expression is None:
        return None, True
    normalized = " ".join(expression.casefold().split())
    if normalized in {"сегодня", "today"}:
        return captured_local_date, True
    if normalized in {"вчера", "yesterday"}:
        return captured_local_date - timedelta(days=1), True
    return None, False
