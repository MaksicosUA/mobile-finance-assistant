"""SQLAlchemy mappings for accounts, auth, and Home read projections."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    ForeignKeyConstraint,
    Index,
    LargeBinary,
    Numeric,
    SmallInteger,
    String,
    UniqueConstraint,
    Uuid,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class UserRow(Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(
            "base_currency ~ '^[A-Z]{3}$'",
            name="ck_users_base_currency_iso_shape",
        ),
        CheckConstraint(
            "(timezone_revision = 0 AND canonical_timezone IS NULL) OR "
            "(timezone_revision = 1 AND "
            "canonical_timezone = btrim(canonical_timezone) AND "
            "canonical_timezone <> '' AND "
            "canonical_timezone !~ '[[:cntrl:]]' AND "
            "canonical_timezone NOT IN ('Factory', 'localtime', 'posixrules'))",
            name="ck_users_canonical_timezone_revision",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    email_normalized: Mapped[str] = mapped_column(
        String(254),
        nullable=False,
        unique=True,
    )
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str] = mapped_column(String(100), nullable=False)
    base_currency: Mapped[str] = mapped_column(
        String(3),
        nullable=False,
        default="EUR",
    )
    canonical_timezone: Mapped[str | None] = mapped_column(
        String(128),
        nullable=True,
    )
    timezone_revision: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
        default=0,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    disabled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class AuthSessionRow(Base):
    __tablename__ = "auth_sessions"
    __table_args__ = (
        CheckConstraint(
            "absolute_expires_at > created_at",
            name="ck_auth_sessions_expiry_after_creation",
        ),
        CheckConstraint(
            "revocation_reason IS NULL OR revocation_reason IN "
            "('logout', 'reuse_detected', 'expired')",
            name="ck_auth_sessions_revocation_reason",
        ),
        Index("ix_auth_sessions_user_id", "user_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    absolute_expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    revocation_reason: Mapped[str | None] = mapped_column(
        String(32),
        nullable=True,
    )


class AuthRefreshTokenRow(Base):
    __tablename__ = "auth_refresh_tokens"
    __table_args__ = (
        CheckConstraint(
            "octet_length(token_hash) = 32",
            name="ck_auth_refresh_tokens_sha256_length",
        ),
        CheckConstraint(
            "expires_at > created_at",
            name="ck_auth_refresh_tokens_expiry_after_creation",
        ),
        UniqueConstraint(
            "parent_token_id",
            name="uq_auth_refresh_tokens_parent_token_id",
        ),
        Index("ix_auth_refresh_tokens_session_id", "session_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    session_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("auth_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    token_hash: Mapped[bytes] = mapped_column(
        LargeBinary(32),
        nullable=False,
        unique=True,
    )
    parent_token_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("auth_refresh_tokens.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    consumed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class FinanceAccountRow(Base):
    """Authoritative v1 account and its immutable opening baseline."""

    __tablename__ = "finance_accounts"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_accounts_schema_version",
        ),
        CheckConstraint(
            "name = btrim(name) AND name <> '' AND name !~ '[[:cntrl:]]'",
            name="ck_finance_accounts_name",
        ),
        CheckConstraint(
            "currency = 'EUR'",
            name="ck_finance_accounts_v1_currency",
        ),
        CheckConstraint(
            "opening_balance NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_accounts_finite_opening_balance",
        ),
        CheckConstraint(
            "opening_balance_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_accounts_opening_date",
        ),
        CheckConstraint(
            "opening_timezone = btrim(opening_timezone) AND "
            "opening_timezone <> '' AND "
            "opening_timezone !~ '[[:cntrl:]]' AND "
            "opening_timezone NOT IN ('Factory', 'localtime', 'posixrules')",
            name="ck_finance_accounts_opening_timezone",
        ),
        CheckConstraint(
            "status = 'active' AND is_default IS TRUE",
            name="ck_finance_accounts_v1_state",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_accounts_payload_hash_length",
        ),
        CheckConstraint(
            "confirmed_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' AND "
            "confirmed_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_accounts_confirmed_at_range",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_accounts_user_command",
        ),
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_finance_accounts_id_user",
        ),
        UniqueConstraint(
            "id",
            "user_id",
            "currency",
            name="uq_finance_accounts_id_user_currency",
        ),
        Index(
            "uq_finance_accounts_default_user",
            "user_id",
            unique=True,
            postgresql_where=text("is_default IS TRUE"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    opening_balance: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    opening_balance_on: Mapped[date] = mapped_column(Date, nullable=False)
    opening_timezone: Mapped[str] = mapped_column(String(128), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False)
    confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceAccountAuditRow(Base):
    __tablename__ = "finance_account_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type = 'account_opened' AND actor_type = 'user'",
            name="ck_finance_account_audit_open_event",
        ),
        CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_account_audit_hash_length",
        ),
        ForeignKeyConstraint(
            ["account_id", "user_id"],
            ["finance_accounts.id", "finance_accounts.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "account_id",
            "event_type",
            name="uq_finance_account_audit_account_event",
        ),
        Index("ix_finance_account_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceAccountOutboxEventRow(Base):
    __tablename__ = "finance_account_outbox_events"
    __table_args__ = (
        CheckConstraint(
            "aggregate_type = 'finance_account'",
            name="ck_finance_account_outbox_aggregate_type",
        ),
        CheckConstraint(
            "event_type = 'finance.account.opened.v1'",
            name="ck_finance_account_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_account_outbox_attempt_count",
        ),
        ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_accounts.id", "finance_accounts.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "aggregate_id",
            "event_type",
            name="uq_finance_account_outbox_aggregate_event",
        ),
        Index(
            "ix_finance_account_outbox_unpublished",
            "published_at",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    aggregate_type: Mapped[str] = mapped_column(String(32), nullable=False)
    aggregate_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    published_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    attempt_count: Mapped[int] = mapped_column(SmallInteger, nullable=False)


class FinanceOperationRow(Base):
    """Authoritative confirmed income/expense operation."""

    __tablename__ = "finance_operations"
    __table_args__ = (
        CheckConstraint(
            "operation_type IN ('expense', 'income')",
            name="ck_finance_operations_type",
        ),
        CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_operations_schema_version",
        ),
        CheckConstraint(
            "status = 'confirmed'",
            name="ck_finance_operations_status",
        ),
        CheckConstraint(
            "amount > 0 AND amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_operations_positive_finite_amount",
        ),
        CheckConstraint(
            "currency = 'EUR'",
            name="ck_finance_operations_v1_currency",
        ),
        CheckConstraint(
            "captured_timezone = btrim(captured_timezone) AND "
            "captured_timezone <> '' AND captured_timezone !~ '[[:cntrl:]]'",
            name="ck_finance_operations_captured_timezone",
        ),
        CheckConstraint(
            "(category IS NULL OR (category = btrim(category) AND "
            "category <> '' AND category !~ '[[:cntrl:]]')) AND "
            "(merchant IS NULL OR (merchant = btrim(merchant) AND "
            "merchant <> '' AND merchant !~ '[[:cntrl:]]')) AND "
            "(source_expression IS NULL OR "
            "(source_expression = btrim(source_expression) AND "
            "source_expression <> '' AND "
            "source_expression !~ '[[:cntrl:]]'))",
            name="ck_finance_operations_optional_text",
        ),
        CheckConstraint(
            "date_resolver_version = 'calendar-relative-v1'",
            name="ck_finance_operations_date_resolver",
        ),
        CheckConstraint(
            "source IN ('manual_text', 'voice')",
            name="ck_finance_operations_source",
        ),
        CheckConstraint(
            "confirmed_at >= captured_at",
            name="ck_finance_operations_timestamp_order",
        ),
        CheckConstraint(
            "occurred_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31' "
            "AND captured_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND captured_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND confirmed_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND confirmed_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND (occurred_at IS NULL OR "
            "(occurred_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND occurred_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'))",
            name="ck_finance_operations_supported_dates",
        ),
        CheckConstraint(
            "occurred_at IS NULL OR "
            "(occurred_at AT TIME ZONE captured_timezone)::date = occurred_on",
            name="ck_finance_operations_occurred_local_date",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_operations_payload_hash_length",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_operations_user_command",
        ),
        ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_operations_owned_account_currency",
        ),
        Index("ix_finance_operations_user_occurred", "user_id", "occurred_on"),
        Index(
            "ix_finance_operations_user_account_occurred",
            "user_id",
            "account_id",
            "occurred_on",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    operation_type: Mapped[str] = mapped_column(String(16), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    account_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    category: Mapped[str | None] = mapped_column(String(100), nullable=True)
    merchant: Mapped[str | None] = mapped_column(String(160), nullable=True)
    captured_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    captured_timezone: Mapped[str] = mapped_column(String(128), nullable=False)
    source_expression: Mapped[str | None] = mapped_column(String(128), nullable=True)
    date_resolver_version: Mapped[str] = mapped_column(String(32), nullable=False)
    occurred_on: Mapped[date] = mapped_column(Date, nullable=False)
    occurred_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class FinanceOperationAuditRow(Base):
    __tablename__ = "finance_operation_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type = 'operation_accepted' AND actor_type = 'user'",
            name="ck_finance_operation_audit_accept_event",
        ),
        CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_operation_audit_hash_length",
        ),
        UniqueConstraint(
            "operation_id",
            "event_type",
            name="uq_finance_operation_audit_operation_event",
        ),
        Index("ix_finance_operation_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    operation_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("finance_operations.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class FinanceOutboxEventRow(Base):
    __tablename__ = "finance_outbox_events"
    __table_args__ = (
        CheckConstraint(
            "aggregate_type = 'finance_operation'",
            name="ck_finance_outbox_aggregate_type",
        ),
        CheckConstraint(
            "event_type = 'finance.operation.accepted.v1'",
            name="ck_finance_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_outbox_attempt_count",
        ),
        UniqueConstraint(
            "aggregate_id",
            "event_type",
            name="uq_finance_outbox_aggregate_event",
        ),
        Index("ix_finance_outbox_unpublished", "published_at", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    aggregate_type: Mapped[str] = mapped_column(String(32), nullable=False)
    aggregate_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("finance_operations.id", ondelete="CASCADE"),
        nullable=False,
    )
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    published_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    attempt_count: Mapped[int] = mapped_column(SmallInteger, nullable=False)


_FINITE_SNAPSHOT_DECIMALS = (
    "balance_amount, balance_delta_amount, balance_delta_percent, "
    "month_income, month_expense, month_net_flow, trend_total"
)
_FINITE_SPECIAL_VALUES = "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)"


class HomeProjectionSnapshotRow(Base):
    """One immutable, transactionally published Home read-model revision."""

    __tablename__ = "home_projection_snapshots"
    __table_args__ = (
        CheckConstraint(
            "EXTRACT(DAY FROM period_start) = 1 AND "
            "period_end = "
            "(period_start + INTERVAL '1 month' - INTERVAL '1 day')::date",
            name="ck_home_projection_snapshots_month_boundaries",
        ),
        CheckConstraint(
            "revision > 0",
            name="ck_home_projection_snapshots_revision_positive",
        ),
        CheckConstraint(
            "data_as_of <= generated_at",
            name="ck_home_projection_snapshots_timestamp_order",
        ),
        CheckConstraint(
            "base_currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_snapshots_base_currency",
        ),
        CheckConstraint(
            "timezone_name = btrim(timezone_name) AND timezone_name <> '' "
            "AND timezone_name !~ '[[:cntrl:]]'",
            name="ck_home_projection_snapshots_timezone_name",
        ),
        CheckConstraint(
            "month_income >= 0 AND month_expense >= 0 AND "
            "month_net_flow = month_income - month_expense",
            name="ck_home_projection_snapshots_month_summary",
        ),
        CheckConstraint(
            "trend_metric <> 'expense' OR trend_total >= 0",
            name="ck_home_projection_snapshots_expense_trend_total",
        ),
        CheckConstraint(
            "btrim(trend_metric) <> '' AND btrim(trend_period) <> ''",
            name="ck_home_projection_snapshots_trend_values",
        ),
        CheckConstraint(
            " AND ".join(
                f"{column} NOT IN {_FINITE_SPECIAL_VALUES}"
                for column in _FINITE_SNAPSHOT_DECIMALS.split(", ")
            ),
            name="ck_home_projection_snapshots_finite_decimals",
        ),
        UniqueConstraint(
            "user_id",
            "timezone_name",
            "period_start",
            "revision",
            name="uq_home_projection_snapshots_user_timezone_period_revision",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    timezone_name: Mapped[str] = mapped_column(String(128), nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    revision: Mapped[int] = mapped_column(BigInteger, nullable=False)
    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    data_as_of: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    base_currency: Mapped[str] = mapped_column(String(3), nullable=False)
    balance_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    balance_delta_amount: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    balance_delta_percent: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    month_income: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    month_expense: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    month_net_flow: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    trend_metric: Mapped[str] = mapped_column(String(64), nullable=False)
    trend_period: Mapped[str] = mapped_column(String(64), nullable=False)
    trend_total: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)


class HomeProjectionTrendPointRow(Base):
    __tablename__ = "home_projection_trend_points"
    __table_args__ = (
        CheckConstraint(
            f"amount NOT IN {_FINITE_SPECIAL_VALUES}",
            name="ck_home_projection_trend_points_finite_amount",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    point_date: Mapped[date] = mapped_column(Date, primary_key=True)
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)


class HomeProjectionGoalRow(Base):
    __tablename__ = "home_projection_primary_goals"
    __table_args__ = (
        CheckConstraint(
            "btrim(goal_id) <> '' AND btrim(title) <> ''",
            name="ck_home_projection_primary_goals_text",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_primary_goals_currency",
        ),
        CheckConstraint(
            " AND ".join(
                f"{column} NOT IN {_FINITE_SPECIAL_VALUES}"
                for column in (
                    "current_amount",
                    "target_amount",
                    "monthly_contribution",
                    "current_base_amount",
                    "target_base_amount",
                    "monthly_contribution_base_amount",
                    "progress_percent",
                )
            ),
            name="ck_home_projection_primary_goals_finite_decimals",
        ),
        CheckConstraint(
            "current_amount >= 0 AND target_amount > 0 AND "
            "monthly_contribution >= 0 AND current_base_amount >= 0 AND "
            "target_base_amount > 0 AND "
            "monthly_contribution_base_amount >= 0 AND "
            "progress_percent BETWEEN 0 AND 100",
            name="ck_home_projection_primary_goals_bounds",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    goal_id: Mapped[str] = mapped_column(String(128), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    current_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    target_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    monthly_contribution: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    current_base_amount: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    target_base_amount: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    monthly_contribution_base_amount: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    due_date: Mapped[date] = mapped_column(Date, nullable=False)
    progress_percent: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )


class HomeProjectionPaymentRow(Base):
    __tablename__ = "home_projection_upcoming_payments"
    __table_args__ = (
        CheckConstraint(
            "btrim(payment_id) <> '' AND btrim(title) <> '' AND btrim(status) <> ''",
            name="ck_home_projection_upcoming_payments_text",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_upcoming_payments_currency",
        ),
        CheckConstraint(
            f"amount NOT IN {_FINITE_SPECIAL_VALUES} AND "
            f"base_amount NOT IN {_FINITE_SPECIAL_VALUES}",
            name="ck_home_projection_upcoming_payments_finite_amounts",
        ),
        CheckConstraint(
            "amount >= 0 AND base_amount >= 0",
            name="ck_home_projection_upcoming_payments_nonnegative_amounts",
        ),
        Index(
            "ix_home_projection_upcoming_payments_order",
            "snapshot_id",
            "due_at",
            "payment_id",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    payment_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    base_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)


class HomeProjectionTransactionRow(Base):
    __tablename__ = "home_projection_recent_transactions"
    __table_args__ = (
        CheckConstraint(
            "btrim(transaction_id) <> '' AND btrim(title) <> '' "
            "AND btrim(category) <> '' AND btrim(direction) <> ''",
            name="ck_home_projection_recent_transactions_text",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_home_projection_recent_transactions_currency",
        ),
        CheckConstraint(
            "status = 'confirmed'",
            name="ck_home_projection_recent_transactions_confirmed",
        ),
        CheckConstraint(
            f"amount NOT IN {_FINITE_SPECIAL_VALUES} AND "
            f"base_amount NOT IN {_FINITE_SPECIAL_VALUES}",
            name="ck_home_projection_recent_transactions_finite_amounts",
        ),
        CheckConstraint(
            "(direction <> 'income' OR (amount >= 0 AND base_amount >= 0)) "
            "AND (direction <> 'expense' OR "
            "(amount <= 0 AND base_amount <= 0)) "
            "AND amount * base_amount >= 0",
            name="ck_home_projection_recent_transactions_direction_sign",
        ),
        Index(
            "ix_home_projection_recent_transactions_order",
            "snapshot_id",
            "occurred_at",
            "transaction_id",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    transaction_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    category: Mapped[str] = mapped_column(String(160), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    base_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    direction: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)


class HomeProjectionActionRow(Base):
    __tablename__ = "home_projection_actions"
    __table_args__ = (
        CheckConstraint(
            "position BETWEEN 0 AND 15",
            name="ck_home_projection_actions_position",
        ),
        CheckConstraint(
            "btrim(action) <> ''",
            name="ck_home_projection_actions_text",
        ),
        UniqueConstraint(
            "snapshot_id",
            "action",
            name="uq_home_projection_actions_snapshot_action",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    position: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    action: Mapped[str] = mapped_column(String(64), nullable=False)


class HomeProjectionWarningRow(Base):
    __tablename__ = "home_projection_warnings"
    __table_args__ = (
        CheckConstraint(
            "position BETWEEN 0 AND 15",
            name="ck_home_projection_warnings_position",
        ),
        CheckConstraint(
            "btrim(code) <> '' AND btrim(block) <> ''",
            name="ck_home_projection_warnings_text",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    position: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    block: Mapped[str] = mapped_column(String(64), nullable=False)
