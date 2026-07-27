"""Authenticated versioned HTTP boundary for Finance Core operations."""

from __future__ import annotations

from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .finance_core import (
    ConfirmationMismatch,
    FinanceCore,
    FinancePersistenceUnavailable,
    OperationCommandConflict,
    OperationRejected,
)
from .operation_contracts import (
    CommitOperationRequest,
    CommitOperationResponse,
    EvaluateOperationRequest,
    EvaluateOperationResponse,
    OperationErrorCode,
    OperationErrorDetail,
    OperationErrorResponse,
    OperationIssue,
)

router = APIRouter(prefix="/api/v1/operations", tags=["finance-operations"])


def _finance_core(request: Request) -> FinanceCore:
    return cast(FinanceCore, request.app.state.finance_core)


FinanceCoreDependency = Annotated[FinanceCore, Depends(_finance_core)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.post(
    "/evaluate",
    response_model=EvaluateOperationResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        422: {
            "model": OperationErrorResponse,
            "description": "Malformed operation contract",
        },
        503: {
            "model": OperationErrorResponse,
            "description": "Finance Core is unavailable",
        },
    },
)
async def evaluate_operation(
    body: EvaluateOperationRequest,
    core: FinanceCoreDependency,
    user: CurrentUserDependency,
) -> EvaluateOperationResponse:
    try:
        user_id = UUID(user.subject)
    except ValueError:
        raise _unavailable() from None
    try:
        return await core.evaluate(user_id=user_id, draft=body.draft)
    except FinancePersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/commit",
    response_model=CommitOperationResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": CommitOperationResponse,
            "description": "Idempotent replay of an accepted command",
        },
        401: {"description": "Authentication is required"},
        409: {
            "model": OperationErrorResponse,
            "description": "Confirmation or command identity conflict",
        },
        422: {
            "model": OperationErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": OperationErrorResponse,
            "description": "Finance Core persistence is unavailable",
        },
    },
)
async def commit_operation(
    body: CommitOperationRequest,
    response: Response,
    core: FinanceCoreDependency,
    user: CurrentUserDependency,
) -> CommitOperationResponse:
    try:
        user_id = UUID(user.subject)
    except ValueError:
        raise _unavailable() from None

    try:
        result = await core.commit(
            user_id=user_id,
            draft=body.draft,
            expected_draft_hash=body.draft_hash,
            confirmed_at=body.confirmed_at,
        )
    except ConfirmationMismatch:
        public_error = _operation_error(
            status_code=status.HTTP_409_CONFLICT,
            code="CONFIRMATION_MISMATCH",
        )
    except OperationCommandConflict:
        public_error = _operation_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except OperationRejected as rejection:
        public_error = _operation_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="OPERATION_REJECTED",
            issues=rejection.issues,
        )
    except FinancePersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return CommitOperationResponse(
            idempotent_replay=result.idempotent_replay,
            operation=result.operation,
        )
    # Raise outside the active handler so financial input and DB details are not
    # retained as public exception context.
    raise public_error


def _unavailable() -> HTTPException:
    return _operation_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="FINANCE_PERSISTENCE_UNAVAILABLE",
    )


def _operation_error(
    *,
    status_code: int,
    code: OperationErrorCode,
    issues: tuple[OperationIssue, ...] = (),
) -> HTTPException:
    detail = OperationErrorDetail(code=code, issues=issues).model_dump(
        mode="json",
        by_alias=True,
    )
    return HTTPException(status_code=status_code, detail=detail)
