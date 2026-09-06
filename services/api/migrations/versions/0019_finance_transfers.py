"""Move money between two wallets without inventing a rate.

Revision ID: 0019_finance_transfers
Revises: 0018_wallet_per_currency
Create Date: 2026-09-06

ADR 0029. Exchanging 100 € for 108 $ records both numbers the person actually
witnessed; the rate is implied by them and is never stored, so no report can
change because a rate moved.

A table of its own rather than a third `operation_type`, for the reason a
reversal got one (ADR 0023): every existing read would otherwise have to learn
to exclude a transfer from income, expense, net flow, the trend, the category
breakdown and every budget, and missing one of them is a silently wrong total.
Here the default is exclusion, and only the balance opts in.

Each side carries a composite foreign key into `finance_accounts` on
`(account_id, user_id, currency)`, the same key every other money table uses,
so a transfer cannot name a currency the wallet it points at does not hold.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0019_finance_transfers"
down_revision: str | None = "0018_wallet_per_currency"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_FINITE = "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"
_OUTBOX_DELIVERY_STATE = (
    "(published_at IS NULL AND dead_lettered_at IS NULL "
    "AND next_attempt_at IS NOT NULL) OR "
    "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
    "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
    "AND failure_code IS NULL) OR "
    "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
    "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
    "AND failure_code = 'invalid_outbox_contract')"
)
_OUTBOX_FAILURE_METADATA = (
    "(last_failed_at IS NULL AND failure_code IS NULL) OR "
    "(last_failed_at IS NOT NULL "
    "AND failure_code = 'invalid_outbox_contract' "
    "AND validation_failure_count > 0)"
)
_OUTBOX_TIMESTAMPS = (
    "(next_attempt_at IS NULL OR next_attempt_at >= created_at) "
    "AND (last_failed_at IS NULL OR last_failed_at >= created_at) "
    "AND (dead_lettered_at IS NULL OR "
    "(last_failed_at IS NOT NULL AND dead_lettered_at >= last_failed_at)) "
    "AND (published_at IS NULL OR published_at >= created_at) "
    "AND (last_failed_at IS NULL OR next_attempt_at IS NULL OR "
    "next_attempt_at > last_failed_at) "
    "AND (published_at IS NULL OR last_failed_at IS NULL OR "
    "published_at >= last_failed_at)"
)


def upgrade() -> None:
    op.create_table(
        "finance_transfers",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("schema_version", sa.String(16), nullable=False),
        sa.Column("from_account_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("from_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("from_currency", sa.String(3), nullable=False),
        sa.Column("to_account_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("to_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("to_currency", sa.String(3), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("captured_timezone", sa.String(128), nullable=False),
        sa.Column("occurred_on", sa.Date(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_transfers_schema_version",
        ),
        sa.CheckConstraint(
            "from_account_id <> to_account_id",
            name="ck_finance_transfers_distinct_wallets",
        ),
        sa.CheckConstraint(
            "from_amount > 0 AND to_amount > 0",
            name="ck_finance_transfers_positive_amounts",
        ),
        sa.CheckConstraint(
            f"from_amount NOT IN {_FINITE} AND to_amount NOT IN {_FINITE}",
            name="ck_finance_transfers_finite_amounts",
        ),
        sa.CheckConstraint(
            "from_currency ~ '^[A-Z]{3}$' AND to_currency ~ '^[A-Z]{3}$'",
            name="ck_finance_transfers_currency_shape",
        ),
        sa.CheckConstraint(
            "occurred_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_transfers_occurred_on_range",
        ),
        sa.CheckConstraint(
            "status = 'confirmed'",
            name="ck_finance_transfers_v1_status",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_transfers_payload_hash_length",
        ),
        sa.CheckConstraint(
            "captured_timezone = btrim(captured_timezone) AND "
            "captured_timezone <> '' AND "
            "captured_timezone !~ '[[:cntrl:]]' AND "
            "captured_timezone NOT IN ('Factory', 'localtime', 'posixrules')",
            name="ck_finance_transfers_captured_timezone",
        ),
        sa.ForeignKeyConstraint(
            ["from_account_id", "user_id", "from_currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_transfers_from_account_currency",
        ),
        sa.ForeignKeyConstraint(
            ["to_account_id", "user_id", "to_currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_transfers_to_account_currency",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_transfers_user_command",
        ),
        sa.UniqueConstraint("id", "user_id", name="uq_finance_transfers_id_user"),
    )
    op.create_index(
        "ix_finance_transfers_user_occurred_on",
        "finance_transfers",
        ["user_id", "occurred_on"],
    )

    op.create_table(
        "finance_transfer_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("transfer_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("actor_type", sa.String(16), nullable=False),
        sa.Column("payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "event_type = 'transfer_confirmed' AND actor_type = 'user'",
            name="ck_finance_transfer_audit_event_type",
        ),
        sa.CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_transfer_audit_hash_length",
        ),
        sa.ForeignKeyConstraint(
            ["transfer_id", "user_id"],
            ["finance_transfers.id", "finance_transfers.user_id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "transfer_id",
            "command_id",
            name="uq_finance_transfer_audit_transfer_command",
        ),
    )
    op.create_index(
        "ix_finance_transfer_audit_user_created",
        "finance_transfer_audit_events",
        ["user_id", "created_at"],
    )

    op.create_table(
        "finance_transfer_outbox_events",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
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
        sa.CheckConstraint(
            "aggregate_type = 'finance_transfer'",
            name="ck_finance_transfer_outbox_aggregate_type",
        ),
        sa.CheckConstraint(
            "event_type = 'finance.transfer.accepted.v1'",
            name="ck_finance_transfer_outbox_event_type",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_transfer_outbox_attempt_count",
        ),
        sa.CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_transfer_outbox_validation_failure_count",
        ),
        sa.CheckConstraint(
            _OUTBOX_DELIVERY_STATE,
            name="ck_finance_transfer_outbox_delivery_state",
        ),
        sa.CheckConstraint(
            _OUTBOX_FAILURE_METADATA,
            name="ck_finance_transfer_outbox_failure_metadata",
        ),
        sa.CheckConstraint(
            _OUTBOX_TIMESTAMPS,
            name="ck_finance_transfer_outbox_operational_timestamps",
        ),
        sa.ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_transfers.id", "finance_transfers.user_id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_transfer_outbox_aggregate_command",
        ),
    )
    op.create_index(
        "ix_finance_transfer_outbox_pending_ready",
        "finance_transfer_outbox_events",
        ["next_attempt_at", "created_at", "id"],
        postgresql_where=sa.text("published_at IS NULL AND dead_lettered_at IS NULL"),
    )
    op.create_index(
        "ix_finance_transfer_outbox_dead_lettered",
        "finance_transfer_outbox_events",
        ["dead_lettered_at", "created_at", "id"],
        postgresql_where=sa.text("dead_lettered_at IS NOT NULL"),
    )


def downgrade() -> None:
    # Refuse rather than drop money: a transfer is the only record that a
    # balance moved between two wallets, and no other table carries it.
    recorded = (
        op.get_bind().exec_driver_sql("SELECT 1 FROM finance_transfers LIMIT 1").first()
    )
    if recorded is not None:
        raise RuntimeError("Refusing lossy downgrade: transfers exist")

    op.drop_index(
        "ix_finance_transfer_outbox_dead_lettered",
        table_name="finance_transfer_outbox_events",
    )
    op.drop_index(
        "ix_finance_transfer_outbox_pending_ready",
        table_name="finance_transfer_outbox_events",
    )
    op.drop_table("finance_transfer_outbox_events")
    op.drop_index(
        "ix_finance_transfer_audit_user_created",
        table_name="finance_transfer_audit_events",
    )
    op.drop_table("finance_transfer_audit_events")
    op.drop_index(
        "ix_finance_transfers_user_occurred_on",
        table_name="finance_transfers",
    )
    op.drop_table("finance_transfers")
