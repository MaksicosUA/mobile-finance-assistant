"""Give every wallet its own Home revision.

Revision ID: 0020_projection_per_wallet
Revises: 0019_finance_transfers
Create Date: 2026-09-08

ADR 0029. A projection was one row per user, month and timezone, built from
whichever account was the default. With several wallets that answers only for
one of them, and Home is meant to draw the default large with the others
beneath it.

Both sides of a transfer must move on screen together, which is why the other
wallets are projected rather than computed live beside a projected card: one
cycle publishes a revision for every wallet in one transaction, so a balance
leaving one and arriving in another is never visible in only one place.

The backfill is unambiguous: every existing profile holds exactly one account,
and it is the default one.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0020_projection_per_wallet"
down_revision: str | None = "0019_finance_transfers"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_OLD_UNIQUE = "uq_home_projection_snapshots_user_timezone_period_revision"
_NEW_UNIQUE = "uq_home_projection_snapshots_account_timezone_period_revision"
_ACCOUNT_FK = "fk_home_projection_snapshots_owned_account"


def upgrade() -> None:
    op.add_column(
        "home_projection_snapshots",
        sa.Column("account_id", sa.Uuid(as_uuid=True), nullable=True),
    )
    # Every profile that has a projection has exactly one account, and it is
    # the default one. A revision that cannot be attributed is deleted rather
    # than guessed at: it is a replaceable read model, and the projector
    # rebuilds it on the next cycle.
    op.execute(
        "UPDATE home_projection_snapshots AS snapshots "
        "SET account_id = accounts.id "
        "FROM finance_accounts AS accounts "
        "WHERE accounts.user_id = snapshots.user_id "
        "AND accounts.is_default IS TRUE"
    )
    op.execute("DELETE FROM home_projection_snapshots WHERE account_id IS NULL")
    op.alter_column("home_projection_snapshots", "account_id", nullable=False)

    op.drop_constraint(_OLD_UNIQUE, "home_projection_snapshots", type_="unique")
    op.create_unique_constraint(
        _NEW_UNIQUE,
        "home_projection_snapshots",
        ["user_id", "account_id", "timezone_name", "period_start", "revision"],
    )
    op.create_foreign_key(
        _ACCOUNT_FK,
        "home_projection_snapshots",
        "finance_accounts",
        ["account_id", "user_id"],
        ["id", "user_id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    # Two wallets can hold revisions that collide on the old key, and dropping
    # one of them would leave a wallet with no balance and no way to know it.
    crowded = (
        op.get_bind()
        .exec_driver_sql(
            "SELECT 1 FROM home_projection_snapshots "
            "GROUP BY user_id, timezone_name, period_start, revision "
            "HAVING count(*) > 1 LIMIT 1"
        )
        .first()
    )
    if crowded is not None:
        raise RuntimeError("Refusing lossy downgrade: a wallet would lose its balance")

    op.drop_constraint(_ACCOUNT_FK, "home_projection_snapshots", type_="foreignkey")
    op.drop_constraint(_NEW_UNIQUE, "home_projection_snapshots", type_="unique")
    op.create_unique_constraint(
        _OLD_UNIQUE,
        "home_projection_snapshots",
        ["user_id", "timezone_name", "period_start", "revision"],
    )
    op.drop_column("home_projection_snapshots", "account_id")
