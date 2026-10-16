"""Versioned JSON authentication routes for the first-party mobile client."""

from __future__ import annotations

from typing import Annotated, cast

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth_contracts import (
    AuthTokenResponse,
    AuthUserResponse,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
)
from .auth_service import (
    AuthenticationRejected,
    AuthenticationService,
    AuthenticationUnavailable,
    AuthGrant,
    RegistrationRejected,
)

router = APIRouter(prefix="/api/v1/auth", tags=["authentication"])


def _authentication_service(request: Request) -> AuthenticationService:
    return cast(AuthenticationService, request.app.state.authentication_service)


AuthServiceDependency = Annotated[
    AuthenticationService,
    Depends(_authentication_service),
]


@router.post(
    "/register",
    response_model=AuthTokenResponse,
    response_model_by_alias=True,
    status_code=status.HTTP_201_CREATED,
)
async def register(
    request: Request,
    body: RegisterRequest,
    service: AuthServiceDependency,
) -> AuthTokenResponse:
    allowlist = getattr(request.app.state, "registration_allowlist", None)
    if allowlist is not None and body.email.strip().casefold() not in allowlist:
        # Deliberately the same refusal a taken address gets. Telling the two
        # apart would turn this endpoint into an oracle for who is invited.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Account could not be created",
        )
    try:
        grant = await service.register(
            email=body.email,
            password=body.password.get_secret_value(),
            display_name=body.display_name,
        )
    except RegistrationRejected:
        sanitized_error = HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Account could not be created",
        )
    except AuthenticationUnavailable:
        sanitized_error = _unavailable()
    except Exception:
        sanitized_error = _unavailable()
    else:
        return _response(grant)
    # Raise outside the active handler so password-bearing exception locals and
    # database details are not retained as an exception context for telemetry.
    raise sanitized_error


@router.post(
    "/login",
    response_model=AuthTokenResponse,
    response_model_by_alias=True,
)
async def login(
    body: LoginRequest,
    service: AuthServiceDependency,
) -> AuthTokenResponse:
    try:
        grant = await service.login(
            email=body.email,
            password=body.password.get_secret_value(),
        )
    except AuthenticationRejected:
        sanitized_error = _unauthorized()
    except AuthenticationUnavailable:
        sanitized_error = _unavailable()
    except Exception:
        sanitized_error = _unavailable()
    else:
        return _response(grant)
    raise sanitized_error


@router.post(
    "/refresh",
    response_model=AuthTokenResponse,
    response_model_by_alias=True,
)
async def refresh(
    body: RefreshRequest,
    service: AuthServiceDependency,
) -> AuthTokenResponse:
    try:
        grant = await service.refresh(
            refresh_token=body.refresh_token.get_secret_value()
        )
    except AuthenticationRejected:
        sanitized_error = _unauthorized()
    except AuthenticationUnavailable:
        sanitized_error = _unavailable()
    except Exception:
        sanitized_error = _unavailable()
    else:
        return _response(grant)
    raise sanitized_error


@router.post(
    "/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    response_class=Response,
)
async def logout(
    body: LogoutRequest,
    service: AuthServiceDependency,
) -> Response:
    try:
        await service.logout(refresh_token=body.refresh_token.get_secret_value())
    except AuthenticationUnavailable:
        sanitized_error = _unavailable()
    except Exception:
        sanitized_error = _unavailable()
    else:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    raise sanitized_error


def _response(grant: AuthGrant) -> AuthTokenResponse:
    return AuthTokenResponse(
        access_token=grant.access_token,
        refresh_token=grant.refresh_token,
        access_expires_in=grant.access_expires_in,
        refresh_expires_in=grant.refresh_expires_in,
        cache_scope_id=str(grant.user_id),
        user=AuthUserResponse(
            id=grant.user_id,
            display_name=grant.display_name,
        ),
        deletion_cancelled=grant.deletion_cancelled,
    )


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Authentication required",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Authentication temporarily unavailable",
    )
