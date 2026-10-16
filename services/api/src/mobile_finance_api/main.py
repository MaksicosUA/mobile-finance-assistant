"""FastAPI factory for auth, read-only Home, and Finance Core operations."""

from __future__ import annotations

import hashlib
import re
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Literal, cast
from uuid import uuid4
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from sqlalchemy.ext.asyncio import AsyncEngine
from starlette.datastructures import MutableHeaders
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from .account_core import AccountCore, UnavailableFinanceAccountRepository
from .account_data import UnavailableAccountDataRepository
from .account_data_routes import router as account_data_router
from .account_routes import router as account_router
from .analytics_routes import router as analytics_router
from .app_release import AppReleaseStore, NoAppReleaseStore
from .app_release_routes import router as app_release_router
from .auth import (
    AuthenticatedUser,
    CurrentUserAuthenticator,
    DenyAllCurrentUserAuthenticator,
    current_user,
)
from .auth_routes import router as auth_router
from .auth_service import AuthenticationService, UnavailableAuthenticationService
from .budget_core import BudgetCore, UnavailableBudgetRepository
from .budget_routes import router as budget_router
from .category_routes import router as category_router
from .finance_core import FinanceCore, UnavailableFinanceOperationRepository
from .goal_core import GoalCore, UnavailableGoalRepository
from .goal_routes import router as goal_router
from .models import HomeResponse, HomeV1Response
from .operation_routes import router as operation_router
from .planned_cost_core import PlannedCostCore, UnavailablePlannedCostRepository
from .planned_cost_recurrence_core import (
    PlannedCostRecurrenceCore,
    UnavailablePlannedCostRecurrenceRepository,
)
from .planned_cost_recurrence_routes import (
    router as planned_cost_recurrence_router,
)
from .planned_cost_routes import router as planned_cost_router
from .postgres_analytics_repository import UnavailableAnalyticsRepository
from .postgres_category_repository import UnavailableCategoryRepository
from .postgres_profile_repository import UnavailableProfileRepository
from .profile_routes import router as profile_router
from .repository import (
    HomeCanonicalTimezoneMismatch,
    HomeQuery,
    HomeRepository,
    UnavailableHomeRepository,
)
from .text_entry_routes import router as text_entry_router
from .text_entry_routes import transfer_router as transfer_text_entry_router
from .timezones import validated_iana_timezone
from .transfer_core import TransferCore, UnavailableTransferRepository
from .transfer_routes import router as transfer_router

_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
_CACHE_HEADERS = {
    "Cache-Control": "private, no-cache",
    "Vary": "Authorization",
}
_HOME_PATHS = {"/api/v1/home", "/api/v2/home"}


class RequestIdMiddleware:
    """Attach a non-sensitive bounded request ID to every HTTP response."""

    def __init__(self, app: ASGIApp) -> None:
        self._app = app

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope["type"] != "http":
            await self._app(scope, receive, send)
            return

        request_id = _request_id_from_scope(scope) or uuid4().hex
        scope.setdefault("state", {})["request_id"] = request_id

        async def send_with_request_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                headers["X-Request-ID"] = request_id
                if scope.get("path") in _HOME_PATHS:
                    headers["Cache-Control"] = _CACHE_HEADERS["Cache-Control"]
                    vary = headers.get("Vary", "")
                    vary_names = {
                        name.strip().lower() for name in vary.split(",") if name.strip()
                    }
                    if "authorization" not in vary_names:
                        headers["Vary"] = (
                            f"{vary}, Authorization" if vary else "Authorization"
                        )
                path = str(scope.get("path", ""))
                if path.startswith(
                    (
                        "/api/v1/auth/",
                        "/api/v1/accounts",
                        "/api/v1/operations/",
                        "/api/v1/planned-costs",
                    )
                ):
                    headers["Cache-Control"] = "no-store"
                    headers["Pragma"] = "no-cache"
            await send(message)

        await self._app(scope, receive, send_with_request_id)


