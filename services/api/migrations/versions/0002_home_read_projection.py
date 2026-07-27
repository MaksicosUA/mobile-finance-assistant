"""Create the versioned PostgreSQL Home read projection.

Revision ID: 0002_home_read_projection
Revises: 0001_auth_accounts
Create Date: 2026-07-26
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002_home_read_projection"
down_revision: str | None = "0001_auth_accounts"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SPECIAL_NUMERICS = "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"


def _finite(*columns: str) -> str:
    return " AND ".join(f"{column} NOT IN {_SPECIAL_NUMERICS}" for column in columns)


def upgrade() -> None:
    op.create_table(
        "home_projection_snapshots",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("timezone_name", sa.String(length=128), nullable=False),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("data_as_of", sa.DateTime(timezone=True), nullable=False),
        sa.Column("base_currency", sa.String(length=3), nullable=False),
        sa.Column("balance_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("balance_delta_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("balance_delta_percent", sa.Numeric(38, 18), nullable=False),
        sa.Column("month_income", sa.Numeric(38, 18), nullable=False),
        sa.Column("month_expense", sa.Numeric(38, 18), nullable=False),
        sa.Column("month_net_flow", sa.Numeric(38, 18), nullable=False),
        sa.Column("trend_metric", sa.String(length=64), nullable=False),
        sa.Column("trend_period", sa.String(length=64), nullable=False),
        sa.Column("trend_total", sa.Numeric(38, 18), nullable=False),
        sa.CheckConstraint(
            "EXTRACT(DAY FROM period_start) = 1 AND "
            "period_end = "
            "(period_start + INTERVAL '1 month' - INTERVAL '1 day')::date",
            name="ck_home_projection_snapshots_month_boundaries",
        ),
        sa.CheckConstraint(
            "revision > 0",
            name="ck_home_projection_snapshots_revision_positive",
        ),
        sa.CheckConstraint(
            "data_as_of <= generated_at",
            name="ck_home_projection_snapshots_timestamp_order",
        ),
        sa.CheckConstraint(
            "base_currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_snapshots_base_currency",
        ),
        sa.CheckConstraint(
            "timezone_name = btrim(timezone_name) AND timezone_name <> '' "
            "AND timezone_name !~ '[[:cntrl:]]'",
            name="ck_home_projection_snapshots_timezone_name",
        ),
        sa.CheckConstraint(
            "month_income >= 0 AND month_expense >= 0 AND "
            "month_net_flow = month_income - month_expense",
            name="ck_home_projection_snapshots_month_summary",
        ),
        sa.CheckConstraint(
            "trend_metric <> 'expense' OR trend_total >= 0",
            name="ck_home_projection_snapshots_expense_trend_total",
        ),
        sa.CheckConstraint(
            "btrim(trend_metric) <> '' AND btrim(trend_period) <> ''",
            name="ck_home_projection_snapshots_trend_values",
        ),
        sa.CheckConstraint(
            _finite(
                "balance_amount",
                "balance_delta_amount",
                "balance_delta_percent",
                "month_income",
                "month_expense",
                "month_net_flow",
                "trend_total",
            ),
            name="ck_home_projection_snapshots_finite_decimals",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "timezone_name",
            "period_start",
            "revision",
            name="uq_home_projection_snapshots_user_timezone_period_revision",
        ),
    )
    op.create_table(
        "home_projection_trend_points",
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("point_date", sa.Date(), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.CheckConstraint(
            _finite("amount"),
            name="ck_home_projection_trend_points_finite_amount",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["home_projection_snapshots.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id", "point_date"),
    )
    op.create_table(
        "home_projection_primary_goals",
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("goal_id", sa.String(length=128), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("current_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("target_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("monthly_contribution", sa.Numeric(38, 18), nullable=False),
        sa.Column("current_base_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("target_base_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column(
            "monthly_contribution_base_amount",
            sa.Numeric(38, 18),
            nullable=False,
        ),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("progress_percent", sa.Numeric(38, 18), nullable=False),
        sa.CheckConstraint(
            "btrim(goal_id) <> '' AND btrim(title) <> ''",
            name="ck_home_projection_primary_goals_text",
        ),
        sa.CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_primary_goals_currency",
        ),
        sa.CheckConstraint(
            _finite(
                "current_amount",
                "target_amount",
                "monthly_contribution",
                "current_base_amount",
                "target_base_amount",
                "monthly_contribution_base_amount",
                "progress_percent",
            ),
            name="ck_home_projection_primary_goals_finite_decimals",
        ),
        sa.CheckConstraint(
            "current_amount >= 0 AND target_amount > 0 AND "
            "monthly_contribution >= 0 AND current_base_amount >= 0 AND "
            "target_base_amount > 0 AND "
            "monthly_contribution_base_amount >= 0 AND "
            "progress_percent BETWEEN 0 AND 100",
            name="ck_home_projection_primary_goals_bounds",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["home_projection_snapshots.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id"),
    )
    op.create_table(
        "home_projection_upcoming_payments",
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("payment_id", sa.String(length=128), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("base_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("status", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "btrim(payment_id) <> '' AND btrim(title) <> '' AND btrim(status) <> ''",
            name="ck_home_projection_upcoming_payments_text",
        ),
        sa.CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_upcoming_payments_currency",
        ),
        sa.CheckConstraint(
            _finite("amount", "base_amount"),
            name="ck_home_projection_upcoming_payments_finite_amounts",
        ),
        sa.CheckConstraint(
            "amount >= 0 AND base_amount >= 0",
            name="ck_home_projection_upcoming_payments_nonnegative_amounts",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["home_projection_snapshots.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id", "payment_id"),
    )
    op.create_index(
        "ix_home_projection_upcoming_payments_order",
        "home_projection_upcoming_payments",
        ["snapshot_id", "due_at", "payment_id"],
        unique=False,
    )
    op.create_table(
        "home_projection_recent_transactions",
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("transaction_id", sa.String(length=128), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("category", sa.String(length=160), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("base_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("direction", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "btrim(transaction_id) <> '' AND btrim(title) <> '' "
            "AND btrim(category) <> '' AND btrim(direction) <> ''",
            name="ck_home_projection_recent_transactions_text",
        ),
        sa.CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_recent_transactions_currency",
        ),
        sa.CheckConstraint(
            "status = 'confirmed'",
            name="ck_home_projection_recent_transactions_confirmed",
        ),
        sa.CheckConstraint(
            _finite("amount", "base_amount"),
            name="ck_home_projection_recent_transactions_finite_amounts",
        ),
        sa.CheckConstraint(
            "(direction <> 'income' OR (amount >= 0 AND base_amount >= 0)) "
            "AND (direction <> 'expense' OR "
            "(amount <= 0 AND base_amount <= 0)) "
            "AND amount * base_amount >= 0",
            name="ck_home_projection_recent_transactions_direction_sign",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["home_projection_snapshots.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id", "transaction_id"),
    )
    op.create_index(
        "ix_home_projection_recent_transactions_order",
        "home_projection_recent_transactions",
        ["snapshot_id", "occurred_at", "transaction_id"],
        unique=False,
    )
    op.create_table(
        "home_projection_actions",
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "position BETWEEN 0 AND 15",
            name="ck_home_projection_actions_position",
        ),
        sa.CheckConstraint(
            "btrim(action) <> ''",
            name="ck_home_projection_actions_text",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["home_projection_snapshots.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id", "position"),
        sa.UniqueConstraint(
            "snapshot_id",
            "action",
            name="uq_home_projection_actions_snapshot_action",
        ),
    )
    op.create_table(
        "home_projection_warnings",
        sa.Column("snapshot_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("block", sa.String(length=64), nullable=False),
        sa.CheckConstraint(
            "position BETWEEN 0 AND 15",
            name="ck_home_projection_warnings_position",
        ),
        sa.CheckConstraint(
            "btrim(code) <> '' AND btrim(block) <> ''",
            name="ck_home_projection_warnings_text",
        ),
        sa.ForeignKeyConstraint(
            ["snapshot_id"],
            ["home_projection_snapshots.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("snapshot_id", "position"),
    )


def downgrade() -> None:
    op.drop_table("home_projection_warnings")
    op.drop_table("home_projection_actions")
    op.drop_index(
        "ix_home_projection_recent_transactions_order",
        table_name="home_projection_recent_transactions",
    )
    op.drop_table("home_projection_recent_transactions")
    op.drop_index(
        "ix_home_projection_upcoming_payments_order",
        table_name="home_projection_upcoming_payments",
    )
    op.drop_table("home_projection_upcoming_payments")
    op.drop_table("home_projection_primary_goals")
    op.drop_table("home_projection_trend_points")
    op.drop_table("home_projection_snapshots")
