"""Authenticated read boundary for category analytics.

Deliberately outside Finance Core: this decides nothing and changes nothing.
The period is the account's own canonical month, so the client asks no
question it could get wrong (ADR 0010).
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Literal, Protocol, cast
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from .analytics_contracts import (
    MAXIMUM_CUSTOM_PERIOD_DAYS,
    AnalyticsErrorCode,
    AnalyticsErrorDetail,
    AnalyticsErrorResponse,
    AnalyticsResponse,
    AnalyticsV2Response,
)
from .auth import AuthenticatedUser, current_user
from .home_projection import (
    HomeProjectionInvariantError,
    ReportingPeriodKind,
)

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


class AnalyticsReader(Protocol):
    """Structural type of the adapter this route needs."""

    async def analyse_current_month(self, *, user_id: UUID) -> AnalyticsResponse:
        """Group the caller's current local month."""

    async def analyse_period(
        self,
        *,
        user_id: UUID,
        kind: ReportingPeriodKind,
        from_date: date | None = None,
        to_date: date | None = None,
        account_id: UUID | None = None,
    ) -> AnalyticsV2Response:
        """Group one requested window for one wallet, beside the window
        before it."""


def _analytics_repository(request: Request) -> AnalyticsReader:
    return cast(AnalyticsReader, request.app.state.analytics_repository)


AnalyticsRepositoryDependency = Annotated[
    AnalyticsReader,
    Depends(_analytics_repository),
]
CurrentUserDependency = Annotated[AuthenticatedUser, Depends(current_user)]
PeriodQuery = Annotated[
    Literal["last_7_days", "month", "quarter", "year", "custom"],
    Query(),
]
FromQuery = Annotated[date | None, Query(alias="from")]
ToQuery = Annotated[date | None, Query(alias="to")]


@router.get(
    "",
    response_model=AnalyticsResponse,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        503: {
            "model": AnalyticsErrorResponse,
            "description": "Analytics cannot be computed",
        },
    },
)
async def read_analytics(
    repository: AnalyticsRepositoryDependency,
    user: CurrentUserDependency,
) -> AnalyticsResponse:
    user_id = _user_id(user)
    try:
        return await repository.analyse_current_month(user_id=user_id)
    except Exception:
        public_error = _unavailable()
    # Raised outside the active handler so amounts, category names, and
    # database details are not retained as public exception context.
    raise public_error


@router.get(
    "/v2",
    response_model=AnalyticsV2Response,
    response_model_by_alias=True,
    responses={
        401: {"description": "Authentication is required"},
        422: {
            "model": AnalyticsErrorResponse,
            "description": "The requested window cannot be reported",
        },
        503: {
            "model": AnalyticsErrorResponse,
            "description": "Analytics cannot be computed",
        },
    },
)
async def read_analytics_period(
    repository: AnalyticsRepositoryDependency,
    user: CurrentUserDependency,
    period: PeriodQuery = "month",
    from_date: FromQuery = None,
    to_date: ToQuery = None,
    account_id: Annotated[UUID | None, Query(alias="accountId")] = None,
) -> AnalyticsV2Response:
    """Report one window for one wallet.

    Defaults to the month, which is what Home projects, and to the default
    wallet, which is what its balance card shows. Figures are never added
    across wallets: that would need a rate, and there is none (ADR 0029).
    """

    user_id = _user_id(user)
    _validate_window(period, from_date, to_date)
    try:
        return await repository.analyse_period(
            user_id=user_id,
            kind=period,
            from_date=from_date,
            to_date=to_date,
            account_id=account_id,
        )
    except HomeProjectionInvariantError:
        # A window lying entirely before the account existed is a bad request,
        # not a broken service: answering zero would read as "you had nothing".
        raise _malformed() from None
    except Exception:
        public_error = _unavailable()
    raise public_error


def _validate_window(period: str, from_date: date | None, to_date: date | None) -> None:
    """Refuse a range the report cannot honour, before touching the database."""

    if period != "custom":
        if from_date is not None or to_date is not None:
            # Silently ignoring them would report a window the caller did not
            # ask for and could not tell apart from the one they did.
            raise _malformed()
        return
    if from_date is None or to_date is None or from_date > to_date:
        raise _malformed()
    if (to_date - from_date).days + 1 > MAXIMUM_CUSTOM_PERIOD_DAYS:
        raise _malformed()


def _malformed() -> HTTPException:
    return _analytics_error(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        code="MALFORMED_ANALYTICS_QUERY",
    )


def _user_id(user: AuthenticatedUser) -> UUID:
    try:
        return UUID(user.subject)
    except ValueError:
        raise _unavailable() from None


def _unavailable() -> HTTPException:
    return _analytics_error(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="ANALYTICS_UNAVAILABLE",
    )


def _analytics_error(*, status_code: int, code: AnalyticsErrorCode) -> HTTPException:
    detail = AnalyticsErrorDetail(code=code).model_dump(mode="json", by_alias=True)
    return HTTPException(status_code=status_code, detail=detail)
