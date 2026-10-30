"""Authenticated HTTP boundary for authoritative Finance accounts."""

from __future__ import annotations

from collections.abc import Callable, Coroutine
from typing import Annotated, Any, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from starlette.responses import JSONResponse

from .account_contracts import (
    AccountErrorCode,
    AccountErrorDetail,
    AccountErrorResponse,
    AccountIssue,
    BaselineIssue,
    CommitAccountRequest,
    CommitAccountResponse,
    CommitBaselineRequest,
    CommitBaselineResponse,
    CorrectTimezoneCommand,
    CorrectTimezoneResponse,
    EvaluateAccountRequest,
    EvaluateAccountResponse,
    EvaluateBaselineRequest,
    EvaluateBaselineResponse,
    ListAccountsResponse,
    TimezoneIssue,
)
from .account_core import (
    AccountAlreadyInitialized,
    AccountCommandConflict,
    AccountConfirmationMismatch,
    AccountCore,
    AccountPersistenceUnavailable,
    AccountRejected,
    AccountUnavailable,
    BaselineRejected,
    TimezoneRejected,
)
from .auth import AuthenticatedUser, current_user
from .quotas import QuotaExceeded

_NO_STORE_HEADERS = {"Cache-Control": "no-store", "Pragma": "no-cache"}


class RedactedAccountRoute(APIRoute):
    """Redact sensitive account drafts before global error handling."""

    def get_route_handler(
        self,
    ) -> Callable[[Request], Coroutine[Any, Any, Response]]:
        original = super().get_route_handler()

        async def redacted_handler(request: Request) -> Response:
            try:
                response = await original(request)
            except RequestValidationError:
                return JSONResponse(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    content={"detail": {"code": "MALFORMED_ACCOUNT", "issues": []}},
                    headers=_NO_STORE_HEADERS,
                )
            except HTTPException as error:
                headers = {**(error.headers or {}), **_NO_STORE_HEADERS}
                raise HTTPException(
                    status_code=error.status_code,
                    detail=error.detail,
                    headers=headers,
                ) from None
            response.headers.update(_NO_STORE_HEADERS)
            return response

        return redacted_handler


router = APIRouter(
    prefix="/api/v1/accounts",
    tags=["finance-accounts"],
    route_class=RedactedAccountRoute,
)


def _account_core(request: Request) -> AccountCore:
    return cast(AccountCore, request.app.state.account_core)


AccountCoreDependency = Annotated[AccountCore, Depends(_account_core)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.post(
    "/evaluate",
    response_model=EvaluateAccountResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        422: {
            "model": AccountErrorResponse,
            "description": "Malformed account draft",
        },
        503: {
            "model": AccountErrorResponse,
            "description": "Finance account persistence is unavailable",
        },
    },
)
async def evaluate_account(
    body: EvaluateAccountRequest,
    core: AccountCoreDependency,
    user: CurrentUserDependency,
) -> EvaluateAccountResponse:
    user_id = _authenticated_user_id(user)
    try:
        return await core.evaluate(user_id=user_id, draft=body.draft)
    except AccountPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/commit",
    response_model=CommitAccountResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": CommitAccountResponse,
            "description": "Idempotent replay of an accepted account command",
        },
        401: {"description": "Authentication is required"},
        409: {
            "model": AccountErrorResponse,
            "description": "Confirmation, command, or setup-state conflict",
        },
        422: {
            "model": AccountErrorResponse,
            "description": "Malformed or deterministically rejected account command",
        },
        503: {
            "model": AccountErrorResponse,
            "description": "Finance account persistence is unavailable",
        },
    },
)
async def commit_account(
    body: CommitAccountRequest,
    response: Response,
    core: AccountCoreDependency,
    user: CurrentUserDependency,
) -> CommitAccountResponse:
    user_id = _authenticated_user_id(user)
    try:
        result = await core.commit(
            user_id=user_id,
            draft=body.draft,
            expected_draft_hash=body.draft_hash,
            confirmed_at=body.confirmed_at,
        )
    except QuotaExceeded:
        raise
    except AccountConfirmationMismatch:
        public_error = _account_error(
            status_code=status.HTTP_409_CONFLICT,
            code="CONFIRMATION_MISMATCH",
        )
    except AccountCommandConflict:
        public_error = _account_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except AccountAlreadyInitialized:
        public_error = _account_error(
            status_code=status.HTTP_409_CONFLICT,
            code="ACCOUNT_ALREADY_INITIALIZED",
        )
    except AccountRejected as rejection:
        public_error = _account_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="ACCOUNT_REJECTED",
            issues=rejection.issues,
        )
    except AccountPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return CommitAccountResponse(
            idempotent_replay=result.idempotent_replay,
            canonical_timezone=result.canonical_timezone,
            timezone_revision=1,
            account=result.account,
        )
    raise public_error


