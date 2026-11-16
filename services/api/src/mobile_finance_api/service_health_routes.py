"""The one route a watcher asks: is this service serving."""

from __future__ import annotations

from typing import Annotated, cast

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from .service_health import ServiceHealth

router = APIRouter(prefix="/api/v1", tags=["health"])


def _service_health(request: Request) -> ServiceHealth:
    return cast(ServiceHealth, request.app.state.service_health)


ServiceHealthDependency = Annotated[ServiceHealth, Depends(_service_health)]


@router.get(
    "/health",
    responses={
        200: {"description": "Requests that need the database are being served"},
        503: {"description": "They are not"},
    },
)
async def read_health(health: ServiceHealthDependency) -> JSONResponse:
    """Open to anyone, so it says up or down and nothing about why."""

    serving = await health.serving()
    return JSONResponse(
        status_code=200 if serving else 503,
        content={"status": "ok" if serving else "unavailable"},
    )
