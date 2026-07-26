"""Replaceable current-user authentication boundary.

The production default denies every request. Deployments must inject a real
token verifier; this module intentionally contains no development token or
authentication bypass.
"""

from __future__ import annotations

import re
from typing import Annotated, Protocol

from fastapi import HTTPException, Request, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, StringConstraints

_BEARER_TOKEN = re.compile(r"^[A-Za-z0-9._~+/=-]{1,8192}$")
_bearer_scheme = HTTPBearer(
    auto_error=False,
    bearerFormat="opaque",
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
        return await authenticator.authenticate(credentials.credentials)
    except AuthenticationRequired as error:
        raise _unauthorized() from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication temporarily unavailable",
        ) from error


def _safe_access_token(value: str) -> bool:
    return _BEARER_TOKEN.fullmatch(value) is not None


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"},
    )
