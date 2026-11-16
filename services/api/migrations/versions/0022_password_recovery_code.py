"""Let a person keep a code that resets a forgotten password.

Revision ID: 0022_password_recovery_code
Revises: 0021_scheduled_account_erasure
Create Date: 2026-11-16

ADR 0035. The server sends no mail, so a forgotten password is reset with a code
the person was shown once and kept. What is stored is its SHA-256 digest and the
day it was issued, on the person's own row: it is erased with them and needs no
table of its own. Nobody has a code until they ask for one.

The two columns are set and cleared together and the digest is always 32 bytes.
The database refuses anything else rather than trusting the writer.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0022_password_recovery_code"
down_revision: str | None = "0021_scheduled_account_erasure"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("recovery_code_hash", sa.LargeBinary(32), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column(
            "recovery_code_created_at", sa.DateTime(timezone=True), nullable=True
        ),
    )
    op.create_check_constraint(
        "ck_users_recovery_code",
        "users",
        "(recovery_code_hash IS NULL AND recovery_code_created_at IS NULL) OR "
        "(recovery_code_hash IS NOT NULL AND "
        "octet_length(recovery_code_hash) = 32 AND "
        "recovery_code_created_at IS NOT NULL)",
    )


def downgrade() -> None:
    # Dropping the column would leave people holding a code that silently no
    # longer works, and they would find out on the day they need it. Refuse.
    bind = op.get_bind()
    issued = bind.execute(
        sa.text("SELECT count(*) FROM users WHERE recovery_code_hash IS NOT NULL")
    ).scalar_one()
    if issued:
        raise RuntimeError(
            "Refusing to downgrade: accounts hold a recovery code. "
            "They would lose the only way back in they were given."
        )
    op.drop_constraint("ck_users_recovery_code", "users", type_="check")
    op.drop_column("users", "recovery_code_created_at")
    op.drop_column("users", "recovery_code_hash")
