"""PostgreSQL read adapter for the profile screen."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select

from .database import AsyncSessionFactory
from .db_models import FinanceAccountRow, UserRow
from .profile_contracts import ProfileAccount, ProfileResponse, ProfileUser


class ProfileUnavailable(Exception):
    """The authoritative store could not safely read the profile."""


class PostgresProfileRepository:
    def __init__(self, *, session_factory: AsyncSessionFactory) -> None:
        self._session_factory = session_factory

    async def read_profile(self, *, user_id: UUID) -> ProfileResponse:
        async with self._session_factory() as database:
            user = await database.scalar(
                select(UserRow).where(
                    UserRow.id == user_id,
                    UserRow.disabled_at.is_(None),
                )
            )
            if user is None:
                raise ProfileUnavailable
            account = await database.scalar(
                select(FinanceAccountRow).where(
                    FinanceAccountRow.user_id == user_id,
                    FinanceAccountRow.status == "active",
                    FinanceAccountRow.is_default.is_(True),
                )
            )
        return ProfileResponse(
            user=ProfileUser(
                id=user.id,
                display_name=user.display_name,
                # The normalized form is what the table keeps and what a
                # sign-in matches against, so it is the honest answer to
                # "which account am I in".
                email=user.email_normalized,
            ),
            # A registered user without an account is a real state; the screen
            # says so rather than failing.
            account=None
            if account is None
            else ProfileAccount(
                id=account.id,
                currency=account.currency,
                canonical_timezone=account.opening_timezone,
                opening_balance_on=account.opening_balance_on,
            ),
        )


class UnavailableProfileRepository:
    async def read_profile(self, *, user_id: UUID) -> ProfileResponse:
        del user_id
        raise ProfileUnavailable
