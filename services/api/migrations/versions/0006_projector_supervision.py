"""Add durable Home projector supervision and outbox retry state.

Revision ID: 0006_projector_supervision
Revises: 0005_home_projector
Create Date: 2026-07-29
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0006_projector_supervision"
down_revision: str | None = "0005_home_projector"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_ACCOUNT_OUTBOX = "finance_account_outbox_events"
_OPERATION_OUTBOX = "finance_outbox_events"
_RUNTIME_STATE = "home_projector_runtime_state"

_OUTBOXES = (
    (
        _ACCOUNT_OUTBOX,
        "finance_account_outbox",
        "ix_finance_account_outbox_pending_ready",
        "ix_finance_account_outbox_dead_lettered",
    ),
    (
        _OPERATION_OUTBOX,
        "finance_outbox",
        "ix_finance_outbox_pending_ready",
        "ix_finance_outbox_dead_lettered",
    ),
)


def upgrade() -> None:
    for table_name, constraint_prefix, pending_index, dead_letter_index in _OUTBOXES:
        outbox = sa.table(
            table_name,
            sa.column("created_at"),
            sa.column("published_at"),
            sa.column("attempt_count"),
            sa.column("validation_failure_count"),
            sa.column("next_attempt_at"),
            sa.column("last_failed_at"),
            sa.column("failure_code"),
            sa.column("dead_lettered_at"),
        )
        op.add_column(
            table_name,
            sa.Column(
                "validation_failure_count",
                sa.SmallInteger(),
                server_default="0",
                nullable=False,
            ),
        )
        op.add_column(
            table_name,
            sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.add_column(
            table_name,
            sa.Column("last_failed_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.add_column(
            table_name,
            sa.Column("failure_code", sa.String(length=32), nullable=True),
        )
        op.add_column(
            table_name,
            sa.Column("dead_lettered_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.execute(
            outbox.update()
            .where(outbox.c.published_at.is_(None))
            .values(next_attempt_at=outbox.c.created_at)
        )
        op.alter_column(
            table_name,
            "validation_failure_count",
            server_default=None,
        )
        op.create_check_constraint(
            f"ck_{constraint_prefix}_validation_failure_count",
            table_name,
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
        )
        op.create_check_constraint(
            f"ck_{constraint_prefix}_delivery_state",
            table_name,
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
        )
        op.create_check_constraint(
            f"ck_{constraint_prefix}_failure_metadata",
            table_name,
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
        )
        op.create_check_constraint(
            f"ck_{constraint_prefix}_operational_timestamps",
            table_name,
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
        )
        op.create_index(
            pending_index,
            table_name,
            ["next_attempt_at", "created_at", "id"],
            unique=False,
            postgresql_where=sa.text(
                "published_at IS NULL AND dead_lettered_at IS NULL"
            ),
        )
        op.create_index(
            dead_letter_index,
            table_name,
            ["dead_lettered_at", "created_at", "id"],
            unique=False,
            postgresql_where=sa.text("dead_lettered_at IS NOT NULL"),
        )

    op.create_table(
        _RUNTIME_STATE,
        sa.Column(
            "singleton_id",
            sa.SmallInteger(),
            server_default="1",
            nullable=False,
        ),
        sa.Column("lease_id", sa.Uuid(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("heartbeat_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_cycle_status", sa.String(length=32), nullable=False),
        sa.CheckConstraint(
            "singleton_id = 1",
            name="ck_home_projector_runtime_state_singleton",
        ),
        sa.CheckConstraint(
            "lease_id <> '00000000-0000-0000-0000-000000000000'::uuid",
            name="ck_home_projector_runtime_state_lease_id",
        ),
        sa.CheckConstraint(
            "started_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' AND "
            "started_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' AND "
            "heartbeat_at >= started_at AND "
            "heartbeat_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_home_projector_runtime_state_timestamps",
        ),
        sa.CheckConstraint(
            "last_cycle_status IN "
            "('starting', 'idle', 'published', 'retry_scheduled', "
            "'degraded', 'stopped')",
            name="ck_home_projector_runtime_state_status",
        ),
        sa.PrimaryKeyConstraint("singleton_id"),
    )


def downgrade() -> None:
    connection = op.get_bind()
    for table_name, _, _, _ in _OUTBOXES:
        outbox = sa.table(
            table_name,
            sa.column("created_at"),
            sa.column("published_at"),
            sa.column("validation_failure_count"),
            sa.column("next_attempt_at"),
            sa.column("last_failed_at"),
            sa.column("failure_code"),
            sa.column("dead_lettered_at"),
        )
        has_retry_or_dead_letter_metadata = bool(
            connection.scalar(
                sa.select(
                    sa.exists().where(
                        sa.or_(
                            outbox.c.last_failed_at.is_not(None),
                            outbox.c.failure_code.is_not(None),
                            outbox.c.dead_lettered_at.is_not(None),
                            outbox.c.validation_failure_count > 0,
                            sa.and_(
                                outbox.c.published_at.is_(None),
                                outbox.c.next_attempt_at.is_distinct_from(
                                    outbox.c.created_at
                                ),
                            ),
                        )
                    )
                )
            )
        )
        if has_retry_or_dead_letter_metadata:
            raise RuntimeError(
                "Refusing lossy downgrade: outbox retry or dead-letter metadata exists"
            )

    op.drop_table(_RUNTIME_STATE)

    for table_name, constraint_prefix, pending_index, dead_letter_index in reversed(
        _OUTBOXES
    ):
        op.drop_index(dead_letter_index, table_name=table_name)
        op.drop_index(pending_index, table_name=table_name)
        op.drop_constraint(
            f"ck_{constraint_prefix}_operational_timestamps",
            table_name,
            type_="check",
        )
        op.drop_constraint(
            f"ck_{constraint_prefix}_failure_metadata",
            table_name,
            type_="check",
        )
        op.drop_constraint(
            f"ck_{constraint_prefix}_delivery_state",
            table_name,
            type_="check",
        )
        op.drop_constraint(
            f"ck_{constraint_prefix}_validation_failure_count",
            table_name,
            type_="check",
        )
        op.drop_column(table_name, "dead_lettered_at")
        op.drop_column(table_name, "failure_code")
        op.drop_column(table_name, "last_failed_at")
        op.drop_column(table_name, "next_attempt_at")
        op.drop_column(table_name, "validation_failure_count")
