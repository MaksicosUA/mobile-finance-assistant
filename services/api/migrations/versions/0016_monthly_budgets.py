"""Add monthly spending ceilings per category and one overall.

Revision ID: 0016_monthly_budgets
Revises: 0015_recurring_planned_costs
Create Date: 2026-09-01

ADR 0027 stores a ceiling and nothing else: what has been spent against it is
derived from committed operations at read time, like a goal's balance and a
plan's due state. There is no projection and no outbox — a ceiling is not a
fact anyone else derives from.

A budget with no category is the overall monthly ceiling. Two partial unique
indexes say the rule: at most one per category, at most one overall, and both
ignore removed budgets so a category can be given a new ceiling later.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0016_monthly_budgets"
down_revision: str | None = "0015_recurring_planned_costs"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SUPPORTED_TIMESTAMP_RANGE = (
    "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
    "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'"
)


def upgrade() -> None:
    op.create_table(
        "finance_budgets",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("account_id", sa.Uuid(as_uuid=True), nullable=False),
        # Null is the overall monthly ceiling rather than a missing value.
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=True),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("schema_version", sa.String(16), nullable=False),
        sa.Column("limit_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_budgets_schema_version",
        ),
        sa.CheckConstraint(
            "limit_amount > 0 AND limit_amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_budgets_positive_finite_limit",
        ),
        sa.CheckConstraint(
            "currency = 'EUR'",
            name="ck_finance_budgets_v1_currency",
        ),
        sa.CheckConstraint(
            "status IN ('active', 'removed')",
            name="ck_finance_budgets_status",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_budgets_payload_hash_length",
        ),
        sa.CheckConstraint(
            f"updated_at >= created_at AND {_SUPPORTED_TIMESTAMP_RANGE} "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_budgets_operational_timestamps",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_budgets_user_command",
        ),
        sa.UniqueConstraint("id", "user_id", name="uq_finance_budgets_id_user"),
        sa.ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_budgets_owned_account_currency",
        ),
        sa.ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_budgets_owned_category",
        ),
    )
    # At most one live ceiling per category…
    op.create_index(
        "uq_finance_budgets_active_category",
        "finance_budgets",
        ["user_id", "category_id"],
        unique=True,
        postgresql_where=sa.text("category_id IS NOT NULL AND status = 'active'"),
    )
    # …and at most one overall. A plain unique would not say this: PostgreSQL
    # treats NULLs as distinct, so every overall ceiling would be allowed.
    op.create_index(
        "uq_finance_budgets_active_overall",
        "finance_budgets",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("category_id IS NULL AND status = 'active'"),
    )

    op.create_table(
        "finance_budget_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("budget_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("previous_limit", sa.Numeric(38, 18), nullable=True),
        sa.Column("new_limit", sa.Numeric(38, 18), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "event_type IN ('budget_set', 'budget_changed', 'budget_removed')",
            name="ck_finance_budget_audit_event_type",
        ),
        sa.CheckConstraint(
            "(event_type = 'budget_set' AND previous_limit IS NULL "
            "AND new_limit IS NOT NULL) OR "
            "(event_type = 'budget_changed' AND previous_limit IS NOT NULL "
            "AND new_limit IS NOT NULL) OR "
            "(event_type = 'budget_removed' AND previous_limit IS NOT NULL "
            "AND new_limit IS NULL)",
            name="ck_finance_budget_audit_limits",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_budget_audit_hash_length",
        ),
        sa.CheckConstraint(
            _SUPPORTED_TIMESTAMP_RANGE,
            name="ck_finance_budget_audit_operational_timestamps",
        ),
        sa.ForeignKeyConstraint(
            ["budget_id", "user_id"],
            ["finance_budgets.id", "finance_budgets.user_id"],
            ondelete="CASCADE",
            name="fk_finance_budget_audit_owned_budget",
        ),
        sa.UniqueConstraint(
            "budget_id",
            "command_id",
            name="uq_finance_budget_audit_budget_command",
        ),
    )
    op.create_index(
        "ix_finance_budget_audit_user_created",
        "finance_budget_audit_events",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    # A ceiling is a declaration, not a financial fact, so losing one loses no
    # money — but it does lose something the user set deliberately, and the
    # earlier schema cannot hold it.
    connection = op.get_bind()
    has_budgets = bool(
        connection.scalar(sa.text("SELECT EXISTS (SELECT 1 FROM finance_budgets)"))
    )
    if has_budgets:
        raise RuntimeError("Refusing lossy downgrade: budgets exist")

    op.drop_index(
        "ix_finance_budget_audit_user_created",
        table_name="finance_budget_audit_events",
    )
    op.drop_table("finance_budget_audit_events")
    op.drop_index(
        "uq_finance_budgets_active_overall",
        table_name="finance_budgets",
    )
    op.drop_index(
        "uq_finance_budgets_active_category",
        table_name="finance_budgets",
    )
    op.drop_table("finance_budgets")