def _request_id_from_scope(scope: Scope) -> str | None:
    for raw_name, raw_value in scope.get("headers", ()):  # pragma: no branch
        if raw_name.lower() not in {b"x-correlation-id", b"x-request-id"}:
            continue
        try:
            candidate = raw_value.decode("ascii")
        except UnicodeDecodeError:
            return None
        return candidate if _SAFE_REQUEST_ID.fullmatch(candidate) else None
    return None


async def _home_repository(request: Request) -> HomeRepository:
    return cast(HomeRepository, request.app.state.home_repository)


def _iana_timezone(value: str) -> ZoneInfo:
    try:
        return validated_iana_timezone(value)
    except ValueError as error:
        raise HTTPException(status_code=422, detail="Invalid IANA timezone") from error


def _strong_etag(content: bytes) -> str:
    return f'"{hashlib.sha256(content).hexdigest()}"'


def _if_none_match_matches(value: str | None, etag: str) -> bool:
    if value is None or len(value) > 8192:
        return False
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        return False
    for raw_candidate in value.split(","):
        candidate = raw_candidate.strip()
        if candidate == "*":
            return True
        if candidate[:2].lower() == "w/":
            candidate = candidate[2:].strip()
        if candidate == etag:
            return True
    return False


router = APIRouter()


@router.get(
    "/api/v1/home",
    response_model=HomeV1Response,
    response_model_by_alias=True,
    responses={
        200: {"description": "Original non-null Home v1 aggregate"},
        304: {"description": "The authenticated representation is unchanged"},
        409: {"description": "Requested timezone conflicts with the profile"},
        401: {"description": "Authentication is required"},
        422: {"description": "Unsupported period or invalid IANA timezone"},
        503: {"description": "The Home projection is temporarily unavailable"},
    },
)
async def get_home(
    period: Literal["current_month"] = Query(),
    timezone_name: str = Query(alias="timezone", min_length=1, max_length=128),
    if_none_match: str | None = Header(default=None, alias="If-None-Match"),
    user: AuthenticatedUser = Depends(current_user),
    repository: HomeRepository = Depends(_home_repository),
) -> Response:
    return await _get_home_response(
        period=period,
        timezone_name=timezone_name,
        if_none_match=if_none_match,
        user=user,
        repository=repository,
        legacy_v1=True,
    )


@router.get(
    "/api/v2/home",
    response_model=HomeResponse,
    response_model_by_alias=True,
    responses={
        200: {"description": "Validated Home aggregate with date-only facts"},
        304: {"description": "The authenticated representation is unchanged"},
        409: {"description": "Requested timezone conflicts with the profile"},
        401: {"description": "Authentication is required"},
        422: {"description": "Unsupported period or invalid IANA timezone"},
        503: {"description": "The Home projection is temporarily unavailable"},
    },
)
async def get_home_v2(
    period: Literal["current_month"] = Query(),
    timezone_name: str = Query(alias="timezone", min_length=1, max_length=128),
    if_none_match: str | None = Header(default=None, alias="If-None-Match"),
    user: AuthenticatedUser = Depends(current_user),
    repository: HomeRepository = Depends(_home_repository),
) -> Response:
    return await _get_home_response(
        period=period,
        timezone_name=timezone_name,
        if_none_match=if_none_match,
        user=user,
        repository=repository,
        legacy_v1=False,
    )


