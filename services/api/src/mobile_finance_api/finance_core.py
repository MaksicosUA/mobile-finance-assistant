"""Deterministic Finance Core boundary for the first confirmed-operation slice."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .account_core import FinanceAccountDirectory, FinanceAccountSnapshot
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


class OperationAccountUnavailable(Exception):
    """The account disappeared or is outside the authenticated user scope."""


class OperationBeforeAccountBaseline(Exception):
    """The operation precedes the immutable account opening baseline."""


@dataclass(frozen=True, slots=True)
class OperationWriteResult:
    operation: CommittedOperation
    idempotent_replay: bool


class FinanceOperationRepository(Protocol):
    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationWriteResult | None: ...

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationWriteResult: ...


class UnavailableFinanceOperationRepository:
    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationWriteResult | None:
        del user_id, command_id, payload_hash
        raise FinancePersistenceUnavailable

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

    def __init__(
        self,
        *,
        repository: FinanceOperationRepository,
        account_directory: FinanceAccountDirectory,
    ) -> None:
        self._repository = repository
        self._account_directory = account_directory

    async def evaluate(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
    ) -> EvaluateOperationResponse:
        account = await self._account_for_draft(user_id=user_id, draft=draft)
        issues = _evaluate_issues(draft, account=account)
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
        actual_hash = draft_hash(draft)
        if actual_hash != expected_draft_hash:
            raise ConfirmationMismatch
        command_hash = confirmed_command_hash(
            draft=draft,
            confirmed_at=confirmed_at,
            evaluated_draft_hash=actual_hash,
        )
        payload_hash = bytes.fromhex(command_hash)
        try:
            existing = await self._repository.replay_existing(
                user_id=user_id,
                command_id=draft.command_id,
                payload_hash=payload_hash,
            )
        except OperationCommandConflict:
            raise
        except FinancePersistenceUnavailable:
            raise
        except Exception as error:
            raise FinancePersistenceUnavailable from error
        if existing is not None:
            return existing

        if confirmed_at < draft.captured_at:
            raise OperationRejected(
                (
                    OperationIssue(
                        code="CONFIRMATION_BEFORE_CAPTURE",
                        field="confirmedAt",
                    ),
                )
            )

        evaluation = await self.evaluate(user_id=user_id, draft=draft)
        if evaluation.decision == "REJECT":
            raise OperationRejected(evaluation.issues)
        try:
            return await self._repository.commit(
                user_id=user_id,
                draft=draft,
                payload_hash=payload_hash,
                confirmed_at=confirmed_at,
            )
        except OperationAccountUnavailable:
            raise OperationRejected(
                (OperationIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"),)
            ) from None
        except OperationBeforeAccountBaseline:
            raise OperationRejected(
                (
                    OperationIssue(
                        code="OPERATION_BEFORE_ACCOUNT_BASELINE",
                        field="occurredOn",
                    ),
                )
            ) from None

    async def _account_for_draft(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
    ) -> FinanceAccountSnapshot | None:
        if draft.account_id is None:
            return None
        try:
            return await self._account_directory.get_owned_active_account(
                user_id=user_id,
                account_id=draft.account_id,
            )
        except Exception as error:
            raise FinancePersistenceUnavailable from error


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


def _evaluate_issues(
    draft: OperationDraft,
    *,
    account: FinanceAccountSnapshot | None,
) -> tuple[OperationIssue, ...]:
    issues: list[OperationIssue] = []
    timezone = ZoneInfo(draft.captured_timezone)
    captured_local_date = draft.captured_at.astimezone(timezone).date()

    if draft.account_id is None:
        issues.append(OperationIssue(code="ACCOUNT_REQUIRED", field="accountId"))
    elif account is None:
        issues.append(OperationIssue(code="ACCOUNT_UNAVAILABLE", field="accountId"))
    else:
        if account.currency != draft.currency:
            issues.append(
                OperationIssue(
                    code="ACCOUNT_CURRENCY_MISMATCH",
                    field="currency",
                )
            )
        if draft.occurred_on < account.opening_balance_on:
            issues.append(
                OperationIssue(
                    code="OPERATION_BEFORE_ACCOUNT_BASELINE",
                    field="occurredOn",
                )
            )
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
