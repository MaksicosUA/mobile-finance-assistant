"""Introduce the owned category catalogue and link operations to it.

Revision ID: 0011_category_catalogue
Revises: 0010_savings_goals
Create Date: 2026-08-11

ADR 0020 replaces free-text categories with owned rows an operation references
by identifier. Measured before this migration: 13 operations carried 11 distinct
strings, 9 of them used exactly once, so nothing could be grouped.

The original `finance_operations.category` text is deliberately kept. It is the
only evidence of what the user wrote, and it is what makes a wrong link visible
and correctable.

The backfill carries existing values over as they are: one category per distinct
(user, name, direction). No similarity matching and no merging — reclassifying
someone's records is a decision with its own audit, not something a migration
performs quietly.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011_category_catalogue"
down_revision: str | None = "0010_savings_goals"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# Russian first; the key is what stays stable across languages.
_SEEDED: tuple[tuple[str, str, str], ...] = (
    ("groceries", "Продукты", "expense"),
    ("eating_out", "Кафе и рестораны", "expense"),
    ("transport", "Транспорт", "expense"),
    ("housing", "Жильё", "expense"),
    ("utilities", "Связь и интернет", "expense"),
    ("health", "Здоровье", "expense"),
    ("clothing", "Одежда", "expense"),
    ("entertainment", "Развлечения", "expense"),
    ("education", "Образование", "expense"),
    ("gifts_out", "Подарки", "expense"),
    ("other_expense", "Прочее", "expense"),
    ("salary", "Зарплата", "income"),
    ("freelance", "Подработка", "income"),
    ("gifts_in", "Подарки", "income"),
    ("interest", "Проценты", "income"),
    ("other_income", "Прочее", "income"),
)


def upgrade() -> None:
    op.create_table(
        "finance_categories",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("direction", sa.String(16), nullable=False),
        sa.Column("system_key", sa.String(64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name="pk_finance_categories"),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_finance_categories_user",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("id", "user_id", name="uq_finance_categories_id_user"),
        sa.CheckConstraint(
            "name = btrim(name) AND name <> '' AND name !~ '[[:cntrl:]]'",
            name="ck_finance_categories_name_text",
        ),
        sa.CheckConstraint(
            "direction IN ('expense', 'income')",
            name="ck_finance_categories_direction",
        ),
        sa.CheckConstraint(
            "system_key IS NULL OR system_key ~ '^[a-z][a-z0-9_]{0,62}$'",
            name="ck_finance_categories_system_key",
        ),
        sa.CheckConstraint(
            "archived_at IS NULL OR archived_at >= created_at",
            name="ck_finance_categories_archived_after_created",
        ),
        sa.CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_categories_operational_timestamps",
        ),
    )
    # The point of the catalogue: two spellings of one name cannot become two
    # categories. Archived rows are excluded so a hidden name can be reused.
    op.create_index(
        "uq_finance_categories_active_name",
        "finance_categories",
        ["user_id", "direction", sa.text("lower(name)")],
        unique=True,
        postgresql_where=sa.text("archived_at IS NULL"),
    )
    op.create_index(
        "uq_finance_categories_system_key",
        "finance_categories",
        ["user_id", "system_key"],
        unique=True,
        postgresql_where=sa.text("system_key IS NOT NULL"),
    )
    op.create_index(
        "ix_finance_categories_user_active",
        "finance_categories",
        ["user_id", "direction"],
        postgresql_where=sa.text("archived_at IS NULL"),
    )

    op.add_column(
        "finance_operations",
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_finance_operations_owned_category",
        "finance_operations",
        "finance_categories",
        ["category_id", "user_id"],
        ["id", "user_id"],
    )
    op.create_index(
        "ix_finance_operations_user_category_occurred",
        "finance_operations",
        ["user_id", "category_id", "occurred_on"],
        postgresql_where=sa.text("category_id IS NOT NULL"),
    )

    connection = op.get_bind()

    # Seed every existing user who already has an account, so nobody who
    # bootstrapped before this migration faces an empty picker.
    for system_key, name, direction in _SEEDED:
        connection.execute(
            sa.text(
                """
                INSERT INTO finance_categories
                    (id, user_id, name, direction, system_key, created_at)
                SELECT gen_random_uuid(), a.user_id, :name, :direction,
                       :system_key, now()
                FROM (SELECT DISTINCT user_id FROM finance_accounts) AS a
                ON CONFLICT DO NOTHING
                """
            ),
            {"name": name, "direction": direction, "system_key": system_key},
        )

    # Carry existing free-text values over as they are. A value that collides
    # with a seeded name is absorbed by it rather than duplicated, which is the
    # unique index doing exactly its job.
    connection.execute(
        sa.text(
            """
            INSERT INTO finance_categories
                (id, user_id, name, direction, system_key, created_at)
            SELECT gen_random_uuid(), source.user_id, source.name,
                   source.direction, NULL, now()
            FROM (
                SELECT DISTINCT o.user_id,
                       btrim(o.category) AS name,
                       o.operation_type AS direction
                FROM finance_operations AS o
                WHERE o.category IS NOT NULL AND btrim(o.category) <> ''
            ) AS source
            ON CONFLICT DO NOTHING
            """
        )
    )
    connection.execute(
        sa.text(
            """
            UPDATE finance_operations AS o
            SET category_id = c.id
            FROM finance_categories AS c
            WHERE o.category IS NOT NULL
              AND btrim(o.category) <> ''
              AND c.user_id = o.user_id
              AND c.direction = o.operation_type
              AND c.archived_at IS NULL
              AND lower(c.name) = lower(btrim(o.category))
            """
        )
    )


def downgrade() -> None:
    # Dropping the catalogue with rows present would destroy the grouping every
    # operation already carries, and the previous schema cannot express it at
    # all. Refuse instead of losing it.
    connection = op.get_bind()
    has_categories = bool(
        connection.scalar(sa.text("SELECT EXISTS (SELECT 1 FROM finance_categories)"))
    )
    if has_categories:
        raise RuntimeError("Refusing lossy downgrade: categories exist")

    op.drop_index(
        "ix_finance_operations_user_category_occurred",
        table_name="finance_operations",
    )
    op.drop_constraint(
        "fk_finance_operations_owned_category",
        "finance_operations",
        type_="foreignkey",
    )
    op.drop_column("finance_operations", "category_id")

    op.drop_index("ix_finance_categories_user_active", table_name="finance_categories")
    op.drop_index("uq_finance_categories_system_key", table_name="finance_categories")
    op.drop_index("uq_finance_categories_active_name", table_name="finance_categories")
    op.drop_table("finance_categories")
