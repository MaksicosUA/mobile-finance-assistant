"""Add recurrence rules for planned costs and link plans to the catalogue.

Revision ID: 0015_recurring_planned_costs
Revises: 0014_operation_reversals
Create Date: 2026-08-31

ADR 0025 models a repeating plan as a rule that generates ordinary
``planned_costs`` rows, so the lifecycle already built for a one-off plan keeps
working unchanged. Two tables arrive: the rule and its audit trail. No new
outbox table and no new event type — a generated instance *is* a planned cost,
so the existing invalidations describe it exactly.

``planned_costs`` also joins the category catalogue here (ADR 0020). It was the
last financial row still carrying only free text, and a rule that writes free
text writes it every month forever. The two existing plans are left as they
are: matching their text against the catalogue would be a guess.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0015_recurring_planned_costs"
down_revision: str | None = "0014_operation_reversals"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SUPPORTED_TIMESTAMP_RANGE = (
    "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
    "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'"
)


def upgrade() -> None:
    op.create_table(
        "planned_cost_recurrences",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("account_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("schema_version", sa.String(16), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("category", sa.String(100), nullable=True),
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=True),
        sa.Column("frequency", sa.String(16), nullable=False),
        # The day the user meant, stored unclamped: 31 stays 31, and each
        # occurrence shortens it into its own month at generation time.
        sa.Column("day_of_month", sa.SmallInteger(), nullable=False),
        sa.Column("starts_on", sa.Date(), nullable=False),
        sa.Column("ends_on", sa.Date(), nullable=True),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_planned_cost_recurrences_schema_version",
        ),
        sa.CheckConstraint(
            "amount > 0 AND amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_planned_cost_recurrences_positive_finite_amount",
        ),
        sa.CheckConstraint(
            "currency = 'EUR'",
            name="ck_planned_cost_recurrences_v1_currency",
        ),
        sa.CheckConstraint(
            "title = btrim(title) AND title <> '' AND title !~ '[[:cntrl:]]' AND "
            "(category IS NULL OR (category = btrim(category) AND "
            "category <> '' AND category !~ '[[:cntrl:]]'))",
            name="ck_planned_cost_recurrences_text",
        ),
        sa.CheckConstraint(
            "frequency = 'monthly'",
            name="ck_planned_cost_recurrences_frequency",
        ),
        sa.CheckConstraint(
            "day_of_month BETWEEN 1 AND 31",
            name="ck_planned_cost_recurrences_day_of_month",
        ),
        sa.CheckConstraint(
            "starts_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31' AND "
            "(ends_on IS NULL OR "
            "(ends_on >= starts_on AND "
            "ends_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'))",
            name="ck_planned_cost_recurrences_dates",
        ),
        sa.CheckConstraint(
            "status IN ('active', 'ended')",
            name="ck_planned_cost_recurrences_status",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_planned_cost_recurrences_payload_hash_length",
        ),
        sa.CheckConstraint(
            f"updated_at >= created_at AND {_SUPPORTED_TIMESTAMP_RANGE} "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_planned_cost_recurrences_operational_timestamps",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_planned_cost_recurrences_user_command",
        ),
        sa.UniqueConstraint(
            "id",
            "user_id",
            name="uq_planned_cost_recurrences_id_user",
        ),
        sa.ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_planned_cost_recurrences_owned_account_currency",
        ),
        sa.ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_planned_cost_recurrences_owned_category",
        ),
    )
    op.create_index(
        "ix_planned_cost_recurrences_user_active",
        "planned_cost_recurrences",
        ["user_id"],
        postgresql_where=sa.text("status = 'active'"),
    )

    op.create_table(
        "planned_cost_recurrence_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("recurrence_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("previous_status", sa.String(16), nullable=True),
        sa.Column("new_status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "event_type IN ('recurrence_created', 'recurrence_ended')",
            name="ck_planned_cost_recurrence_audit_event_type",
        ),
        sa.CheckConstraint(
            "(event_type = 'recurrence_created' AND previous_status IS NULL "
            "AND new_status = 'active') OR "
            "(event_type = 'recurrence_ended' AND previous_status = 'active' "
            "AND new_status = 'ended')",
            name="ck_planned_cost_recurrence_audit_transition",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_planned_cost_recurrence_audit_hash_length",
        ),
        sa.CheckConstraint(
            _SUPPORTED_TIMESTAMP_RANGE,
            name="ck_planned_cost_recurrence_audit_operational_timestamps",
        ),
        sa.ForeignKeyConstraint(
            ["recurrence_id", "user_id"],
            [
                "planned_cost_recurrences.id",
                "planned_cost_recurrences.user_id",
            ],
            ondelete="CASCADE",
            name="fk_planned_cost_recurrence_audit_owned_recurrence",
        ),
        sa.UniqueConstraint(
            "recurrence_id",
            "command_id",
            name="uq_planned_cost_recurrence_audit_recurrence_command",
        ),
    )
    op.create_index(
        "uq_planned_cost_recurrence_audit_single_create",
        "planned_cost_recurrence_audit_events",
        ["recurrence_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'recurrence_created'"),
    )
    op.create_index(
        "uq_planned_cost_recurrence_audit_single_end",
        "planned_cost_recurrence_audit_events",
        ["recurrence_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'recurrence_ended'"),
    )
    op.create_index(
        "ix_planned_cost_recurrence_audit_user_created",
        "planned_cost_recurrence_audit_events",
        ["user_id", "created_at"],
    )

    op.add_column(
        "planned_costs",
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=True),
    )
    op.add_column(
        "planned_costs",
        sa.Column("recurrence_id", sa.Uuid(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_planned_costs_owned_category",
        "planned_costs",
        "finance_categories",
        ["category_id", "user_id"],
        ["id", "user_id"],
    )
    op.create_foreign_key(
        "fk_planned_costs_owned_recurrence",
        "planned_costs",
        "planned_cost_recurrences",
        ["recurrence_id", "user_id"],
        ["id", "user_id"],
    )
    # One live instance per rule per date. This index, not the generator's own
    # care, is what makes materialisation idempotent under a retry, a restart,
    # or two leaders briefly overlapping. Cancelled rows are excluded so editing
    # a rule can regenerate a date it has just superseded.
    op.create_index(
        "uq_planned_costs_recurrence_occurrence",
        "planned_costs",
        ["recurrence_id", "planned_on"],
        unique=True,
        postgresql_where=sa.text("recurrence_id IS NOT NULL AND status <> 'cancelled'"),
    )
    op.create_index(
        "ix_planned_costs_recurrence",
        "planned_costs",
        ["recurrence_id"],
        postgresql_where=sa.text("recurrence_id IS NOT NULL"),
    )


def downgrade() -> None:
    # The earlier schema can represent neither a rule nor a plan's link into the
    # catalogue. Going back with either present would silently discard them, and
    # a category link cannot be rebuilt from the free text beside it — that text
    # is what the user wrote, not what they chose.
    connection = op.get_bind()
    has_recurrences = bool(
        connection.scalar(
            sa.text("SELECT EXISTS (SELECT 1 FROM planned_cost_recurrences)")
        )
    )
    if has_recurrences:
        raise RuntimeError("Refusing lossy downgrade: recurrence rules exist")
    has_linked_plans = bool(
        connection.scalar(
            sa.text(
                "SELECT EXISTS (SELECT 1 FROM planned_costs "
                "WHERE category_id IS NOT NULL)"
            )
        )
    )
    if has_linked_plans:
        raise RuntimeError("Refusing lossy downgrade: categorised plans exist")

    op.drop_index("ix_planned_costs_recurrence", table_name="planned_costs")
    op.drop_index(
        "uq_planned_costs_recurrence_occurrence",
        table_name="planned_costs",
    )
    op.drop_constraint(
        "fk_planned_costs_owned_recurrence",
        "planned_costs",
        type_="foreignkey",
    )
    op.drop_constraint(
        "fk_planned_costs_owned_category",
        "planned_costs",
        type_="foreignkey",
    )
    op.drop_column("planned_costs", "recurrence_id")
    op.drop_column("planned_costs", "category_id")

    op.drop_index(
        "ix_planned_cost_recurrence_audit_user_created",
        table_name="planned_cost_recurrence_audit_events",
    )
    op.drop_index(
        "uq_planned_cost_recurrence_audit_single_end",
        table_name="planned_cost_recurrence_audit_events",
    )
    op.drop_index(
        "uq_planned_cost_recurrence_audit_single_create",
        table_name="planned_cost_recurrence_audit_events",
    )
    op.drop_table("planned_cost_recurrence_audit_events")
    op.drop_index(
        "ix_planned_cost_recurrences_user_active",
        table_name="planned_cost_recurrences",
    )
    op.drop_table("planned_cost_recurrences")
