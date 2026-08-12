"""PostgreSQL adapter for the owned category catalogue (ADR 0020)."""

from __future__ import annotations

from collections.abc import Callable, Sequence
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import Select, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .category_contracts import (
    SEEDED_CATEGORIES,
    Category,
    CreateCategoryCommand,
    ListCategoriesResponse,
    ManagedCategory,
    ManagedCategoryListResponse,
    RenameCategoryCommand,
)
from .database import AsyncSessionFactory
from .db_models import (
    FinanceCategoryAuditRow,
    FinanceCategoryOutboxEventRow,
    FinanceCategoryRow,
    UserRow,
)
from .finance_core import FinanceCategorySnapshot


class CategoryPersistenceUnavailable(Exception):
    """The authoritative store could not safely read the catalogue."""


class CategoryNotFound(Exception):
    """No such category belongs to this user."""


class CategoryNameTaken(Exception):
    """An offered category of this direction already uses that name."""


class CategoryArchived(Exception):
    """The category is hidden, so it cannot be renamed until it is restored."""


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

    async def list_managed_categories(
        self,
        *,
        user_id: UUID,
    ) -> ManagedCategoryListResponse:
        """Return the whole catalogue, hidden rows included.

        Separate from [list_categories] because hidden rows must never reach
        the picker, and because that response is parsed by installed clients
        with a closed key set.
        """

        async with self._session_factory() as database:
            rows = (
                await database.scalars(
                    select(FinanceCategoryRow)
                    .where(FinanceCategoryRow.user_id == user_id)
                    .order_by(
                        FinanceCategoryRow.direction.asc(),
                        # Offered categories first: the hidden ones are a
                        # recovery list, not the working one.
                        FinanceCategoryRow.archived_at.is_not(None).asc(),
                        FinanceCategoryRow.name.asc(),
                        FinanceCategoryRow.id.asc(),
                    )
                )
            ).all()
        return ManagedCategoryListResponse(categories=_to_managed(rows))

    async def create_category(
        self,
        *,
        user_id: UUID,
        command: CreateCategoryCommand,
    ) -> ManagedCategory:
        async with self._session_factory() as database:
            try:
                async with database.begin():
                    await self._lock_user(database, user_id=user_id)
                    conflict = await database.scalar(
                        _active_name_query(
                            user_id=user_id,
                            direction=command.direction,
                            name=command.name,
                        )
                    )
                    if conflict is not None:
                        raise CategoryNameTaken

                    created_at = _aware_utc(self._clock())
                    row = FinanceCategoryRow(
                        id=uuid4(),
                        user_id=user_id,
                        name=command.name,
                        direction=command.direction,
                        # A user-authored category has no stable key: its label
                        # is the name they chose, in the language they chose.
                        system_key=None,
                        created_at=created_at,
                        archived_at=None,
                    )
                    database.add(row)
                    await database.flush()
                    database.add(
                        _audit_row(
                            category_id=row.id,
                            user_id=user_id,
                            event_type="category_created",
                            previous_name=None,
                            new_name=command.name,
                            previous_status=None,
                            new_status="active",
                            created_at=created_at,
                        )
                    )
                    created = _to_managed_one(row)
            except IntegrityError as error:
                # The user row is locked above, so the only unique index a
                # fresh row can still violate is the active-name one: the id is
                # newly generated and a user-authored category has no key.
                raise CategoryNameTaken from error
        return created

    async def rename_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
        command: RenameCategoryCommand,
    ) -> tuple[ManagedCategory, bool]:
        """Rename one category. Returns the row and whether it changed.

        Renaming to the name a category already has is accepted and changes
        nothing, so a retried request converges rather than failing.
        """

        async with self._session_factory() as database:
            async with database.begin():
                row = await self._locked_category(
                    database,
                    user_id=user_id,
                    category_id=category_id,
                )
                if row.archived_at is not None:
                    # Renaming a hidden row could resurrect a name collision on
                    # restore, and the user cannot see it anyway. Restore first.
                    raise CategoryArchived
                if row.name == command.name:
                    return _to_managed_one(row), False

                conflict = await database.scalar(
                    _active_name_query(
                        user_id=user_id,
                        direction=row.direction,
                        name=command.name,
                    ).where(FinanceCategoryRow.id != category_id)
                )
                if conflict is not None:
                    raise CategoryNameTaken

                changed_at = _aware_utc(self._clock())
                previous_name = row.name
                command_id = uuid4()
                row.name = command.name
                # A seeded key means "show the translated label". Once the user
                # names it themselves, translating would contradict them.
                row.system_key = None
                database.add_all(
                    [
                        _audit_row(
                            category_id=row.id,
                            user_id=user_id,
                            command_id=command_id,
                            event_type="category_renamed",
                            previous_name=previous_name,
                            new_name=command.name,
                            previous_status="active",
                            new_status="active",
                            created_at=changed_at,
                        ),
                        # Published Home projections store the label they
                        # resolved through this category, so they are stale
                        # until the projector rebuilds them.
                        _outbox_row(
                            category_id=row.id,
                            user_id=user_id,
                            command_id=command_id,
                            created_at=changed_at,
                        ),
                    ]
                )
                renamed = _to_managed_one(row)
        return renamed, True

    async def archive_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        """Hide one category. Returns the row and whether it changed.

        Hiding is the only removal there is: the row survives, so every
        historical operation keeps its grouping (ADR 0020).
        """

        async with self._session_factory() as database:
            async with database.begin():
                row = await self._locked_category(
                    database,
                    user_id=user_id,
                    category_id=category_id,
                )
                if row.archived_at is not None:
                    return _to_managed_one(row), False

                archived_at = _aware_utc(self._clock())
                # created_at can exceed a clock that moved backwards, and the
                # table forbids archiving before creation.
                row.archived_at = max(archived_at, _aware_utc(row.created_at))
                database.add(
                    _audit_row(
                        category_id=row.id,
                        user_id=user_id,
                        event_type="category_archived",
                        previous_name=None,
                        new_name=None,
                        previous_status="active",
                        new_status="archived",
                        created_at=archived_at,
                    )
                )
                archived = _to_managed_one(row)
        return archived, True

    async def restore_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        """Offer a hidden category again. Returns the row and whether it changed."""

        async with self._session_factory() as database:
            async with database.begin():
                row = await self._locked_category(
                    database,
                    user_id=user_id,
                    category_id=category_id,
                )
                if row.archived_at is None:
                    return _to_managed_one(row), False

                # Uniqueness only constrains offered categories, so the name
                # may have been taken while this one was hidden.
                conflict = await database.scalar(
                    _active_name_query(
                        user_id=user_id,
                        direction=row.direction,
                        name=row.name,
                    ).where(FinanceCategoryRow.id != category_id)
                )
                if conflict is not None:
                    raise CategoryNameTaken

                row.archived_at = None
                database.add(
                    _audit_row(
                        category_id=row.id,
                        user_id=user_id,
                        event_type="category_restored",
                        previous_name=None,
                        new_name=None,
                        previous_status="archived",
                        new_status="active",
                        created_at=_aware_utc(self._clock()),
                    )
                )
                restored = _to_managed_one(row)
        return restored, True

    async def _lock_user(self, database: AsyncSession, *, user_id: UUID) -> None:
        active_user = await database.scalar(
            select(UserRow)
            .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
            .with_for_update()
        )
        if active_user is None:
            raise CategoryPersistenceUnavailable

    async def _locked_category(
        self,
        database: AsyncSession,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> FinanceCategoryRow:
        row = await database.scalar(
            select(FinanceCategoryRow)
            .where(
                FinanceCategoryRow.id == category_id,
                # Scoped to the owner, so another user's category is not merely
                # rejected later — it is never loaded at all.
                FinanceCategoryRow.user_id == user_id,
            )
            .with_for_update()
        )
        if row is None:
            raise CategoryNotFound
        return row

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


def _active_name_query(
    *,
    user_id: UUID,
    direction: str,
    name: str,
) -> Select[tuple[FinanceCategoryRow]]:
    """Find the offered category of one direction holding a name.

    Compared case-insensitively, matching the partial unique index. Hidden rows
    are excluded there too, so a hidden name is free to reuse.
    """

    return select(FinanceCategoryRow).where(
        FinanceCategoryRow.user_id == user_id,
        FinanceCategoryRow.direction == direction,
        FinanceCategoryRow.archived_at.is_(None),
        func.lower(FinanceCategoryRow.name) == name.lower(),
    )


def _audit_row(
    *,
    category_id: UUID,
    user_id: UUID,
    event_type: str,
    previous_name: str | None,
    new_name: str | None,
    previous_status: str | None,
    new_status: str,
    created_at: datetime,
    command_id: UUID | None = None,
) -> FinanceCategoryAuditRow:
    return FinanceCategoryAuditRow(
        id=uuid4(),
        category_id=category_id,
        user_id=user_id,
        # Minted here rather than accepted from the client: a catalogue write
        # is idempotent by target state and needs no replay key. It exists to
        # tie one accepted write to the outbox event it produced.
        command_id=command_id if command_id is not None else uuid4(),
        event_type=event_type,
        actor_type="user",
        previous_name=previous_name,
        new_name=new_name,
        previous_status=previous_status,
        new_status=new_status,
        created_at=created_at,
    )


def _outbox_payload(
    *,
    category_id: UUID,
    user_id: UUID,
    command_id: UUID,
) -> dict[str, object]:
    """Identifier-only invalidation.

    The projector rebuilds from authoritative rows and must never learn a fact
    from an event payload (ADR 0011), so the new name is deliberately absent —
    and with it any chance of a stale name being replayed into a projection.
    """

    return {
        "schemaVersion": "1",
        "categoryId": str(category_id),
        "userId": str(user_id),
        "commandId": str(command_id),
    }


def _outbox_row(
    *,
    category_id: UUID,
    user_id: UUID,
    command_id: UUID,
    created_at: datetime,
) -> FinanceCategoryOutboxEventRow:
    return FinanceCategoryOutboxEventRow(
        id=uuid4(),
        aggregate_type="finance_category",
        aggregate_id=category_id,
        user_id=user_id,
        command_id=command_id,
        event_type="finance.category.renamed.v1",
        payload=_outbox_payload(
            category_id=category_id,
            user_id=user_id,
            command_id=command_id,
        ),
        created_at=created_at,
        published_at=None,
        attempt_count=0,
        validation_failure_count=0,
        next_attempt_at=created_at,
        last_failed_at=None,
        failure_code=None,
        dead_lettered_at=None,
    )


def _to_managed(rows: Sequence[FinanceCategoryRow]) -> tuple[ManagedCategory, ...]:
    return tuple(_to_managed_one(row) for row in rows)


def _to_managed_one(row: FinanceCategoryRow) -> ManagedCategory:
    return ManagedCategory(
        category_id=row.id,
        name=row.name,
        direction=row.direction,  # type: ignore[arg-type]
        system_key=row.system_key,
        created_at=row.created_at,
        archived_at=row.archived_at,
    )


def _aware_utc(value: datetime) -> datetime:
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


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

    async def list_managed_categories(
        self,
        *,
        user_id: UUID,
    ) -> ManagedCategoryListResponse:
        del user_id
        raise CategoryPersistenceUnavailable

    async def create_category(
        self,
        *,
        user_id: UUID,
        command: CreateCategoryCommand,
    ) -> ManagedCategory:
        del user_id, command
        raise CategoryPersistenceUnavailable

    async def rename_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
        command: RenameCategoryCommand,
    ) -> tuple[ManagedCategory, bool]:
        del user_id, category_id, command
        raise CategoryPersistenceUnavailable

    async def archive_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        del user_id, category_id
        raise CategoryPersistenceUnavailable

    async def restore_category(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> tuple[ManagedCategory, bool]:
        del user_id, category_id
        raise CategoryPersistenceUnavailable


def _utc_now() -> datetime:
    return datetime.now(UTC)
