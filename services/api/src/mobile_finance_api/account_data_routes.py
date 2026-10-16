"""The person's own account: taking their data along, and erasing it (ADR 0030).

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
from pydantic import BaseModel, ConfigDict, Field, SecretStr

from .account_data import PasswordRejected
from .auth import AuthenticatedUser, current_user

router = APIRouter(prefix="/api/v1/account", tags=["account"])

#: A copy of someone's whole financial life is not something any cache keeps.
_PRIVATE = {"Cache-Control": "no-store"}

AccountDataErrorCode = Literal["ACCOUNT_DATA_UNAVAILABLE", "PASSWORD_REJECTED"]


class AccountDataErrorDetail(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    code: AccountDataErrorCode


class AccountDataErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    detail: AccountDataErrorDetail


class RequestDeletionCommand(BaseModel):
    """Erase my account a week from now. The password says it is really me."""

    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    password: SecretStr = Field(min_length=1, max_length=128)


class DeletionScheduledResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)

    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    #: When the account will be erased unless its owner signs in before then.
    deletion_due_at: datetime = Field(alias="deletionDueAt")


class AccountDataReader(Protocol):
    """Structural type of the adapter these routes need."""

    async def request_deletion(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> datetime:
        """Schedule erasure and sign out everywhere; returns when it happens."""

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


@router.post(
    "/deletion",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=DeletionScheduledResponse,
    response_model_by_alias=True,
    responses={
        403: {
            "model": AccountDataErrorResponse,
            "description": "The password did not match; nothing was scheduled",
        },
        422: {"description": "The request is malformed"},
        **_UNAVAILABLE_RESPONSE,
    },
)
async def request_deletion(
    command: RequestDeletionCommand,
    repository: AccountDataRepositoryDependency,
    user: CurrentUserDependency,
) -> DeletionScheduledResponse:
    """Schedule erasure a week from now, and sign every device out.

    A wrong password is 403, never 401: a 401 tells the app its session has
    expired, and it would sign the person out over a typo.
    """

    user_id = _user_id(user)
    try:
        due = await repository.request_deletion(
            user_id=user_id,
            password=command.password.get_secret_value(),
            now=datetime.now(UTC),
        )
    except PasswordRejected:
        public_error = _error(status.HTTP_403_FORBIDDEN, "PASSWORD_REJECTED")
    except Exception:
        public_error = _unavailable()
    else:
        return DeletionScheduledResponse(deletion_due_at=due)
    raise public_error


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _error(status.HTTP_503_SERVICE_UNAVAILABLE, "ACCOUNT_DATA_UNAVAILABLE")


def _error(status_code: int, code: AccountDataErrorCode) -> HTTPException:
    detail = AccountDataErrorDetail(code=code).model_dump(mode="json")
    return HTTPException(status_code=status_code, detail=detail)
