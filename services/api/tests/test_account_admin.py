"""Administering accounts from the host (ADR 0024).

The PostgreSQL E2E proves blocking and erasure against a real database. These
pin what must hold before a connection is ever opened — and the property of the
schema that erasure rests on, so a table added later cannot quietly break it.
"""

from __future__ import annotations

import io

import pytest

from mobile_finance_api import account_admin
from mobile_finance_api.account_data import user_tables
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
    names = {table.name for table in user_tables()}

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
        table.name for table in user_tables() if not _cascade_path_to_users(table.name)
    ]

    assert unreachable == []


# --- setting a password -------------------------------------------------------


class _Terminal:
    """A stdin that says it is a terminal, as `docker compose exec` without -T."""

    def isatty(self) -> bool:
        return True

    def readline(self) -> str:  # pragma: no cover - never read on a terminal
        raise AssertionError("a terminal password must come from getpass")


def _refuse_database(monkeypatch: pytest.MonkeyPatch) -> None:
    def refuse(*_: object, **__: object) -> None:
        raise AssertionError("the database was opened")

    monkeypatch.setattr(account_admin, "create_database", refuse)
    monkeypatch.setattr(account_admin, "require_database_url", refuse)


def _prompts(monkeypatch: pytest.MonkeyPatch, *answers: str) -> None:
    queue = list(answers)
    monkeypatch.setattr(
        account_admin.getpass, "getpass", lambda _prompt="": queue.pop(0)
    )


def test_a_password_is_never_taken_from_the_command_line() -> None:
    """Arguments land in shell history and in the process list."""

    with pytest.raises(SystemExit):
        account_admin.parse_arguments(
            ["set-password", "owner@example.com", "synthetic-new-password-42"]
        )


def test_two_different_passwords_change_nothing(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    _refuse_database(monkeypatch)
    monkeypatch.setattr(account_admin.sys, "stdin", _Terminal())
    _prompts(monkeypatch, "synthetic-new-password-42", "synthetic-new-password-43")

    code = account_admin.main(["set-password", "owner@example.com"])

    assert code == account_admin.EXIT_REFUSED
    assert "Nothing was changed" in capsys.readouterr().err


def test_a_password_the_policy_refuses_never_reaches_the_database(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    _refuse_database(monkeypatch)
    monkeypatch.setattr(account_admin.sys, "stdin", _Terminal())
    _prompts(monkeypatch, "short", "short")

    code = account_admin.main(["set-password", "owner@example.com"])

    assert code == account_admin.EXIT_REFUSED
    assert "12" in capsys.readouterr().err


def test_an_address_sign_in_would_reject_is_refused_before_asking(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _refuse_database(monkeypatch)

    def never(_prompt: str = "") -> str:
        raise AssertionError("asked for a password for an impossible address")

    monkeypatch.setattr(account_admin.getpass, "getpass", never)

    assert account_admin.main(["set-password", "test3@gmai"]) == (
        account_admin.EXIT_NOT_FOUND
    )


def test_without_a_terminal_it_asks_for_an_explicit_stdin_flag(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """`exec -T` has no terminal: getpass would echo, or read something that was
    never meant to be a password."""

    _refuse_database(monkeypatch)
    monkeypatch.setattr(account_admin.sys, "stdin", io.StringIO(""))

    code = account_admin.main(["set-password", "owner@example.com"])

    assert code == account_admin.EXIT_REFUSED
    assert "--password-stdin" in capsys.readouterr().err


def test_password_stdin_reads_exactly_one_line(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    seen: list[str] = []

    async def record(args: object) -> int:
        seen.append(args.password)  # type: ignore[attr-defined]
        return account_admin.EXIT_OK

    monkeypatch.setattr(account_admin, "_main", record)
    monkeypatch.setattr(
        account_admin.sys,
        "stdin",
        io.StringIO("  synthetic new password 42  \nnot part of it\n"),
    )

    code = account_admin.main(["set-password", "owner@example.com", "--password-stdin"])

    assert code == account_admin.EXIT_OK
    # Only the line ending is removed: spaces can belong to a password.
    assert seen == ["  synthetic new password 42  "]
