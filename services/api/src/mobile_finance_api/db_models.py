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
    select,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.sql.elements import ColumnElement


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
            # At least one, not exactly one: the number counts how many times
            # the timezone has been settled, and it is correctable (ADR 0028).
            "(timezone_revision >= 1 AND "
            "canonical_timezone = btrim(canonical_timezone) AND "
            "canonical_timezone <> '' AND "
            "canonical_timezone !~ '[[:cntrl:]]' AND "
            "canonical_timezone NOT IN ('Factory', 'localtime', 'posixrules'))",
            name="ck_users_canonical_timezone_revision",
        ),
        # Set and cleared together, and erasure always after the request
        # (ADR 0030).
        CheckConstraint(
            "(deletion_requested_at IS NULL AND deletion_due_at IS NULL) OR "
            "(deletion_requested_at IS NOT NULL AND deletion_due_at IS NOT NULL "
            "AND deletion_due_at > deletion_requested_at)",
            name="ck_users_deletion_schedule",
        ),
        Index(
            "ix_users_deletion_due_at",
            "deletion_due_at",
            postgresql_where=text("deletion_due_at IS NOT NULL"),
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
    #: When the person asked for their account to be erased, and when it will
    #: be. Signing in before then clears both (ADR 0030). Separate from
    #: `disabled_at`, which is the operator's block and is never cleared by it.
    deletion_requested_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    deletion_due_at: Mapped[datetime | None] = mapped_column(
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
            "currency ~ '^[A-Z]{3}$'",
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
            # A wallet that is not the default one is a real account
            # (ADR 0029); only exactly-one-default is still enforced, by the
            # partial unique index below.
            "status = 'active'",
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
            "event_type IN ('account_opened', 'account_baseline_corrected', "
            "'account_timezone_corrected') "
            "AND actor_type = 'user'",
            name="ck_finance_account_audit_event_type",
        ),
        CheckConstraint(
            "(event_type = 'account_opened' AND details IS NULL) OR "
            "(event_type = 'account_baseline_corrected' AND details IS NOT NULL "
            "AND jsonb_typeof(details) = 'object' "
            "AND details ? 'previousOpeningBalanceOn' "
            "AND details ? 'openingBalanceOn' "
            "AND jsonb_typeof(details -> 'previousOpeningBalanceOn') = 'string' "
            "AND jsonb_typeof(details -> 'openingBalanceOn') = 'string') OR "
            "(event_type = 'account_timezone_corrected' AND details IS NOT NULL "
            "AND jsonb_typeof(details) = 'object' "
            "AND details ? 'previousTimezone' "
            "AND details ? 'timezone' "
            "AND jsonb_typeof(details -> 'previousTimezone') = 'string' "
            "AND jsonb_typeof(details -> 'timezone') = 'string')",
            name="ck_finance_account_audit_details",
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
        # One audit row per account-level command. This is what makes a
        # replayed baseline correction idempotent: the account row keeps the
        # opening command, so command identity lives here instead.
        UniqueConstraint(
            "account_id",
            "command_id",
            name="uq_finance_account_audit_account_command",
        ),
        Index(
            "uq_finance_account_audit_single_open",
            "account_id",
            unique=True,
            postgresql_where=text("event_type = 'account_opened'"),
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
    # Only a baseline correction populates this, and only with the previous and
    # new local dates. It never carries an amount or any user-authored text.
    details: Mapped[dict[str, object] | None] = mapped_column(JSONB, nullable=True)
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
            "event_type IN ('finance.account.opened.v1', "
            "'finance.account.baseline_corrected.v1', "
            "'finance.account.timezone_corrected.v1')",
            name="ck_finance_account_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_account_outbox_attempt_count",
        ),
        CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_account_outbox_validation_failure_count",
        ),
        CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_finance_account_outbox_delivery_state",
        ),
        CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_account_outbox_failure_metadata",
        ),
        CheckConstraint(
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
            name="ck_finance_account_outbox_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_accounts.id", "finance_accounts.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_account_outbox_aggregate_command",
        ),
        Index(
            "uq_finance_account_outbox_single_open",
            "aggregate_id",
            unique=True,
            postgresql_where=text("event_type = 'finance.account.opened.v1'"),
        ),
        Index(
            "ix_finance_account_outbox_unpublished",
            "published_at",
            "created_at",
        ),
        Index(
            "ix_finance_account_outbox_pending_ready",
            "next_attempt_at",
            "created_at",
            "id",
            postgresql_where=text("published_at IS NULL AND dead_lettered_at IS NULL"),
        ),
        Index(
            "ix_finance_account_outbox_dead_lettered",
            "dead_lettered_at",
            "created_at",
            "id",
            postgresql_where=text("dead_lettered_at IS NOT NULL"),
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
    validation_failure_count: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    failure_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dead_lettered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


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
            "currency ~ '^[A-Z]{3}$'",
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
        # Lets a dependent row reference an operation together with its owner,
        # so no cross-user link can be expressed at all (see planned_costs).
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_finance_operations_id_user",
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
        # The composite key makes borrowing another user's category
        # unrepresentable rather than merely validated (ADR 0020).
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_operations_owned_category",
        ),
        Index("ix_finance_operations_user_occurred", "user_id", "occurred_on"),
        # Serves the per-category totals Analytics will read.
        Index(
            "ix_finance_operations_user_category_occurred",
            "user_id",
            "category_id",
            "occurred_on",
            postgresql_where=text("category_id IS NOT NULL"),
        ),
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
    # Kept exactly as the user wrote it. It is the only evidence of what they
    # meant, so a wrong link stays visible and correctable (ADR 0020).
    category: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Nullable because "uncategorized" is a real state, not a gap to guess at.
    category_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
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
            "event_type IN ('operation_accepted', 'operation_reversed') "
            "AND actor_type = 'user'",
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