async def _get_home_response(
    *,
    period: Literal["current_month"],
    timezone_name: str,
    if_none_match: str | None,
    user: AuthenticatedUser,
    repository: HomeRepository,
    legacy_v1: bool,
) -> Response:
    query = HomeQuery(period=period, timezone=_iana_timezone(timezone_name))
    try:
        raw_home = await repository.get_home(user=user, query=query)
        home = HomeResponse.model_validate(raw_home)
        response = HomeV1Response.from_v2(home) if legacy_v1 else home
        content = response.model_dump_json(by_alias=True).encode("utf-8")
    except HomeCanonicalTimezoneMismatch as mismatch:
        # The zone is the caller's own account metadata behind their own
        # bearer token, and naming it is what lets a client that is behind a
        # correction recover on its own.
        return JSONResponse(
            status_code=409,
            content={
                "detail": {
                    "code": "CANONICAL_TIMEZONE_MISMATCH",
                    "canonicalTimezone": mismatch.canonical_timezone,
                }
            },
        )
    except Exception:
        # Return a sanitized response instead of chaining an exception whose
        # locals may contain a future financial Home snapshot.
        return JSONResponse(
            status_code=503,
            content={"detail": "Home temporarily unavailable"},
        )
    etag = _strong_etag(content)
    headers = {**_CACHE_HEADERS, "ETag": etag}

    if _if_none_match_matches(if_none_match, etag):
        return Response(status_code=304, headers=headers)
    return Response(
        content=content,
        status_code=200,
        media_type="application/json",
        headers=headers,
    )


