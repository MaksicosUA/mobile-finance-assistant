"""Administering accounts from the host (ADR 0024).

The PostgreSQL E2E proves blocking and erasure against a real database. These
pin what must hold before a connection is ever opened — and the property of the
schema that erasure rests on, so a table added later cannot quietly break it.
"""

from __future__ import annotations

import pytest

from mobile_finance_api import account_admin
from mobile_finance_api.db_models import Base


def test_erasing_requires_the_address_twice() -> None:
    with pytest.raises(SystemExit):
        account_admin.parse_arguments(["delete", "owner@example.com"])


def test_a_mismatched_confirmation_never_opens_the_database(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """A typo must not get as far as a connection to what it would destroy."""

    def refuse(*_: object, **__: object) -> None:
        raise AssertionError("the database was opened")

    monkeypatch.setattr(account_admin, "create_database", refuse)
    monkeypatch.setattr(account_admin, "require_database_url", refuse)

    code = account_admin.main(
        ["delete", "owner@example.com", "--confirm", "other@example.com"]
    )

    assert code == account_admin.EXIT_REFUSED
    assert "Nothing was touched" in capsys.readouterr().err


def test_a_confirmation_is_compared_the_way_sign_in_compares() -> None:
    assert account_admin.same_address("Owner@Example.com", "  owner@example.com ")
    assert not account_admin.same_address("owner@example.com", "other@example.com")


def test_an_address_sign_in_would_reject_never_confirms_anything() -> None:
    # Two identical typos are still not an account.
    assert not account_admin.same_address("test3@gmai", "test3@gmai")


def test_every_table_with_user_rows_is_found_from_the_schema() -> None:
    names = {table.name for table in account_admin.user_tables()}

    assert "users" not in names
    assert {"auth_sessions", "finance_accounts", "finance_operations"} <= names
    assert names == {
        table.name
        for table in Base.metadata.tables.values()
        if "user_id" in table.c and table.name != "users"
    }


def _cascade_path_to_users(table_name: str, seen: tuple[str, ...] = ()) -> bool:
    table = Base.metadata.tables[table_name]
    for foreign_key in table.foreign_keys:
        if (foreign_key.constraint.ondelete or "").upper() != "CASCADE":
            continue
        target = foreign_key.column.table.name
        if target == "users":
            return True
        if target not in seen and _cascade_path_to_users(target, (*seen, table_name)):
            return True
    return False


def test_every_user_table_is_erased_with_its_user() -> None:
    """Erasure is one DELETE on the user row. That is only an erasure while
    every table holding a user's rows reaches ``users`` through foreign keys
    that all cascade — a table with a ``user_id`` and no such path would be left
    behind as orphans the projector then trips over."""

    unreachable = [
        table.name
        for table in account_admin.user_tables()
        if not _cascade_path_to_users(table.name)
    ]

    assert unreachable == []
