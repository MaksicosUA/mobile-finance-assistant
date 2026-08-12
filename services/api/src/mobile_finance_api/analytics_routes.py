"""Authenticated read boundary for category analytics.

Deliberately outside Finance Core: this decides nothing and changes nothing.
The period is the account's own canonical month, so the client asks no
question it could get wrong (ADR 0010).
"""

from __future__ import annotations

from typing import Annotated, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from .analytics_contracts import (
    AnalyticsErrorCode,
    AnalyticsErrorDetail,
    AnalyticsErrorResponse,
    AnalyticsResponse,
)
from .auth import AuthenticatedUser, current_user

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


class AnalyticsReader(Protocol):
    """Structural type of the adapter this route needs."""

    async def analyse_current_month(self, *, user_id: UUID) -> AnalyticsResponse:
        """Group the caller's current local month."""


def _analytics_repository(request: Request) -> AnalyticsReader:
    return cast(AnalyticsReader, request.app.state.analytics_repository)


AnalyticsRepositoryDependency = Annotated[
    AnalyticsReader,
    Depends(_analytics_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.get(
    "",
    response_model=AnalyticsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": AnalyticsErrorResponse,
            "description": "Analytics cannot be computed",
        },
    },
)
async def read_analytics(
    repository: AnalyticsRepositoryDependency,
    user: CurrentUserDependency,
) -> AnalyticsResponse:
    user_id = _user_id(user)
    try:
        return await repository.analyse_current_month(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so amounts, category names, and
    # database details are not retained as public exception context.
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _analytics_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="ANALYTICS_UNAVAILABLE",
    )


def _analytics_error(*, status_code: int, code: AnalyticsErrorCode) -> HTTPException:
    detail = AnalyticsErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
