"""PostgreSQL adapter for the owned category catalogue (ADR 0020)."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import select

from .category_contracts import SEEDED_CATEGORIES, Category, ListCategoriesResponse
from .database import AsyncSessionFactory
from .db_models import FinanceCategoryRow
from .finance_core import FinanceCategorySnapshot


class CategoryPersistenceUnavailable(Exception):
    """The authoritative store could not safely read the catalogue."""


def seeded_category_rows(
    *,
    user_id: UUID,
    created_at: datetime,
) -> list[FinanceCategoryRow]:
    """Build the starting set for one user.

    Returned rather than written so the caller can insert it inside the same
    transaction as the account, which is what makes seeding all-or-nothing.
    """

    return [
        FinanceCategoryRow(
            id=uuid4(),
            user_id=user_id,
            name=seeded.name,
            direction=seeded.direction,
            system_key=seeded.system_key,
            created_at=created_at,
            archived_at=None,
        )
        for seeded in SEEDED_CATEGORIES
    ]


class PostgresCategoryRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        """Return the user's visible catalogue in a stable order."""

        async with self._session_factory() as database:
            rows = (
                await database.scalars(
                    select(FinanceCategoryRow)
                    .where(
                        FinanceCategoryRow.user_id == user_id,
                        # Archived rows keep historical operations grouped but
                        # are not offered for new ones.
                        FinanceCategoryRow.archived_at.is_(None),
                    )
                    .order_by(
                        FinanceCategoryRow.direction.asc(),
                        FinanceCategoryRow.name.asc(),
                        FinanceCategoryRow.id.asc(),
                    )
                )
            ).all()
        return ListCategoriesResponse(categories=_to_contract(rows))

    async def get_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> FinanceCategorySnapshot | None:
        """Resolve one owned category for draft validation (ADR 0020)."""

        async with self._session_factory() as database:
            row = await database.scalar(
                select(FinanceCategoryRow).where(
                    FinanceCategoryRow.id == category_id,
                    # Scoped to the owner, so another user's catalogue is not
                    # merely rejected later — it is never returned at all.
                    FinanceCategoryRow.user_id == user_id,
                )
            )
        if row is None:
            return None
        return FinanceCategorySnapshot(
            category_id=row.id,
            user_id=row.user_id,
            direction=row.direction,
            archived=row.archived_at is not None,
        )


def _to_contract(rows: Sequence[FinanceCategoryRow]) -> tuple[Category, ...]:
    return tuple(
        Category(
            category_id=row.id,
            name=row.name,
            direction=row.direction,  # type: ignore[arg-type]
            system_key=row.system_key,
            created_at=row.created_at,
        )
        for row in rows
    )


class UnavailableCategoryRepository:
    async def list_categories(self, *, user_id: UUID) -> ListCategoriesResponse:
        del user_id
        raise CategoryPersistenceUnavailable


def _utc_now() -> datetime:
    return datetime.now(UTC)
