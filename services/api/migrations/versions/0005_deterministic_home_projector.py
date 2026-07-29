"""Make Home projection fields preserve authoritative operation truth.

Revision ID: 0005_home_projector
Revises: 0004_authoritative_accounts
Create Date: 2026-07-28
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0005_home_projector"
down_revision: str | None = "0004_authoritative_accounts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_RECENT_TRANSACTIONS = "home_projection_recent_transactions"
_SNAPSHOTS = "home_projection_snapshots"


def upgrade() -> None:
    op.add_column(
        _SNAPSHOTS,
        sa.Column(
            "projection_schema_version",
            sa.SmallInteger(),
            nullable=False,
            server_default="1",
        ),
    )
    op.create_check_constraint(
        "ck_home_projection_snapshots_schema_version",
        _SNAPSHOTS,
        "projection_schema_version > 0",
    )
    op.alter_column(
        _SNAPSHOTS,
        "balance_delta_percent",
        existing_type=sa.Numeric(38, 18),
        nullable=True,
    )

    op.add_column(
        _RECENT_TRANSACTIONS,
        sa.Column("occurred_on", sa.Date(), nullable=True),
    )
    op.add_column(
        _RECENT_TRANSACTIONS,
        sa.Column("position", sa.SmallInteger(), nullable=True),
    )

    op.drop_index(
        "ix_home_projection_recent_transactions_order",
        table_name=_RECENT_TRANSACTIONS,
    )
    op.drop_constraint(
        "ck_home_projection_recent_transactions_text",
        _RECENT_TRANSACTIONS,
        type_="check",
    )
    op.alter_column(
        _RECENT_TRANSACTIONS,
        "title",
        existing_type=sa.String(length=160),
        nullable=True,
    )
    op.alter_column(
        _RECENT_TRANSACTIONS,
        "category",
        existing_type=sa.String(length=160),
        nullable=True,
    )
    op.alter_column(
        _RECENT_TRANSACTIONS,
        "occurred_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=True,
    )
    op.create_check_constraint(
        "ck_home_projection_recent_transactions_text",
        _RECENT_TRANSACTIONS,
        "btrim(transaction_id) <> '' "
        "AND (title IS NULL OR btrim(title) <> '') "
        "AND (category IS NULL OR btrim(category) <> '') "
        "AND btrim(direction) <> ''",
    )
    op.create_check_constraint(
        "ck_home_projection_recent_transactions_position",
        _RECENT_TRANSACTIONS,
        "position IS NULL OR position BETWEEN 0 AND 2",
    )
    op.create_unique_constraint(
        "uq_home_projection_recent_transactions_position",
        _RECENT_TRANSACTIONS,
        ["snapshot_id", "position"],
    )


def downgrade() -> None:
    op.execute(
        sa.text(
            "DO $migration$ "
            "BEGIN "
            "IF EXISTS ("
            "SELECT 1 FROM home_projection_snapshots "
            "WHERE balance_delta_percent IS NULL"
            ") OR EXISTS ("
            "SELECT 1 FROM home_projection_recent_transactions "
            "WHERE title IS NULL OR category IS NULL OR occurred_at IS NULL "
            "OR position IS NOT NULL"
            ") OR EXISTS ("
            "SELECT 1 FROM home_projection_recent_transactions AS recent "
            "JOIN home_projection_snapshots AS snapshots "
            "ON snapshots.id = recent.snapshot_id "
            "WHERE recent.occurred_on IS NOT NULL "
            "AND recent.occurred_on <> "
            "(recent.occurred_at AT TIME ZONE snapshots.timezone_name)::date"
            ") THEN "
            "RAISE EXCEPTION 'Refusing lossy downgrade: Home projection "
            "contains values that the previous schema cannot represent'; "
            "END IF; "
            "END $migration$"
        )
    )

    op.drop_constraint(
        "uq_home_projection_recent_transactions_position",
        _RECENT_TRANSACTIONS,
        type_="unique",
    )
    op.drop_constraint(
        "ck_home_projection_recent_transactions_position",
        _RECENT_TRANSACTIONS,
        type_="check",
    )
    op.drop_constraint(
        "ck_home_projection_recent_transactions_text",
        _RECENT_TRANSACTIONS,
        type_="check",
    )
    op.alter_column(
        _RECENT_TRANSACTIONS,
        "title",
        existing_type=sa.String(length=160),
        nullable=False,
    )
    op.alter_column(
        _RECENT_TRANSACTIONS,
        "category",
        existing_type=sa.String(length=160),
        nullable=False,
    )
    op.alter_column(
        _RECENT_TRANSACTIONS,
        "occurred_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
    )
    op.alter_column(
        _SNAPSHOTS,
        "balance_delta_percent",
        existing_type=sa.Numeric(38, 18),
        nullable=False,
    )
    op.create_check_constraint(
        "ck_home_projection_recent_transactions_text",
        _RECENT_TRANSACTIONS,
        "btrim(transaction_id) <> '' AND btrim(title) <> '' "
        "AND btrim(category) <> '' AND btrim(direction) <> ''",
    )
    op.create_index(
        "ix_home_projection_recent_transactions_order",
        _RECENT_TRANSACTIONS,
        ["snapshot_id", "occurred_at", "transaction_id"],
        unique=False,
    )
    op.drop_column(_RECENT_TRANSACTIONS, "position")
    op.drop_column(_RECENT_TRANSACTIONS, "occurred_on")
    op.drop_constraint(
        "ck_home_projection_snapshots_schema_version",
        _SNAPSHOTS,
        type_="check",
    )
    op.drop_column(_SNAPSHOTS, "projection_schema_version")
