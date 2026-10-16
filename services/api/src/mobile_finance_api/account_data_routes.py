"""The person's own account: taking their data with them (ADR 0030).

Everything here answers only for the authenticated caller — no route takes an
identifier, so another person's data is unrepresentable rather than merely
refused. Nothing is generated ahead of time, stored, or logged.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated, Any, Literal, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict

from .auth import AuthenticatedUser, current_user

router = APIRouter(prefix="/api/v1/account", tags=["account"])

#: A copy of someone's whole financial life is not something any cache keeps.
_PRIVATE = {"Cache-Control": "no-store"}

AccountDataErrorCode = Literal["ACCOUNT_DATA_UNAVAILABLE"]


class AccountDataErrorDetail(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    code: AccountDataErrorCode


class AccountDataErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    detail: AccountDataErrorDetail


class AccountDataReader(Protocol):
    """Structural type of the adapter these routes need."""

    async def export(
        self, *, user_id: UUID, exported_at: datetime
    ) -> dict[str, object]:
        """Every authoritative fact the caller owns, as stored."""

    async def operations_csv(self, *, user_id: UUID) -> str:
        """The caller's operations, as a spreadsheet."""


def _account_data_repository(request: Request) -> AccountDataReader:
    return cast(AccountDataReader, request.app.state.account_data_repository)


AccountDataRepositoryDependency = Annotated[
    AccountDataReader,
    Depends(_account_data_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]

_UNAVAILABLE_RESPONSE: dict[int | str, dict[str, Any]] = {
    401: {"description": "Authentication is required"},
    503: {
        "model": AccountDataErrorResponse,
        "description": "The data cannot be read right now",
    },
}


@router.get(
    "/export",
    responses={
        200: {"description": "Every fact the caller owns, in the database's own names"},
        **_UNAVAILABLE_RESPONSE,
    },
)
async def export_account(
    repository: AccountDataRepositoryDependency,
    user: CurrentUserDependency,
) -> JSONResponse:
    user_id = _user_id(user)
    try:
        document = await repository.export(
            user_id=user_id, exported_at=datetime.now(UTC)
        )
    except Exception:
        public_error = _unavailable()
    else:
        return JSONResponse(document, headers=_PRIVATE)
    # Raised outside the handler, so nothing the person owns is retained as
    # exception context on its way to a log.
    raise public_error


@router.get(
    "/export/operations.csv",
    responses={
        200: {
            "description": "The caller's operations as a spreadsheet",
            "content": {"text/csv": {}},
        },
        **_UNAVAILABLE_RESPONSE,
    },
)
async def export_operations_csv(
    repository: AccountDataRepositoryDependency,
    user: CurrentUserDependency,
) -> Response:
    user_id = _user_id(user)
    try:
        table = await repository.operations_csv(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    else:
        return Response(
            content=table.encode("utf-8"),
            media_type="text/csv; charset=utf-8",
            headers=_PRIVATE,
        )
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    detail = AccountDataErrorDetail(code="ACCOUNT_DATA_UNAVAILABLE").model_dump(
        mode="json"
    )
    return HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=detail)
