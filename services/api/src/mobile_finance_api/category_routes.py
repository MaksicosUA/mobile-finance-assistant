"""Authenticated boundary for the category catalogue (ADR 0020).

Reading and managing are deliberately separate representations. The picker's
`GET /api/v1/categories` is frozen for installed clients, which parse it with a
closed key set on both the envelope and each item; the management view lives at
`GET /api/v1/categories/managed` and may grow.

Removal is archiving. A category is never deleted, so an operation recorded
against it keeps its grouping forever.
"""

from __future__ import annotations

from collections.abc import Awaitable
from typing import Annotated, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import AuthenticatedUser, current_user
from .category_contracts import (
    CategoryErrorCode,
    CategoryErrorDetail,
    CategoryErrorResponse,
    CategoryKeywordsResponse,
    CategoryResponse,
    CreateCategoryCommand,
    ListCategoriesResponse,
    ManagedCategory,
    ManagedCategoryListResponse,
    RenameCategoryCommand,
    ReplaceCategoryKeywordsCommand,
)
from .postgres_category_repository import (
    CategoryArchived,
    CategoryKeywordTaken,
    CategoryNameTaken,
    CategoryNotFound,
    CategoryPersistenceUnavailable,
)
from .quotas import QuotaExceeded

router = APIRouter(prefix="/api/v1/categories", tags=["categories"])


class CategoryReader(Protocol):
    """Structural type of the adapter these routes need."""

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        """Return the authenticated user's offered catalogue."""

    async def list_managed_categories(
        self,
        *,
        user_id: UUID,
    ) -> ManagedCategoryListResponse:
        """Return the whole catalogue, hidden rows included."""

    async def create_category(
        self,
        *,
        user_id: UUID,
        command: CreateCategoryCommand,
    ) -> ManagedCategory:
        """Add one owned category."""

    async def rename_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
        command: RenameCategoryCommand,
    ) -> tuple[ManagedCategory, bool]:
        """Rename one category, reporting whether it changed."""

    async def archive_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        """Hide one category, reporting whether it changed."""

    async def list_keywords(
        self, *, user_id: UUID, category_id: UUID
    ) -> CategoryKeywordsResponse:
        """Return the words that lead to one category."""

    async def replace_keywords(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
        command: ReplaceCategoryKeywordsCommand,
    ) -> tuple[CategoryKeywordsResponse, bool]:
        """Make the stored set equal to the requested one."""

    async def restore_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        """Offer a hidden category again, reporting whether it changed."""


def _category_repository(request: Request) -> CategoryReader:
    return cast(CategoryReader, request.app.state.category_repository)


CategoryRepositoryDependency = Annotated[
    CategoryReader,
    Depends(_category_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]

_WRITE_RESPONSES: dict[int | str, dict[str, object]] = {
    401: {"description": "Authentication is required"},
    404: {
        "model": CategoryErrorResponse,
        "description": "No such category belongs to this user",
    },
    409: {
        "model": CategoryErrorResponse,
        "description": "The name is taken, or the category is hidden",
    },
    503: {
        "model": CategoryErrorResponse,
        "description": "Category persistence is unavailable",
    },
}


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
    except QuotaExceeded:
        raise
    except CategoryPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so category names and database details
    # are not retained as public exception context.
    raise public_error


@router.get(
    "/managed",
    response_model=ManagedCategoryListResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": CategoryErrorResponse,
            "description": "Category persistence is unavailable",
        },
    },
)
async def list_managed_categories(
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
) -> ManagedCategoryListResponse:
    user_id = _user_id(user)
    try:
        return await repository.list_managed_categories(user_id=user_id)
    except CategoryPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=CategoryResponse,
    response_model_by_alias=True,
    responses=_WRITE_RESPONSES,
)
async def create_category(
    command: CreateCategoryCommand,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
) -> CategoryResponse:
    user_id = _user_id(user)
    try:
        created = await repository.create_category(user_id=user_id, command=command)
    except CategoryNameTaken:
        raise _name_taken() from None
    except CategoryPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        return CategoryResponse(category=created)
    raise public_error


@router.patch(
    "/{category_id}",
    response_model=CategoryResponse,
    response_model_by_alias=True,
    responses=_WRITE_RESPONSES,
)
async def rename_category(
    category_id: UUID,
    command: RenameCategoryCommand,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
    response: Response,
) -> CategoryResponse:
    return await _write(
        repository.rename_category(
            user_id=_user_id(user),
            category_id=category_id,
            command=command,
        ),
        response=response,
    )