@router.get(
    "",
    response_model=ListAccountsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": AccountErrorResponse,
            "description": "Finance account persistence is unavailable",
        },
    },
)
async def list_accounts(
    core: AccountCoreDependency,
    user: CurrentUserDependency,
) -> ListAccountsResponse:
    user_id = _authenticated_user_id(user)
    try:
        return await core.list_accounts(user_id=user_id)
    except AccountPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/timezone",
    response_model=CorrectTimezoneResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        409: {
            "model": AccountErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": AccountErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": AccountErrorResponse,
            "description": "Account persistence is unavailable",
        },
    },
)
async def correct_timezone(
    body: CorrectTimezoneCommand,
    core: AccountCoreDependency,
    user: CurrentUserDependency,
) -> CorrectTimezoneResponse:
    """Move where this account's months are drawn (ADR 0028).

    One phase: no balance moves, because an operation keeps the local date it
    was captured with.
    """

    try:
        return await core.correct_timezone(
            user_id=_authenticated_user_id(user), command=body
        )
    except AccountCommandConflict:
        public_error = _account_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except TimezoneRejected as rejection:
        public_error = _account_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="TIMEZONE_REJECTED",
            timezone_issues=rejection.issues,
        )
    except AccountPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/baseline/evaluate",
    response_model=EvaluateBaselineResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {
            "model": AccountErrorResponse,
            "description": "The account is not an owned active account",
        },
        422: {
            "model": AccountErrorResponse,
            "description": "Malformed baseline draft",
        },
        503: {
            "model": AccountErrorResponse,
            "description": "Finance account persistence is unavailable",
        },
    },
)
async def evaluate_baseline(
    body: EvaluateBaselineRequest,
    core: AccountCoreDependency,
    user: CurrentUserDependency,
) -> EvaluateBaselineResponse:
    user_id = _authenticated_user_id(user)
    try:
        return await core.evaluate_baseline(user_id=user_id, draft=body.draft)
    except AccountUnavailable:
        public_error = _account_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="ACCOUNT_UNAVAILABLE",
        )
    except AccountPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/baseline/commit",
    response_model=CommitBaselineResponse,
    response_model_by_alias=True,
    responses={
        200: {
            "model": CommitBaselineResponse,
            "description": "Accepted or idempotently replayed baseline correction",
        },
        401: {"description": "Authentication is required"},
        404: {
            "model": AccountErrorResponse,
            "description": "The account is not an owned active account",
        },
        409: {
            "model": AccountErrorResponse,
            "description": "Confirmation or command identity conflict",
        },
        422: {
            "model": AccountErrorResponse,
            "description": "Malformed or deterministically rejected correction",
        },
        503: {
            "model": AccountErrorResponse,
            "description": "Finance account persistence is unavailable",
        },
    },
)
async def commit_baseline(
    body: CommitBaselineRequest,
    core: AccountCoreDependency,
    user: CurrentUserDependency,
) -> CommitBaselineResponse:
    user_id = _authenticated_user_id(user)
    try:
        result = await core.commit_baseline(
            user_id=user_id,
            draft=body.draft,
            expected_draft_hash=body.draft_hash,
            confirmed_at=body.confirmed_at,
        )
    except AccountConfirmationMismatch:
        public_error = _account_error(
            status_code=status.HTTP_409_CONFLICT,
            code="CONFIRMATION_MISMATCH",
        )
    except AccountCommandConflict:
        public_error = _account_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except AccountUnavailable:
        public_error = _account_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="ACCOUNT_UNAVAILABLE",
        )
    except BaselineRejected as rejection:
        public_error = _account_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="BASELINE_REJECTED",
            baseline_issues=rejection.issues,
        )
    except AccountPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        # A correction is never a creation, so it always answers 200.
        return CommitBaselineResponse(
            idempotent_replay=result.idempotent_replay,
            previous_opening_balance_on=result.previous_opening_balance_on,
            account=result.account,
        )
    raise public_error


def _authenticated_user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _account_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="FINANCE_PERSISTENCE_UNAVAILABLE",
    )


def _account_error(
    *,
    status_code: int,
    code: AccountErrorCode,
    issues: tuple[AccountIssue, ...] = (),
    baseline_issues: tuple[BaselineIssue, ...] = (),
    timezone_issues: tuple[TimezoneIssue, ...] = (),
) -> HTTPException:
    detail = AccountErrorDetail(
        code=code,
        issues=issues,
        baseline_issues=baseline_issues,
        timezone_issues=timezone_issues,
    ).model_dump(mode="json", by_alias=True)
    # Keep the wire shape of every pre-existing error byte-identical: installed
    # clients parse this strictly, so each field appears only when it is used.
    if not baseline_issues:
        detail.pop("baselineIssues", None)
    if not timezone_issues:
        detail.pop("timezoneIssues", None)
    return HTTPException(
        status_code=status_code,
        detail=detail,
        headers=_NO_STORE_HEADERS,
    )
