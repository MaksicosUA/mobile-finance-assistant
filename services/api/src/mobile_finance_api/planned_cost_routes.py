"""Authenticated versioned HTTP boundary for planned costs (ADR 0018)."""

from __future__ import annotations

from datetime import date
from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .planned_cost_contracts import (
    CreatePlannedCostCommand,
    CreatePlannedCostResponse,
    ListPlannedCostsResponse,
    PlannedCostErrorCode,
    PlannedCostErrorDetail,
    PlannedCostErrorResponse,
    PlannedCostIssue,
    TransitionPlannedCostCommand,
    TransitionPlannedCostResponse,
)
from .planned_cost_core import (
    PlannedCostCommandConflict,
    PlannedCostCore,
    PlannedCostNotFound,
    PlannedCostPersistenceUnavailable,
    PlannedCostRejected,
)

router = APIRouter(prefix="/api/v1/planned-costs", tags=["planned-costs"])


def _planned_cost_core(request: Request) -> PlannedCostCore:
    return cast(PlannedCostCore, request.app.state.planned_cost_core)


PlannedCostCoreDependency = Annotated[PlannedCostCore, Depends(_planned_cost_core)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]
PlannedFromQuery = Annotated[date | None, Query(alias="from")]
PlannedToQuery = Annotated[date | None, Query(alias="to")]


@router.post(
    "",
    response_model=CreatePlannedCostResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": CreatePlannedCostResponse,
            "description": "Idempotent replay of an accepted command",
        },
        401: {"description": "Authentication is required"},
        409: {
            "model": PlannedCostErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": PlannedCostErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": PlannedCostErrorResponse,
            "description": "Planned cost persistence is unavailable",
        },
    },
)
async def create_planned_cost(
    body: CreatePlannedCostCommand,
    response: Response,
    core: PlannedCostCoreDependency,
    user: CurrentUserDependency,
) -> CreatePlannedCostResponse:
    user_id = _user_id(user)
    try:
        result = await core.create(user_id=user_id, command=body)
    except PlannedCostCommandConflict:
        public_error = _planned_cost_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except PlannedCostRejected as rejection:
        public_error = _planned_cost_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="PLANNED_COST_REJECTED",
            issues=rejection.issues,
        )
    except PlannedCostPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return result
    # Raise outside the active handler so financial intent and database details
    # are not retained as public exception context.
    raise public_error


@router.post(
    "/{planned_cost_id}/transition",
    response_model=TransitionPlannedCostResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {
            "model": PlannedCostErrorResponse,
            "description": "No such planned cost for this user",
        },
        409: {
            "model": PlannedCostErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": PlannedCostErrorResponse,
            "description": "Malformed or deterministically rejected transition",
        },
        503: {
            "model": PlannedCostErrorResponse,
            "description": "Planned cost persistence is unavailable",
        },
    },
)
async def transition_planned_cost(
    planned_cost_id: UUID,
    body: TransitionPlannedCostCommand,
    core: PlannedCostCoreDependency,
    user: CurrentUserDependency,
) -> TransitionPlannedCostResponse:
    user_id = _user_id(user)
    try:
        return await core.transition(
            user_id=user_id,
            planned_cost_id=planned_cost_id,
            command=body,
        )
    except PlannedCostNotFound:
        public_error = _planned_cost_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="PLANNED_COST_NOT_FOUND",
        )
    except PlannedCostCommandConflict:
        public_error = _planned_cost_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except PlannedCostRejected as rejection:
        public_error = _planned_cost_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="PLANNED_COST_REJECTED",
            issues=rejection.issues,
        )
    except PlannedCostPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.get(
    "",
    response_model=ListPlannedCostsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        422: {
            "model": PlannedCostErrorResponse,
            "description": "Malformed query",
        },
        503: {
            "model": PlannedCostErrorResponse,
            "description": "Planned cost persistence is unavailable",
        },
    },
)
async def list_planned_costs(
    core: PlannedCostCoreDependency,
    user: CurrentUserDependency,
    planned_from: PlannedFromQuery = None,
    planned_to: PlannedToQuery = None,
) -> ListPlannedCostsResponse:
    user_id = _user_id(user)
    try:
        return await core.list_plans(
            user_id=user_id,
            planned_from=planned_from,
            planned_to=planned_to,
        )
    except Exception:
        public_error = _unavailable()
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _planned_cost_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="PLANNED_COST_PERSISTENCE_UNAVAILABLE",
    )


def _planned_cost_error(
    *,
    status_code: int,
    code: PlannedCostErrorCode,
    issues: tuple[PlannedCostIssue, ...] = (),
) -> HTTPException:
    detail = PlannedCostErrorDetail(code=code, issues=issues).model_dump(
        mode="json",
        by_alias=True,
    )
    return HTTPException(status_code=status_code, detail=detail)
