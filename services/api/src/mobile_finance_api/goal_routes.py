"""Authenticated versioned HTTP boundary for savings goals (ADR 0019)."""

from __future__ import annotations

from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .goal_contracts import (
    CancelGoalCommand,
    CancelGoalResponse,
    CreateGoalCommand,
    CreateGoalResponse,
    GoalErrorCode,
    GoalErrorDetail,
    GoalErrorResponse,
    GoalIssue,
    ListGoalContributionsResponse,
    ListGoalsResponse,
    RecordGoalContributionCommand,
    RecordGoalContributionResponse,
)
from .goal_core import (
    GoalCommandConflict,
    GoalCore,
    GoalNotFound,
    GoalPersistenceUnavailable,
    GoalRejected,
)
from .quotas import QuotaExceeded

router = APIRouter(prefix="/api/v1/goals", tags=["goals"])


def _goal_core(request: Request) -> GoalCore:
    return cast(GoalCore, request.app.state.goal_core)


GoalCoreDependency = Annotated[GoalCore, Depends(_goal_core)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]

_WRITE_RESPONSES: dict[int | str, dict[str, object]] = {
    401: {"description": "Authentication is required"},
    404: {"model": GoalErrorResponse, "description": "No such goal for this user"},
    409: {"model": GoalErrorResponse, "description": "Command identity conflict"},
    422: {
        "model": GoalErrorResponse,
        "description": "Malformed or deterministically rejected command",
    },
    503: {
        "model": GoalErrorResponse,
        "description": "Goal persistence is unavailable",
    },
}


@router.post(
    "",
    response_model=CreateGoalResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": CreateGoalResponse,
            "description": "Idempotent replay of an accepted command",
        },
        401: {"description": "Authentication is required"},
        409: {"model": GoalErrorResponse, "description": "Command identity conflict"},
        422: {
            "model": GoalErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": GoalErrorResponse,
            "description": "Goal persistence is unavailable",
        },
    },
)
async def create_goal(
    body: CreateGoalCommand,
    response: Response,
    core: GoalCoreDependency,
    user: CurrentUserDependency,
) -> CreateGoalResponse:
    user_id = _user_id(user)
    try:
        result = await core.create(user_id=user_id, command=body)
    except QuotaExceeded:
        raise
    except GoalCommandConflict:
        public_error = _goal_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except GoalRejected as rejection:
        public_error = _goal_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="GOAL_REJECTED",
            issues=rejection.issues,
        )
    except GoalPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return result
    # Raised outside the active handler so financial intent and database details
    # are not retained as public exception context.
    raise public_error


@router.post(
    "/{goal_id}/cancel",
    response_model=CancelGoalResponse,
    response_model_by_alias=True,
    responses=_WRITE_RESPONSES,
)
async def cancel_goal(
    goal_id: UUID,
    body: CancelGoalCommand,
    core: GoalCoreDependency,
    user: CurrentUserDependency,
) -> CancelGoalResponse:
    user_id = _user_id(user)
    try:
        return await core.cancel(user_id=user_id, goal_id=goal_id, command=body)
    except GoalNotFound:
        public_error = _goal_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="GOAL_NOT_FOUND",
        )
    except GoalCommandConflict:
        public_error = _goal_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except GoalRejected as rejection:
        public_error = _goal_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="GOAL_REJECTED",
            issues=rejection.issues,
        )
    except GoalPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "/{goal_id}/contributions",
    response_model=RecordGoalContributionResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
    responses={
        200: {
            "model": RecordGoalContributionResponse,
            "description": "Idempotent replay of an accepted command",
        },
        **_WRITE_RESPONSES,
    },
)
async def record_goal_contribution(
    goal_id: UUID,
    body: RecordGoalContributionCommand,
    response: Response,
    core: GoalCoreDependency,
    user: CurrentUserDependency,
) -> RecordGoalContributionResponse:
    user_id = _user_id(user)
    try:
        result = await core.record_contribution(
            user_id=user_id,
            goal_id=goal_id,
            command=body,
        )
    except GoalNotFound:
        public_error = _goal_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="GOAL_NOT_FOUND",
        )
    except GoalCommandConflict:
        public_error = _goal_error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except GoalRejected as rejection:
        public_error = _goal_error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="GOAL_REJECTED",
            issues=rejection.issues,
        )
    except GoalPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if result.idempotent_replay:
            response.status_code = status.HTTP_200_OK
        return result
    raise public_error


@router.get(
    "",
    response_model=ListGoalsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": GoalErrorResponse,
            "description": "Goal persistence is unavailable",
        },
    },
)
async def list_goals(
    core: GoalCoreDependency,
    user: CurrentUserDependency,
) -> ListGoalsResponse:
    user_id = _user_id(user)
    try:
        return await core.list_goals(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.get(
    "/{goal_id}/contributions",
    response_model=ListGoalContributionsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {"model": GoalErrorResponse, "description": "No such goal for this user"},
        503: {
            "model": GoalErrorResponse,
            "description": "Goal persistence is unavailable",
        },
    },
)
async def list_goal_contributions(
    goal_id: UUID,
    core: GoalCoreDependency,
    user: CurrentUserDependency,
) -> ListGoalContributionsResponse:
    user_id = _user_id(user)
    try:
        return await core.list_contributions(user_id=user_id, goal_id=goal_id)
    except GoalNotFound:
        public_error = _goal_error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="GOAL_NOT_FOUND",
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
    return _goal_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="GOAL_PERSISTENCE_UNAVAILABLE",
    )


def _goal_error(
    *,
    status_code: int,
    code: GoalErrorCode,
    issues: tuple[GoalIssue, ...] = (),
) -> HTTPException:
    detail = GoalErrorDetail(code=code, issues=issues).model_dump(
        mode="json",
        by_alias=True,
    )
    return HTTPException(status_code=status_code, detail=detail)
