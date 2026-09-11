"""The boundary for the build a device may install (ADR 0026).

Two doors, and the difference is deliberate. An installed app updates
itself through the bearer token it already holds. A person with no copy
holds nothing, so a first install is reached instead through a signed,
expiring link — see `app_download_link`.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated, cast

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.responses import FileResponse

from .app_download_link import verify_download_link
from .app_release import AppReleaseStore, AppReleaseUnavailable
from .app_release_contracts import (
    AppReleaseErrorDetail,
    AppReleaseErrorResponse,
    AppUpdateResponse,
)
from .auth import AuthenticatedUser, current_user

router = APIRouter(prefix="/api/v1/app", tags=["app"])

#: What Android's package installer expects to be handed.
APK_MEDIA_TYPE = "application/vnd.android.package-archive"


def _release_store(request: Request) -> AppReleaseStore:
    return cast(AppReleaseStore, request.app.state.app_release_store)


ReleaseStoreDependency = Annotated[AppReleaseStore, Depends(_release_store)]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]


@router.get(
    "/update",
    response_model=AppUpdateResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": AppReleaseErrorResponse,
            "description": "A configured release could not be read",
        },
    },
)
async def read_update(
    response: Response,
    store: ReleaseStoreDependency,
    user: CurrentUserDependency,
) -> AppUpdateResponse:
    del user
    try:
        published = store.published()
    except AppReleaseUnavailable:
        raise _error(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="APP_RELEASE_UNAVAILABLE",
        ) from None
    except Exception:
        raise _error(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="APP_RELEASE_UNAVAILABLE",
        ) from None
    # A published build changes only when someone uploads one, but a stale
    # answer here would offer an update that no longer exists.
    response.headers["cache-control"] = "no-store"
    return AppUpdateResponse(
        release=None if published is None else published.release,
    )


@router.get(
    "/download",
    responses={
        200: {
            "content": {APK_MEDIA_TYPE: {}},
            "description": "The published Android package",
        },
        401: {"description": "Authentication is required"},
        404: {
            "model": AppReleaseErrorResponse,
            "description": "Nothing is published",
        },
        503: {
            "model": AppReleaseErrorResponse,
            "description": "A configured release could not be read",
        },
    },
)
async def download_release(
    store: ReleaseStoreDependency,
    user: CurrentUserDependency,
) -> FileResponse:
    del user
    try:
        published = store.published()
    except Exception:
        raise _error(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="APP_RELEASE_UNAVAILABLE",
        ) from None
    if published is None:
        raise _error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="APP_RELEASE_NOT_FOUND",
        )
    # Streamed by Starlette rather than read into memory: this is the one
    # response measured in tens of megabytes.
    return FileResponse(
        published.apk_path,
        media_type=APK_MEDIA_TYPE,
        filename=f"mobile-finance-assistant-{published.release.version_name}.apk",
        headers={"cache-control": "no-store"},
    )


@router.get(
    "/get/{link}",
    responses={
        200: {
            "content": {APK_MEDIA_TYPE: {}},
            "description": "The published Android package",
        },
        404: {
            "model": AppReleaseErrorResponse,
            "description": "Nothing is published, or the link is not valid",
        },
        503: {
            "model": AppReleaseErrorResponse,
            "description": "A configured release could not be read",
        },
    },
)
async def download_release_by_link(
    request: Request,
    link: str,
    store: ReleaseStoreDependency,
) -> FileResponse:
    """Serve the published build to someone who has no account yet (ADR 0026).

    The only route here that takes no bearer token, because a first install
    cannot present one. A malformed link, a forged link, an expired link, a
    host that issues no links, and a host with nothing published are **one
    answer**: telling them apart would turn this into an oracle for whether a
    guess was close, exactly as the registration allowlist refuses to do.
    """

    secret = getattr(request.app.state, "app_download_link_secret", None)
    if secret is None or not verify_download_link(
        secret=secret,
        link=link,
        now=datetime.now(UTC),
    ):
        raise _error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="APP_RELEASE_NOT_FOUND",
        )
    try:
        published = store.published()
    except Exception:
        raise _error(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="APP_RELEASE_UNAVAILABLE",
        ) from None
    if published is None:
        raise _error(
            status_code=status.HTTP_404_NOT_FOUND,
            code="APP_RELEASE_NOT_FOUND",
        )
    return FileResponse(
        published.apk_path,
        media_type=APK_MEDIA_TYPE,
        filename=f"mobile-finance-assistant-{published.release.version_name}.apk",
        headers={"cache-control": "no-store"},
    )


def _error(*, status_code: int, code: str) -> HTTPException:
    detail = AppReleaseErrorDetail(code=code).model_dump(  # type: ignore[arg-type]
        mode="json",
        by_alias=True,
    )
    return HTTPException(status_code=status_code, detail=detail)
