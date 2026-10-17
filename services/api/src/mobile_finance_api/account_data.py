"""A person's own data: what they can take with them, and erasing it (ADR 0030).

The export carries every authoritative fact the person owns, **as stored** —
the database's own table and column names — so it cannot drift from the data it
describes. Which tables travel is not remembered but enforced: every table in
the schema is either exported or excluded with a reason, and a test fails the
moment one is neither.
"""

from __future__ import annotations

import csv
import io
from collections.abc import Iterable, Mapping
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Table, delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .database import AsyncSessionFactory
from .db_models import (
    AuthSessionRow,
    Base,
    FinanceAccountRow,
    FinanceCategoryRow,
    FinanceOperationRow,
    UserRow,
    operation_counts,
)
from .passwords import PasswordService

EXPORT_SCHEMA_VERSION = "1"

#: How long a requested erasure waits. Signing in during it cancels the request
#: — the owner chose a week to undo a mistaken tap over erasing at once.
DELETION_GRACE = timedelta(days=7)


def user_tables() -> tuple[Table, ...]:
    """Every table that holds a user's rows, read from the schema itself.

    Found rather than listed, so a table added later is counted and checked
    without anyone remembering to add it here.
    """

    return tuple(
        table
        for table in Base.metadata.sorted_tables
        if "user_id" in table.c and table.name != UserRow.__tablename__
    )


#: Every table the export carries, as stored.
EXPORTED_TABLES: tuple[str, ...] = (
    "users",
    "finance_accounts",
    "finance_operations",
    "finance_operation_reversals",
    "finance_transfers",
    "finance_categories",
    "finance_category_keywords",
    "planned_costs",
    "planned_cost_recurrences",
    "finance_goals",
    "finance_goal_contributions",
    "finance_budgets",
)

#: Columns that never leave, whatever table they sit in.
WITHHELD_COLUMNS: Mapping[str, frozenset[str]] = {
    # A credential, not data: with it someone could test guesses offline.
    "users": frozenset({"password_hash"}),
}

_CREDENTIAL = "a credential: it lets someone act as the person, and is not their data"
_DERIVED = "derived from the exported facts, and rebuilt from them at any time"
_OUTBOX = "an identifier-only notice to the Home projector; it carries no fact"
_AUDIT = "how the exported facts were written; the facts themselves are exported"

#: Every other table in the schema, with the reason it is left out.
EXCLUDED_TABLES: Mapping[str, str] = {
    "auth_sessions": _CREDENTIAL,
    "auth_refresh_tokens": _CREDENTIAL,
    "home_projector_runtime_state": "the projector's own bookkeeping; nobody's data",
    "home_projection_snapshots": _DERIVED,
    "home_projection_actions": _DERIVED,
    "home_projection_primary_goals": _DERIVED,
    "home_projection_recent_transactions": _DERIVED,
    "home_projection_trend_points": _DERIVED,
    "home_projection_upcoming_payments": _DERIVED,
    "home_projection_warnings": _DERIVED,
    "finance_outbox_events": _OUTBOX,
    "finance_account_outbox_events": _OUTBOX,
    "finance_category_outbox_events": _OUTBOX,
    "finance_goal_outbox_events": _OUTBOX,
    "finance_transfer_outbox_events": _OUTBOX,
    "planned_cost_outbox_events": _OUTBOX,
    "finance_account_audit_events": _AUDIT,
    "finance_budget_audit_events": _AUDIT,
    "finance_category_audit_events": _AUDIT,
    "finance_category_keyword_audit_events": _AUDIT,
    "finance_goal_audit_events": _AUDIT,
    "finance_operation_audit_events": _AUDIT,
    "finance_transfer_audit_events": _AUDIT,
    "planned_cost_audit_events": _AUDIT,
    "planned_cost_recurrence_audit_events": _AUDIT,
}

#: One operation as the spreadsheet shows it: its date, direction, amount,
#: currency, wallet, category, merchant, whether it still counts, and when it
#: was recorded.
OperationLine = tuple[
    date, str, Decimal, str, str, str | None, str | None, bool, datetime
]

#: The operations table, for a spreadsheet. Stable English keys: the server has
#: no interface language, and the JSON beside it is the complete record.
OPERATIONS_CSV_COLUMNS: tuple[str, ...] = (
    "date",
    "type",
    "amount",
    "currency",
    "wallet",
    "category",
    "merchant",
    "status",
    "recorded_at",
)