class FinanceOperationReversalRow(Base):
    """One operation withdrawn from the ledger, and what replaced it.

    The reversed operation itself is never touched: it stays exactly as it was
    confirmed, and this row is the only statement that it stopped counting
    (ADR 0023). A removal is a reversal with no replacement; a correction is a
    reversal whose replacement is written in the same transaction.
    """

    __tablename__ = "finance_operation_reversals"
    __table_args__ = (
        CheckConstraint(
            "replacement_operation_id IS NULL "
            "OR replacement_operation_id <> operation_id",
            name="ck_finance_operation_reversals_distinct_replacement",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_operation_reversals_hash_length",
        ),
        # An operation is reversed once. A double tap, a retried request, and a
        # replayed command all land on the same row instead of withdrawing the
        # same money twice.
        UniqueConstraint(
            "operation_id",
            name="uq_finance_operation_reversals_operation",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_operation_reversals_user_command",
        ),
        # A replacement replaces one original, so a correction cannot be made
        # to stand in for two different operations.
        UniqueConstraint(
            "replacement_operation_id",
            name="uq_finance_operation_reversals_replacement",
        ),
        # Composite keys: a reversal that reaches across users is
        # unrepresentable rather than merely validated.
        ForeignKeyConstraint(
            ["operation_id", "user_id"],
            ["finance_operations.id", "finance_operations.user_id"],
            name="fk_finance_operation_reversals_owned_operation",
            ondelete="CASCADE",
        ),
        ForeignKeyConstraint(
            ["replacement_operation_id", "user_id"],
            ["finance_operations.id", "finance_operations.user_id"],
            name="fk_finance_operation_reversals_owned_replacement",
        ),
        Index(
            "ix_finance_operation_reversals_user_created",
            "user_id",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    operation_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Null means the user removed the operation rather than correcting it.
    # The distinction is derived from this column and never stored twice.
    replacement_operation_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), nullable=True
    )
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
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
            "event_type IN ('finance.operation.accepted.v1', "
            "'finance.operation.reversed.v1')",
            name="ck_finance_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_outbox_attempt_count",
        ),
        CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_outbox_validation_failure_count",
        ),
        CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_finance_outbox_delivery_state",
        ),
        CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_outbox_failure_metadata",
        ),
        CheckConstraint(
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
            name="ck_finance_outbox_operational_timestamps",
        ),
        UniqueConstraint(
            "aggregate_id",
            "event_type",
            name="uq_finance_outbox_aggregate_event",
        ),
        Index("ix_finance_outbox_unpublished", "published_at", "created_at"),
        Index(
            "ix_finance_outbox_pending_ready",
            "next_attempt_at",
            "created_at",
            "id",
            postgresql_where=text("published_at IS NULL AND dead_lettered_at IS NULL"),
        ),
        Index(
            "ix_finance_outbox_dead_lettered",
            "dead_lettered_at",
            "created_at",
            "id",
            postgresql_where=text("dead_lettered_at IS NOT NULL"),
        ),
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
    validation_failure_count: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    failure_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dead_lettered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class FinanceBudgetRow(Base):
    """A monthly spending ceiling (ADR 0027).

    Stores the limit and nothing else. What has been spent against it is
    derived from committed operations at read time, exactly as a goal's balance
    and a plan's due state are — a stored total is a second answer that can
    disagree with the operations it claims to summarise, silently.

    ``category_id`` is null for the overall monthly ceiling. That is a
    meaningful value, not a missing one.
    """

    __tablename__ = "finance_budgets"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_budgets_schema_version",
        ),
        CheckConstraint(
            "limit_amount > 0 AND limit_amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_budgets_positive_finite_limit",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_finance_budgets_v1_currency",
        ),
        CheckConstraint(
            "status IN ('active', 'removed')",
            name="ck_finance_budgets_status",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_budgets_payload_hash_length",
        ),
        CheckConstraint(
            "updated_at >= created_at "
            "AND created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_budgets_operational_timestamps",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_budgets_user_command",
        ),
        UniqueConstraint("id", "user_id", name="uq_finance_budgets_id_user"),
        ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_budgets_owned_account_currency",
        ),
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_budgets_owned_category",
        ),
        Index(
            "uq_finance_budgets_active_category",
            "user_id",
            "category_id",
            unique=True,
            postgresql_where=text("category_id IS NOT NULL AND status = 'active'"),
        ),
        # A plain unique would not say "one overall ceiling": PostgreSQL treats
        # NULLs as distinct, so every one of them would be allowed.
        Index(
            "uq_finance_budgets_active_overall",
            "user_id",
            unique=True,
            postgresql_where=text("category_id IS NULL AND status = 'active'"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    category_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        nullable=True,
    )
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    limit_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceTransferRow(Base):
    """One movement of money between two wallets of the same person.

    An entity of its own rather than a third `operation_type`, for the same
    reason a reversal is its own row (ADR 0023): every existing read would
    otherwise have to learn to exclude it from income, expense, net flow, the
    trend, the category breakdown and every budget, and missing one of them is
    a silently wrong total. Here the default is exclusion and only the balance
    opts in.

    **Both sides carry their own amount**, because that is what the person
    actually witnessed: 100 € left one wallet and 108 $ arrived in the other.
    No rate is stored — it is implied by the two amounts, and a stored copy is
    a second answer that can disagree with the first (ADR 0029).
    """

    __tablename__ = "finance_transfers"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_transfers_schema_version",
        ),
        CheckConstraint(
            "from_account_id <> to_account_id",
            name="ck_finance_transfers_distinct_wallets",
        ),
        CheckConstraint(
            "from_amount > 0 AND to_amount > 0",
            name="ck_finance_transfers_positive_amounts",
        ),
        CheckConstraint(
            "from_amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric) AND "
            "to_amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_transfers_finite_amounts",
        ),
        CheckConstraint(
            "from_currency ~ '^[A-Z]{3}$' AND to_currency ~ '^[A-Z]{3}$'",
            name="ck_finance_transfers_currency_shape",
        ),
        CheckConstraint(
            "occurred_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_transfers_occurred_on_range",
        ),
        CheckConstraint(
            "status = 'confirmed'",
            name="ck_finance_transfers_v1_status",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_transfers_payload_hash_length",
        ),
        CheckConstraint(
            "captured_timezone = btrim(captured_timezone) AND "
            "captured_timezone <> '' AND "
            "captured_timezone !~ '[[:cntrl:]]' AND "
            "captured_timezone NOT IN ('Factory', 'localtime', 'posixrules')",
            name="ck_finance_transfers_captured_timezone",
        ),
        # Each side's currency must be the currency of the wallet it names.
        # The same composite key every other money table uses, so a transfer
        # cannot invent a currency a wallet does not hold.
        ForeignKeyConstraint(
            ["from_account_id", "user_id", "from_currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_transfers_from_account_currency",
        ),
        ForeignKeyConstraint(
            ["to_account_id", "user_id", "to_currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_transfers_to_account_currency",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_transfers_user_command",
        ),
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_finance_transfers_id_user",
        ),
        Index("ix_finance_transfers_user_occurred_on", "user_id", "occurred_on"),
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
    from_account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    from_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    from_currency: Mapped[str] = mapped_column(String(3), nullable=False)
    to_account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    to_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    to_currency: Mapped[str] = mapped_column(String(3), nullable=False)
    captured_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    captured_timezone: Mapped[str] = mapped_column(String(128), nullable=False)
    #: The local date the money moved, frozen at capture like every other
    #: authoritative date (ADR 0007).
    occurred_on: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    confirmed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceTransferAuditRow(Base):
    __tablename__ = "finance_transfer_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type = 'transfer_confirmed' AND actor_type = 'user'",
            name="ck_finance_transfer_audit_event_type",
        ),
        CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_transfer_audit_hash_length",
        ),
        ForeignKeyConstraint(
            ["transfer_id", "user_id"],
            ["finance_transfers.id", "finance_transfers.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "transfer_id",
            "command_id",
            name="uq_finance_transfer_audit_transfer_command",
        ),
        Index("ix_finance_transfer_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    transfer_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceTransferOutboxEventRow(Base):
    """Identifier-only Home invalidation for a transfer.

    Its own table for the reason every other one has: `finance_outbox_events`
    pins a single aggregate type, and the projector dead-letters event types it
    does not know (ADR 0012).
    """

    __tablename__ = "finance_transfer_outbox_events"
    __table_args__ = (
        CheckConstraint(
            "aggregate_type = 'finance_transfer'",
            name="ck_finance_transfer_outbox_aggregate_type",
        ),
        CheckConstraint(
            "event_type = 'finance.transfer.accepted.v1'",
            name="ck_finance_transfer_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_transfer_outbox_attempt_count",
        ),
        CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_transfer_outbox_validation_failure_count",
        ),
        CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_finance_transfer_outbox_delivery_state",
        ),
        CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_transfer_outbox_failure_metadata",
        ),
        CheckConstraint(
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
            name="ck_finance_transfer_outbox_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_transfers.id", "finance_transfers.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_transfer_outbox_aggregate_command",
        ),
        Index(
            "ix_finance_transfer_outbox_pending_ready",
            "next_attempt_at",
            "created_at",
            "id",
            postgresql_where=text("published_at IS NULL AND dead_lettered_at IS NULL"),
        ),
        Index(
            "ix_finance_transfer_outbox_dead_lettered",
            "dead_lettered_at",
            "created_at",
            "id",
            postgresql_where=text("dead_lettered_at IS NOT NULL"),
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
    validation_failure_count: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    failure_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dead_lettered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class FinanceBudgetAuditRow(Base):
    """Append-only record of every ceiling that was set, changed or removed."""

    __tablename__ = "finance_budget_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('budget_set', 'budget_changed', 'budget_removed')",
            name="ck_finance_budget_audit_event_type",
        ),
        CheckConstraint(
            "(event_type = 'budget_set' AND previous_limit IS NULL "
            "AND new_limit IS NOT NULL) OR "
            "(event_type = 'budget_changed' AND previous_limit IS NOT NULL "
            "AND new_limit IS NOT NULL) OR "
            "(event_type = 'budget_removed' AND previous_limit IS NOT NULL "
            "AND new_limit IS NULL)",
            name="ck_finance_budget_audit_limits",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_budget_audit_hash_length",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_budget_audit_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["budget_id", "user_id"],
            ["finance_budgets.id", "finance_budgets.user_id"],
            ondelete="CASCADE",
            name="fk_finance_budget_audit_owned_budget",
        ),
        UniqueConstraint(
            "budget_id",
            "command_id",
            name="uq_finance_budget_audit_budget_command",
        ),
        Index("ix_finance_budget_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    budget_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    previous_limit: Mapped[Decimal | None] = mapped_column(
        Numeric(38, 18),
        nullable=True,
    )
    new_limit: Mapped[Decimal | None] = mapped_column(Numeric(38, 18), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class PlannedCostRecurrenceRow(Base):
    """A rule that generates planned instances (ADR 0025).

    The rule itself is never a payment. It holds intent; every date it implies
    becomes an ordinary ``planned_costs`` row, so confirming, skipping and
    cancelling keep working exactly as they already do.

    The anchor day is stored as the user meant it — 31 stays 31 — and each
    occurrence clamps it into its own month at generation time. Storing a
    already-clamped day would lose the intent after the first February.
    """

    __tablename__ = "planned_cost_recurrences"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_planned_cost_recurrences_schema_version",
        ),
        CheckConstraint(
            "amount > 0 AND amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_planned_cost_recurrences_positive_finite_amount",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_planned_cost_recurrences_v1_currency",
        ),
        CheckConstraint(
            "title = btrim(title) AND title <> '' AND title !~ '[[:cntrl:]]' AND "
            "(category IS NULL OR (category = btrim(category) AND "
            "category <> '' AND category !~ '[[:cntrl:]]'))",
            name="ck_planned_cost_recurrences_text",
        ),
        # Monthly only for now (ADR 0025). Weekly and yearly reuse the same
        # anchor machinery and are added by widening this list deliberately.
        CheckConstraint(
            "frequency = 'monthly'",
            name="ck_planned_cost_recurrences_frequency",
        ),
        CheckConstraint(
            "day_of_month BETWEEN 1 AND 31",
            name="ck_planned_cost_recurrences_day_of_month",
        ),
        CheckConstraint(
            "starts_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31' AND "
            "(ends_on IS NULL OR "
            "(ends_on >= starts_on AND "
            "ends_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'))",
            name="ck_planned_cost_recurrences_dates",
        ),
        CheckConstraint(
            "status IN ('active', 'ended')",
            name="ck_planned_cost_recurrences_status",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_planned_cost_recurrences_payload_hash_length",
        ),
        CheckConstraint(
            "updated_at >= created_at "
            "AND created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_planned_cost_recurrences_operational_timestamps",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_planned_cost_recurrences_user_command",
        ),
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_planned_cost_recurrences_id_user",
        ),
        ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_planned_cost_recurrences_owned_account_currency",
        ),
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_planned_cost_recurrences_owned_category",
        ),
        Index(
            "ix_planned_cost_recurrences_user_active",
            "user_id",
            postgresql_where=text("status = 'active'"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    title: Mapped[str] = mapped_column(String(100), nullable=False)
    category: Mapped[str | None] = mapped_column(String(100), nullable=True)
    category_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    frequency: Mapped[str] = mapped_column(String(16), nullable=False)
    day_of_month: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    starts_on: Mapped[date] = mapped_column(Date, nullable=False)
    ends_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class PlannedCostRecurrenceAuditRow(Base):
    """Append-only record of what happened to a rule.

    The instances a rule generates keep their own audit rows in
    ``planned_cost_audit_events``; this table records only the rule.
    """

    __tablename__ = "planned_cost_recurrence_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('recurrence_created', 'recurrence_ended')",
            name="ck_planned_cost_recurrence_audit_event_type",
        ),
        CheckConstraint(
            "(event_type = 'recurrence_created' AND previous_status IS NULL "
            "AND new_status = 'active') OR "
            "(event_type = 'recurrence_ended' AND previous_status = 'active' "
            "AND new_status = 'ended')",
            name="ck_planned_cost_recurrence_audit_transition",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_planned_cost_recurrence_audit_hash_length",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_planned_cost_recurrence_audit_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["recurrence_id", "user_id"],
            [
                "planned_cost_recurrences.id",
                "planned_cost_recurrences.user_id",
            ],
            ondelete="CASCADE",
            name="fk_planned_cost_recurrence_audit_owned_recurrence",
        ),
        UniqueConstraint(
            "recurrence_id",
            "command_id",
            name="uq_planned_cost_recurrence_audit_recurrence_command",
        ),
        Index(
            "uq_planned_cost_recurrence_audit_single_create",
            "recurrence_id",
            unique=True,
            postgresql_where=text("event_type = 'recurrence_created'"),
        ),
        Index(
            "uq_planned_cost_recurrence_audit_single_end",
            "recurrence_id",
            unique=True,
            postgresql_where=text("event_type = 'recurrence_ended'"),
        ),
        Index(
            "ix_planned_cost_recurrence_audit_user_created",
            "user_id",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    recurrence_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    previous_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    new_status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class PlannedCostRow(Base):
    """Forecast-only intended payment (ADR 0018).

    This table is deliberately separate from ``finance_operations``. Nothing
    here may ever be summed into an authoritative balance, monthly total, net
    flow, or trend point.
    """

    __tablename__ = "planned_costs"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_planned_costs_schema_version",
        ),
        CheckConstraint(
            "amount > 0 AND amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_planned_costs_positive_finite_amount",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_planned_costs_v1_currency",
        ),
        CheckConstraint(
            "title = btrim(title) AND title <> '' AND title !~ '[[:cntrl:]]' AND "
            "(category IS NULL OR (category = btrim(category) AND "
            "category <> '' AND category !~ '[[:cntrl:]]'))",
            name="ck_planned_costs_text",
        ),
        CheckConstraint(
            "planned_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_planned_costs_planned_on_range",
        ),
        CheckConstraint(
            "status IN ('planned', 'confirmed', 'skipped', 'cancelled')",
            name="ck_planned_costs_status",
        ),
        # A confirmed plan always points at the real operation that settled it,
        # and an unconfirmed plan never carries such a link.
        CheckConstraint(
            "(status = 'confirmed') = (confirmed_operation_id IS NOT NULL) AND "
            "(status = 'confirmed') = (confirmed_operation_command_id IS NOT NULL)",
            name="ck_planned_costs_confirmation_link",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_planned_costs_payload_hash_length",
        ),
        CheckConstraint(
            "updated_at >= created_at "
            "AND created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_planned_costs_operational_timestamps",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_planned_costs_user_command",
        ),
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_planned_costs_id_user",
        ),
        # Pinning the currency through the account foreign key is what makes an
        # account/plan currency mismatch unrepresentable rather than merely
        # validated, exactly as finance_operations does.
        ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_planned_costs_owned_account_currency",
        ),
        # NO ACTION, not RESTRICT: deleting a user cascades to both operations
        # and planned costs in one statement, and the check is deferred to the
        # end of that statement so the cascade completes.
        ForeignKeyConstraint(
            ["confirmed_operation_id", "user_id"],
            ["finance_operations.id", "finance_operations.user_id"],
            name="fk_planned_costs_confirmed_operation",
        ),
        # The composite key makes borrowing another user's category
        # unrepresentable rather than merely validated (ADR 0020).
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_planned_costs_owned_category",
        ),
        ForeignKeyConstraint(
            ["recurrence_id", "user_id"],
            [
                "planned_cost_recurrences.id",
                "planned_cost_recurrences.user_id",
            ],
            name="fk_planned_costs_owned_recurrence",
        ),
        Index("ix_planned_costs_user_planned_on", "user_id", "planned_on"),
        Index(
            "ix_planned_costs_user_outstanding",
            "user_id",
            "planned_on",
            postgresql_where=text("status = 'planned'"),
        ),
        # What actually makes materialisation idempotent (ADR 0025): one live
        # instance per rule per date, enforced by the database rather than by
        # the generator remembering to look first. Cancelled rows are excluded
        # so editing a rule can regenerate the same date it just superseded.
        Index(
            "uq_planned_costs_recurrence_occurrence",
            "recurrence_id",
            "planned_on",
            unique=True,
            postgresql_where=text(
                "recurrence_id IS NOT NULL AND status <> 'cancelled'"
            ),
        ),
        Index(
            "ix_planned_costs_recurrence",
            "recurrence_id",
            postgresql_where=text("recurrence_id IS NOT NULL"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    title: Mapped[str] = mapped_column(String(100), nullable=False)
    # Kept as the evidence of what the user wrote, exactly as operations do.
    category: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Nullable because "uncategorized" is a real state, not a gap to guess at.
    category_id: Mapped[UUID | None] = mapped_column(Uuid(as_uuid=True), nullable=True)
    # Set only on an instance a rule generated. A one-off plan has none, which
    # is the whole difference between the two (ADR 0025).
    recurrence_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        nullable=True,
    )
    planned_on: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    confirmed_operation_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        nullable=True,
    )
    confirmed_operation_command_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class PlannedCostAuditRow(Base):
    __tablename__ = "planned_cost_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('planned_cost_created', 'planned_cost_confirmed', "
            "'planned_cost_skipped', 'planned_cost_cancelled') "
            # 'recurrence' only ever creates. Every transition is still someone
            # deciding something, and the trail must not claim a user typed a
            # row a rule generated on its own (ADR 0025).
            "AND ((actor_type = 'user') OR "
            "(actor_type = 'recurrence' AND event_type = 'planned_cost_created'))",
            name="ck_planned_cost_audit_event_type",
        ),
        # Creation has no predecessor; every transition starts from 'planned'
        # and lands on exactly the status its event names.
        CheckConstraint(
            "(event_type = 'planned_cost_created' AND previous_status IS NULL "
            "AND new_status = 'planned') OR "
            "(event_type = 'planned_cost_confirmed' AND previous_status = 'planned' "
            "AND new_status = 'confirmed') OR "
            "(event_type = 'planned_cost_skipped' AND previous_status = 'planned' "
            "AND new_status = 'skipped') OR "
            "(event_type = 'planned_cost_cancelled' AND previous_status = 'planned' "
            "AND new_status = 'cancelled')",
            name="ck_planned_cost_audit_transition",
        ),
        CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_planned_cost_audit_hash_length",
        ),
        ForeignKeyConstraint(
            ["planned_cost_id", "user_id"],
            ["planned_costs.id", "planned_costs.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "planned_cost_id",
            "command_id",
            name="uq_planned_cost_audit_plan_command",
        ),
        Index(
            "uq_planned_cost_audit_single_create",
            "planned_cost_id",
            unique=True,
            postgresql_where=text("event_type = 'planned_cost_created'"),
        ),
        # One terminal transition per plan: the lifecycle has no path back to
        # 'planned', so a second transition row must be impossible.
        Index(
            "uq_planned_cost_audit_single_transition",
            "planned_cost_id",
            unique=True,
            postgresql_where=text("event_type <> 'planned_cost_created'"),
        ),
        Index("ix_planned_cost_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    planned_cost_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    previous_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    new_status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class PlannedCostOutboxEventRow(Base):
    """Identifier-only Home invalidation for planned-cost changes.

    Kept separate from ``finance_outbox_events`` because that table pins a
    single aggregate and event type, and because the Home projector dead-letters
    event types it does not know (ADR 0012). Rows accumulate here unpublished
    until the upcoming-payments slice turns consumption on, which is why no
    backfill will be needed then.
    """

    __tablename__ = "planned_cost_outbox_events"
    __table_args__ = (
        CheckConstraint(
            "aggregate_type = 'planned_cost'",
            name="ck_planned_cost_outbox_aggregate_type",
        ),
        CheckConstraint(
            "event_type IN ('finance.planned_cost.created.v1', "
            "'finance.planned_cost.transitioned.v1')",
            name="ck_planned_cost_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_planned_cost_outbox_attempt_count",
        ),
        CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_planned_cost_outbox_validation_failure_count",
        ),
        CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_planned_cost_outbox_delivery_state",
        ),
        CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_planned_cost_outbox_failure_metadata",
        ),
        CheckConstraint(
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
            name="ck_planned_cost_outbox_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["planned_costs.id", "planned_costs.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_planned_cost_outbox_aggregate_command",
        ),
        Index(
            "ix_planned_cost_outbox_pending_ready",
            "next_attempt_at",
            "created_at",
            "id",
            postgresql_where=text("published_at IS NULL AND dead_lettered_at IS NULL"),
        ),
        Index(
            "ix_planned_cost_outbox_dead_lettered",
            "dead_lettered_at",
            "created_at",
            "id",
            postgresql_where=text("dead_lettered_at IS NOT NULL"),
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
    validation_failure_count: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    failure_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dead_lettered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class FinanceCategoryRow(Base):
    """One owned spending or income category (ADR 0020).

    A category is a label, never money. Nothing here may reach a balance, a
    monthly total, a net flow, or a trend point.

    Seeded rows carry a stable ``system_key`` so the client can render a
    localized label instead of the Russian name stored here. Renaming clears
    that key: once a user names it themselves, it is their category and a
    translated label would contradict their choice.
    """

    __tablename__ = "finance_categories"
    __table_args__ = (
        CheckConstraint(
            "name = btrim(name) AND name <> '' AND name !~ '[[:cntrl:]]'",
            name="ck_finance_categories_name_text",
        ),
        CheckConstraint(
            "direction IN ('expense', 'income')",
            name="ck_finance_categories_direction",
        ),
        # A key is either absent or a stable lowercase slug; it never carries
        # user-authored text.
        CheckConstraint(
            "system_key IS NULL OR system_key ~ '^[a-z][a-z0-9_]{0,62}$'",
            name="ck_finance_categories_system_key",
        ),
        CheckConstraint(
            "archived_at IS NULL OR archived_at >= created_at",
            name="ck_finance_categories_archived_after_created",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_categories_operational_timestamps",
        ),
        # The point of the catalogue: two spellings of one name cannot become
        # two categories. Archived rows are excluded so a hidden name can be
        # reused.
        Index(
            "uq_finance_categories_active_name",
            "user_id",
            "direction",
            text("lower(name)"),
            unique=True,
            postgresql_where=text("archived_at IS NULL"),
        ),
        # A seeded key appears at most once per user, so re-running the seed is
        # idempotent rather than duplicating the starting set.
        Index(
            "uq_finance_categories_system_key",
            "user_id",
            "system_key",
            unique=True,
            postgresql_where=text("system_key IS NOT NULL"),
        ),
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_finance_categories_id_user",
        ),
        # Lets a keyword row carry its direction and have the database prove it
        # matches this category's, rather than trusting whoever wrote the row.
        UniqueConstraint(
            "id",
            "direction",
            name="uq_finance_categories_id_direction",
        ),
        Index(
            "ix_finance_categories_user_active",
            "user_id",
            "direction",
            postgresql_where=text("archived_at IS NULL"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    direction: Mapped[str] = mapped_column(String(16), nullable=False)
    system_key: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    archived_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class FinanceCategoryAuditRow(Base):
    """Immutable record of every catalogue change (ADR 0020).

    A rename replaces the only stored copy of a name, so without this row the
    previous name would be unrecoverable. That matters because published Home
    projections and the operation's own free text both hold names, and telling
    a stale label from a wrong one later needs to know what the name was.

    There is no ``payload_hash`` because a category write carries no client
    command: the endpoints are idempotent by target state, and the command id
    here is minted by the server to tie one accepted write to its outbox event.
    """

    __tablename__ = "finance_category_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('category_created', 'category_renamed', "
            "'category_archived', 'category_restored') AND actor_type = 'user'",
            name="ck_finance_category_audit_event_type",
        ),
        # Only a rename carries names, and it must actually change one: a
        # request that renames a category to what it is already called is a
        # no-op the repository answers without writing anything here.
        CheckConstraint(
            "(event_type = 'category_created' AND previous_name IS NULL "
            "AND new_name IS NOT NULL) OR "
            "(event_type = 'category_renamed' AND previous_name IS NOT NULL "
            "AND new_name IS NOT NULL AND previous_name <> new_name) OR "
            "(event_type IN ('category_archived', 'category_restored') "
            "AND previous_name IS NULL AND new_name IS NULL)",
            name="ck_finance_category_audit_names",
        ),
        CheckConstraint(
            "(event_type = 'category_created' AND previous_status IS NULL "
            "AND new_status = 'active') OR "
            "(event_type = 'category_renamed' AND previous_status = 'active' "
            "AND new_status = 'active') OR "
            "(event_type = 'category_archived' AND previous_status = 'active' "
            "AND new_status = 'archived') OR "
            "(event_type = 'category_restored' AND previous_status = 'archived' "
            "AND new_status = 'active')",
            name="ck_finance_category_audit_transition",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_category_audit_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            ondelete="CASCADE",
            name="fk_finance_category_audit_owned_category",
        ),
        UniqueConstraint(
            "category_id",
            "command_id",
            name="uq_finance_category_audit_category_command",
        ),
        Index(
            "uq_finance_category_audit_single_create",
            "category_id",
            unique=True,
            postgresql_where=text("event_type = 'category_created'"),
        ),
        Index("ix_finance_category_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    category_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    previous_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    new_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    previous_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    new_status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceCategoryKeywordRow(Base):
    """One word that leads to a category (ADR 0020 step 3).

    A name and a keyword do different jobs. The name is what reports and the
    picker show, so it must stay readable; the keyword is what a written
    sentence is matched against. Keeping them apart is what lets a category be
    called "Автомобиль" while "заправил", "машина" and "car" all reach it, and
    what lets one catalogue serve four languages without a translation table.

    The stored form is already normalized, and the parser matches it from a
    word start, so one row covers an inflected form and a compound alike.
    """

    __tablename__ = "finance_category_keywords"
    __table_args__ = (
        CheckConstraint(
            "direction IN ('expense', 'income')",
            name="ck_finance_category_keywords_direction",
        ),
        CheckConstraint(
            "keyword = lower(keyword) AND char_length(keyword) >= 3 "
            "AND keyword !~ '[^[:alnum:]]'",
            name="ck_finance_category_keywords_word_shape",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_category_keywords_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            ondelete="CASCADE",
            name="fk_finance_category_keywords_owned_category",
        ),
        ForeignKeyConstraint(
            ["category_id", "direction"],
            ["finance_categories.id", "finance_categories.direction"],
            ondelete="CASCADE",
            name="fk_finance_category_keywords_direction",
        ),
        # One word means one category per direction, so a match can never
        # depend on row order. Archiving is ignored on purpose: a hidden
        # category keeps its name and therefore its words, and restoring it
        # must not collide with something claimed in the meantime.
        UniqueConstraint(
            "user_id",
            "direction",
            "keyword",
            name="uq_finance_category_keywords_word",
        ),
        Index("ix_finance_category_keywords_category", "category_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    category_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    direction: Mapped[str] = mapped_column(String(16), nullable=False)
    keyword: Mapped[str] = mapped_column(String(40), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceCategoryKeywordAuditRow(Base):
    """Immutable record of every keyword a user added or removed.

    Keywords decide where later entries land, so "why did this go to
    Автомобиль" has to be answerable after the fact.
    """

    __tablename__ = "finance_category_keyword_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('keyword_added', 'keyword_removed') "
            "AND actor_type = 'user'",
            name="ck_finance_category_keyword_audit_event_type",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_category_keyword_audit_timestamps",
        ),
        ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            ondelete="CASCADE",
            name="fk_finance_category_keyword_audit_owned_category",
        ),
        Index(
            "ix_finance_category_keyword_audit_category",
            "category_id",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    category_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    keyword: Mapped[str] = mapped_column(String(40), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceCategoryOutboxEventRow(Base):
    """Identifier-only Home invalidation for a renamed category (ADR 0020).

    Only a rename is published. A published Home projection stores the label it
    resolved through the operation's category link, so renaming a category makes
    every projection holding that label stale. Creating, archiving, and
    restoring change nothing already published: an archived category stays
    linked to its historical operations and keeps its name.

    Separate from the four existing outboxes for the reason ADR 0018
    established: each pins one ``aggregate_type`` and a closed set of event
    types, and the projector dead-letters types it does not know (ADR 0012).
    """

    __tablename__ = "finance_category_outbox_events"
    __table_args__ = (
        CheckConstraint(
            "aggregate_type = 'finance_category'",
            name="ck_finance_category_outbox_aggregate_type",
        ),
        CheckConstraint(
            "event_type = 'finance.category.renamed.v1'",
            name="ck_finance_category_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_category_outbox_attempt_count",
        ),
        CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_category_outbox_validation_failure_count",
        ),
        CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_finance_category_outbox_delivery_state",
        ),
        CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_category_outbox_failure_metadata",
        ),
        CheckConstraint(
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
            name="ck_finance_category_outbox_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_category_outbox_aggregate_command",
        ),
        Index(
            "ix_finance_category_outbox_pending_ready",
            "next_attempt_at",
            "created_at",
            "id",
            postgresql_where=text("published_at IS NULL AND dead_lettered_at IS NULL"),
        ),
        Index(
            "ix_finance_category_outbox_dead_lettered",
            "dead_lettered_at",
            "created_at",
            "id",
            postgresql_where=text("dead_lettered_at IS NOT NULL"),
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
    validation_failure_count: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    failure_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dead_lettered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class FinanceGoalRow(Base):
    """Savings target (ADR 0019).

    The goal stores only what the user declared. ``current``, ``progress``, and
    ``achieved`` are derived from ``finance_goal_contributions`` at read time, so
    there is no running total here that could drift from its own ledger.

    Nothing in this table or its ledger may be summed into an authoritative
    balance, monthly total, net flow, or trend point.
    """

    __tablename__ = "finance_goals"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_goals_schema_version",
        ),
        CheckConstraint(
            "target_amount > 0 AND target_amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_goals_positive_finite_target",
        ),
        # Zero is the honest encoding of "no declared monthly plan".
        CheckConstraint(
            "monthly_contribution >= 0 AND monthly_contribution NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_goals_monthly_contribution",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_finance_goals_v1_currency",
        ),
        CheckConstraint(
            "title = btrim(title) AND title <> '' AND title !~ '[[:cntrl:]]'",
            name="ck_finance_goals_text",
        ),
        CheckConstraint(
            "target_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_goals_target_on_range",
        ),
        CheckConstraint(
            "status IN ('active', 'cancelled')",
            name="ck_finance_goals_status",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_goals_payload_hash_length",
        ),
        CheckConstraint(
            "updated_at >= created_at "
            "AND created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' "
            "AND updated_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_goals_operational_timestamps",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_goals_user_command",
        ),
        UniqueConstraint(
            "id",
            "user_id",
            name="uq_finance_goals_id_user",
        ),
        # Pinning the currency through the account foreign key makes an
        # account/goal currency mismatch unrepresentable rather than merely
        # validated, exactly as planned costs and operations do.
        ForeignKeyConstraint(
            ["account_id", "user_id", "currency"],
            [
                "finance_accounts.id",
                "finance_accounts.user_id",
                "finance_accounts.currency",
            ],
            name="fk_finance_goals_owned_account_currency",
        ),
        # Serves primary-goal selection: the active goal with the earliest
        # target date, which is the only ordering Home needs.
        Index(
            "ix_finance_goals_user_active_target",
            "user_id",
            "target_on",
            postgresql_where=text("status = 'active'"),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    title: Mapped[str] = mapped_column(String(100), nullable=False)
    target_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    monthly_contribution: Mapped[Decimal] = mapped_column(
        Numeric(38, 18),
        nullable=False,
    )
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    target_on: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceGoalContributionRow(Base):
    """Append-only ledger entry earmarking money for one goal (ADR 0019).

    Immutable by design: a mistaken entry is corrected by an opposite entry, so
    both the mistake and the fix stay visible behind the figure a user is shown.
    A contribution never moves money — it allocates balance that is already
    there — so it must never reach an authoritative total.
    """

    __tablename__ = "finance_goal_contributions"
    __table_args__ = (
        CheckConstraint(
            "schema_version = '1'",
            name="ck_finance_goal_contributions_schema_version",
        ),
        CheckConstraint(
            "amount > 0 AND amount NOT IN "
            "('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)",
            name="ck_finance_goal_contributions_positive_finite_amount",
        ),
        # Two positive directions rather than one signed amount: a sign error
        # would silently reverse meaning, and every money column here is
        # constrained positive.
        CheckConstraint(
            "direction IN ('deposit', 'withdrawal')",
            name="ck_finance_goal_contributions_direction",
        ),
        CheckConstraint(
            "currency ~ '^[A-Z]{3}$'",
            name="ck_finance_goal_contributions_v1_currency",
        ),
        CheckConstraint(
            "occurred_on BETWEEN DATE '1900-01-01' AND DATE '2100-12-31'",
            name="ck_finance_goal_contributions_occurred_on_range",
        ),
        CheckConstraint(
            "octet_length(command_payload_hash) = 32",
            name="ck_finance_goal_contributions_payload_hash_length",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_goal_contributions_operational_timestamps",
        ),
        UniqueConstraint(
            "user_id",
            "command_id",
            name="uq_finance_goal_contributions_user_command",
        ),
        # The composite key is what makes attaching an entry to another user's
        # goal unrepresentable rather than merely checked.
        ForeignKeyConstraint(
            ["goal_id", "user_id"],
            ["finance_goals.id", "finance_goals.user_id"],
            ondelete="CASCADE",
            name="fk_finance_goal_contributions_owned_goal",
        ),
        Index(
            "ix_finance_goal_contributions_goal_occurred",
            "goal_id",
            "occurred_on",
            "id",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    goal_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    schema_version: Mapped[str] = mapped_column(String(16), nullable=False)
    direction: Mapped[str] = mapped_column(String(16), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    occurred_on: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceGoalAuditRow(Base):
    __tablename__ = "finance_goal_audit_events"
    __table_args__ = (
        CheckConstraint(
            "event_type IN ('goal_created', 'goal_cancelled', "
            "'goal_contribution_recorded') AND actor_type = 'user'",
            name="ck_finance_goal_audit_event_type",
        ),
        # Creation has no predecessor. A contribution never changes the goal's
        # status, so both of its status columns stay 'active'.
        CheckConstraint(
            "(event_type = 'goal_created' AND previous_status IS NULL "
            "AND new_status = 'active') OR "
            "(event_type = 'goal_cancelled' AND previous_status = 'active' "
            "AND new_status = 'cancelled') OR "
            "(event_type = 'goal_contribution_recorded' "
            "AND previous_status = 'active' AND new_status = 'active')",
            name="ck_finance_goal_audit_transition",
        ),
        CheckConstraint(
            "(event_type = 'goal_contribution_recorded') "
            "= (contribution_id IS NOT NULL)",
            name="ck_finance_goal_audit_contribution_link",
        ),
        CheckConstraint(
            "octet_length(payload_hash) = 32",
            name="ck_finance_goal_audit_hash_length",
        ),
        CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_goal_audit_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["goal_id", "user_id"],
            ["finance_goals.id", "finance_goals.user_id"],
            ondelete="CASCADE",
            name="fk_finance_goal_audit_owned_goal",
        ),
        UniqueConstraint(
            "goal_id",
            "command_id",
            name="uq_finance_goal_audit_goal_command",
        ),
        Index(
            "uq_finance_goal_audit_single_create",
            "goal_id",
            unique=True,
            postgresql_where=text("event_type = 'goal_created'"),
        ),
        # Cancellation is terminal, so a second cancellation row must be
        # impossible even if a caller retried with a fresh command id.
        Index(
            "uq_finance_goal_audit_single_cancel",
            "goal_id",
            unique=True,
            postgresql_where=text("event_type = 'goal_cancelled'"),
        ),
        Index("ix_finance_goal_audit_user_created", "user_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    goal_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    user_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    command_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    contribution_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        nullable=True,
    )
    event_type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)
    payload_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    previous_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    new_status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )


class FinanceGoalOutboxEventRow(Base):
    """Identifier-only Home invalidation for goal changes.

    Separate from the operation and planned-cost outboxes for the reason ADR
    0018 established: those tables pin one ``aggregate_type`` and a closed set of
    event types, and the Home projector dead-letters types it does not know
    (ADR 0012). Rows accumulate here unpublished until the Home ``primaryGoal``
    slice turns consumption on, so no backfill will be needed then.
    """

    __tablename__ = "finance_goal_outbox_events"
    __table_args__ = (
        CheckConstraint(
            "aggregate_type = 'finance_goal'",
            name="ck_finance_goal_outbox_aggregate_type",
        ),
        CheckConstraint(
            "event_type IN ('finance.goal.created.v1', "
            "'finance.goal.cancelled.v1', 'finance.goal.contributed.v1')",
            name="ck_finance_goal_outbox_event_type",
        ),
        CheckConstraint(
            "attempt_count >= 0",
            name="ck_finance_goal_outbox_attempt_count",
        ),
        CheckConstraint(
            "validation_failure_count >= 0 "
            "AND validation_failure_count <= attempt_count",
            name="ck_finance_goal_outbox_validation_failure_count",
        ),
        CheckConstraint(
            "(published_at IS NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NOT NULL) OR "
            "(published_at IS NOT NULL AND dead_lettered_at IS NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(published_at IS NULL AND dead_lettered_at IS NOT NULL "
            "AND next_attempt_at IS NULL AND last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract')",
            name="ck_finance_goal_outbox_delivery_state",
        ),
        CheckConstraint(
            "(last_failed_at IS NULL AND failure_code IS NULL) OR "
            "(last_failed_at IS NOT NULL "
            "AND failure_code = 'invalid_outbox_contract' "
            "AND validation_failure_count > 0)",
            name="ck_finance_goal_outbox_failure_metadata",
        ),
        CheckConstraint(
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
            name="ck_finance_goal_outbox_operational_timestamps",
        ),
        ForeignKeyConstraint(
            ["aggregate_id", "user_id"],
            ["finance_goals.id", "finance_goals.user_id"],
            ondelete="CASCADE",
        ),
        UniqueConstraint(
            "aggregate_id",
            "command_id",
            name="uq_finance_goal_outbox_aggregate_command",
        ),
        Index(
            "ix_finance_goal_outbox_pending_ready",
            "next_attempt_at",
            "created_at",
            "id",
            postgresql_where=text("published_at IS NULL AND dead_lettered_at IS NULL"),
        ),
        Index(
            "ix_finance_goal_outbox_dead_lettered",
            "dead_lettered_at",
            "created_at",
            "id",
            postgresql_where=text("dead_lettered_at IS NOT NULL"),
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
    validation_failure_count: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
    )
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    failure_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    dead_lettered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )


class HomeProjectorRuntimeStateRow(Base):
    """Singleton operational heartbeat for the active Home projector lease."""

    __tablename__ = "home_projector_runtime_state"
    __table_args__ = (
        CheckConstraint(
            "singleton_id = 1",
            name="ck_home_projector_runtime_state_singleton",
        ),
        CheckConstraint(
            "lease_id <> '00000000-0000-0000-0000-000000000000'::uuid",
            name="ck_home_projector_runtime_state_lease_id",
        ),
        CheckConstraint(
            "started_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' AND "
            "started_at < TIMESTAMPTZ '2101-01-01 00:00:00+00' AND "
            "heartbeat_at >= started_at AND "
            "heartbeat_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_home_projector_runtime_state_timestamps",
        ),
        CheckConstraint(
            "last_cycle_status IN "
            "('starting', 'idle', 'published', 'retry_scheduled', "
            "'degraded', 'stopped')",
            name="ck_home_projector_runtime_state_status",
        ),
    )

    singleton_id: Mapped[int] = mapped_column(
        SmallInteger,
        primary_key=True,
        default=1,
    )
    lease_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    heartbeat_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    last_cycle_status: Mapped[str] = mapped_column(String(32), nullable=False)


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
            "projection_schema_version > 0",
            name="ck_home_projection_snapshots_schema_version",
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
        # A revision belongs to one wallet: a user may hold several, one
        # currency each, and their balances are never summed (ADR 0029).
        ForeignKeyConstraint(
            ["account_id", "user_id"],
            ["finance_accounts.id", "finance_accounts.user_id"],
            ondelete="CASCADE",
            name="fk_home_projection_snapshots_owned_account",
        ),
        UniqueConstraint(
            "user_id",
            "account_id",
            "timezone_name",
            "period_start",
            "revision",
            name="uq_home_projection_snapshots_account_timezone_period_revision",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    account_id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    timezone_name: Mapped[str] = mapped_column(String(128), nullable=False)
    period_start: Mapped[date] = mapped_column(Date, nullable=False)
    period_end: Mapped[date] = mapped_column(Date, nullable=False)
    revision: Mapped[int] = mapped_column(BigInteger, nullable=False)
    projection_schema_version: Mapped[int] = mapped_column(
        SmallInteger,
        nullable=False,
        server_default="1",
    )
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
    balance_delta_percent: Mapped[Decimal | None] = mapped_column(
        Numeric(38, 18),
        nullable=True,
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
        # `due_on` is authoritative and `due_at` is an optional exact instant.
        # Their agreement cannot be a CHECK here: the timezone lives on the
        # snapshot row, and a CHECK may not contain a subquery. The projection
        # builder enforces it instead, covered by a test.
        Index(
            "ix_home_projection_upcoming_payments_order",
            "snapshot_id",
            "due_on",
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
    due_on: Mapped[date] = mapped_column(Date, nullable=False)
    due_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    base_amount: Mapped[Decimal] = mapped_column(Numeric(38, 18), nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False)
    status: Mapped[str] = mapped_column(String(64), nullable=False)


class HomeProjectionTransactionRow(Base):
    __tablename__ = "home_projection_recent_transactions"
    __table_args__ = (
        CheckConstraint(
            "btrim(transaction_id) <> '' "
            "AND (title IS NULL OR btrim(title) <> '') "
            "AND (category IS NULL OR btrim(category) <> '') "
            "AND btrim(direction) <> ''",
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
            "position IS NULL OR position BETWEEN 0 AND 2",
            name="ck_home_projection_recent_transactions_position",
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
        UniqueConstraint(
            "snapshot_id",
            "position",
            name="uq_home_projection_recent_transactions_position",
        ),
    )

    snapshot_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey("home_projection_snapshots.id", ondelete="CASCADE"),
        primary_key=True,
    )
    transaction_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    position: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    title: Mapped[str | None] = mapped_column(String(160), nullable=True)
    category: Mapped[str | None] = mapped_column(String(160), nullable=True)
    occurred_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    occurred_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
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


def operation_counts() -> ColumnElement[bool]:
    """The single definition of "this operation still counts" (ADR 0023).

    Every read path uses it — the Home projection rebuild, Analytics, and the
    operation history — because two definitions of what counts is how two
    screens start disagreeing about the same money.
    """

    return ~(
        select(FinanceOperationReversalRow.id)
        .where(FinanceOperationReversalRow.operation_id == FinanceOperationRow.id)
        # Explicit: an uncorrelated subquery would silently become a cross
        # join and report every operation as reversed.
        .correlate(FinanceOperationRow)
        .exists()
    )