@router.post(
    "/{category_id}/archive",
    response_model=CategoryResponse,
    response_model_by_alias=True,
    responses=_WRITE_RESPONSES,
)
async def archive_category(
    category_id: UUID,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
    response: Response,
) -> CategoryResponse:
    return await _write(
        repository.archive_category(user_id=_user_id(user), category_id=category_id),
        response=response,
    )


@router.post(
    "/{category_id}/restore",
    response_model=CategoryResponse,
    response_model_by_alias=True,
    responses=_WRITE_RESPONSES,
)
async def restore_category(
    category_id: UUID,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
    response: Response,
) -> CategoryResponse:
    return await _write(
        repository.restore_category(user_id=_user_id(user), category_id=category_id),
        response=response,
    )


@router.get(
    "/{category_id}/keywords",
    response_model=CategoryKeywordsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {"model": CategoryErrorResponse, "description": "No such category"},
        503: {
            "model": CategoryErrorResponse,
            "description": "The catalogue cannot be read",
        },
    },
)
async def list_category_keywords(
    category_id: UUID,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
) -> CategoryKeywordsResponse:
    try:
        return await repository.list_keywords(
            user_id=_user_id(user), category_id=category_id
        )
    except CategoryNotFound:
        raise _not_found() from None
    except Exception:
        public_error = _unavailable()
    raise public_error


@router.put(
    "/{category_id}/keywords",
    response_model=CategoryKeywordsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        404: {"model": CategoryErrorResponse, "description": "No such category"},
        409: {
            "model": CategoryErrorResponse,
            "description": "A word already leads elsewhere, or the category is hidden",
        },
        422: {"description": "The request is malformed"},
        503: {
            "model": CategoryErrorResponse,
            "description": "The catalogue cannot be written",
        },
    },
)
async def replace_category_keywords(
    category_id: UUID,
    command: ReplaceCategoryKeywordsCommand,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
    response: Response,
) -> CategoryKeywordsResponse:
    """Replace the whole set, so the write is idempotent by target state."""

    try:
        keywords, changed = await repository.replace_keywords(
            user_id=_user_id(user),
            category_id=category_id,
            command=command,
        )
    except QuotaExceeded:
        raise
    except CategoryNotFound:
        raise _not_found() from None
    except CategoryArchived:
        raise _archived() from None
    except CategoryKeywordTaken as taken:
        # The owner travels in the message so the user can act on the refusal
        # rather than guess which category already claimed the word.
        raise _keyword_taken(keyword=taken.keyword, owner=taken.owner) from None
    except Exception:
        public_error = _unavailable()
    else:
        if not changed:
            response.headers["X-Category-Unchanged"] = "1"
        return keywords
    raise public_error


async def _write(
    pending: Awaitable[tuple[ManagedCategory, bool]],
    *,
    response: Response,
) -> CategoryResponse:
    """Run one catalogue write and translate its failures.

    A write that changed nothing answers 200 with the current row rather than an
    error: hiding a hidden category or renaming one to its own name is what a
    retried request looks like, and the caller's intent already holds.
    """

    try:
        category, changed = await pending
    except CategoryNotFound:
        raise _not_found() from None
    except CategoryNameTaken:
        raise _name_taken() from None
    except CategoryArchived:
        raise _archived() from None
    except CategoryPersistenceUnavailable:
        public_error = _unavailable()
    except Exception:
        public_error = _unavailable()
    else:
        if not changed:
            # Distinguishable for clients that care, without making an
            # idempotent repeat look like a failure.
            response.headers["X-Category-Unchanged"] = "1"
        return CategoryResponse(category=category)
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


def _not_found() -> HTTPException:
    return _category_error(
        status_code=status.HTTP_404_NOT_FOUND,
        code="CATEGORY_NOT_FOUND",
    )


def _keyword_taken(*, keyword: str, owner: str) -> HTTPException:
    detail = CategoryErrorDetail(code="CATEGORY_KEYWORD_TAKEN").model_dump(
        mode="json", by_alias=True
    )
    # The clashing word and its current owner are the user's own catalogue
    # text, returned only to the authenticated owner of both.
    detail["keyword"] = keyword
    detail["owner"] = owner
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detail)


def _name_taken() -> HTTPException:
    return _category_error(
        status_code=status.HTTP_409_CONFLICT,
        code="CATEGORY_NAME_TAKEN",
    )


def _archived() -> HTTPException:
    return _category_error(
        status_code=status.HTTP_409_CONFLICT,
        code="CATEGORY_ARCHIVED",
    )


def _category_error(*, status_code: int, code: CategoryErrorCode) -> HTTPException:
    detail = CategoryErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
