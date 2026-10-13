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
from .text_entry import CategoryOption, parse_operation_text, read_transfer_sides
from .text_entry_contracts import (
    ParsedOperationProposal,
    ParsedTransferProposal,
    ParsedTransferSide,
    ParseOperationRequest,
    ParseOperationResponse,
    ParseTransferResponse,
    TextEntryErrorCode,
    TextEntryErrorDetail,
    TextEntryErrorResponse,
)

router = APIRouter(prefix="/api/v1/operations", tags=["operations"])

#: Reading a sentence as a transfer is the same kind of read as reading one as
#: an operation — it decides nothing and writes nothing — so it lives here
#: rather than beside the Finance Core write path it eventually feeds.
transfer_router = APIRouter(prefix="/api/v1/transfers", tags=["transfers"])


class CategoryReader(Protocol):
    """Structural type of the adapter this route needs."""

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        """Return the caller's own non-archived categories."""

    async def list_category_keywords(
        self, *, user_id: UUID
    ) -> dict[UUID, tuple[str, ...]]:
        """Return the words that lead to each of them."""


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
        # Read separately because the catalogue response is frozen for the
        # installed client; only the parser needs these (ADR 0020 step 3).
        keywords = await repository.list_category_keywords(user_id=user_id)
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
                    keywords=keywords.get(category.category_id, ()),
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


@transfer_router.post(
    "/parse",
    response_model=ParseTransferResponse,
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
async def parse_transfer(
    request: ParseOperationRequest,
    user: CurrentUserDependency,
) -> ParseTransferResponse:
    """Read a sentence as an exchange, or say it is not one.

    It needs no catalogue and no wallets: a transfer has no category, and which
    wallets the two currencies mean is the client's to resolve from the list it
    already holds. Nothing here is confirmable — the ordinary
    evaluate/review/commit pair still writes the transfer (ADR 0029).
    """

    _user_id(user)
    try:
        today = request.captured_at.astimezone(
            ZoneInfo(request.captured_timezone)
        ).date()
        sides = read_transfer_sides(request.text, today=today)
        if sides is None:
            return ParseTransferResponse(proposal=None)
        sent, received = sides
        # The day the money moved is read the same way an operation's is, so
        # «вчера» means yesterday here too. No catalogue is passed: a transfer
        # has no category.
        occurred_on = parse_operation_text(text=request.text, today=today).occurred_on
        return ParseTransferResponse(
            proposal=ParsedTransferProposal(
                sent=ParsedTransferSide(amount=sent.amount, currency=sent.currency),
                received=ParsedTransferSide(
                    amount=received.amount, currency=received.currency
                ),
                occurred_on=occurred_on,
            )
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
    return _text_entry_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="TEXT_ENTRY_UNAVAILABLE",
    )


def _text_entry_error(*, status_code: int, code: TextEntryErrorCode) -> HTTPException:
    detail = TextEntryErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
