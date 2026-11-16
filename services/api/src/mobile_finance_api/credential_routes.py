"""Changing a password, and resetting a forgotten one with a code (ADR 0035).

Three of these routes answer only for the signed-in caller and take no
identifier. The fourth is for someone who cannot sign in, and so it is the only
one that takes an address: it answers the same way for every address, known or
not, and is counted like a sign-in attempt.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated, Any, Literal, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import BaseModel, ConfigDict, Field, SecretStr

from .auth import AuthenticatedUser, current_user
from .auth_contracts import EmailInput
from .credentials import (
    CurrentPasswordRejected,
    IssuedRecoveryCode,
    NewPasswordRejected,
    RecoveryRejected,
)
from .recovery_codes import MAXIMUM_INPUT_LENGTH
from .request_limits import (
    address_key,
    client_key,
    refuse_if_exhausted,
    request_limits,
)

router = APIRouter(prefix="/api/v1/auth", tags=["authentication"])

CredentialErrorCode = Literal[
    "CREDENTIALS_UNAVAILABLE",
    "PASSWORD_REJECTED",
    "NEW_PASSWORD_REJECTED",
    "RECOVERY_REJECTED",
]

_Password = Annotated[SecretStr, Field(min_length=1, max_length=128)]


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class CredentialErrorDetail(_Model):
    code: CredentialErrorCode


class CredentialErrorResponse(_Model):
    detail: CredentialErrorDetail


class IssueRecoveryCodeCommand(_Model):
    """Give me a new recovery code. The password says it is really me."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    password: _Password


class ChangePasswordCommand(_Model):
    schema_version: Literal["1"] = Field(alias="schemaVersion")
    current_password: _Password = Field(alias="currentPassword")
    new_password: _Password = Field(alias="newPassword")


class ResetPasswordCommand(_Model):
    """I forgot my password; here is my address and the code I was given."""

    schema_version: Literal["1"] = Field(alias="schemaVersion")
    email: EmailInput
    recovery_code: Annotated[
        SecretStr, Field(min_length=1, max_length=MAXIMUM_INPUT_LENGTH)
    ] = Field(alias="recoveryCode")
    new_password: _Password = Field(alias="newPassword")


class RecoveryCodeStatusResponse(_Model):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    #: Whether the account has a code, and since when. Never the code.
    exists: bool
    created_at: datetime | None = Field(alias="createdAt")


class RecoveryCodeResponse(_Model):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    #: Shown once. The server keeps a digest and cannot show it again.
    recovery_code: str = Field(alias="recoveryCode", repr=False)
    created_at: datetime = Field(alias="createdAt")


