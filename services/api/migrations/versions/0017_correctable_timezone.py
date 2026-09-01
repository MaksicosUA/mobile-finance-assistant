"""Let the canonical reporting timezone be corrected.

Revision ID: 0017_correctable_timezone
Revises: 0016_monthly_budgets
Create Date: 2026-09-01

ADR 0028. The timezone was chosen once when the account was created and could
never be fixed; someone who moved was stuck with month boundaries drawn where
they used to live.

Nothing here re-files history: an operation's `occurred_on` is a local date
frozen when it was captured (ADR 0007), and every report filters on that. What
changes is what "today" and "this month" mean from now on.

The revision counter relaxes from exactly one to at least one, so it counts how
many times the timezone has been settled.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0017_correctable_timezone"
down_revision: str | None = "0016_monthly_budgets"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_TIMEZONE_SHAPE = (
    "canonical_timezone = btrim(canonical_timezone) AND "
    "canonical_timezone <> '' AND "
    "canonical_timezone !~ '[[:cntrl:]]' AND "
    "canonical_timezone NOT IN ('Factory', 'localtime', 'posixrules')"
)
_AUDIT_TYPES_BEFORE = (
    "event_type IN ('account_opened', 'account_baseline_corrected') "
    "AND actor_type = 'user'"
)
_AUDIT_TYPES_AFTER = (
    "event_type IN ('account_opened', 'account_baseline_corrected', "
    "'account_timezone_corrected') AND actor_type = 'user'"
)
_BASELINE_DETAILS = (
    "(event_type = 'account_opened' AND details IS NULL) OR "
    "(event_type = 'account_baseline_corrected' AND details IS NOT NULL "
    "AND jsonb_typeof(details) = 'object' "
    "AND details ? 'previousOpeningBalanceOn' "
    "AND details ? 'openingBalanceOn' "
    "AND jsonb_typeof(details -> 'previousOpeningBalanceOn') = 'string' "
    "AND jsonb_typeof(details -> 'openingBalanceOn') = 'string')"
)
_TIMEZONE_DETAILS = (
    "(event_type = 'account_timezone_corrected' AND details IS NOT NULL "
    "AND jsonb_typeof(details) = 'object' "
    "AND details ? 'previousTimezone' "
    "AND details ? 'timezone' "
    "AND jsonb_typeof(details -> 'previousTimezone') = 'string' "
    "AND jsonb_typeof(details -> 'timezone') = 'string')"
)
_OUTBOX_TYPES_BEFORE = (
    "event_type IN ('finance.account.opened.v1', "
    "'finance.account.baseline_corrected.v1')"
)
_OUTBOX_TYPES_AFTER = (
    "event_type IN ('finance.account.opened.v1', "
    "'finance.account.baseline_corrected.v1', "
    "'finance.account.timezone_corrected.v1')"
)


def _replace_check(table: str, name: str, condition: str) -> None:
    op.drop_constraint(name, table, type_="check")
    op.create_check_constraint(name, table, condition)


def upgrade() -> None:
    _replace_check(
        "users",
        "ck_users_canonical_timezone_revision",
        "(timezone_revision = 0 AND canonical_timezone IS NULL) OR "
        f"(timezone_revision >= 1 AND {_TIMEZONE_SHAPE})",
    )
    _replace_check(
        "finance_account_audit_events",
        "ck_finance_account_audit_event_type",
        _AUDIT_TYPES_AFTER,
    )
    _replace_check(
        "finance_account_audit_events",
        "ck_finance_account_audit_details",
        f"{_BASELINE_DETAILS} OR {_TIMEZONE_DETAILS}",
    )
    _replace_check(
        "finance_account_outbox_events",
        "ck_finance_account_outbox_event_type",
        _OUTBOX_TYPES_AFTER,
    )


def downgrade() -> None:
    # The earlier schema cannot express a timezone that was corrected, and
    # narrowing over rows that record one would fail anyway. Refuse first, with
    # a message that says what is in the way.
    connection = op.get_bind()
    corrected = bool(
        connection.scalar(
            sa.text(
                "SELECT EXISTS (SELECT 1 FROM finance_account_audit_events "
                "WHERE event_type = 'account_timezone_corrected')"
            )
        )
    )
    if corrected:
        raise RuntimeError("Refusing lossy downgrade: timezones were corrected")

    _replace_check(
        "finance_account_outbox_events",
        "ck_finance_account_outbox_event_type",
        _OUTBOX_TYPES_BEFORE,
    )
    _replace_check(
        "finance_account_audit_events",
        "ck_finance_account_audit_details",
        _BASELINE_DETAILS,
    )
    _replace_check(
        "finance_account_audit_events",
        "ck_finance_account_audit_event_type",
        _AUDIT_TYPES_BEFORE,
    )
    _replace_check(
        "users",
        "ck_users_canonical_timezone_revision",
        "(timezone_revision = 0 AND canonical_timezone IS NULL) OR "
        f"(timezone_revision = 1 AND {_TIMEZONE_SHAPE})",
    )
