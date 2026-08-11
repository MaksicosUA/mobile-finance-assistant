"""Introduce savings goals with an append-only contribution ledger.

Revision ID: 0010_savings_goals
Revises: 0009_payment_due_on
Create Date: 2026-08-11

ADR 0019 models a goal as a declared target plus a separate immutable ledger of
contributions, because the goal's headline figure is derived rather than typed.
Four tables are added: the goal, its ledger, its audit trail, and a separate
identifier-only outbox the Home projector will consume once the `primaryGoal`
slice lands.

A contribution earmarks balance that is already in the account. Nothing here may
be summed into an authoritative balance, monthly total, net flow, or trend.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0010_savings_goals"
down_revision: str | None = "0009_payment_due_on"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_SUPPORTED_TIMESTAMP_RANGE = (
    "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
    "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'"
)
_FINITE = "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"


def upgrade() -> None:
    op.create_table(
        "finance_goals",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("account_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("schema_version", sa.String(16), nullable=False),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("target_amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("monthly_contribution", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("target_on", sa.Date(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_finance_goals"),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name="fk_finance_goals_user",
            ondelete="CASCADE",
        ),
        # Pinning the currency through the account key makes a mismatch
        # unrepresentable rather than merely validated.
        sa.ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_goals_owned_account_currency",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_goals_user_command",
        ),
        sa.UniqueConstraint("id", "user_id", name="uq_finance_goals_id_user"),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_goals_schema_version",
        ),
        sa.CheckConstraint(
            f"target_amount > 0 AND target_amount NOT IN {_FINITE}",
            name="ck_finance_goals_positive_finite_target",
        ),
        sa.CheckConstraint(
            f"monthly_contribution >= 0 AND monthly_contribution NOT IN {_FINITE}",
            name="ck_finance_goals_monthly_contribution",
        ),
        sa.CheckConstraint("currency = 'EUR'", name="ck_finance_goals_v1_currency"),
        sa.CheckConstraint(
            "title = btrim(title) AND title <> '' AND title !~ '[[:cntrl:]]'",
            name="ck_finance_goals_text",
        ),
        sa.CheckConstraint(
            "target_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_goals_target_on_range",
        ),
        sa.CheckConstraint(
            "status IN ('active', 'cancelled')",
            name="ck_finance_goals_status",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_goals_payload_hash_length",
        ),
        sa.CheckConstraint(
            f"updated_at >= created_at AND {_SUPPORTED_TIMESTAMP_RANGE} "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_goals_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_finance_goals_user_active_target",
        "finance_goals",
        ["user_id", "target_on"],
        postgresql_where=sa.text("status = 'active'"),
    )

    op.create_table(
        "finance_goal_contributions",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("goal_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("schema_version", sa.String(16), nullable=False),
        sa.Column("direction", sa.String(16), nullable=False),
        sa.Column("amount", sa.Numeric(38, 18), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False),
        sa.Column("occurred_on", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_finance_goal_contributions"),
        sa.ForeignKeyConstraint(
            ["goal_id", "user_id"],
            ["finance_goals.id", "finance_goals.user_id"],
            name="fk_finance_goal_contributions_owned_goal",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_goal_contributions_user_command",
        ),
        sa.CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_goal_contributions_schema_version",
        ),
        sa.CheckConstraint(
            f"amount > 0 AND amount NOT IN {_FINITE}",
            name="ck_finance_goal_contributions_positive_finite_amount",
        ),
        sa.CheckConstraint(
            "direction IN ('deposit', 'withdrawal')",
            name="ck_finance_goal_contributions_direction",
        ),
        sa.CheckConstraint(
            "currency = 'EUR'",
            name="ck_finance_goal_contributions_v1_currency",
        ),
        sa.CheckConstraint(
            "occurred_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_goal_contributions_occurred_on_range",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_goal_contributions_payload_hash_length",
        ),
        sa.CheckConstraint(
            _SUPPORTED_TIMESTAMP_RANGE,
            name="ck_finance_goal_contributions_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_finance_goal_contributions_goal_occurred",
        "finance_goal_contributions",
        ["goal_id", "occurred_on", "id"],
    )

    op.create_table(
        "finance_goal_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("goal_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("contribution_id", sa.Uuid(as_uuid=True), nullable=True),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("actor_type", sa.String(16), nullable=False),
        sa.Column("payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("previous_status", sa.String(16), nullable=True),
        sa.Column("new_status", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_finance_goal_audit_events"),
        sa.ForeignKeyConstraint(
            ["goal_id", "user_id"],
            ["finance_goals.id", "finance_goals.user_id"],
            name="fk_finance_goal_audit_owned_goal",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "goal_id",
            "command_id",
            name="uq_finance_goal_audit_goal_command",
        ),
        sa.CheckConstraint(
            "event_type IN ('goal_created', 'goal_cancelled', "
            "'goal_contribution_recorded') AND actor_type = 'user'",
            name="ck_finance_goal_audit_event_type",
        ),
        sa.CheckConstraint(
            "(event_type = 'goal_created' AND previous_status IS NULL "
            "AND new_status = 'active') OR "
            "(event_type = 'goal_cancelled' AND previous_status = 'active' "
            "AND new_status = 'cancelled') OR "
            "(event_type = 'goal_contribution_recorded' "
            "AND previous_status = 'active' AND new_status = 'active')",
            name="ck_finance_goal_audit_transition",
        ),
        sa.CheckConstraint(
            "(event_type = 'goal_contribution_recorded') "
            "= (contribution_id IS NOT NULL)",
            name="ck_finance_goal_audit_contribution_link",
        ),
        sa.CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_goal_audit_hash_length",
        ),
        sa.CheckConstraint(
            _SUPPORTED_TIMESTAMP_RANGE,
            name="ck_finance_goal_audit_operational_timestamps",
        ),
    )
    op.create_index(
        "uq_finance_goal_audit_single_create",
        "finance_goal_audit_events",
        ["goal_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'goal_created'"),
    )
    op.create_index(
        "uq_finance_goal_audit_single_cancel",
        "finance_goal_audit_events",
        ["goal_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'goal_cancelled'"),
    )
    op.create_index(
        "ix_finance_goal_audit_user_created",
        "finance_goal_audit_events",
        ["user_id", "created_at"],
    )

    op.create_table(
        "finance_goal_outbox_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("aggregate_type", sa.String(32), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(64), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempt_count", sa.SmallInteger(), nullable=False),
        sa.Column("validation_failure_count", sa.SmallInteger(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_code", sa.String(32), nullable=True),
        sa.Column("dead_lettered_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name="pk_finance_goal_outbox_events"),
        sa.ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_goals.id", "finance_goals.user_id"],
            name="fk_finance_goal_outbox_goal",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_goal_outbox_aggregate_command",
        ),
        sa.CheckConstraint(
            "aggregate_type = 'finance_goal'",
            name="ck_finance_goal_outbox_aggregate_type",
        ),
        sa.CheckConstraint(
            "event_type IN ('finance.goal.created.v1', "
            "'finance.goal.cancelled.v1', 'finance.goal.contributed.v1')",
            name="ck_finance_goal_outbox_event_type",
        ),
        sa.CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_goal_outbox_attempt_count",
        ),
        sa.CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_goal_outbox_validation_failure_count",
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
            name="ck_finance_goal_outbox_delivery_state",
        ),
        sa.CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_goal_outbox_failure_metadata",
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
            name="ck_finance_goal_outbox_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_finance_goal_outbox_pending_ready",
        "finance_goal_outbox_events",
        ["next_attempt_at", "created_at", "id"],
        postgresql_where=sa.text("published_at IS NULL AND dead_lettered_at IS NULL"),
    )
    op.create_index(
        "ix_finance_goal_outbox_dead_lettered",
        "finance_goal_outbox_events",
        ["dead_lettered_at", "created_at", "id"],
        postgresql_where=sa.text("dead_lettered_at IS NOT NULL"),
    )


def downgrade() -> None:
    # The previous schema cannot represent a goal at all, so dropping these
    # tables with rows present would silently destroy the evidence behind a
    # figure the user was shown. Refuse instead of losing it.
    connection = op.get_bind()
    has_goals = bool(
        connection.scalar(sa.text("SELECT EXISTS (SELECT 1 FROM finance_goals)"))
    )
    if has_goals:
        raise RuntimeError("Refusing lossy downgrade: savings goals exist")

    op.drop_index(
        "ix_finance_goal_outbox_dead_lettered",
        table_name="finance_goal_outbox_events",
    )
    op.drop_index(
        "ix_finance_goal_outbox_pending_ready",
        table_name="finance_goal_outbox_events",
    )
    op.drop_table("finance_goal_outbox_events")

    op.drop_index(
        "ix_finance_goal_audit_user_created",
        table_name="finance_goal_audit_events",
    )
    op.drop_index(
        "uq_finance_goal_audit_single_cancel",
        table_name="finance_goal_audit_events",
    )
    op.drop_index(
        "uq_finance_goal_audit_single_create",
        table_name="finance_goal_audit_events",
    )
    op.drop_table("finance_goal_audit_events")

    op.drop_index(
        "ix_finance_goal_contributions_goal_occurred",
        table_name="finance_goal_contributions",
    )
    op.drop_table("finance_goal_contributions")

    op.drop_index(
        "ix_finance_goals_user_active_target",
        table_name="finance_goals",
    )
    op.drop_table("finance_goals")