class CredentialStore(Protocol):
    """Structural type of the adapter these routes need."""

    async def recovery_code_created_at(self, *, user_id: UUID) -> datetime | None:
        """When the caller's current code was issued, if they have one."""

    async def issue_recovery_code(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> IssuedRecoveryCode:
        """Replace the caller's code and return the new one."""

    async def change_password(
        self,
        *,
        user_id: UUID,
        session_id: UUID | None,
        current_password: str,
        new_password: str,
        now: datetime,
    ) -> None:
        """Set a new password and end every other session."""

    async def reset_password(
        self,
        *,
        email: str,
        recovery_code: str,
        new_password: str,
        now: datetime,
    ) -> IssuedRecoveryCode:
        """Replace a forgotten password and return the next recovery code."""


def _credential_repository(request: Request) -> CredentialStore:
    return cast(CredentialStore, request.app.state.credential_repository)


CredentialRepositoryDependency = Annotated[
    CredentialStore,
    Depends(_credential_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]

_UNAVAILABLE_RESPONSE: dict[int | str, dict[str, Any]] = {
    503: {
        "model": CredentialErrorResponse,
        "description": "The credential cannot be read or changed right now",
    },
}
_SIGNED_IN_RESPONSES: dict[int | str, dict[str, Any]] = {
    401: {"description": "Authentication is required"},
    **_UNAVAILABLE_RESPONSE,
}
_WRONG_PASSWORD_RESPONSE: dict[int | str, dict[str, Any]] = {
    403: {
        "model": CredentialErrorResponse,
        "description": "The password did not match; nothing was changed",
    },
}
_NEW_PASSWORD_RESPONSE: dict[int | str, dict[str, Any]] = {
    400: {
        "model": CredentialErrorResponse,
        "description": "The new password is outside what the server accepts",
    },
}


@router.get(
    "/recovery-code",
    response_model=RecoveryCodeStatusResponse,
    response_model_by_alias=True,
    responses=_SIGNED_IN_RESPONSES,
)
async def recovery_code_status(
    repository: CredentialRepositoryDependency,
    user: CurrentUserDependency,
) -> RecoveryCodeStatusResponse:
    user_id = _user_id(user)
    try:
        created_at = await repository.recovery_code_created_at(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    else:
        return RecoveryCodeStatusResponse(
            exists=created_at is not None, created_at=created_at
        )
    raise public_error


@router.post(
    "/recovery-code",
    status_code=status.HTTP_201_CREATED,
    response_model=RecoveryCodeResponse,
    response_model_by_alias=True,
    responses={**_WRONG_PASSWORD_RESPONSE, **_SIGNED_IN_RESPONSES},
)
async def issue_recovery_code(
    request: Request,
    command: IssueRecoveryCodeCommand,
    repository: CredentialRepositoryDependency,
    user: CurrentUserDependency,
) -> RecoveryCodeResponse:
    """Replace the caller's recovery code; the one before it stops working.

    A wrong password is 403, never 401: a 401 tells the app its session has
    expired, and it would sign the person out over a typo.
    """

    user_id = _user_id(user)
    # A stolen session must not be a way to guess the password.
    guesses = request_limits(request).password_by_user
    refuse_if_exhausted((guesses, user.subject))
    try:
        issued = await repository.issue_recovery_code(
            user_id=user_id,
            password=command.password.get_secret_value(),
            now=datetime.now(UTC),
        )
    except CurrentPasswordRejected:
        guesses.record(user.subject)
        public_error = _error(status.HTTP_403_FORBIDDEN, "PASSWORD_REJECTED")
    except Exception:
        public_error = _unavailable()
    else:
        return _issued(issued)
    # Raised outside the handler, so the password is not kept as exception
    # context on its way to a log.
    raise public_error


@router.post(
    "/password/change",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
    responses={
        **_NEW_PASSWORD_RESPONSE,
        **_WRONG_PASSWORD_RESPONSE,
        **_SIGNED_IN_RESPONSES,
    },
)
async def change_password(
    request: Request,
    command: ChangePasswordCommand,
    repository: CredentialRepositoryDependency,
    user: CurrentUserDependency,
) -> Response:
    """Set a new password; every other device is signed out, this one stays."""

    user_id = _user_id(user)
    guesses = request_limits(request).password_by_user
    refuse_if_exhausted((guesses, user.subject))
    try:
        await repository.change_password(
            user_id=user_id,
            session_id=user.session_id,
            current_password=command.current_password.get_secret_value(),
            new_password=command.new_password.get_secret_value(),
            now=datetime.now(UTC),
        )
    except CurrentPasswordRejected:
        guesses.record(user.subject)
        public_error = _error(status.HTTP_403_FORBIDDEN, "PASSWORD_REJECTED")
    except NewPasswordRejected:
        public_error = _error(status.HTTP_400_BAD_REQUEST, "NEW_PASSWORD_REJECTED")
    except Exception:
        public_error = _unavailable()
    else:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    raise public_error


@router.post(
    "/password/reset",
    response_model=RecoveryCodeResponse,
    response_model_by_alias=True,
    responses={
        **_NEW_PASSWORD_RESPONSE,
        403: {
            "model": CredentialErrorResponse,
            "description": "The address and code did not open an account",
        },
        429: {"description": "Too many attempts; Retry-After says how long to wait"},
        **_UNAVAILABLE_RESPONSE,
    },
)
async def reset_password(
    request: Request,
    command: ResetPasswordCommand,
    repository: CredentialRepositoryDependency,
) -> RecoveryCodeResponse:
    """Replace a forgotten password with the recovery code, and sign out everywhere.

    The code is spent by this. The answer carries the next one, to be kept the
    same way. No session is opened: signing in afterwards is the ordinary sign-in.
    """

    limits = request_limits(request)
    address = address_key(command.email)
    origin = client_key(request)
    # Checked before the code, and the same for an address nobody owns: a limit
    # that only applied to real accounts would say which ones are real.
    refuse_if_exhausted(
        (limits.recovery_by_address, address),
        (limits.recovery_by_ip, origin),
    )
    limits.recovery_by_ip.record(origin)
    try:
        issued = await repository.reset_password(
            email=command.email,
            recovery_code=command.recovery_code.get_secret_value(),
            new_password=command.new_password.get_secret_value(),
            now=datetime.now(UTC),
        )
    except RecoveryRejected:
        limits.recovery_by_address.record(address)
        public_error = _error(status.HTTP_403_FORBIDDEN, "RECOVERY_REJECTED")
    except NewPasswordRejected:
        public_error = _error(status.HTTP_400_BAD_REQUEST, "NEW_PASSWORD_REJECTED")
    except Exception:
        public_error = _unavailable()
    else:
        limits.recovery_by_address.clear(address)
        # The forgotten password is gone, and with it every count kept against
        # guesses at it.
        limits.login_by_address.clear(address)
        return _issued(issued)
    raise public_error


def _issued(issued: IssuedRecoveryCode) -> RecoveryCodeResponse:
    return RecoveryCodeResponse(
        recovery_code=issued.value,
        created_at=issued.created_at,
    )


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _error(status.HTTP_503_SERVICE_UNAVAILABLE, "CREDENTIALS_UNAVAILABLE")


def _error(status_code: int, code: CredentialErrorCode) -> HTTPException:
    detail = CredentialErrorDetail(code=code).model_dump(mode="json")
    return HTTPException(status_code=status_code, detail=detail)
