"""Authenticated boundary that proposes an operation from a sentence.

Deliberately outside Finance Core: this decides nothing and writes nothing.
It reads the caller's category catalogue and returns a proposal the client
turns into an ordinary draft (ADR 0022). A bug here can misfill a form the
user is looking at; it cannot create or change financial state.
"""

from __future__ import annotations

from typing import Annotated, Protocol, cast
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Request, status

from .auth import AuthenticatedUser, current_user
from .category_contracts import ListCategoriesResponse
from .text_entry import CategoryOption, parse_operation_text
from .text_entry_contracts import (
    ParsedOperationProposal,
    ParseOperationRequest,
    ParseOperationResponse,
    TextEntryErrorCode,
    TextEntryErrorDetail,
    TextEntryErrorResponse,
)

router = APIRouter(prefix="/api/v1/operations", tags=["operations"])


class CategoryReader(Protocol):
    """Structural type of the adapter this route needs."""

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        """Return the caller's own non-archived categories."""


def _category_repository(request: Request) -> CategoryReader:
    return cast(CategoryReader, request.app.state.category_repository)


CategoryRepositoryDependency = Annotated[
    CategoryReader,
    Depends(_category_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.post(
    "/parse",
    response_model=ParseOperationResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        422: {"description": "The request is malformed"},
        503: {
            "model": TextEntryErrorResponse,
            "description": "The sentence cannot be read",
        },
    },
)
async def parse_operation(
    request: ParseOperationRequest,
    repository: CategoryRepositoryDependency,
    user: CurrentUserDependency,
) -> ParseOperationResponse:
    user_id = _user_id(user)
    try:
        catalogue = await repository.list_categories(user_id=user_id)
        # The day the sentence means, in the user's own timezone. The parser
        # never decides what "today" is.
        today = request.captured_at.astimezone(
            ZoneInfo(request.captured_timezone)
        ).date()
        parsed = parse_operation_text(
            text=request.text,
            today=today,
            categories=tuple(
                CategoryOption(
                    category_id=category.category_id,
                    name=category.name,
                    direction=category.direction,
                )
                for category in catalogue.categories
            ),
        )
        return ParseOperationResponse(
            proposal=ParsedOperationProposal(
                operation_type=parsed.operation_type,
                amount=parsed.amount,
                currency=parsed.currency,
                occurred_on=parsed.occurred_on,
                source_expression=parsed.source_expression,
                category_id=parsed.category_id,
                category=parsed.category,
                gaps=parsed.gaps,
            )
        )
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so the sentence itself, amounts, and
    # category names are not retained as public exception context.
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _text_entry_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="TEXT_ENTRY_UNAVAILABLE",
    )


def _text_entry_error(*, status_code: int, code: TextEntryErrorCode) -> HTTPException:
    detail = TextEntryErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
