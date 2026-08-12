"""Authenticated read boundary for the profile screen."""

from __future__ import annotations

from typing import Annotated, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from .auth import AuthenticatedUser, current_user
from .profile_contracts import (
    ProfileErrorCode,
    ProfileErrorDetail,
    ProfileErrorResponse,
    ProfileResponse,
)

router = APIRouter(prefix="/api/v1/profile", tags=["profile"])


class ProfileReader(Protocol):
    """Structural type of the adapter this route needs."""

    async def read_profile(self, *, user_id: UUID) -> ProfileResponse:
        """Return the caller's own identity and account facts."""


def _profile_repository(request: Request) -> ProfileReader:
    return cast(ProfileReader, request.app.state.profile_repository)


ProfileRepositoryDependency = Annotated[
    ProfileReader,
    Depends(_profile_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.get(
    "",
    response_model=ProfileResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": ProfileErrorResponse,
            "description": "The profile cannot be read",
        },
    },
)
async def read_profile(
    repository: ProfileRepositoryDependency,
    user: CurrentUserDependency,
) -> ProfileResponse:
    # Always the caller's own profile. There is no identifier to pass, so
    # reading someone else's is unrepresentable rather than merely rejected.
    user_id = _user_id(user)
    try:
        return await repository.read_profile(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so the email and database details are
    # not retained as public exception context.
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _profile_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="PROFILE_UNAVAILABLE",
    )


def _profile_error(*, status_code: int, code: ProfileErrorCode) -> HTTPException:
    detail = ProfileErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
