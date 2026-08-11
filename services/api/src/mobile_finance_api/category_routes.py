"""Authenticated read boundary for the category catalogue (ADR 0020)."""

from __future__ import annotations

from typing import Annotated, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status

from .auth import AuthenticatedUser, current_user
from .category_contracts import (
    CategoryErrorCode,
    CategoryErrorDetail,
    CategoryErrorResponse,
    ListCategoriesResponse,
)
from .postgres_category_repository import CategoryPersistenceUnavailable

router = APIRouter(prefix="/api/v1/categories", tags=["categories"])


class CategoryReader(Protocol):
    """Structural type of the adapter this route needs."""

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        """Return the authenticated user's visible catalogue."""


def _category_repository(request: Request) -> CategoryReader:
    return cast(CategoryReader, request.app.state.category_repository)


CategoryRepositoryDependency = Annotated[
    CategoryReader,
    Depends(_category_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.get(
    "",
    response_model=ListCategoriesResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": CategoryErrorResponse,
            "description": "Category persistence is unavailable",
        },
    },
)
async def list_categories(
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
) -> ListCategoriesResponse:
    user_id = _user_id(user)
    try:
        return await repository.list_categories(user_id=user_id)
    except CategoryPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so category names and database details
    # are not retained as public exception context.
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _category_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="CATEGORY_PERSISTENCE_UNAVAILABLE",
    )


def _category_error(*, status_code: int, code: CategoryErrorCode) -> HTTPException:
    detail = CategoryErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
