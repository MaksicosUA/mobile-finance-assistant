"""Authenticated versioned HTTP boundary for Finance Core operations."""

from __future__ import annotations

from typing import Annotated, Protocol, cast
from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Request,
    Response,
    status,
)

from .auth import AuthenticatedUser, current_user
from .finance_core import (
    ConfirmationMismatch,
    FinanceCore,
    FinancePersistenceUnavailable,
    OperationAlreadyReversed,
    OperationCommandConflict,
    OperationNotFound,
    OperationRejected,
)
from .operation_contracts import (
    CommitOperationRequest,
    CommitOperationResponse,
    CorrectOperationRequest,
    CorrectOperationResponse,
    EvaluateOperationRequest,
    EvaluateOperationResponse,
    ListOperationsResponse,
    OperationErrorCode,
    OperationErrorDetail,
    OperationErrorResponse,
    OperationIssue,
    RemoveOperationRequest,
    RemoveOperationResponse,
)
from .postgres_finance_repository import (
    MAXIMUM_HISTORY_PAGE,
    InvalidOperationCursor,
)


class FinanceOperationReader(Protocol):
    """Structural type of the read adapter the history route needs."""

    async def list_operations(
        self,
        *,
        user_id: UUID,
        limit: int,
        cursor: str | None,
    ) -> ListOperationsResponse:
        """Return one page of the user's confirmed operations."""


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


_REVERSAL_RESPONSES: dict[int | str, dict[str, object]] = {
    200: {"description": "Idempotent replay of an accepted command"},
    401: {"description": "Authentication is required"},
    404: {
        "model": OperationErrorResponse,
        "description": "No such operation for this user",
    },
    409: {
        "model": OperationErrorResponse,
        "description": "Confirmation, command, or reversal conflict",
    },
    422: {
        "model": OperationErrorResponse,
        "description": "Malformed or deterministically rejected command",
    },
    503: {
        "model": OperationErrorResponse,
        "description": "Finance Core persistence is unavailable",
    },
}


@router.post(
    "/correction",
    response_model=CorrectOperationResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses=_REVERSAL_RESPONSES,
)
async def correct_operation(
    body: CorrectOperationRequest,
    response: Response,
    core: FinanceCoreDependency,
    user: CurrentUserDependency,
) -> CorrectOperationResponse:
    """Replace a confirmed operation with a reviewed draft (ADR 0023).

    The original is withdrawn and its replacement written in one transaction,
    so there is no moment where the money is gone and nothing replaced it.
    """

    try:
        user_id = UUID(user.subject)
    except ValueError:
        raise _unavailable() from None

    try:
        result = await core.correct(user_id=user_id, request=body)
    except Exception as error:
        public_error = _reversal_error(error)
    else:
        if result.replacement is None:
            # Unreachable through Finance Core; a correction always writes one.
            raise _unavailable()
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return CorrectOperationResponse(
            idempotent_replay=result.idempotent_replay,
            reversal=result.reversal,
            operation=result.replacement,
        )
    raise public_error


@router.post(
    "/removal",
    response_model=RemoveOperationResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses=_REVERSAL_RESPONSES,
)
async def remove_operation(
    body: RemoveOperationRequest,
    response: Response,
    core: FinanceCoreDependency,
    user: CurrentUserDependency,
) -> RemoveOperationResponse:
    """Withdraw a confirmed operation without replacing it (ADR 0023)."""

    try:
        user_id = UUID(user.subject)
    except ValueError:
        raise _unavailable() from None

    try:
        result = await core.remove(user_id=user_id, request=body)
    except Exception as error:
        public_error = _reversal_error(error)
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return RemoveOperationResponse(
            idempotent_replay=result.idempotent_replay,
            reversal=result.reversal,
        )
    raise public_error


@router.get(
    "",
    response_model=ListOperationsResponse,
    response_model_by_alias=True,
    responses={
        400: {
            "model": OperationErrorResponse,
            "description": "The paging cursor is malformed",
        },
        401: {"description": "Authentication is required"},
        503: {
            "model": OperationErrorResponse,
            "description": "Finance Core persistence is unavailable",
        },
    },
)
async def list_operations(
    request: Request,
    user: CurrentUserDependency,
    limit: Annotated[int, Query(ge=1, le=MAXIMUM_HISTORY_PAGE)] = 30,
    cursor: Annotated[str | None, Query(max_length=256)] = None,
) -> ListOperationsResponse:
    """Read the caller's own confirmed operations, newest first.

    Deliberately not routed through Finance Core: this changes nothing, and
    the core is the authority for decisions, not for reads.
    """

    try:
        user_id = UUID(user.subject)
    except ValueError:
        raise _unavailable() from None

    repository = cast(
        FinanceOperationReader,
        request.app.state.finance_operation_repository,
    )
    try:
        return await repository.list_operations(
            user_id=user_id,
            limit=limit,
            cursor=cursor,
        )
    except InvalidOperationCursor:
        public_error = _operation_error(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="MALFORMED_OPERATION",
        )
    except Exception:
        public_error = _unavailable()
    raise public_error


def _reversal_error(error: Exception) -> HTTPException:
    """Map a correction failure to its public status, losing every detail.

    A missing operation and another user's operation answer the same 404, so
    the API never confirms that an identifier exists outside the caller's own
    ledger.
    """

    match error:
        case ConfirmationMismatch():
            return _operation_error(
                status_code=status.HTTP_409_CONFLICT,
                code="CONFIRMATION_MISMATCH",
            )
        case OperationCommandConflict():
            return _operation_error(
                status_code=status.HTTP_409_CONFLICT,
                code="COMMAND_CONFLICT",
            )
        case OperationAlreadyReversed():
            return _operation_error(
                status_code=status.HTTP_409_CONFLICT,
                code="OPERATION_ALREADY_REVERSED",
            )
        case OperationNotFound():
            return _operation_error(
                status_code=status.HTTP_404_NOT_FOUND,
                code="OPERATION_NOT_FOUND",
            )
        case OperationRejected(issues=issues):
            return _operation_error(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="OPERATION_REJECTED",
                issues=issues,
            )
        case _:
            return _unavailable()


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
