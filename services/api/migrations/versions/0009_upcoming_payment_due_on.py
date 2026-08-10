"""Give projected upcoming payments an authoritative local due date.

Revision ID: 0009_payment_due_on
Revises: 0008_planned_costs
Create Date: 2026-08-10

A planned cost has a local calendar date and no time of day (ADR 0018), while
the projected payment row required a non-null instant. Filling that instant
would mean inventing a time, which ADR 0007 forbids and which the ADR 0011
amendment removes for payments exactly as it did for transactions.

`due_on` becomes the authoritative field and `due_at` becomes optional. The
table holds no rows in any environment — nothing has ever produced an upcoming
payment — so `due_on` is added as NOT NULL directly, without a synthetic
backfill that would bake in the very fabrication this migration removes. The
upgrade refuses to run if that assumption is ever false.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009_payment_due_on"
down_revision: str | None = "0008_planned_costs"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_TABLE = "home_projection_upcoming_payments"


def upgrade() -> None:
    connection = op.get_bind()
    has_rows = bool(
        connection.scalar(
            sa.text("SELECT EXISTS (SELECT 1 FROM home_projection_upcoming_payments)")
        )
    )
    if has_rows:
        # Deriving due_on from due_at would need the snapshot timezone and would
        # assert a local date nobody recorded. Fail closed instead of guessing.
        raise RuntimeError(
            "Refusing to add due_on: existing projected payments have no "
            "authoritative local date to migrate from"
        )

    op.add_column(_TABLE, sa.Column("due_on", sa.Date(), nullable=False))
    op.alter_column(
        _TABLE, "due_at", existing_type=sa.DateTime(timezone=True), nullable=True
    )
    op.drop_index("ix_home_projection_upcoming_payments_order", table_name=_TABLE)
    op.create_index(
        "ix_home_projection_upcoming_payments_order",
        _TABLE,
        ["snapshot_id", "due_on", "payment_id"],
    )


def downgrade() -> None:
    connection = op.get_bind()
    has_dateless_instant = bool(
        connection.scalar(
            sa.text(
                "SELECT EXISTS (SELECT 1 FROM home_projection_upcoming_payments"
                " WHERE due_at IS NULL)"
            )
        )
    )
    if has_dateless_instant:
        # The previous schema cannot represent a payment whose due is a date.
        raise RuntimeError(
            "Refusing lossy downgrade: projected payments without an exact "
            "due_at cannot be represented by the previous schema"
        )

    op.drop_index("ix_home_projection_upcoming_payments_order", table_name=_TABLE)
    op.create_index(
        "ix_home_projection_upcoming_payments_order",
        _TABLE,
        ["snapshot_id", "due_at", "payment_id"],
    )
    op.alter_column(
        _TABLE,
        "due_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
    )
    op.drop_column(_TABLE, "due_on")