class AccountDataUnavailable(Exception):
    """The authoritative store could not safely produce the person's data."""


class PasswordRejected(Exception):
    """The password given to confirm a destructive request did not match."""


class IncompleteErasure(RuntimeError):
    """Rows for the user were still present after the delete; it was rolled back."""


class PostgresAccountDataRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        passwords: PasswordService | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._passwords = passwords if passwords is not None else PasswordService()

    async def request_deletion(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> datetime:
        """Schedule erasure a week out and sign the person out everywhere.

        The password is asked because an unlocked phone alone must not be enough
        to destroy someone's history. It is checked before the row is locked —
        Argon2 is deliberately slow — and the hash is compared again under the
        lock, so a password changed in between cannot slip through.
        """

        async with self._session_factory() as database:
            stored = await database.scalar(
                select(UserRow.password_hash).where(UserRow.id == user_id)
            )
        if not await self._passwords.verify(password, stored):
            raise PasswordRejected
        due = now + DELETION_GRACE
        async with self._session_factory() as database, database.begin():
            user = await database.scalar(
                select(UserRow).where(UserRow.id == user_id).with_for_update()
            )
            if user is None or user.password_hash != stored:
                raise PasswordRejected
            user.deletion_requested_at = now
            user.deletion_due_at = due
            user.updated_at = now
            # Every bearer request joins its session, so deleting them all is
            # what signs every device out — no separate "blocked" state needed.
            # Refresh tokens hang off their sessions and go with them.
            await database.execute(
                delete(AuthSessionRow).where(AuthSessionRow.user_id == user_id)
            )
        return due

    async def export(
        self, *, user_id: UUID, exported_at: datetime
    ) -> dict[str, object]:
        tables: dict[str, list[dict[str, object]]] = {}
        async with self._session_factory() as database:
            for name in EXPORTED_TABLES:
                table = Base.metadata.tables[name]
                owner = table.c.id if name == UserRow.__tablename__ else table.c.user_id
                withheld = WITHHELD_COLUMNS.get(name, frozenset())
                columns = [column for column in table.c if column.name not in withheld]
                ordering = [table.c.created_at] if "created_at" in table.c else []
                ordering.extend(table.primary_key.columns)
                rows = (
                    await database.execute(
                        select(*columns).where(owner == user_id).order_by(*ordering)
                    )
                ).mappings()
                tables[name] = [
                    {key: plain(value) for key, value in row.items()} for row in rows
                ]
        if len(tables[UserRow.__tablename__]) != 1:
            raise AccountDataUnavailable
        return {
            "schemaVersion": EXPORT_SCHEMA_VERSION,
            "exportedAt": plain(exported_at),
            "tables": tables,
        }

    async def operations_csv(self, *, user_id: UUID) -> str:
        async with self._session_factory() as database:
            rows = (
                await database.execute(
                    select(
                        FinanceOperationRow,
                        FinanceAccountRow.name.label("wallet"),
                        FinanceCategoryRow.name.label("category_name"),
                        operation_counts().label("counts"),
                    )
                    .join(
                        FinanceAccountRow,
                        FinanceAccountRow.id == FinanceOperationRow.account_id,
                    )
                    .outerjoin(
                        FinanceCategoryRow,
                        FinanceCategoryRow.id == FinanceOperationRow.category_id,
                    )
                    .where(FinanceOperationRow.user_id == user_id)
                    .order_by(
                        FinanceOperationRow.occurred_on,
                        FinanceOperationRow.created_at,
                        FinanceOperationRow.id,
                    )
                )
            ).all()
        return operations_table(
            (
                operation.occurred_on,
                operation.operation_type,
                operation.amount,
                operation.currency,
                wallet,
                # The catalogue's name when the operation is linked, the words
                # the person wrote when it is not: never an empty cell where
                # something was said.
                category_name if category_name is not None else operation.category,
                operation.merchant,
                bool(counts),
                operation.created_at,
            )
            for operation, wallet, category_name, counts in rows
        )


class UnavailableAccountDataRepository:
    async def request_deletion(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> datetime:
        del user_id, password, now
        raise AccountDataUnavailable

    async def export(
        self, *, user_id: UUID, exported_at: datetime
    ) -> dict[str, object]:
        del user_id, exported_at
        raise AccountDataUnavailable

    async def operations_csv(self, *, user_id: UUID) -> str:
        del user_id
        raise AccountDataUnavailable


async def erase_user(session: AsyncSession, user_id: UUID) -> dict[str, int]:
    """Erase one person inside the caller's transaction, and prove it.

    One `DELETE` of the user row; every table holding a `user_id` cascades. The
    count is taken again before the transaction commits, so a cascade that
    stopped short raises and rolls everything back instead of committing half an
    erasure. Returns what was removed, per table.
    """

    tables = user_tables()
    removed: dict[str, int] = {}
    for table in tables:
        count = await _count(session, table, user_id)
        if count:
            removed[table.name] = count
    await session.execute(delete(UserRow).where(UserRow.id == user_id))
    remaining = [
        table.name for table in tables if await _count(session, table, user_id)
    ]
    still_there = await session.scalar(
        select(func.count()).select_from(UserRow).where(UserRow.id == user_id)
    )
    if remaining or still_there:
        raise IncompleteErasure(", ".join(sorted(remaining)) or "users")
    return removed


async def erase_due_accounts(
    session_factory: AsyncSessionFactory, *, now: datetime
) -> int:
    """Erase every account whose week has run out. Returns how many.

    Each account in its own transaction, re-checked under its row lock: a
    sign-in that cancelled the request a moment ago must win, and one account
    that cannot be erased must not stop the others from being erased.
    """

    async with session_factory() as database:
        due = list(
            await database.scalars(
                select(UserRow.id).where(UserRow.deletion_due_at <= now)
            )
        )
    erased = 0
    for user_id in due:
        async with session_factory() as database, database.begin():
            still_due = await database.scalar(
                select(UserRow.id)
                .where(UserRow.id == user_id, UserRow.deletion_due_at <= now)
                .with_for_update()
            )
            if still_due is None:
                continue
            await erase_user(database, user_id)
        erased += 1
    return erased


async def _count(session: AsyncSession, table: Table, user_id: UUID) -> int:
    return int(
        await session.scalar(
            select(func.count()).select_from(table).where(table.c.user_id == user_id)
        )
        or 0
    )


def plain(value: object) -> object:
    """A stored value as JSON carries it, without losing what it was."""

    if value is None or isinstance(value, bool | int | str):
        return value
    if isinstance(value, Decimal):
        return _decimal_text(value)
    if isinstance(value, datetime):
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, Mapping):
        return {str(key): plain(item) for key, item in value.items()}
    if isinstance(value, list | tuple):
        return [plain(item) for item in value]
    return str(value)


def operations_table(rows: Iterable[OperationLine]) -> str:
    """The operations, for a spreadsheet in the owner's locale family.

    UTF-8 with a byte-order mark, `;` between fields and a decimal comma: what
    Excel opens without an import dialog in Russian, Ukrainian and German, and
    what Google Sheets opens anywhere. The JSON is the machine-readable record;
    this file is for reading.
    """

    buffer = io.StringIO()
    writer = csv.writer(buffer, delimiter=";", lineterminator="\r\n")
    writer.writerow(OPERATIONS_CSV_COLUMNS)
    for (
        occurred_on,
        operation_type,
        amount,
        currency,
        wallet,
        category,
        merchant,
        counts,
        recorded_at,
    ) in rows:
        writer.writerow(
            (
                occurred_on.isoformat(),
                operation_type,
                _money_cell(amount),
                currency,
                _text_cell(wallet),
                _text_cell(category),
                _text_cell(merchant),
                "active" if counts else "withdrawn",
                plain(recorded_at),
            )
        )
    return "﻿" + buffer.getvalue()


def _decimal_text(value: Decimal) -> str:
    # The columns are NUMERIC(38, 18): 12.5 comes back as 12.500000000000000000.
    # Dropping that padding is exact, and never turns into an exponent.
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return "0" if text in {"", "-0"} else text


def _money_cell(value: Decimal) -> str:
    text = _decimal_text(value)
    whole, _, fraction = text.partition(".")
    # Two decimals when the amount has no more: «12,50», not «12,5».
    if len(fraction) <= 2:
        fraction = fraction.ljust(2, "0")
    return f"{whole},{fraction}"


def _text_cell(value: str | None) -> str:
    """Words the person wrote, made safe to open in a spreadsheet.

    A cell beginning with `=`, `+`, `-`, `@` or a tab is read as a formula, so a
    category typed as «=HYPERLINK(…)» would run when the file is opened. A
    leading apostrophe keeps it text, which is what it was.
    """

    if value is None:
        return ""
    if value[:1] in {"=", "+", "-", "@", "\t", "\r"}:
        return "'" + value
    return value
