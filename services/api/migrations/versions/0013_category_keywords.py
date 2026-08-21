"""Give a category the words that lead to it.

Revision ID: 0013_category_keywords
Revises: 0012_category_management
Create Date: 2026-08-22

ADR 0020 step 3. A category name has one job — being readable in reports and
in the picker — and matching a written sentence is a different job. Conflating
them forces bad names: "Автомобиль" is the right label, but people write
"заправил", "машина", "car". Keywords separate the two, and they are what
makes one catalogue serve Russian, Ukrainian, German, and English without a
translation table.

A keyword is matched from a word start, so one entry covers an inflected form
("продукт" reads "продуктов") and a compound ("авто" reads "автохимию")
without a morphology dictionary.

Two rules are enforced here rather than in code. A word leads to exactly one
category per direction, so a match can never depend on row order. And that
uniqueness ignores archiving: a hidden category keeps its name (step 2b), so
it keeps its words too, and restoring it can never collide with something
claimed meanwhile.

No outbox event: keywords change no published label, so nothing already
projected becomes stale. Only a rename does that, and it already publishes.
"""

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

import sqlalchemy as sa
from alembic import op

from mobile_finance_api.category_contracts import (
    SEEDED_CATEGORIES,
    SEEDED_CATEGORY_KEYWORDS,
)

revision: str = "0013_category_keywords"
down_revision: str | None = "0012_category_management"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Lets a keyword row carry its direction and have the database guarantee
    # it matches the category's, instead of trusting the writer.
    op.create_unique_constraint(
        "uq_finance_categories_id_direction",
        "finance_categories",
        ["id", "direction"],
    )

    op.create_table(
        "finance_category_keywords",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("direction", sa.String(16), nullable=False),
        sa.Column("keyword", sa.String(40), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_finance_category_keywords"),
        sa.ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_category_keywords_owned_category",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["category_id", "direction"],
            ["finance_categories.id", "finance_categories.direction"],
            name="fk_finance_category_keywords_direction",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "user_id",
            "direction",
            "keyword",
            name="uq_finance_category_keywords_word",
        ),
        sa.CheckConstraint(
            "direction IN ('expense', 'income')",
            name="ck_finance_category_keywords_direction",
        ),
        # Stored already normalized: one spelling, no spaces, no punctuation,
        # and long enough that it describes a category instead of matching
        # everything.
        sa.CheckConstraint(
            "keyword = lower(keyword) AND char_length(keyword) >= 3 "
            "AND keyword !~ '[^[:alnum:]]'",
            name="ck_finance_category_keywords_word_shape",
        ),
        sa.CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_category_keywords_operational_timestamps",
        ),
    )
    op.create_index(
        "ix_finance_category_keywords_category",
        "finance_category_keywords",
        ["category_id"],
    )

    op.create_table(
        "finance_category_keyword_audit_events",
        sa.Column("id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("category_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("command_id", sa.Uuid(as_uuid=True), nullable=False),
        sa.Column("event_type", sa.String(32), nullable=False),
        sa.Column("actor_type", sa.String(16), nullable=False),
        sa.Column("keyword", sa.String(40), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name="pk_finance_category_keyword_audit_events"),
        sa.ForeignKeyConstraint(
            ["category_id", "user_id"],
            ["finance_categories.id", "finance_categories.user_id"],
            name="fk_finance_category_keyword_audit_owned_category",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(
            "event_type IN ('keyword_added', 'keyword_removed') "
            "AND actor_type = 'user'",
            name="ck_finance_category_keyword_audit_event_type",
        ),
        sa.CheckConstraint(
            "created_at >= TIMESTAMPTZ '1900-01-01 00:00:00+00' "
            "AND created_at < TIMESTAMPTZ '2101-01-01 00:00:00+00'",
            name="ck_finance_category_keyword_audit_timestamps",
        ),
    )
    op.create_index(
        "ix_finance_category_keyword_audit_category",
        "finance_category_keyword_audit_events",
        ["category_id", "created_at"],
    )

    _backfill_seeded_keywords()


def _backfill_seeded_keywords() -> None:
    """Give accounts that already exist the same starting vocabulary.

    Seeding only runs when an account is created, so without this every
    catalogue written before today would match nothing until its owner typed
    every word by hand. Only seeded categories are touched — a user-authored
    one has no key and no vocabulary anyone could guess for it.

    Nothing can collide: no keyword existed before this migration.
    """

    direction_of = {seeded.system_key: seeded.direction for seeded in SEEDED_CATEGORIES}
    connection = op.get_bind()
    created_at = datetime.now(UTC)
    insert = sa.text(
        "INSERT INTO finance_category_keywords"
        " (id, category_id, user_id, direction, keyword, created_at)"
        " SELECT :id, c.id, c.user_id, c.direction, :keyword, :created_at"
        " FROM finance_categories c"
        " WHERE c.id = :category_id"
        " ON CONFLICT DO NOTHING"
    )
    rows = connection.execute(
        sa.text(
            "SELECT id, system_key, direction FROM finance_categories"
            " WHERE system_key IS NOT NULL"
        )
    ).all()
    for category_id, system_key, direction in rows:
        # A renamed category keeps its key only until it is renamed, and a key
        # whose direction moved is not the category this vocabulary describes.
        if direction_of.get(system_key) != direction:
            continue
        for keyword in SEEDED_CATEGORY_KEYWORDS.get(system_key, ()):
            connection.execute(
                insert,
                {
                    "id": uuid.uuid4(),
                    "category_id": category_id,
                    "keyword": keyword,
                    "created_at": created_at,
                },
            )


def downgrade() -> None:
    op.drop_index(
        "ix_finance_category_keyword_audit_category",
        table_name="finance_category_keyword_audit_events",
    )
    op.drop_table("finance_category_keyword_audit_events")
    op.drop_index(
        "ix_finance_category_keywords_category",
        table_name="finance_category_keywords",
    )
    op.drop_table("finance_category_keywords")
    op.drop_constraint(
        "uq_finance_categories_id_direction",
        "finance_categories",
        type_="unique",
    )
