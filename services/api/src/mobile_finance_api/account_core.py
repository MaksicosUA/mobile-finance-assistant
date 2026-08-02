"""Deterministic Finance Core boundary for authoritative account bootstrap."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Literal, Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from .account_contracts import (
    AccountDraft,
    AccountIssue,
    BaselineIssue,
    CommittedFinanceAccount,
    CorrectBaselineDraft,
    EvaluateAccountResponse,
    EvaluateBaselineResponse,
    ListAccountsResponse,
    account_draft_hash,
    baseline_draft_hash,
    confirmed_account_command_hash,
    confirmed_baseline_command_hash,
)


class AccountConfirmationMismatch(Exception):
    """The committed draft differs from the explicitly evaluated draft."""


class AccountCommandConflict(Exception):
    """A command ID is already bound to different confirmed content."""


class AccountAlreadyInitialized(Exception):
    """The user already has an authoritative Finance account setup."""


class AccountRejected(Exception):
    def __init__(self, issues: tuple[AccountIssue, ...]) -> None:
        super().__init__("account rejected")
        self.issues = issues


class AccountPersistenceUnavailable(Exception):
    """The authoritative store could not safely read or commit an account."""


class AccountUnavailable(Exception):
    """The referenced account is not an owned active account."""


class BaselineRejected(Exception):
    def __init__(self, issues: tuple[BaselineIssue, ...]) -> None:
        super().__init__("baseline correction rejected")
        self.issues = issues


@dataclass(frozen=True, slots=True)
class FinanceAccountSnapshot:
    """Minimal owned-account facts needed for operation allocation."""

    account_id: UUID
    user_id: UUID
    currency: str
    opening_balance_on: date
    status: Literal["active"]


class FinanceAccountDirectory(Protocol):
    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        """Return an owned active account without exposing foreign accounts."""


@dataclass(frozen=True, slots=True)
class AccountSetupSnapshot:
    """Minimal profile state used to evaluate a first-account draft."""

    account_id: UUID | None
    canonical_timezone: str | None
    timezone_revision: int

    @property
    def initialized(self) -> bool:
        return self.account_id is not None

    @property
    def is_consistent(self) -> bool:
        if self.account_id is None:
            return self.canonical_timezone is None and self.timezone_revision == 0
        return self.canonical_timezone is not None and self.timezone_revision == 1


@dataclass(frozen=True, slots=True)
class AccountListSnapshot:
    canonical_timezone: str | None
    timezone_revision: Literal[0, 1]
    accounts: tuple[CommittedFinanceAccount, ...]


@dataclass(frozen=True, slots=True)
class AccountWriteResult:
    account: CommittedFinanceAccount
    canonical_timezone: str
    timezone_revision: Literal[1]
    idempotent_replay: bool


@dataclass(frozen=True, slots=True)
class BaselineCorrectionSnapshot:
    """Owned-account facts a baseline correction is evaluated against."""

    account_id: UUID
    user_id: UUID
    opening_balance_on: date
    canonical_timezone: str
    earliest_operation_on: date | None


@dataclass(frozen=True, slots=True)
class BaselineWriteResult:
    account: CommittedFinanceAccount
    previous_opening_balance_on: date
    idempotent_replay: bool


class FinanceAccountRepository(FinanceAccountDirectory, Protocol):
    async def get_setup_snapshot(self, *, user_id: UUID) -> AccountSetupSnapshot:
        """Return account/timezone bootstrap state for one authenticated user."""

    async def list_accounts(self, *, user_id: UUID) -> AccountListSnapshot:
        """Return a restart-stable authoritative account list snapshot."""

    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> AccountWriteResult | None:
        """Return an exact prior result or reject command identity reuse."""

    async def commit_account(
        self,
        *,
        user_id: UUID,
        draft: AccountDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> AccountWriteResult:
        """Atomically commit or exactly replay account/audit/outbox state."""

    async def get_baseline_snapshot(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> BaselineCorrectionSnapshot | None:
        """Return the owned baseline and its earliest operation date."""

    async def replay_existing_baseline(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BaselineWriteResult | None:
        """Return an exact prior correction or reject command identity reuse."""

    async def correct_opening_baseline(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> BaselineWriteResult:
        """Atomically move the baseline earlier with audit and invalidation."""


class UnavailableFinanceAccountRepository:
    async def get_owned_active_account(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> FinanceAccountSnapshot | None:
        del user_id, account_id
        raise AccountPersistenceUnavailable

    async def get_setup_snapshot(self, *, user_id: UUID) -> AccountSetupSnapshot:
        del user_id
        raise AccountPersistenceUnavailable

    async def list_accounts(self, *, user_id: UUID) -> AccountListSnapshot:
        del user_id
        raise AccountPersistenceUnavailable

    async def replay_existing(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> AccountWriteResult | None:
        del user_id, command_id, payload_hash
        raise AccountPersistenceUnavailable

    async def commit_account(
        self,
        *,
        user_id: UUID,
        draft: AccountDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> AccountWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise AccountPersistenceUnavailable

    async def get_baseline_snapshot(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
    ) -> BaselineCorrectionSnapshot | None:
        del user_id, account_id
        raise AccountPersistenceUnavailable

    async def replay_existing_baseline(
        self,
        *,
        user_id: UUID,
        account_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BaselineWriteResult | None:
        del user_id, account_id, command_id, payload_hash
        raise AccountPersistenceUnavailable

    async def correct_opening_baseline(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
        payload_hash: bytes,
        confirmed_at: datetime,
    ) -> BaselineWriteResult:
        del user_id, draft, payload_hash, confirmed_at
        raise AccountPersistenceUnavailable


class AccountCore:
    """Validate and commit the only supported first-account lifecycle."""

    def __init__(
        self,
        *,
        repository: FinanceAccountRepository,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._repository = repository
        self._clock = clock or _utc_now

    async def evaluate(
        self,
        *,
        user_id: UUID,
        draft: AccountDraft,
    ) -> EvaluateAccountResponse:
        now = _aware_utc(self._clock())
        snapshot = await self._repository.get_setup_snapshot(user_id=user_id)
        if not snapshot.is_consistent:
            raise AccountPersistenceUnavailable
        issues = list(_draft_issues(draft=draft, today_utc=now))
        if snapshot.initialized:
            issues.append(
                AccountIssue(code="ACCOUNT_ALREADY_INITIALIZED", field="account")
            )
        if issues:
            return EvaluateAccountResponse(
                decision="REJECT",
                draft=draft,
                draft_hash=None,
                issues=tuple(issues),
            )
        return EvaluateAccountResponse(
            decision="NEEDS_CONFIRMATION",
            draft=draft,
            draft_hash=account_draft_hash(draft),
            issues=(),
        )

    async def commit(
        self,
        *,
        user_id: UUID,
        draft: AccountDraft,
        expected_draft_hash: str,
        confirmed_at: datetime,
    ) -> AccountWriteResult:
        actual_hash = account_draft_hash(draft)
        if actual_hash != expected_draft_hash:
            raise AccountConfirmationMismatch
        command_hash = confirmed_account_command_hash(
            draft=draft,
            confirmed_at=confirmed_at,
            evaluated_draft_hash=actual_hash,
        )
        payload_hash = bytes.fromhex(command_hash)
        existing = await self._repository.replay_existing(
            user_id=user_id,
            command_id=draft.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            _validate_write_result(
                result=existing,
                user_id=user_id,
                draft=draft,
                confirmed_at=confirmed_at,
            )
            return existing

        issues = _draft_issues(
            draft=draft,
            today_utc=_aware_utc(self._clock()),
        )
        if issues:
            raise AccountRejected(issues)
        result = await self._repository.commit_account(
            user_id=user_id,
            draft=draft,
            payload_hash=payload_hash,
            confirmed_at=confirmed_at,
        )
        _validate_write_result(
            result=result,
            user_id=user_id,
            draft=draft,
            confirmed_at=confirmed_at,
        )
        return result

    async def evaluate_baseline(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
    ) -> EvaluateBaselineResponse:
        snapshot = await self._baseline_snapshot(user_id=user_id, draft=draft)
        issues = _baseline_issues(
            draft=draft,
            snapshot=snapshot,
            now_utc=_aware_utc(self._clock()),
        )
        if issues:
            return EvaluateBaselineResponse(
                decision="REJECT",
                draft=draft,
                draft_hash=None,
                current_opening_balance_on=snapshot.opening_balance_on,
                earliest_operation_on=snapshot.earliest_operation_on,
                issues=issues,
            )
        return EvaluateBaselineResponse(
            decision="NEEDS_CONFIRMATION",
            draft=draft,
            draft_hash=baseline_draft_hash(draft),
            current_opening_balance_on=snapshot.opening_balance_on,
            earliest_operation_on=snapshot.earliest_operation_on,
            issues=(),
        )

    async def commit_baseline(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
        expected_draft_hash: str,
        confirmed_at: datetime,
    ) -> BaselineWriteResult:
        actual_hash = baseline_draft_hash(draft)
        if actual_hash != expected_draft_hash:
            raise AccountConfirmationMismatch
        payload_hash = bytes.fromhex(
            confirmed_baseline_command_hash(
                draft=draft,
                confirmed_at=confirmed_at,
                evaluated_draft_hash=actual_hash,
            )
        )
        existing = await self._repository.replay_existing_baseline(
            user_id=user_id,
            account_id=draft.account_id,
            command_id=draft.command_id,
            payload_hash=payload_hash,
        )
        if existing is not None:
            _validate_baseline_result(
                result=existing,
                user_id=user_id,
                draft=draft,
            )
            return existing

        # Re-read and re-validate: an operation may have been committed between
        # evaluation and confirmation, which can invalidate the correction.
        snapshot = await self._baseline_snapshot(user_id=user_id, draft=draft)
        issues = _baseline_issues(
            draft=draft,
            snapshot=snapshot,
            now_utc=_aware_utc(self._clock()),
        )
        if issues:
            raise BaselineRejected(issues)
        result = await self._repository.correct_opening_baseline(
            user_id=user_id,
            draft=draft,
            payload_hash=payload_hash,
            confirmed_at=confirmed_at,
        )
        _validate_baseline_result(result=result, user_id=user_id, draft=draft)
        return result

    async def _baseline_snapshot(
        self,
        *,
        user_id: UUID,
        draft: CorrectBaselineDraft,
    ) -> BaselineCorrectionSnapshot:
        snapshot = await self._repository.get_baseline_snapshot(
            user_id=user_id,
            account_id=draft.account_id,
        )
        if snapshot is None:
            raise AccountUnavailable
        if snapshot.user_id != user_id or snapshot.account_id != draft.account_id:
            raise AccountPersistenceUnavailable
        return snapshot

    async def list_accounts(self, *, user_id: UUID) -> ListAccountsResponse:
        snapshot = await self._repository.list_accounts(user_id=user_id)
        if any(account.user_id != user_id for account in snapshot.accounts):
            raise AccountPersistenceUnavailable
        return ListAccountsResponse(
            canonical_timezone=snapshot.canonical_timezone,
            timezone_revision=snapshot.timezone_revision,
            accounts=snapshot.accounts,
        )


def _validate_write_result(
    *,
    result: AccountWriteResult,
    user_id: UUID,
    draft: AccountDraft,
    confirmed_at: datetime,
) -> None:
    account = result.account
    if (
        account.user_id != user_id
        or account.command_id != draft.command_id
        or account.name != draft.name
        or account.currency != draft.currency
        or account.opening_balance != draft.opening_balance
        or account.opening_balance_on != draft.opening_balance_on
        or account.opening_timezone != draft.canonical_timezone
        or account.confirmed_at != confirmed_at
        or result.canonical_timezone != account.opening_timezone
        or result.timezone_revision != 1
    ):
        raise AccountPersistenceUnavailable


def _validate_baseline_result(
    *,
    result: BaselineWriteResult,
    user_id: UUID,
    draft: CorrectBaselineDraft,
) -> None:
    account = result.account
    if (
        account.user_id != user_id
        or account.account_id != draft.account_id
        or account.opening_balance_on != draft.opening_balance_on
        or account.opening_balance_on > result.previous_opening_balance_on
    ):
        raise AccountPersistenceUnavailable


def _baseline_issues(
    *,
    draft: CorrectBaselineDraft,
    snapshot: BaselineCorrectionSnapshot,
    now_utc: datetime,
) -> tuple[BaselineIssue, ...]:
    """Apply the ADR 0016 correction bounds in a fixed, deterministic order."""

    issues: list[BaselineIssue] = []
    # Only the earlier direction is permitted: moving a baseline later can
    # strand operations before it, which is the state the invariant prevents.
    if draft.opening_balance_on >= snapshot.opening_balance_on:
        issues.append(
            BaselineIssue(code="BASELINE_NOT_EARLIER", field="openingBalanceOn")
        )
    timezone = ZoneInfo(snapshot.canonical_timezone)
    if draft.opening_balance_on > now_utc.astimezone(timezone).date():
        issues.append(
            BaselineIssue(code="BASELINE_DATE_IN_FUTURE", field="openingBalanceOn")
        )
    # Redundant while corrections only move earlier, but validated explicitly so
    # the rule survives any future relaxation of the direction constraint.
    earliest = snapshot.earliest_operation_on
    if earliest is not None and draft.opening_balance_on > earliest:
        issues.append(
            BaselineIssue(
                code="BASELINE_AFTER_EXISTING_OPERATION",
                field="openingBalanceOn",
            )
        )
    return tuple(issues)


def _draft_issues(
    *,
    draft: AccountDraft,
    today_utc: datetime,
) -> tuple[AccountIssue, ...]:
    issues: list[AccountIssue] = []
    if draft.currency != "EUR":
        issues.append(AccountIssue(code="UNSUPPORTED_CURRENCY", field="currency"))
    timezone = ZoneInfo(draft.canonical_timezone)
    if draft.opening_balance_on > today_utc.astimezone(timezone).date():
        issues.append(
            AccountIssue(
                code="OPENING_BALANCE_DATE_IN_FUTURE",
                field="openingBalanceOn",
            )
        )
    return tuple(issues)


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("clock must return a timezone-aware datetime")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
