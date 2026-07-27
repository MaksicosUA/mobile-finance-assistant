"""Create authoritative finance accounts and canonical user timezones.

Revision ID: 0004_authoritative_accounts
Revises: 0003_finance_operations
Create Date: 2026-07-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004_authoritative_accounts"
down_revision: str | None = "0003_finance_operations"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SPECIAL_NUMERICS = "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("canonical_timezone", sa.String(length=128), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column(
            "timezone_revision",
            sa.SmallInteger(),
            server_default="0",
            nullable=False,
        ),
    )
    op.create_check_constraint(
        "ck_users_canonical_timezone_revision",
        "users",
        "(timezone_revision = 0 AND canonical_timezone IS NULL) OR "
        "(timezone_revision = 1 AND "
        "canonical_timezone = btrim(canonical_timezone) AND "
        "canonical_timezone <> '' AND "
        "canonical_timezone !~ '[[:cntrl:]]' AND "
        "canonical_timezone NOT IN ('Factory', 'localtime', 'posixrules'))",
    )

    op.create_table(
        "finance_accounts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("command_id", sa.Uuid(), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("schema_version", sa.String(length=16), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("currency", sa.String(length=3), nullable=False),
        sa.Column("opening_balance", sa.Numeric(38, 18), nullable=False),
        sa.Column("opening_balance_on", sa.Date(), nullable=False),
        sa.Column("opening_timezone", sa.String(length=128), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("is_default", sa.Boolean(), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_accounts_schema_version",
        ),
        sa.CheckConstraint(
            "name = btrim(name) AND name <> '' AND name !~ '[[:cntrl:]]'",
            name="ck_finance_accounts_name",
        ),
        sa.CheckConstraint(
            "currency = 'EUR'",
            name="ck_finance_accounts_v1_currency",
        ),
        sa.CheckConstraint(
            f"opening_balance NOT IN {_SPECIAL_NUMERICS}",
            name="ck_finance_accounts_finite_opening_balance",
        ),
        sa.CheckConstraint(
            "opening_balance_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_accounts_opening_date",
        ),
        sa.CheckConstraint(
            "opening_timezone = btrim(opening_timezone) AND "
            "opening_timezone <> '' AND "
            "opening_timezone !~ '[[:cntrl:]]' AND "
            "opening_timezone NOT IN ('Factory', 'localtime', 'posixrules')",
            name="ck_finance_accounts_opening_timezone",
        ),
        sa.CheckConstraint(
            "status = 'active' AND is_default IS TRUE",
            name="ck_finance_accounts_v1_state",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_accounts_payload_hash_length",
        ),
        sa.CheckConstraint(
            "confirmed_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' AND "
            "confirmed_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_accounts_confirmed_at_range",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_accounts_user_command",
        ),
        sa.UniqueConstraint(
            "id",
            "user_id",
            name="uq_finance_accounts_id_user",
        ),
        sa.UniqueConstraint(
            "id",
            "user_id",
            "currency",
            name="uq_finance_accounts_id_user_currency",
        ),
    )
    op.create_index(
        "uq_finance_accounts_default_user",
        "finance_accounts",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("is_default IS TRUE"),
    )

    op.create_table(
        "finance_account_audit_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("account_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("command_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("actor_type", sa.String(length=16), nullable=False),
        sa.Column("payload_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "event_type = 'account_opened' AND actor_type = 'user'",
            name="ck_finance_account_audit_open_event",
        ),
        sa.CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_account_audit_hash_length",
        ),
        sa.ForeignKeyConstraint(
            ["account_id", "user_id"],
            ["finance_accounts.id", "finance_accounts.user_id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "account_id",
            "event_type",
            name="uq_finance_account_audit_account_event",
        ),
    )
    op.create_index(
        "ix_finance_account_audit_user_created",
        "finance_account_audit_events",
        ["user_id", "created_at"],
        unique=False,
    )

    op.create_table(
        "finance_account_outbox_events",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("aggregate_type", sa.String(length=32), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("command_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "attempt_count",
            sa.SmallInteger(),
            server_default="0",
            nullable=False,
        ),
        sa.CheckConstraint(
            "aggregate_type = 'finance_account'",
            name="ck_finance_account_outbox_aggregate_type",
        ),
        sa.CheckConstraint(
            "event_type = 'finance.account.opened.v1'",
            name="ck_finance_account_outbox_event_type",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_account_outbox_attempt_count",
        ),
        sa.ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_accounts.id", "finance_accounts.user_id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "aggregate_id",
            "event_type",
            name="uq_finance_account_outbox_aggregate_event",
        ),
    )
    op.create_index(
        "ix_finance_account_outbox_unpublished",
        "finance_account_outbox_events",
        ["published_at", "created_at"],
        unique=False,
    )

    op.drop_constraint(
        "ck_finance_operations_v1_unallocated_account",
        "finance_operations",
        type_="check",
    )
    op.create_foreign_key(
        "fk_finance_operations_owned_account_currency",
        "finance_operations",
        "finance_accounts",
        ["account_id", "user_id", "currency"],
        ["id", "user_id", "currency"],
    )
    op.create_index(
        "ix_finance_operations_user_account_occurred",
        "finance_operations",
        ["user_id", "account_id", "occurred_on"],
        unique=False,
    )


def downgrade() -> None:
    connection = op.get_bind()
    has_account_rows = bool(
        connection.scalar(sa.text("SELECT EXISTS (SELECT 1 FROM finance_accounts)"))
    )
    has_allocated_operations = bool(
        connection.scalar(
            sa.text(
                "SELECT EXISTS ("
                "SELECT 1 FROM finance_operations WHERE account_id IS NOT NULL"
                ")"
            )
        )
    )
    if has_account_rows or has_allocated_operations:
        raise RuntimeError(
            "Refusing lossy downgrade: finance accounts or allocated operations exist"
        )

    op.drop_index(
        "ix_finance_operations_user_account_occurred",
        table_name="finance_operations",
    )
    op.drop_constraint(
        "fk_finance_operations_owned_account_currency",
        "finance_operations",
        type_="foreignkey",
    )
    op.create_check_constraint(
        "ck_finance_operations_v1_unallocated_account",
        "finance_operations",
        "account_id IS NULL",
    )

    op.drop_index(
        "ix_finance_account_outbox_unpublished",
        table_name="finance_account_outbox_events",
    )
    op.drop_table("finance_account_outbox_events")
    op.drop_index(
        "ix_finance_account_audit_user_created",
        table_name="finance_account_audit_events",
    )
    op.drop_table("finance_account_audit_events")
    op.drop_index(
        "uq_finance_accounts_default_user",
        table_name="finance_accounts",
    )
    op.drop_table("finance_accounts")

    op.drop_constraint(
        "ck_users_canonical_timezone_revision",
        "users",
        type_="check",
    )
    op.drop_column("users", "timezone_revision")
    op.drop_column("users", "canonical_timezone")