def create_app(
    *,
    home_repository: HomeRepository | None = None,
    current_user_authenticator: CurrentUserAuthenticator | None = None,
    authentication_service: AuthenticationService | None = None,
    account_core: AccountCore | None = None,
    finance_core: FinanceCore | None = None,
    budget_core: BudgetCore | None = None,
    transfer_core: TransferCore | None = None,
    planned_cost_core: PlannedCostCore | None = None,
    planned_cost_recurrence_core: PlannedCostRecurrenceCore | None = None,
    goal_core: GoalCore | None = None,
    category_repository: object | None = None,
    finance_operation_repository: object | None = None,
    analytics_repository: object | None = None,
    profile_repository: object | None = None,
    account_data_repository: object | None = None,
    app_release_store: AppReleaseStore | None = None,
    app_download_link_secret: bytes | None = None,
    database_engine: AsyncEngine | None = None,
    registration_allowlist: frozenset[str] | None = None,
) -> FastAPI:
    """Build the API with explicit replaceable data and auth adapters."""

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        try:
            yield
        finally:
            if database_engine is not None:
                await database_engine.dispose()

    application = FastAPI(
        title="Mobile Finance Assistant API",
        version="1.0.0",
        lifespan=lifespan,
    )
    application.state.home_repository = (
        home_repository if home_repository is not None else UnavailableHomeRepository()
    )
    application.state.current_user_authenticator = (
        current_user_authenticator
        if current_user_authenticator is not None
        else DenyAllCurrentUserAuthenticator()
    )
    # Absent means open registration, which is what a local run expects; a
    # public deployment sets it and only invited addresses get through.
    application.state.registration_allowlist = registration_allowlist
    # A deployment that has never published a build has no update, which is a
    # normal answer rather than a misconfiguration (ADR 0026).
    application.state.app_release_store = (
        app_release_store if app_release_store is not None else NoAppReleaseStore()
    )
    # Absent by default: a deployment that never sets a secret offers no
    # unauthenticated download, and upgrading reaches nothing new (ADR 0026).
    application.state.app_download_link_secret = app_download_link_secret
    application.state.authentication_service = (
        authentication_service
        if authentication_service is not None
        else UnavailableAuthenticationService()
    )
    unavailable_accounts = UnavailableFinanceAccountRepository()
    application.state.account_core = (
        account_core
        if account_core is not None
        else AccountCore(repository=unavailable_accounts)
    )
    application.state.finance_core = (
        finance_core
        if finance_core is not None
        else FinanceCore(
            repository=UnavailableFinanceOperationRepository(),
            account_directory=unavailable_accounts,
        )
    )
    application.state.planned_cost_core = (
        planned_cost_core
        if planned_cost_core is not None
        else PlannedCostCore(repository=UnavailablePlannedCostRepository())
    )
    application.state.budget_core = (
        budget_core
        if budget_core is not None
        else BudgetCore(repository=UnavailableBudgetRepository())
    )
    application.state.transfer_core = (
        transfer_core
        if transfer_core is not None
        else TransferCore(repository=UnavailableTransferRepository())
    )
    application.state.planned_cost_recurrence_core = (
        planned_cost_recurrence_core
        if planned_cost_recurrence_core is not None
        else PlannedCostRecurrenceCore(
            repository=UnavailablePlannedCostRecurrenceRepository()
        )
    )
    application.state.goal_core = (
        goal_core
        if goal_core is not None
        else GoalCore(repository=UnavailableGoalRepository())
    )
    application.state.category_repository = (
        category_repository
        if category_repository is not None
        else UnavailableCategoryRepository()
    )
    # Reading history is not a Finance Core decision, so the route reaches the
    # adapter directly rather than widening the core with a read method. It
    # defaults to the core's own adapter rather than to the unavailable stub:
    # a caller that wired writes has wired reads, and forgetting the second
    # parameter used to answer 503 to every read while writes worked.
    application.state.finance_operation_repository = (
        finance_operation_repository
        if finance_operation_repository is not None
        else application.state.finance_core.operation_store
    )
    application.state.profile_repository = (
        profile_repository
        if profile_repository is not None
        else UnavailableProfileRepository()
    )
    application.state.account_data_repository = (
        account_data_repository
        if account_data_repository is not None
        else UnavailableAccountDataRepository()
    )
    application.state.analytics_repository = (
        analytics_repository
        if analytics_repository is not None
        else UnavailableAnalyticsRepository()
    )

    @application.exception_handler(RequestValidationError)
    async def redacted_request_validation_error(
        request: Request,
        error: RequestValidationError,
    ) -> Response:
        # No trailing slash: the collection path itself takes query parameters
        # now, and its validation errors must be redacted the same way.
        if request.url.path.startswith("/api/v1/operations"):
            return JSONResponse(
                status_code=422,
                content={"detail": {"code": "MALFORMED_OPERATION", "issues": []}},
            )
        if request.url.path.startswith("/api/v1/planned-costs"):
            return JSONResponse(
                status_code=422,
                content={"detail": {"code": "MALFORMED_PLANNED_COST", "issues": []}},
            )
        if request.url.path.startswith("/api/v1/goals"):
            return JSONResponse(
                status_code=422,
                content={"detail": {"code": "MALFORMED_GOAL_COMMAND", "issues": []}},
            )
        if request.url.path.startswith("/api/v1/account/"):
            # Carries a password; the default handler would echo it back.
            return JSONResponse(
                status_code=422,
                content={"detail": {"code": "MALFORMED_ACCOUNT_REQUEST"}},
            )
        if not request.url.path.startswith("/api/v1/auth/"):
            return await request_validation_exception_handler(request, error)
        safe_errors = [
            {
                key: value
                for key, value in item.items()
                if key not in {"input", "ctx", "url"}
            }
            for item in error.errors()
        ]
        return JSONResponse(
            status_code=422,
            content={"detail": jsonable_encoder(safe_errors)},
        )

    application.add_middleware(RequestIdMiddleware)
    application.include_router(auth_router)
    application.include_router(account_router)
    application.include_router(operation_router)
    application.include_router(planned_cost_router)
    application.include_router(planned_cost_recurrence_router)
    application.include_router(goal_router)
    application.include_router(budget_router)
    application.include_router(transfer_router)
    application.include_router(category_router)
    application.include_router(analytics_router)
    application.include_router(profile_router)
    application.include_router(account_data_router)
    application.include_router(app_release_router)
    # Shares the /api/v1/operations prefix with the write routes on purpose:
    # proposing and committing are the same resource, but only one of them
    # writes (ADR 0022).
    application.include_router(text_entry_router)
    application.include_router(transfer_text_entry_router)
    application.include_router(router)
    return application


app = create_app()
