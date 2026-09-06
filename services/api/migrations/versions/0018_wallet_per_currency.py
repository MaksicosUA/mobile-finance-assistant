"""Let a profile hold more than one wallet, one currency each.

Revision ID: 0018_wallet_per_currency
Revises: 0017_correctable_timezone
Create Date: 2026-09-06

ADR 0029. Money that is not euro could not be recorded at all, and the schema
was ready for it: every table that carries money already has a composite
foreign key on `(account_id, user_id, currency)` into `finance_accounts`, so an
operation's currency cannot disagree with its account's. Only a `currency =
'EUR'` check sat on top of each one.

Those seven checks relax to an ISO-4217 shape. The integrity is enforced by the
keys underneath them, which are untouched, so nothing is opened up: an amount
still cannot carry a currency its own wallet does not hold.

`finance_accounts` also stops requiring every account to be the default one. A
wallet that is not the default is a real account; that exactly one is remains
enforced by the partial unique index `uq_finance_accounts_default_user`, which
this migration does not touch.

Nothing is converted anywhere, so no column is added and no data moves.
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0018_wallet_per_currency"
down_revision: str | None = "0017_correctable_timezone"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_ISO_SHAPE = "currency ~ '^[A-Z]{3}$'"
_EURO_ONLY = "currency = 'EUR'"

#: Every table whose money is denominated by its wallet.
_CURRENCY_CHECKS: tuple[tuple[str, str], ...] = (
    ("finance_accounts", "ck_finance_accounts_v1_currency"),
    ("finance_operations", "ck_finance_operations_v1_currency"),
    ("finance_budgets", "ck_finance_budgets_v1_currency"),
    ("planned_costs", "ck_planned_costs_v1_currency"),
    ("planned_cost_recurrences", "ck_planned_cost_recurrences_v1_currency"),
    ("finance_goals", "ck_finance_goals_v1_currency"),
    ("finance_goal_contributions", "ck_finance_goal_contributions_v1_currency"),
)

_STATE_CHECK = "ck_finance_accounts_v1_state"
_STATE_BEFORE = "status = 'active' AND is_default IS TRUE"
_STATE_AFTER = "status = 'active'"


def upgrade() -> None:
    for table, name in _CURRENCY_CHECKS:
        op.drop_constraint(name, table, type_="check")
        op.create_check_constraint(name, table, _ISO_SHAPE)

    op.drop_constraint(_STATE_CHECK, "finance_accounts", type_="check")
    op.create_check_constraint(_STATE_CHECK, "finance_accounts", _STATE_AFTER)


def downgrade() -> None:
    # Refuse rather than silently drop a wallet's money: the rows would still
    # be there and the constraint would not describe them.
    foreign = (
        op.get_bind()
        .exec_driver_sql(
            "SELECT 1 FROM finance_accounts WHERE currency <> 'EUR' LIMIT 1"
        )
        .first()
    )
    if foreign is not None:
        raise RuntimeError("Refusing lossy downgrade: a wallet is not in euro")
    secondary = (
        op.get_bind()
        .exec_driver_sql(
            "SELECT 1 FROM finance_accounts WHERE is_default IS FALSE LIMIT 1"
        )
        .first()
    )
    if secondary is not None:
        raise RuntimeError("Refusing lossy downgrade: a wallet is not the default")

    op.drop_constraint(_STATE_CHECK, "finance_accounts", type_="check")
    op.create_check_constraint(_STATE_CHECK, "finance_accounts", _STATE_BEFORE)

    for table, name in reversed(_CURRENCY_CHECKS):
        op.drop_constraint(name, table, type_="check")
        op.create_check_constraint(name, table, _EURO_ONLY)
