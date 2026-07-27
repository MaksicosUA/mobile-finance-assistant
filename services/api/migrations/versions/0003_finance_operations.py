"""Create authoritative finance operations, audit, and outbox.

Revision ID: 0003_finance_operations
Revises: 0002_home_read_projection
Create Date: 2026-07-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003_finance_operations"
down_revision: str | None = "0002_home_read_projection"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SPECIAL_NUMERICS = "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"


def upgrade() -> None:
    op.create_table(
        "finance_operations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("command_id", sa.Uuid(), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("schema_version", sa.String(length=16), nullable=False),
        sa.Column("operation_type", sa.String(length=16), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=True),
        sa.Column("category", sa.String(length=100), nullable=True),
        sa.Column("merchant", sa.String(length=160), nullable=True),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("captured_timezone", sa.String(length=128), nullable=False),
        sa.Column("source_expression", sa.String(length=128), nullable=True),
        sa.Column("date_resolver_version", sa.String(length=32), nullable=False),
        sa.Column("occurred_on", sa.Date(), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "operation_type IN ('expense', 'income')",
            name="ck_finance_operations_type",
        ),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_operations_schema_version",
        ),
        sa.CheckConstraint(
            "status = 'confirmed'",
            name="ck_finance_operations_status",
        ),
        sa.CheckConstraint(
            f"amount > 0 AND amount NOT IN {_SPECIAL_NUMERICS}",
            name="ck_finance_operations_positive_finite_amount",
        ),
        sa.CheckConstraint(
            "currency = 'EUR'",
            name="ck_finance_operations_v1_currency",
        ),
        sa.CheckConstraint(
            "account_id IS NULL",
            name="ck_finance_operations_v1_unallocated_account",
        ),
        sa.CheckConstraint(
            "captured_timezone = btrim(captured_timezone) AND "
            "captured_timezone <> '' AND captured_timezone !~ '[[:cntrl:]]'",
            name="ck_finance_operations_captured_timezone",
        ),
        sa.CheckConstraint(
            "(category IS NULL OR (category = btrim(category) AND "
            "category <> '' AND category !~ '[[:cntrl:]]')) AND "
            "(merchant IS NULL OR (merchant = btrim(merchant) AND "
            "merchant <> '' AND merchant !~ '[[:cntrl:]]')) AND "
            "(source_expression IS NULL OR "
            "(source_expression = btrim(source_expression) AND "
            "source_expression <> '' AND "
            "source_expression !~ '[[:cntrl:]]'))",
            name="ck_finance_operations_optional_text",
        ),
        sa.CheckConstraint(
            "date_resolver_version = 'calendar-relative-v1'",
            name="ck_finance_operations_date_resolver",
        ),
        sa.CheckConstraint(
            "source IN ('manual_text', 'voice')",
            name="ck_finance_operations_source",
        ),
        sa.CheckConstraint(
            "confirmed_at >= captured_at",
            name="ck_finance_operations_timestamp_order",
        ),
        sa.CheckConstraint(
            "occurred_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31' "
            "AND captured_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND captured_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND confirmed_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND confirmed_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND (occurred_at IS NULL OR "
            "(occurred_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND occurred_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'))",
            name="ck_finance_operations_supported_dates",
        ),
        sa.CheckConstraint(
            "occurred_at IS NULL OR "
            "(occurred_at AT TIME ZONE captured_timezone)::date = occurred_on",
            name="ck_finance_operations_occurred_local_date",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_operations_payload_hash_length",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_operations_user_command",
        ),
    )
    op.create_index(
        "ix_finance_operations_user_occurred",
        "finance_operations",
        ["user_id", "occurred_on"],
        unique=False,
    )

    op.create_table(
        "finance_operation_audit_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("operation_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("command_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("actor_type", sa.String(length=16), nullable=False),
        sa.Column("payload_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "event_type = 'operation_accepted' AND actor_type = 'user'",
            name="ck_finance_operation_audit_accept_event",
        ),
        sa.CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_operation_audit_hash_length",
        ),
        sa.ForeignKeyConstraint(
            ["operation_id"], ["finance_operations.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "operation_id",
            "event_type",
            name="uq_finance_operation_audit_operation_event",
        ),
    )
    op.create_index(
        "ix_finance_operation_audit_user_created",
        "finance_operation_audit_events",
        ["user_id", "created_at"],
        unique=False,
    )

    op.create_table(
        "finance_outbox_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("aggregate_type", sa.String(length=32), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "attempt_count", sa.SmallInteger(), server_default="0", nullable=False
        ),
        sa.CheckConstraint(
            "aggregate_type = 'finance_operation'",
            name="ck_finance_outbox_aggregate_type",
        ),
        sa.CheckConstraint(
            "event_type = 'finance.operation.accepted.v1'",
            name="ck_finance_outbox_event_type",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_outbox_attempt_count",
        ),
        sa.ForeignKeyConstraint(
            ["aggregate_id"], ["finance_operations.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "aggregate_id",
            "event_type",
            name="uq_finance_outbox_aggregate_event",
        ),
    )
    op.create_index(
        "ix_finance_outbox_unpublished",
        "finance_outbox_events",
        ["published_at", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_finance_outbox_unpublished", table_name="finance_outbox_events")
    op.drop_table("finance_outbox_events")
    op.drop_index(
        "ix_finance_operation_audit_user_created",
        table_name="finance_operation_audit_events",
    )
    op.drop_table("finance_operation_audit_events")
    op.drop_index(
        "ix_finance_operations_user_occurred",
        table_name="finance_operations",
    )
    op.drop_table("finance_operations")
