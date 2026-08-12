"""Add the audit trail and Home invalidation a managed catalogue needs.

Revision ID: 0012_category_management
Revises: 0011_category_catalogue
Create Date: 2026-08-12

ADR 0020 step 2b lets a user create, rename, and hide their own categories.
Two facts follow from that.

A rename replaces the only stored copy of a name, so the previous one has to be
recorded somewhere or it is gone. `finance_category_audit_events` keeps it.

A published Home projection stores the label it resolved for a transaction, so
renaming a category makes every projection holding that label stale.
`finance_category_outbox_events` carries the identifier-only invalidation that
makes the projector rebuild. Only a rename is published: creating, hiding, and
restoring change no label that is already published.

Removal is archiving and never deletion, so no row here is ever destroyed and
no historical operation can lose its grouping.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012_category_management"
down_revision: str | None = "0011_category_catalogue"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "finance_category_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("actor_type", sa.String(16), nullable=False),
        sa.Column("previous_name", sa.String(100), nullable=True),
        sa.Column("new_name", sa.String(100), nullable=True),
        sa.Column("previous_status", sa.String(16), nullable=True),
        sa.Column("new_status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_finance_category_audit_events"),
        sa.ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_category_audit_owned_category",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "category_id",
            "command_id",
            name="uq_finance_category_audit_category_command",
        ),
        sa.CheckConstraint(
            "event_type IN ('category_created', 'category_renamed', "
            "'category_archived', 'category_restored') AND actor_type = 'user'",
            name="ck_finance_category_audit_event_type",
        ),
        sa.CheckConstraint(
            "(event_type = 'category_created' AND previous_name IS NULL "
            "AND new_name IS NOT NULL) OR "
            "(event_type = 'category_renamed' AND previous_name IS NOT NULL "
            "AND new_name IS NOT NULL AND previous_name <> new_name) OR "
            "(event_type IN ('category_archived', 'category_restored') "
            "AND previous_name IS NULL AND new_name IS NULL)",
            name="ck_finance_category_audit_names",
        ),
        sa.CheckConstraint(
            "(event_type = 'category_created' AND previous_status IS NULL "
            "AND new_status = 'active') OR "
            "(event_type = 'category_renamed' AND previous_status = 'active' "
            "AND new_status = 'active') OR "
            "(event_type = 'category_archived' AND previous_status = 'active' "
            "AND new_status = 'archived') OR "
            "(event_type = 'category_restored' AND previous_status = 'archived' "
            "AND new_status = 'active')",
            name="ck_finance_category_audit_transition",
        ),
        sa.CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_category_audit_operational_timestamps",
        ),
    )
    op.create_index(
        "uq_finance_category_audit_single_create",
        "finance_category_audit_events",
        ["category_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'category_created'"),
    )
    op.create_index(
        "ix_finance_category_audit_user_created",
        "finance_category_audit_events",
        ["user_id", "created_at"],
    )

    op.create_table(
        "finance_category_outbox_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("aggregate_type", sa.String(32), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(64), nullable=False),
        sa.Column("payload", sa.dialects.postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempt_count", sa.SmallInteger(), nullable=False),
        sa.Column("validation_failure_count", sa.SmallInteger(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_code", sa.String(32), nullable=True),
        sa.Column("dead_lettered_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name="pk_finance_category_outbox_events"),
        sa.ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_category_outbox_owned_category",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_category_outbox_aggregate_command",
        ),
        sa.CheckConstraint(
            "aggregate_type = 'finance_category'",
            name="ck_finance_category_outbox_aggregate_type",
        ),
        sa.CheckConstraint(
            "event_type = 'finance.category.renamed.v1'",
            name="ck_finance_category_outbox_event_type",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_category_outbox_attempt_count",
        ),
        sa.CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_category_outbox_validation_failure_count",
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
            name="ck_finance_category_outbox_delivery_state",
        ),
        sa.CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_category_outbox_failure_metadata",
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
            name="ck_finance_category_outbox_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_finance_category_outbox_pending_ready",
        "finance_category_outbox_events",
        ["next_attempt_at", "created_at", "id"],
        postgresql_where=sa.text("published_at IS NULL AND dead_lettered_at IS NULL"),
    )
    op.create_index(
        "ix_finance_category_outbox_dead_lettered",
        "finance_category_outbox_events",
        ["dead_lettered_at", "created_at", "id"],
        postgresql_where=sa.text("dead_lettered_at IS NOT NULL"),
    )


def downgrade() -> None:
    # An audit row is the only surviving record of a name a rename replaced,
    # and a pending outbox row is a Home rebuild that has not happened yet.
    # Dropping either silently would lose something no other table holds.
    connection = op.get_bind()
    has_audit = bool(
        connection.scalar(
            sa.text("SELECT EXISTS (SELECT 1 FROM finance_category_audit_events)")
        )
    )
    if has_audit:
        raise RuntimeError("Refusing lossy downgrade: category audit rows exist")
    has_pending = bool(
        connection.scalar(
            sa.text(
                "SELECT EXISTS (SELECT 1 FROM finance_category_outbox_events "
                "WHERE published_at IS NULL)"
            )
        )
    )
    if has_pending:
        raise RuntimeError(
            "Refusing lossy downgrade: unpublished category events exist"
        )

    op.drop_index(
        "ix_finance_category_outbox_dead_lettered",
        table_name="finance_category_outbox_events",
    )
    op.drop_index(
        "ix_finance_category_outbox_pending_ready",
        table_name="finance_category_outbox_events",
    )
    op.drop_table("finance_category_outbox_events")

    op.drop_index(
        "ix_finance_category_audit_user_created",
        table_name="finance_category_audit_events",
    )
    op.drop_index(
        "uq_finance_category_audit_single_create",
        table_name="finance_category_audit_events",
    )
    op.drop_table("finance_category_audit_events")
