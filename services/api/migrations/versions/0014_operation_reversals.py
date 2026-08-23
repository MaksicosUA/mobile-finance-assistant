"""Let a confirmed operation be corrected or removed.

Revision ID: 0014_operation_reversals
Revises: 0013_category_keywords
Create Date: 2026-08-22

ADR 0023. Until now a confirmed operation was final: a misread amount, a
misfiled category, or a purchase recorded twice stayed in the ledger forever.
Since a sentence fills the form (ADR 0022) and a keyword picks the category
(ADR 0020 step 3), being wrong occasionally is designed in, and being unable
to fix it is not.

The operation row is still never modified. A reversal is a separate row saying
the operation stopped counting; a correction is that same row with the
replacement operation written in one transaction; a removal is a reversal with
no replacement.

Two existing check constraints are widened rather than replaced: the audit
trail gains `operation_reversed`, and the outbox gains
`finance.operation.reversed.v1`. Both stay closed sets, so an unknown event
type still cannot be written.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014_operation_reversals"
down_revision: str | None = "0013_category_keywords"
branch_labels: Sequence[str] | None = None
depends_on: Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "finance_operation_reversals",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("operation_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column(
            "user_id",
            sa.Uuid(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("replacement_operation_id", sa.Uuid(as_uuid=True), nullable=True),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_payload_hash", sa.LargeBinary(32), nullable=False),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "replacement_operation_id IS NULL "
            "OR replacement_operation_id <> operation_id",
            name="ck_finance_operation_reversals_distinct_replacement",
        ),
        sa.CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_operation_reversals_hash_length",
        ),
        sa.UniqueConstraint(
            "operation_id",
            name="uq_finance_operation_reversals_operation",
        ),
        sa.UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_operation_reversals_user_command",
        ),
        sa.UniqueConstraint(
            "replacement_operation_id",
            name="uq_finance_operation_reversals_replacement",
        ),
        sa.ForeignKeyConstraint(
            ["operation_id", "user_id"],
            ["finance_operations.id", "finance_operations.user_id"],
            name="fk_finance_operation_reversals_owned_operation",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["replacement_operation_id", "user_id"],
            ["finance_operations.id", "finance_operations.user_id"],
            name="fk_finance_operation_reversals_owned_replacement",
        ),
    )
    op.create_index(
        "ix_finance_operation_reversals_user_created",
        "finance_operation_reversals",
        ["user_id", "created_at"],
    )

    op.drop_constraint(
        "ck_finance_operation_audit_accept_event",
        "finance_operation_audit_events",
        type_="check",
    )
    op.create_check_constraint(
        "ck_finance_operation_audit_accept_event",
        "finance_operation_audit_events",
        "event_type IN ('operation_accepted', 'operation_reversed') "
        "AND actor_type = 'user'",
    )

    op.drop_constraint(
        "ck_finance_outbox_event_type",
        "finance_outbox_events",
        type_="check",
    )
    op.create_check_constraint(
        "ck_finance_outbox_event_type",
        "finance_outbox_events",
        "event_type IN ('finance.operation.accepted.v1', "
        "'finance.operation.reversed.v1')",
    )


def downgrade() -> None:
    # The previous schema cannot represent a withdrawn operation at all, so
    # going back with reversals present would resurrect money the user had
    # already corrected away — and destroy the evidence of the correction.
    # Refuse instead of losing it.
    connection = op.get_bind()
    has_reversals = bool(
        connection.scalar(
            sa.text("SELECT EXISTS (SELECT 1 FROM finance_operation_reversals)")
        )
    )
    if has_reversals:
        raise RuntimeError("Refusing lossy downgrade: corrected operations exist")
    op.drop_constraint(
        "ck_finance_outbox_event_type",
        "finance_outbox_events",
        type_="check",
    )
    op.create_check_constraint(
        "ck_finance_outbox_event_type",
        "finance_outbox_events",
        "event_type = 'finance.operation.accepted.v1'",
    )
    op.drop_constraint(
        "ck_finance_operation_audit_accept_event",
        "finance_operation_audit_events",
        type_="check",
    )
    op.create_check_constraint(
        "ck_finance_operation_audit_accept_event",
        "finance_operation_audit_events",
        "event_type = 'operation_accepted' AND actor_type = 'user'",
    )
    op.drop_index(
        "ix_finance_operation_reversals_user_created",
        table_name="finance_operation_reversals",
    )
    op.drop_table("finance_operation_reversals")
