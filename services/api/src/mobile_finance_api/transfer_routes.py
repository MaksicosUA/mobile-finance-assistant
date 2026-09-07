"""Authenticated versioned HTTP boundary for transfers between wallets."""

from __future__ import annotations

from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .transfer_contracts import (
    CommitTransferRequest,
    CommitTransferResponse,
    EvaluateTransferRequest,
    EvaluateTransferResponse,
    TransferErrorCode,
    TransferErrorDetail,
    TransferErrorResponse,
    TransferIssue,
)
from .transfer_core import (
    TransferCommandConflict,
    TransferConfirmationMismatch,
    TransferCore,
    TransferPersistenceUnavailable,
    TransferRejected,
)

router = APIRouter(prefix="/api/v1/transfers", tags=["transfers"])

_NO_STORE_HEADERS = {"Cache-Control": "no-store", "Pragma": "no-cache"}


def _transfer_core(request: Request) -> TransferCore:
    return cast(TransferCore, request.app.state.transfer_core)


TransferCoreDependency = Annotated[TransferCore, Depends(_transfer_core)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.post(
    "/evaluate",
    response_model=EvaluateTransferResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        422: {"model": TransferErrorResponse, "description": "Malformed command"},
        503: {
            "model": TransferErrorResponse,
            "description": "Transfer persistence is unavailable",
        },
    },
)
async def evaluate_transfer(
    body: EvaluateTransferRequest,
    core: TransferCoreDependency,
    user: CurrentUserDependency,
) -> EvaluateTransferResponse:
    """Decide a transfer without moving anything."""

    try:
        return await core.evaluate(user_id=_user_id(user), draft=body.draft)
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/commit",
    response_model=CommitTransferResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": CommitTransferResponse,
            "description": "The same command had already settled",
        },
        401: {"description": "Authentication is required"},
        409: {"model": TransferErrorResponse, "description": "Command conflict"},
        422: {
            "model": TransferErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": TransferErrorResponse,
            "description": "Transfer persistence is unavailable",
        },
    },
)
async def commit_transfer(
    body: CommitTransferRequest,
    core: TransferCoreDependency,
    user: CurrentUserDependency,
    response: Response,
) -> CommitTransferResponse:
    """Move the money, exactly once for one command identity."""

    try:
        result = await core.commit(
            user_id=_user_id(user),
            draft=body.draft,
            expected_draft_hash=body.draft_hash,
            confirmed_at=body.confirmed_at,
        )
        # A replay settled nothing new, so it is not a creation.
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return CommitTransferResponse(
            idempotent_replay=result.idempotent_replay,
            transfer=result.transfer,
        )
    except TransferConfirmationMismatch:
        public_error = _error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="CONFIRMATION_MISMATCH",
        )
    except TransferCommandConflict:
        public_error = _error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except TransferRejected as rejection:
        public_error = _error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="TRANSFER_REJECTED",
            issues=rejection.issues,
        )
    except TransferPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError as error:
        raise TransferPersistenceUnavailable from error


def _unavailable() -> HTTPException:
    return _error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="TRANSFER_PERSISTENCE_UNAVAILABLE",
    )


def _error(
    *,
    status_code: int,
    code: TransferErrorCode,
    issues: tuple[TransferIssue, ...] = (),
) -> HTTPException:
    detail = TransferErrorDetail(code=code, issues=issues).model_dump(
        mode="json", by_alias=True
    )
    return HTTPException(
        status_code=status_code,
        detail=detail,
        headers=_NO_STORE_HEADERS,
    )
