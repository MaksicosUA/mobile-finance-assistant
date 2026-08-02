"""Allow an audited correction of the account opening baseline date.

Revision ID: 0007_correctable_baseline
Revises: 0006_projector_supervision
Create Date: 2026-08-02

ADR 0016 makes `finance_accounts.opening_balance_on` correctable in the earlier
direction. Three constraints blocked that. The audit table pinned
`event_type` to `account_opened` and allowed one row per (account, event_type),
so a correction could neither be written nor repeated. The account outbox
pinned its own event type and uniqueness the same way. Both are widened here so
each account-level command contributes exactly one audit row and one
invalidation, while `account_opened` stays unique per account.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0007_correctable_baseline"
down_revision: str | None = "0006_projector_supervision"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_AUDIT_EVENT_TYPES = "('account_opened', 'account_baseline_corrected')"
_OUTBOX_EVENT_TYPES = (
    "('finance.account.opened.v1', 'finance.account.baseline_corrected.v1')"
)


def upgrade() -> None:
    # --- audit -------------------------------------------------------------
    op.drop_constraint(
        "uq_finance_account_audit_account_event",
        "finance_account_audit_events",
        type_="unique",
    )
    op.drop_constraint(
        "ck_finance_account_audit_open_event",
        "finance_account_audit_events",
        type_="check",
    )
    op.add_column(
        "finance_account_audit_events",
        sa.Column(
            "details",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )
    op.create_check_constraint(
        "ck_finance_account_audit_event_type",
        "finance_account_audit_events",
        f"event_type IN {_AUDIT_EVENT_TYPES} AND actor_type = 'user'",
    )
    # A baseline correction must record what it changed; an opening must not
    # carry correction details. Dates are the only payload, never amounts.
    op.create_check_constraint(
        "ck_finance_account_audit_details",
        "finance_account_audit_events",
        "(event_type = 'account_opened' AND details IS NULL) OR "
        "(event_type = 'account_baseline_corrected' AND details IS NOT NULL "
        "AND jsonb_typeof(details) = 'object' "
        "AND details ? 'previousOpeningBalanceOn' "
        "AND details ? 'openingBalanceOn' "
        "AND jsonb_typeof(details -> 'previousOpeningBalanceOn') = 'string' "
        "AND jsonb_typeof(details -> 'openingBalanceOn') = 'string')",
    )
    # One audit row per account-level command: this is what makes a replayed
    # correction idempotent, since the account row keeps its opening command.
    op.create_unique_constraint(
        "uq_finance_account_audit_account_command",
        "finance_account_audit_events",
        ["account_id", "command_id"],
    )
    op.create_index(
        "uq_finance_account_audit_single_open",
        "finance_account_audit_events",
        ["account_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'account_opened'"),
    )

    # --- account outbox ----------------------------------------------------
    op.drop_constraint(
        "uq_finance_account_outbox_aggregate_event",
        "finance_account_outbox_events",
        type_="unique",
    )
    op.drop_constraint(
        "ck_finance_account_outbox_event_type",
        "finance_account_outbox_events",
        type_="check",
    )
    op.create_check_constraint(
        "ck_finance_account_outbox_event_type",
        "finance_account_outbox_events",
        f"event_type IN {_OUTBOX_EVENT_TYPES}",
    )
    op.create_unique_constraint(
        "uq_finance_account_outbox_aggregate_command",
        "finance_account_outbox_events",
        ["aggregate_id", "command_id"],
    )
    op.create_index(
        "uq_finance_account_outbox_single_open",
        "finance_account_outbox_events",
        ["aggregate_id"],
        unique=True,
        postgresql_where=sa.text("event_type = 'finance.account.opened.v1'"),
    )


def downgrade() -> None:
    # Corrections cannot survive a downgrade: the narrower constraints admit
    # neither their event types nor more than one row per account. Remove them
    # first so the original constraints can be restored deterministically.
    op.execute(
        "DELETE FROM finance_account_outbox_events "
        "WHERE event_type = 'finance.account.baseline_corrected.v1'"
    )
    op.execute(
        "DELETE FROM finance_account_audit_events "
        "WHERE event_type = 'account_baseline_corrected'"
    )

    op.drop_index(
        "uq_finance_account_outbox_single_open",
        table_name="finance_account_outbox_events",
    )
    op.drop_constraint(
        "uq_finance_account_outbox_aggregate_command",
        "finance_account_outbox_events",
        type_="unique",
    )
    op.drop_constraint(
        "ck_finance_account_outbox_event_type",
        "finance_account_outbox_events",
        type_="check",
    )
    op.create_check_constraint(
        "ck_finance_account_outbox_event_type",
        "finance_account_outbox_events",
        "event_type = 'finance.account.opened.v1'",
    )
    op.create_unique_constraint(
        "uq_finance_account_outbox_aggregate_event",
        "finance_account_outbox_events",
        ["aggregate_id", "event_type"],
    )

    op.drop_index(
        "uq_finance_account_audit_single_open",
        table_name="finance_account_audit_events",
    )
    op.drop_constraint(
        "uq_finance_account_audit_account_command",
        "finance_account_audit_events",
        type_="unique",
    )
    op.drop_constraint(
        "ck_finance_account_audit_details",
        "finance_account_audit_events",
        type_="check",
    )
    op.drop_constraint(
        "ck_finance_account_audit_event_type",
        "finance_account_audit_events",
        type_="check",
    )
    op.drop_column("finance_account_audit_events", "details")
    op.create_check_constraint(
        "ck_finance_account_audit_open_event",
        "finance_account_audit_events",
        "event_type = 'account_opened' AND actor_type = 'user'",
    )
    op.create_unique_constraint(
        "uq_finance_account_audit_account_event",
        "finance_account_audit_events",
        ["account_id", "event_type"],
    )
