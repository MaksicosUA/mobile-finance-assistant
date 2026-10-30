"""Transactional PostgreSQL adapter for monthly budgets (ADR 0027).

The read is the interesting half: a ceiling is stored, and everything measured
against it is computed here from committed operations, using the same period
and the same eligibility predicate the Home projection and Analytics use. Two
definitions of "this month" is how two screens start disagreeing.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert

from .budget_contracts import (
    BudgetLine,
    BudgetPeriod,
    BudgetsResponse,
    RemoveBudgetCommand,
    SetBudgetCommand,
)
from .budget_core import (
    BudgetAccountContext,
    BudgetAccountUnavailable,
    BudgetAlreadyRemoved,
    BudgetCommandConflict,
    BudgetNotFound,
    BudgetPersistenceUnavailable,
    BudgetWriteResult,
)
from .database import AsyncSessionFactory
from .db_models import (
    FinanceAccountRow,
    FinanceBudgetAuditRow,
    FinanceBudgetRow,
    FinanceCategoryRow,
    FinanceOperationRow,
    PlannedCostRow,
    UserRow,
    operation_counts,
)
from .home_projection import reporting_period


class PostgresBudgetRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._clock = clock or _utc_now

    # --- reads ----------------------------------------------------------------

    async def get_account_context(
        self,
        *,
        user_id: UUID,
    ) -> BudgetAccountContext | None:
        async with self._session_factory() as database:
            account = await database.scalar(_default_account(user_id))
        if account is None:
            return None
        return BudgetAccountContext(
            account_id=account.id,
            user_id=account.user_id,
            currency=account.currency,
        )

    async def get_category_direction(
        self,
        *,
        user_id: UUID,
        category_id: UUID,
    ) -> str | None:
        async with self._session_factory() as database:
            category = await database.scalar(
                select(FinanceCategoryRow).where(
                    FinanceCategoryRow.id == category_id,
                    FinanceCategoryRow.user_id == user_id,
                    # Archived, not deleted (ADR 0020): a hidden category keeps
                    # its history but must not carry a new ceiling.
                    FinanceCategoryRow.archived_at.is_(None),
                )
            )
        return None if category is None else category.direction

    async def read_budgets(self, *, user_id: UUID) -> BudgetsResponse:
        async with self._session_factory() as database:
            account = await database.scalar(_default_account(user_id))
            if account is None:
                raise BudgetPersistenceUnavailable

            period = reporting_period(
                timezone_name=account.opening_timezone,
                generated_at=_aware_utc(self._clock()),
            )
            budgets = (
                await database.execute(
                    select(FinanceBudgetRow, FinanceCategoryRow.name)
                    .outerjoin(
                        FinanceCategoryRow,
                        (FinanceCategoryRow.id == FinanceBudgetRow.category_id)
                        & (FinanceCategoryRow.user_id == FinanceBudgetRow.user_id),
                    )
                    .where(
                        FinanceBudgetRow.user_id == user_id,
                        FinanceBudgetRow.status == "active",
                    )
                    .order_by(FinanceBudgetRow.created_at.asc())
                )
            ).all()

            spent_rows = (
                await database.execute(
                    select(
                        FinanceOperationRow.category_id,
                        func.sum(FinanceOperationRow.amount),
                    )
                    .where(
                        FinanceOperationRow.user_id == user_id,
                        # A ceiling is in one currency. Adding another wallet's
                        # amounts to it would add hryvnias to euros (ADR 0029).
                        FinanceOperationRow.account_id == account.id,
                        FinanceOperationRow.status == "confirmed",
                        FinanceOperationRow.operation_type == "expense",
                        FinanceOperationRow.occurred_on >= period.period_start,
                        FinanceOperationRow.occurred_on <= period.period_end,
                        # The same definition of "still counts" every other read
                        # path uses, so a corrected operation cannot be dropped
                        # by one screen and kept by another (ADR 0023).
                        operation_counts(),
                    )
                    .group_by(FinanceOperationRow.category_id)
                )
            ).all()

            planned_rows = (
                await database.execute(
                    select(PlannedCostRow.category_id, func.sum(PlannedCostRow.amount))
                    .where(
                        PlannedCostRow.user_id == user_id,
                        PlannedCostRow.account_id == account.id,
                        # Outstanding only: a plan already confirmed has become
                        # an operation and is counted as spent, not twice.
                        PlannedCostRow.status == "planned",
                        PlannedCostRow.planned_on >= period.period_start,
                        PlannedCostRow.planned_on <= period.period_end,
                    )
                    .group_by(PlannedCostRow.category_id)
                )
            ).all()

        spent = {category_id: total for category_id, total in spent_rows}
        planned = {category_id: total for category_id, total in planned_rows}
        # Uncategorized spending counts against the overall ceiling and against
        # no category budget: the money left, and nobody said where from.
        spent_total = sum(spent.values(), Decimal("0"))
        planned_total = sum(planned.values(), Decimal("0"))

        overall: BudgetLine | None = None
        categories: list[BudgetLine] = []
        for row, name in budgets:
            if row.category_id is None:
                overall = _line(
                    row=row,
                    name=None,
                    spent=spent_total,
                    planned=planned_total,
                )
            else:
                categories.append(
                    _line(
                        row=row,
                        name=name,
                        spent=spent.get(row.category_id, Decimal("0")),
                        planned=planned.get(row.category_id, Decimal("0")),
                    )
                )

        return BudgetsResponse(
            period=BudgetPeriod(
                start=period.period_start,
                end=period.period_end,
            ),
            currency=account.currency,
            overall=overall,
            categories=tuple(categories),
        )

    # --- writes ---------------------------------------------------------------

    async def replay_existing_set(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        return await self._replay(
            user_id=user_id,
            command_id=command_id,
            payload_hash=payload_hash,
        )

    async def replay_existing_removal(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(FinanceBudgetAuditRow).where(
                    FinanceBudgetAuditRow.budget_id == budget_id,
                    FinanceBudgetAuditRow.user_id == user_id,
                    FinanceBudgetAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            if audit.command_payload_hash != payload_hash:
                raise BudgetCommandConflict
            budget = await database.scalar(
                select(FinanceBudgetRow).where(
                    FinanceBudgetRow.id == budget_id,
                    FinanceBudgetRow.user_id == user_id,
                )
            )
        if budget is None:  # pragma: no cover - the audit FK forbids this
            raise BudgetNotFound
        return _write_result(budget, idempotent_replay=True)

    async def set_budget(
        self,
        *,
        user_id: UUID,
        command: SetBudgetCommand,
        payload_hash: bytes,
    ) -> BudgetWriteResult:
        async with self._session_factory() as database:
            async with database.begin():
                active_user = await database.scalar(
                    select(UserRow)
                    .where(UserRow.id == user_id, UserRow.disabled_at.is_(None))
                    .with_for_update()
                )
                if active_user is None:
                    raise BudgetAccountUnavailable
                account = await database.scalar(
                    _default_account(user_id).with_for_update()
                )
                if (
                    account is None
                    or account.id != command.account_id
                    or account.currency != command.currency
                ):
                    raise BudgetAccountUnavailable

                now = _aware_utc(self._clock())
                # Locked so a concurrent set cannot squeeze past the partial
                # unique index and turn a change into a duplicate.
                existing = await database.scalar(
                    select(FinanceBudgetRow)
                    .where(
                        FinanceBudgetRow.user_id == user_id,
                        FinanceBudgetRow.status == "active",
                        FinanceBudgetRow.category_id.is_(command.category_id)
                        if command.category_id is None
                        else FinanceBudgetRow.category_id == command.category_id,
                    )
                    .with_for_update()
                )

                if existing is None:
                    budget_id = uuid4()
                    inserted = await database.scalar(
                        insert(FinanceBudgetRow)
                        .values(
                            id=budget_id,
                            user_id=user_id,
                            account_id=command.account_id,
                            category_id=command.category_id,
                            command_id=command.command_id,
                            command_payload_hash=payload_hash,
                            schema_version=command.schema_version,
                            limit_amount=command.limit,
                            currency=command.currency,
                            status="active",
                            created_at=now,
                            updated_at=now,
                        )
                        .on_conflict_do_nothing(
                            index_elements=["user_id", "command_id"]
                        )
                        .returning(FinanceBudgetRow.id)
                    )
                    if inserted is None:  # pragma: no cover - replay races
                        raise BudgetCommandConflict
                    database.add(
                        FinanceBudgetAuditRow(
                            id=uuid4(),
                            budget_id=budget_id,
                            user_id=user_id,
                            command_id=command.command_id,
                            command_payload_hash=payload_hash,
                            event_type="budget_set",
                            previous_limit=None,
                            new_limit=command.limit,
                            created_at=now,
                        )
                    )
                    return BudgetWriteResult(
                        budget_id=budget_id,
                        category_id=command.category_id,
                        limit=command.limit,
                        idempotent_replay=False,
                    )

                previous = existing.limit_amount
                existing.limit_amount = command.limit
                existing.command_id = command.command_id
                existing.command_payload_hash = payload_hash
                existing.updated_at = now
                database.add(
                    FinanceBudgetAuditRow(
                        id=uuid4(),
                        budget_id=existing.id,
                        user_id=user_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        event_type="budget_changed",
                        previous_limit=previous,
                        new_limit=command.limit,
                        created_at=now,
                    )
                )
                result = BudgetWriteResult(
                    budget_id=existing.id,
                    category_id=existing.category_id,
                    limit=command.limit,
                    idempotent_replay=False,
                )
        return result

    async def remove_budget(
        self,
        *,
        user_id: UUID,
        budget_id: UUID,
        command: RemoveBudgetCommand,
        payload_hash: bytes,
    ) -> BudgetWriteResult:
        async with self._session_factory() as database:
            async with database.begin():
                budget = await database.scalar(
                    select(FinanceBudgetRow)
                    .where(
                        FinanceBudgetRow.id == budget_id,
                        FinanceBudgetRow.user_id == user_id,
                    )
                    .with_for_update()
                )
                if budget is None:
                    raise BudgetNotFound
                if budget.status != "active":
                    raise BudgetAlreadyRemoved

                now = _aware_utc(self._clock())
                previous = budget.limit_amount
                # A status, not a delete: the audit trail keeps pointing at a
                # row that still exists, and the uniqueness rule ignores removed
                # budgets so the category can be given a new ceiling later.
                budget.status = "removed"
                budget.updated_at = now
                database.add(
                    FinanceBudgetAuditRow(
                        id=uuid4(),
                        budget_id=budget.id,
                        user_id=user_id,
                        command_id=command.command_id,
                        command_payload_hash=payload_hash,
                        event_type="budget_removed",
                        previous_limit=previous,
                        new_limit=None,
                        created_at=now,
                    )
                )
                result = BudgetWriteResult(
                    budget_id=budget.id,
                    category_id=budget.category_id,
                    limit=previous,
                    idempotent_replay=False,
                )
        return result

    async def _replay(
        self,
        *,
        user_id: UUID,
        command_id: UUID,
        payload_hash: bytes,
    ) -> BudgetWriteResult | None:
        async with self._session_factory() as database:
            audit = await database.scalar(
                select(FinanceBudgetAuditRow).where(
                    FinanceBudgetAuditRow.user_id == user_id,
                    FinanceBudgetAuditRow.command_id == command_id,
                )
            )
            if audit is None:
                return None
            if audit.command_payload_hash != payload_hash:
                raise BudgetCommandConflict
            budget = await database.scalar(
                select(FinanceBudgetRow).where(
                    FinanceBudgetRow.id == audit.budget_id,
                    FinanceBudgetRow.user_id == user_id,
                )
            )
        if budget is None:  # pragma: no cover - the audit FK forbids this
            raise BudgetNotFound
        return _write_result(budget, idempotent_replay=True)


def _default_account(user_id: UUID):  # type: ignore[no-untyped-def]
    return select(FinanceAccountRow).where(
        FinanceAccountRow.user_id == user_id,
        FinanceAccountRow.status == "active",
        FinanceAccountRow.is_default.is_(True),
    )


def _line(
    *,
    row: FinanceBudgetRow,
    name: str | None,
    spent: Decimal,
    planned: Decimal,
) -> BudgetLine:
    remaining = row.limit_amount - spent
    return BudgetLine(
        budget_id=row.id,
        category_id=row.category_id,
        name=name,
        limit=row.limit_amount,
        spent=spent,
        remaining=remaining,
        planned=planned,
        overspent=remaining < 0,
    )


def _write_result(
    row: FinanceBudgetRow,
    *,
    idempotent_replay: bool,
) -> BudgetWriteResult:
    return BudgetWriteResult(
        budget_id=row.id,
        category_id=row.category_id,
        limit=row.limit_amount,
        idempotent_replay=idempotent_replay,
    )


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
