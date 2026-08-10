"""Introduce forecast-only planned costs with audit and invalidation.

Revision ID: 0008_planned_costs
Revises: 0007_correctable_baseline
Create Date: 2026-08-10

ADR 0018 models an intended future payment as its own entity rather than as a
future-dated operation, because a confirmed operation moves the authoritative
balance and a forecast must not. Three tables are added: the plan itself, its
append-only audit trail, and a separate identifier-only outbox the Home
projector will consume once the upcoming-payments slice lands.

`finance_operations` also gains a `(id, user_id)` unique constraint so a plan
can reference the operation that settled it together with its owner, making a
cross-user link unrepresentable.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008_planned_costs"
down_revision: str | None = "0007_correctable_baseline"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SUPPORTED_TIMESTAMP_RANGE = (
    "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
    "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'"
)


def upgrade() -> None:
    op.create_unique_constraint(
        "uq_finance_operations_id_user",
        "finance_operations",
        ["id", "user_id"],
    )

    op.create_table(
        "planned_costs",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("account_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("schema_version", sa.String(16), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("category", sa.String(100), nullable=True),
        sa.Column("planned_on", sa.Date(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("confirmed_operation_id", sa.Uuid(as_uuid=True), nullable=True),
        sa.Column(
            "confirmed_operation_command_id",
            sa.Uuid(as_uuid=True),
            nullable=True,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_planned_costs"),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_planned_costs_user",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_planned_costs_owned_account_currency",
        ),
        # NO ACTION rather than RESTRICT: deleting a user cascades to both
        # finance_operations and planned_costs within one statement, and the
        # check is deferred to the end of that statement so it still completes.
        sa.ForeignKeyConstraint(
            ["confirmed_operation_id", "user_id"],
            ["finance_operations.id", "finance_operations.user_id"],
            name="fk_planned_costs_confirmed_operation",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_planned_costs_user_command",
        ),
        sa.UniqueConstraint("id", "user_id", name="uq_planned_costs_id_user"),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_planned_costs_schema_version",
        ),
        sa.CheckConstraint(
            "amount > 0 AND amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_planned_costs_positive_finite_amount",
        ),
        sa.CheckConstraint("currency = 'EUR'", name="ck_planned_costs_v1_currency"),
        sa.CheckConstraint(
            "title = btrim(title) AND title <> '' AND title !~ '[[:cntrl:]]' AND "
            "(category IS NULL OR (category = btrim(category) AND "
            "category <> '' AND category !~ '[[:cntrl:]]'))",
            name="ck_planned_costs_text",
        ),
        sa.CheckConstraint(
            "planned_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_planned_costs_planned_on_range",
        ),
        sa.CheckConstraint(
            "status IN ('planned', 'confirmed', 'skipped', 'cancelled')",
            name="ck_planned_costs_status",
        ),
        sa.CheckConstraint(
            "(status = 'confirmed') = (confirmed_operation_id IS NOT NULL) AND "
            "(status = 'confirmed') = (confirmed_operation_command_id IS NOT NULL)",
            name="ck_planned_costs_confirmation_link",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_planned_costs_payload_hash_length",
        ),
        sa.CheckConstraint(
            f"updated_at >= created_at AND {_SUPPORTED_TIMESTAMP_RANGE} "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_planned_costs_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_planned_costs_user_planned_on",
        "planned_costs",
        ["user_id", "planned_on"],
    )
    op.create_index(
        "ix_planned_costs_user_outstanding",
        "planned_costs",
        ["user_id", "planned_on"],
        postgresql_where=sa.text("status = 'planned'"),
    )

    op.create_table(
        "planned_cost_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("planned_cost_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("actor_type", sa.String(16), nullable=False),
        sa.Column("payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("previous_status", sa.String(16), nullable=True),
        sa.Column("new_status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_planned_cost_audit_events"),
        sa.ForeignKeyConstraint(
            ["planned_cost_id", "user_id"],
            ["planned_costs.id", "planned_costs.user_id"],
            name="fk_planned_cost_audit_plan",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "planned_cost_id",
            "command_id",
            name="uq_planned_cost_audit_plan_command",
        ),
        sa.CheckConstraint(
            "event_type IN ('planned_cost_created', 'planned_cost_confirmed', "
            "'planned_cost_skipped', 'planned_cost_cancelled') "
            "AND actor_type = 'user'",
            name="ck_planned_cost_audit_event_type",
        ),
        sa.CheckConstraint(
            "(event_type = 'planned_cost_created' AND previous_status IS NULL "
            "AND new_status = 'planned') OR "
            "(event_type = 'planned_cost_confirmed' AND previous_status = 'planned' "
            "AND new_status = 'confirmed') OR "
            "(event_type = 'planned_cost_skipped' AND previous_status = 'planned' "
            "AND new_status = 'skipped') OR "
            "(event_type = 'planned_cost_cancelled' AND previous_status = 'planned' "
            "AND new_status = 'cancelled')",
            name="ck_planned_cost_audit_transition",
        ),
        sa.CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_planned_cost_audit_hash_length",
        ),
    )
    op.create_index(
        "uq_planned_cost_audit_single_create",
        "planned_cost_audit_events",
        ["planned_cost_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'planned_cost_created'"),
    )
    # The lifecycle has no path back to 'planned', so a plan can never acquire a
    # second terminal transition row.
    op.create_index(
        "uq_planned_cost_audit_single_transition",
        "planned_cost_audit_events",
        ["planned_cost_id"],
        unique=True,
        postgresql_where=sa.text("event_type <> 'planned_cost_created'"),
    )
    op.create_index(
        "ix_planned_cost_audit_user_created",
        "planned_cost_audit_events",
        ["user_id", "created_at"],
    )

    op.create_table(
        "planned_cost_outbox_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("aggregate_type", sa.String(32), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(64), nullable=False),
        sa.Column(
            "payload",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempt_count", sa.SmallInteger(), nullable=False),
        sa.Column("validation_failure_count", sa.SmallInteger(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_code", sa.String(32), nullable=True),
        sa.Column("dead_lettered_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name="pk_planned_cost_outbox_events"),
        sa.ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["planned_costs.id", "planned_costs.user_id"],
            name="fk_planned_cost_outbox_plan",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_planned_cost_outbox_aggregate_command",
        ),
        sa.CheckConstraint(
            "aggregate_type = 'planned_cost'",
            name="ck_planned_cost_outbox_aggregate_type",
        ),
        sa.CheckConstraint(
            "event_type IN ('finance.planned_cost.created.v1', "
            "'finance.planned_cost.transitioned.v1')",
            name="ck_planned_cost_outbox_event_type",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_planned_cost_outbox_attempt_count",
        ),
        sa.CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_planned_cost_outbox_validation_failure_count",
        ),
        sa.CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_planned_cost_outbox_delivery_state",
        ),
        sa.CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_planned_cost_outbox_failure_metadata",
        ),
        sa.CheckConstraint(
            "(next_attempt_at IS NULL OR next_attempt_at >= created_at) "
            "AND (last_failed_at IS NULL OR last_failed_at >= created_at) "
            "AND (dead_lettered_at IS NULL OR "
            "(last_failed_at IS NOT NULL "
            "AND dead_lettered_at >= last_failed_at)) "
            "AND (published_at IS NULL OR published_at >= created_at) "
            "AND (last_failed_at IS NULL OR next_attempt_at IS NULL OR "
            "next_attempt_at > last_failed_at) "
            "AND (published_at IS NULL OR last_failed_at IS NULL OR "
            "published_at >= last_failed_at)",
            name="ck_planned_cost_outbox_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_planned_cost_outbox_pending_ready",
        "planned_cost_outbox_events",
        ["next_attempt_at", "created_at", "id"],
        postgresql_where=sa.text(
            "published_at IS NULL AND dead_lettered_at IS NULL",
        ),
    )
    op.create_index(
        "ix_planned_cost_outbox_dead_lettered",
        "planned_cost_outbox_events",
        ["dead_lettered_at", "created_at", "id"],
        postgresql_where=sa.text("dead_lettered_at IS NOT NULL"),
    )


def downgrade() -> None:
    # The previous schema cannot represent a plan at all, so dropping these
    # tables with rows present would silently destroy user forecasts and their
    # audit trail. Refuse instead of losing them.
    connection = op.get_bind()
    has_planned_costs = bool(
        connection.scalar(sa.text("SELECT EXISTS (SELECT 1 FROM planned_costs)"))
    )
    if has_planned_costs:
        raise RuntimeError("Refusing lossy downgrade: planned costs exist")

    op.drop_index(
        "ix_planned_cost_outbox_dead_lettered",
        table_name="planned_cost_outbox_events",
    )
    op.drop_index(
        "ix_planned_cost_outbox_pending_ready",
        table_name="planned_cost_outbox_events",
    )
    op.drop_table("planned_cost_outbox_events")

    op.drop_index(
        "ix_planned_cost_audit_user_created",
        table_name="planned_cost_audit_events",
    )
    op.drop_index(
        "uq_planned_cost_audit_single_transition",
        table_name="planned_cost_audit_events",
    )
    op.drop_index(
        "uq_planned_cost_audit_single_create",
        table_name="planned_cost_audit_events",
    )
    op.drop_table("planned_cost_audit_events")

    op.drop_index("ix_planned_costs_user_outstanding", table_name="planned_costs")
    op.drop_index("ix_planned_costs_user_planned_on", table_name="planned_costs")
    op.drop_table("planned_costs")

    op.drop_constraint(
        "uq_finance_operations_id_user",
        "finance_operations",
        type_="unique",
    )
