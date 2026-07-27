"""Replaceable current-user authentication boundary.

The production default denies every request. Deployments must inject a real
token verifier; this module intentionally contains no development token or
authentication bypass.
"""

from __future__ import annotations

import re
from datetime import UTC, datetime
from typing import Annotated, Protocol

from fastapi import HTTPException, Request, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, StringConstraints
from sqlalchemy import select

from .database import AsyncSessionFactory
from .db_models import AuthSessionRow, UserRow
from .tokens import AccessTokenCodec, InvalidToken

_BEARER_TOKEN = re.compile(r"^[A-Za-z0-9._~+/=-]{1,8192}$")
_bearer_scheme = HTTPBearer(
    auto_error=False,
    bearerFormat="JWT",
    description="Access token verified by the deployment authentication adapter.",
    scheme_name="BearerAuth",
)


class AuthenticatedUser(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    subject: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=1, max_length=128),
    ]
    display_name: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    ]


class AuthenticationRequired(Exception):
    """Raised when no verified current user is available."""


class CurrentUserAuthenticator(Protocol):
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        """Validate credentials and return their account-scoped identity."""


class DenyAllCurrentUserAuthenticator:
    """Fail-closed default used until a real verifier is configured."""

    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        raise AuthenticationRequired


class PostgresCurrentUserAuthenticator:
    """Verify a signed access token and its immediately revocable DB session."""

    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        access_tokens: AccessTokenCodec,
    ) -> None:
        self._session_factory = session_factory
        self._access_tokens = access_tokens

    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        try:
            claims = self._access_tokens.decode(access_token)
        except InvalidToken:
            token_is_invalid = True
        else:
            token_is_invalid = False
        if token_is_invalid:
            # Do not retain the bearer in the traceback frame of the sanitized
            # domain error and do not chain the decoder exception.
            access_token = ""
            raise AuthenticationRequired

        now = datetime.now(UTC)
        async with self._session_factory() as database:
            row = (
                await database.execute(
                    select(UserRow, AuthSessionRow)
                    .join(AuthSessionRow, AuthSessionRow.user_id == UserRow.id)
                    .where(
                        UserRow.id == claims.user_id,
                        UserRow.disabled_at.is_(None),
                        AuthSessionRow.id == claims.session_id,
                        AuthSessionRow.revoked_at.is_(None),
                        AuthSessionRow.absolute_expires_at > now,
                    )
                )
            ).one_or_none()
        if row is None:
            raise AuthenticationRequired
        user, _ = row
        return AuthenticatedUser(
            subject=str(user.id),
            display_name=user.display_name,
        )


async def current_user(
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Security(_bearer_scheme),
    ] = None,
) -> AuthenticatedUser:
    if (
        credentials is None
        or credentials.scheme.lower() != "bearer"
        or not _safe_access_token(credentials.credentials)
    ):
        raise _unauthorized()

    authenticator: CurrentUserAuthenticator = (
        request.app.state.current_user_authenticator
    )
    try:
        authenticated_user = await authenticator.authenticate(credentials.credentials)
    except AuthenticationRequired:
        sanitized_error = _unauthorized()
    except Exception:
        sanitized_error = HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "AUTHENTICATION_UNAVAILABLE", "issues": []},
        )
    else:
        return authenticated_user
    # Do not retain the bearer in the traceback of the public error. Raising
    # outside the active handler also avoids preserving the source exception.
    credentials = None
    raise sanitized_error


def _safe_access_token(value: str) -> bool:
    return _BEARER_TOKEN.fullmatch(value) is not None


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"},
    )
