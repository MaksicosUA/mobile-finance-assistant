"""Let a person schedule the erasure of their own account.

Revision ID: 0021_scheduled_account_erasure
Revises: 0020_projection_per_wallet
Create Date: 2026-10-16

ADR 0030. A request records when it was made and when the account will be
erased, seven days later. Signing in before then clears both. Nothing else is
stored: the request is a date on the person's own row, not a separate record
that could outlive them.

The two columns are set and cleared together, and erasure is always after the
request — the database refuses anything else rather than trusting the writer.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0021_scheduled_account_erasure"
down_revision: str | None = "0020_projection_per_wallet"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("deletion_requested_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("deletion_due_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_check_constraint(
        "ck_users_deletion_schedule",
        "users",
        "(deletion_requested_at IS NULL AND deletion_due_at IS NULL) OR "
        "(deletion_requested_at IS NOT NULL AND deletion_due_at IS NOT NULL "
        "AND deletion_due_at > deletion_requested_at)",
    )
    # The hourly sweep looks only at accounts with a date; there are few.
    op.create_index(
        "ix_users_deletion_due_at",
        "users",
        ["deletion_due_at"],
        postgresql_where=sa.text("deletion_due_at IS NOT NULL"),
    )


def downgrade() -> None:
    # Dropping the columns would silently cancel every pending request, and
    # the people who made them would then never be erased. Refuse instead.
    bind = op.get_bind()
    pending = bind.execute(
        sa.text("SELECT count(*) FROM users WHERE deletion_due_at IS NOT NULL")
    ).scalar_one()
    if pending:
        raise RuntimeError(
            "Refusing to downgrade: accounts are scheduled for erasure. "
            "Erase or cancel them first."
        )
    op.drop_index("ix_users_deletion_due_at", table_name="users")
    op.drop_constraint("ck_users_deletion_schedule", "users", type_="check")
    op.drop_column("users", "deletion_due_at")
    op.drop_column("users", "deletion_requested_at")
