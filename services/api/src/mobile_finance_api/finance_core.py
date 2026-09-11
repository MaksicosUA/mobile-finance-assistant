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
    CorrectOperationRequest,
    EvaluateOperationResponse,
    ListOperationsResponse,
    OperationDraft,
    OperationIssue,
    OperationReversal,
    RemoveOperationRequest,
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


class OperationNotFound(Exception):
    """No such operation for this user.

    Another user's operation raises this too, so the API never confirms that
    an identifier exists outside the caller's own ledger.
    """


class OperationAlreadyReversed(Exception):
    """The operation was already corrected or removed (ADR 0023)."""


@dataclass(frozen=True, slots=True)
class OperationWriteResult:
    operation: CommittedOperation
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class OperationReversalResult:
    """One withdrawn operation, and the one that replaced it if any."""

    reversal: OperationReversal
    replacement: CommittedOperation | None
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class FinanceCategorySnapshot:
    """The catalogue facts a draft is validated against (ADR 0020)."""

    category_id: UUID
    user_id: UUID
    direction: str
    archived: bool


class FinanceCategoryDirectory(Protocol):
    async def get_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> FinanceCategorySnapshot | None:
        """Return an owned category without exposing another user's catalogue."""


class UnavailableFinanceCategoryDirectory:
    """Used when no catalogue is wired; a draft may then carry no category."""

    async def get_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> FinanceCategorySnapshot | None:
        del user_id, category_id
        return None


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

    async def replay_reversal(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationReversalResult | None: ...

    async def reverse(
        self,
        *,
        user_id: UUID,
        target_operation_id: UUID,
        command_id: UUID,
        replacement: OperationDraft | None,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationReversalResult: ...


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

    async def list_operations(
        self,
        *,
        user_id: UUID,
        limit: int,
        cursor: str | None,
    ) -> ListOperationsResponse:
        del user_id, limit, cursor
        raise FinancePersistenceUnavailable

    async def replay_reversal(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationReversalResult | None:
        del user_id, command_id, payload_hash
        raise FinancePersistenceUnavailable

    async def reverse(
        self,
        *,
        user_id: UUID,
        target_operation_id: UUID,
        command_id: UUID,
        replacement: OperationDraft | None,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationReversalResult:
        del user_id, target_operation_id, command_id, replacement
        del payload_hash, confirmed_at
        raise FinancePersistenceUnavailable


class FinanceCore:
    """Validate drafts and delegate the sole authoritative write transaction."""

    def __init__(
        self,
        *,
        repository: FinanceOperationRepository,
        account_directory: FinanceAccountDirectory,
        category_directory: FinanceCategoryDirectory | None = None,
    ) -> None:
        self._repository = repository
        self._account_directory = account_directory
        self._category_directory = (
            category_directory
            if category_directory is not None
            else UnavailableFinanceCategoryDirectory()
        )

    @property
    def operation_store(self) -> FinanceOperationRepository:
        """The adapter this core writes through, for read-only routes.

        Exposed so wiring the core also wires reading operations back. Keeping
        them separate meant a deployment could accept writes and answer 503 to
        every read, which is exactly what happened once.
        """

        return self._repository

    async def evaluate(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
    ) -> EvaluateOperationResponse:
        account = await self._account_for_draft(user_id=user_id, draft=draft)
        category = await self._category_for_draft(user_id=user_id, draft=draft)
        issues = _evaluate_issues(draft, account=account, category=category)
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

    async def correct(
        self,
        *,
        user_id: UUID,
        request: CorrectOperationRequest,
    ) -> OperationReversalResult:
        """Replace one confirmed operation with a reviewed draft (ADR 0023).

        The replacement is validated exactly like any new operation, so a
        correction can never write something the ordinary path would refuse.
        """

        draft = request.draft
        if draft_hash(draft) != request.draft_hash:
            raise ConfirmationMismatch
        payload_hash = bytes.fromhex(correction_command_hash(request))
        replay = await self._replay_reversal(
            user_id=user_id,
            command_id=draft.command_id,
            payload_hash=payload_hash,
        )
        if replay is not None:
            return replay

        if request.confirmed_at < draft.captured_at:
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
        return await self._reverse(
            user_id=user_id,
            target_operation_id=request.target_operation_id,
            command_id=draft.command_id,
            replacement=draft,
            payload_hash=payload_hash,
            confirmed_at=request.confirmed_at,
        )

    async def remove(
        self,
        *,
        user_id: UUID,
        request: RemoveOperationRequest,
    ) -> OperationReversalResult:
        """Withdraw one confirmed operation without replacing it."""

        payload_hash = bytes.fromhex(removal_command_hash(request))
        replay = await self._replay_reversal(
            user_id=user_id,
            command_id=request.command_id,
            payload_hash=payload_hash,
        )
        if replay is not None:
            return replay
        return await self._reverse(
            user_id=user_id,
            target_operation_id=request.target_operation_id,
            command_id=request.command_id,
            replacement=None,
            payload_hash=payload_hash,
            confirmed_at=request.confirmed_at,
        )

    async def _replay_reversal(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> OperationReversalResult | None:
        try:
            return await self._repository.replay_reversal(
                user_id=user_id,
                command_id=command_id,
                payload_hash=payload_hash,
            )
        except (OperationCommandConflict, FinancePersistenceUnavailable):
            raise
        except Exception as error:
            raise FinancePersistenceUnavailable from error

    async def _reverse(
        self,
        *,
        user_id: UUID,
        target_operation_id: UUID,
        command_id: UUID,
        replacement: OperationDraft | None,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> OperationReversalResult:
        try:
            return await self._repository.reverse(
                user_id=user_id,
                target_operation_id=target_operation_id,
                command_id=command_id,
                replacement=replacement,
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

    async def _category_for_draft(
        self,
        *,
        user_id: UUID,
        draft: OperationDraft,
    ) -> FinanceCategorySnapshot | None:
        if draft.category_id is None:
            return None
        try:
            return await self._category_directory.get_category(
                user_id=user_id,
                category_id=draft.category_id,
            )
        except Exception as error:
            raise FinancePersistenceUnavailable from error


def draft_hash(draft: OperationDraft) -> str:
    return _canonical_hash(draft.model_dump(mode="json", by_alias=True))


def correction_command_hash(request: CorrectOperationRequest) -> str:
    """Hash the whole correction, target included.

    Hashing only the replacement draft would let a confirmation reviewed for
    one operation be committed against another.
    """

    return _canonical_hash(request.model_dump(mode="json", by_alias=True))


def removal_command_hash(request: RemoveOperationRequest) -> str:
    return _canonical_hash(request.model_dump(mode="json", by_alias=True))


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
    category: FinanceCategorySnapshot | None = None,
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
    if draft.category_id is not None:
        # An archived category still groups history but must not be chosen for
        # something new, so it reads as unavailable here (ADR 0020).
        if category is None or category.archived:
            issues.append(
                OperationIssue(code="CATEGORY_UNAVAILABLE", field="categoryId")
            )
        elif category.direction != draft.operation_type:
            # Filing an expense under an income category would silently corrupt
            # every later breakdown.
            issues.append(
                OperationIssue(
                    code="CATEGORY_DIRECTION_MISMATCH",
                    field="categoryId",
                )
            )
    # No absolute currency rule remains: a wallet holds one currency and money
    # recorded in it carries that currency, which the mismatch check above and
    # the composite (account_id, user_id, currency) foreign key both enforce.
    # Nothing converts anything, so there is nothing left for a base currency
    # to mean (ADR 0029). `UNSUPPORTED_CURRENCY` stays in the contract for
    # installed clients and is no longer raised.
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
