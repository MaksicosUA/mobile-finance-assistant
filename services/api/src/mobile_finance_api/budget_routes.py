"""Authenticated versioned HTTP boundary for monthly budgets (ADR 0027)."""

from __future__ import annotations

from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .budget_contracts import (
    BudgetErrorCode,
    BudgetErrorDetail,
    BudgetErrorResponse,
    BudgetIssue,
    BudgetsResponse,
    RemoveBudgetCommand,
    RemoveBudgetResponse,
    SetBudgetCommand,
    SetBudgetResponse,
)
from .budget_core import (
    BudgetCommandConflict,
    BudgetCore,
    BudgetNotFound,
    BudgetPersistenceUnavailable,
    BudgetRejected,
)

router = APIRouter(prefix="/api/v1/budgets", tags=["budgets"])


def _budget_core(request: Request) -> BudgetCore:
    return cast(BudgetCore, request.app.state.budget_core)


BudgetCoreDependency = Annotated[BudgetCore, Depends(_budget_core)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.get(
    "",
    response_model=BudgetsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": BudgetErrorResponse,
            "description": "Budget persistence is unavailable",
        },
    },
)
async def read_budgets(
    response: Response,
    core: BudgetCoreDependency,
    user: CurrentUserDependency,
) -> BudgetsResponse:
    try:
        result = await core.read_budgets(user_id=_user_id(user))
    except Exception:
        raise _unavailable() from None
    # Derived from operations that can change at any moment, so never cached.
    response.headers["cache-control"] = "no-store"
    return result


@router.put(
    "",
    response_model=SetBudgetResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        409: {
            "model": BudgetErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": BudgetErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": BudgetErrorResponse,
            "description": "Budget persistence is unavailable",
        },
    },
)
async def set_budget(
    body: SetBudgetCommand,
    core: BudgetCoreDependency,
    user: CurrentUserDependency,
) -> SetBudgetResponse:
    # PUT, not POST: declaring a ceiling for a category is idempotent by its
    # target state — saying 400 twice leaves one ceiling of 400.
    try:
        return await core.set_budget(user_id=_user_id(user), command=body)
    except BudgetCommandConflict:
        public_error = _error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except BudgetRejected as rejection:
        public_error = _error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="BUDGET_REJECTED",
            issues=rejection.issues,
        )
    except BudgetPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so financial intent and database
    # details are not retained as public exception context.
    raise public_error


@router.post(
    "/{budget_id}/remove",
    response_model=RemoveBudgetResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {
            "model": BudgetErrorResponse,
            "description": "No such budget for this user",
        },
        409: {
            "model": BudgetErrorResponse,
            "description": "Command identity conflict",
        },
        422: {
            "model": BudgetErrorResponse,
            "description": "Malformed or deterministically rejected command",
        },
        503: {
            "model": BudgetErrorResponse,
            "description": "Budget persistence is unavailable",
        },
    },
)
async def remove_budget(
    budget_id: UUID,
    body: RemoveBudgetCommand,
    core: BudgetCoreDependency,
    user: CurrentUserDependency,
) -> RemoveBudgetResponse:
    try:
        return await core.remove_budget(
            user_id=_user_id(user),
            budget_id=budget_id,
            command=body,
        )
    except BudgetNotFound:
        public_error = _error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="BUDGET_NOT_FOUND",
        )
    except BudgetCommandConflict:
        public_error = _error(
            status_code=status.HTTP_409_CONFLICT,
            code="COMMAND_CONFLICT",
        )
    except BudgetRejected as rejection:
        public_error = _error(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="BUDGET_REJECTED",
            issues=rejection.issues,
        )
    except BudgetPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="BUDGET_PERSISTENCE_UNAVAILABLE",
    )


def _error(
    *,
    status_code: int,
    code: BudgetErrorCode,
    issues: tuple[BudgetIssue, ...] = (),
) -> HTTPException:
    detail = BudgetErrorDetail(code=code, issues=issues).model_dump(
        mode="json",
        by_alias=True,
    )
    return HTTPException(status_code=status_code, detail=detail)
