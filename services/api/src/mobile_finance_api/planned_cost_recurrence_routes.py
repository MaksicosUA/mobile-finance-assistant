"""Authenticated versioned HTTP boundary for recurring planned costs (ADR 0025)."""

from __future__ import annotations

from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .planned_cost_recurrence_contracts import (
    CreatePlannedCostRecurrenceCommand,
    CreatePlannedCostRecurrenceResponse,
    EndPlannedCostRecurrenceCommand,
    EndPlannedCostRecurrenceResponse,
    ListPlannedCostRecurrencesResponse,
    RecurrenceErrorCode,
    RecurrenceErrorDetail,
    RecurrenceErrorResponse,
    RecurrenceIssue,
)
from .planned_cost_recurrence_core import (
    PlannedCostRecurrenceCore,
    RecurrenceCommandConflict,
    RecurrenceNotFound,
    RecurrencePersistenceUnavailable,
    RecurrenceRejected,
)
from .quotas import QuotaExceeded

router = APIRouter(
    prefix="/api/v1/planned-cost-recurrences",
    tags=["planned-costs"],
)


def _recurrence_core(request: Request) -> PlannedCostRecurrenceCore:
    return cast(
        PlannedCostRecurrenceCore,
        request.app.state.planned_cost_recurrence_core,
    )


RecurrenceCoreDependency = Annotated[
    PlannedCostRecurrenceCore,
    Depends(_recurrence_core),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.post(
    "",
    response_model=CreatePlannedCostRecurrenceResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": CreatePlannedCostRecurrenceResponse,
            "description": "Idempotent replay of an accepted command",
        },
        401: {"description": "Authentication is required"},
        409: {
            "model": RecurrenceErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": RecurrenceErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": RecurrenceErrorResponse,
            "description": "Recurrence persistence is unavailable",
        },
    },
)
async def create_recurrence(
    body: CreatePlannedCostRecurrenceCommand,
    response: Response,
    core: RecurrenceCoreDependency,
    user: CurrentUserDependency,
) -> CreatePlannedCostRecurrenceResponse:
    user_id = _user_id(user)
    try:
        result = await core.create(user_id=user_id, command=body)
    except QuotaExceeded:
        raise
    except RecurrenceCommandConflict:
        public_error = _recurrence_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except RecurrenceRejected as rejection:
        public_error = _recurrence_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="RECURRENCE_REJECTED",
            issues=rejection.issues,
        )
    except RecurrencePersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return result
    # Raised outside the active handler so financial intent and database
    # details are not retained as public exception context.
    raise public_error


@router.post(
    "/{recurrence_id}/end",
    response_model=EndPlannedCostRecurrenceResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {
            "model": RecurrenceErrorResponse,
            "description": "No such rule for this user",
        },
        409: {
            "model": RecurrenceErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": RecurrenceErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": RecurrenceErrorResponse,
            "description": "Recurrence persistence is unavailable",
        },
    },
)
async def end_recurrence(
    recurrence_id: UUID,
    body: EndPlannedCostRecurrenceCommand,
    core: RecurrenceCoreDependency,
    user: CurrentUserDependency,
) -> EndPlannedCostRecurrenceResponse:
    user_id = _user_id(user)
    try:
        return await core.end(
            user_id=user_id,
            recurrence_id=recurrence_id,
            command=body,
        )
    except RecurrenceNotFound:
        public_error = _recurrence_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="RECURRENCE_NOT_FOUND",
        )
    except RecurrenceCommandConflict:
        public_error = _recurrence_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except RecurrenceRejected as rejection:
        public_error = _recurrence_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="RECURRENCE_REJECTED",
            issues=rejection.issues,
        )
    except RecurrencePersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.get(
    "",
    response_model=ListPlannedCostRecurrencesResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": RecurrenceErrorResponse,
            "description": "Recurrence persistence is unavailable",
        },
    },
)
async def list_recurrences(
    core: RecurrenceCoreDependency,
    user: CurrentUserDependency,
) -> ListPlannedCostRecurrencesResponse:
    user_id = _user_id(user)
    try:
        return await core.list_recurrences(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _recurrence_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="RECURRENCE_PERSISTENCE_UNAVAILABLE",
    )


def _recurrence_error(
    *,
    status_code: int,
    code: RecurrenceErrorCode,
    issues: tuple[RecurrenceIssue, ...] = (),
) -> HTTPException:
    detail = RecurrenceErrorDetail(code=code, issues=issues).model_dump(
        mode="json",
        by_alias=True,
    )
    return HTTPException(status_code=status_code, detail=detail)
