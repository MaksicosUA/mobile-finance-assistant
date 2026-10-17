"""Look after the accounts on this host: list, block, unblock, reset, erase.

Run it inside the API container, where the database URL already is::

    docker compose --env-file .env exec -T api \\
        python -m mobile_finance_api.account_admin list

There is deliberately no HTTP route for any of this. Registration is open to
anyone who reaches the host (ADR 0024), so the one power that must never be
reachable from the internet is removing somebody. Being able to run a command
in this container already means holding the database.

It prints addresses and names, because telling accounts apart is its whole
purpose — to the operator's terminal only. Nothing is logged except the type of
an unexpected error.

**Blocking is reversible and immediate.** Sign-in, refresh and every
authenticated request already refuse a user whose ``disabled_at`` is set, so
blocking only sets it. Sessions are left alone and simply stop working;
unblocking lets the same devices back in.

**Setting a password needs no email.** This server cannot send mail, and
registration never proves anyone owns the address they typed, so an emailed
reset could reach a stranger and a made-up address could never receive one. The
operator sets the password instead: typed twice at a hidden prompt, or one line
on standard input with ``--password-stdin`` — never as an argument, which would
land in shell history and the process list. It passes the same policy and the
same Argon2id as registration, and every session of that account is deleted
(their refresh tokens cascade), so every device is signed out; an access token
already issued lapses within ten minutes. A blocked account stays blocked.

**Erasing is not reversible.** One ``DELETE`` on the user row, and every table
that carries a ``user_id`` follows it through foreign keys that cascade all the
way down. The command counts what it is about to remove, removes it in one
transaction, and checks inside that transaction that nothing is left before
committing. Daily backups still hold the data until they age out.
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import logging
import sys
from collections.abc import Sequence
from datetime import UTC, datetime
from typing import TextIO
from uuid import UUID

from email_validator import EmailNotValidError
from sqlalchemy import Table, delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .account_data import IncompleteErasure, erase_user
from .auth_service import normalize_email
from .config import require_database_url
from .database import AsyncSessionFactory, create_database
from .db_models import (
    AuthSessionRow,
    FinanceAccountRow,
    FinanceOperationRow,
    UserRow,
)
from .passwords import InvalidPassword, PasswordService, validate_password

_LOGGER = logging.getLogger(__name__)

EXIT_OK = 0
EXIT_NOT_FOUND = 1
EXIT_REFUSED = 2

_CONFIRMATION_REFUSED = (
    "Refusing to erase: --confirm must repeat the same address. Nothing was touched."
)


def same_address(first: str, second: str) -> bool:
    """Whether two typed addresses name the same account, as sign-in would."""

    normalized = _normalized(first)
    return normalized is not None and normalized == _normalized(second)


def parse_arguments(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="python -m mobile_finance_api.account_admin",
        description="List, block, unblock or erase the accounts on this host.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="every account, oldest first")
    block = commands.add_parser("block", help="stop an account signing in (reversible)")
    block.add_argument("email")
    unblock = commands.add_parser("unblock", help="let a blocked account back in")
    unblock.add_argument("email")
    set_password = commands.add_parser(
        "set-password",
        help="give an account a new password and sign it out everywhere",
    )
    set_password.add_argument("email")
    set_password.add_argument(
        "--password-stdin",
        action="store_true",
        help="read the password from one line of standard input",
    )
    erase = commands.add_parser(
        "delete",
        help="erase an account and every row it owns (irreversible)",
    )
    erase.add_argument("email")
    erase.add_argument(
        "--confirm",
        required=True,
        metavar="EMAIL",
        help="the same address again",
    )
    return parser.parse_args(argv)


async def execute(
    args: argparse.Namespace,
    *,
    session_factory: AsyncSessionFactory,
    out: TextIO,
    err: TextIO,
    now: datetime,
) -> int:
    if args.command == "list":
        return await _list(session_factory, out=out)
    if args.command in {"block", "unblock"}:
        return await _set_blocked(
            session_factory,
            args.email,
            blocked=args.command == "block",
            now=now,
            out=out,
            err=err,
        )
    if args.command == "set-password":
        return await _set_password(
            session_factory,
            args.email,
            args.password,
            now=now,
            out=out,
            err=err,
        )
    if args.command == "delete":
        if not same_address(args.email, args.confirm):
            print(_CONFIRMATION_REFUSED, file=err)
            return EXIT_REFUSED
        try:
            return await _erase(session_factory, args.email, out=out, err=err)
        except IncompleteErasure as error:
            print(
                f"Nothing was erased: rows remained in {error}. "
                "The transaction was rolled back.",
                file=err,
            )
            return EXIT_REFUSED
    raise AssertionError(f"unhandled command {args.command!r}")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_arguments(argv)
    logging.basicConfig(level=logging.INFO)
    # Refused before the database is even opened: a typo must not get as far
    # as a connection to the thing it would destroy.
    if args.command == "delete" and not same_address(args.email, args.confirm):
        print(_CONFIRMATION_REFUSED, file=sys.stderr)
        return EXIT_REFUSED
    if args.command == "set-password":
        refusal = _read_new_password(args)
        if refusal is not None:
            code, message = refusal
            print(message, file=sys.stderr)
            return code
    try:
        return asyncio.run(_main(args))
    except Exception as error:
        _LOGGER.error(
            "Account administration failed error_type=%s",
            type(error).__name__,
        )
        return EXIT_REFUSED


async def _main(args: argparse.Namespace) -> int:
    engine, session_factory = create_database(require_database_url())
    try:
        return await execute(
            args,
            session_factory=session_factory,
            out=sys.stdout,
            err=sys.stderr,
            now=datetime.now(UTC),
        )
    finally:
        await engine.dispose()


def _read_new_password(args: argparse.Namespace) -> tuple[int, str] | None:
    """Read the new password before anything is opened, or say why not."""

    if _normalized(args.email) is None:
        return EXIT_NOT_FOUND, "That is not a valid address."
    if args.password_stdin:
        # Only the line ending goes: spaces can belong to a password.
        password = sys.stdin.readline().rstrip("\r\n")
    elif sys.stdin.isatty():
        password = getpass.getpass("New password: ")
        if getpass.getpass("Repeat it: ") != password:
            return EXIT_REFUSED, "The two passwords differ. Nothing was changed."
    else:
        return EXIT_REFUSED, (
            "No terminal to read a password from. Run without -T, or pass "
            "--password-stdin. Nothing was changed."
        )
    try:
        validate_password(password)
    except InvalidPassword:
        return EXIT_REFUSED, (
            "A password must be 12 to 128 characters. Nothing was changed."
        )
    args.password = password
    return None


def _normalized(address: str) -> str | None:
    try:
        return normalize_email(address.strip())
    except (EmailNotValidError, ValueError):
        return None


async def _list(session_factory: AsyncSessionFactory, *, out: TextIO) -> int:
    last_seen = (
        select(
            AuthSessionRow.user_id.label("user_id"),
            func.max(AuthSessionRow.last_seen_at).label("last_seen"),
        )
        .group_by(AuthSessionRow.user_id)
        .subquery()
    )
    wallets = (
        select(
            FinanceAccountRow.user_id.label("user_id"),
            func.count().label("wallets"),
        )
        .group_by(FinanceAccountRow.user_id)
        .subquery()
    )
    records = (
        select(
            FinanceOperationRow.user_id.label("user_id"),
            func.count().label("records"),
        )
        .group_by(FinanceOperationRow.user_id)
        .subquery()
    )
    query = (
        select(
            UserRow.email_normalized,
            UserRow.display_name,
            UserRow.disabled_at,
            UserRow.deletion_due_at,
            UserRow.created_at,
            last_seen.c.last_seen,
            func.coalesce(wallets.c.wallets, 0),
            func.coalesce(records.c.records, 0),
        )
        .outerjoin(last_seen, last_seen.c.user_id == UserRow.id)
        .outerjoin(wallets, wallets.c.user_id == UserRow.id)
        .outerjoin(records, records.c.user_id == UserRow.id)
        .order_by(UserRow.created_at.asc(), UserRow.email_normalized.asc())
    )
    async with session_factory() as session:
        rows = (await session.execute(query)).all()

    print(
        f"{'EMAIL':<34} {'NAME':<22} {'STATUS':<11} {'CREATED':<10} "
        f"{'LAST SEEN':<10} {'WALLETS':>7} {'RECORDS':>7}",
        file=out,
    )
    for (
        email,
        name,
        disabled_at,
        deletion_due_at,
        created_at,
        seen,
        wallet_count,
        record_count,
    ) in rows:
        print(
            f"{email:<34} {name:<22} "
            f"{_status(disabled_at, deletion_due_at):<11} "
            f"{created_at:%Y-%m-%d} "
            f"{(f'{seen:%Y-%m-%d}' if seen is not None else '—'):<10} "
            f"{wallet_count:>7} {record_count:>7}",
            file=out,
        )
    print(f"\n{len(rows)} account(s)", file=out)
    return EXIT_OK


def _status(disabled_at: datetime | None, deletion_due_at: datetime | None) -> str:
    """Blocked by the operator, leaving by their own request, or neither."""

    if disabled_at is not None:
        return "blocked"
    if deletion_due_at is not None:
        # They asked to be erased (ADR 0030); signing in before this cancels it.
        return f"erase {deletion_due_at:%m-%d}"
    return "active"


async def _set_blocked(
    session_factory: AsyncSessionFactory,
    address: str,
    *,
    blocked: bool,
    now: datetime,
    out: TextIO,
    err: TextIO,
) -> int:
    normalized = _normalized(address)
    if normalized is None:
        print("That is not a valid address.", file=err)
        return EXIT_NOT_FOUND
    async with session_factory() as session, session.begin():
        user = await session.scalar(
            select(UserRow)
            .where(UserRow.email_normalized == normalized)
            .with_for_update()
        )
        if user is None:
            print("No account uses that address.", file=err)
            return EXIT_NOT_FOUND
        state = "blocked" if blocked else "active"
        if (user.disabled_at is not None) == blocked:
            print(f"{normalized}: already {state}", file=out)
            return EXIT_OK
        user.disabled_at = now if blocked else None
        user.updated_at = now
    print(f"{normalized}: {state}", file=out)
    return EXIT_OK


async def _set_password(
    session_factory: AsyncSessionFactory,
    address: str,
    password: str,
    *,
    now: datetime,
    out: TextIO,
    err: TextIO,
) -> int:
    normalized = _normalized(address)
    if normalized is None:
        print("That is not a valid address.", file=err)
        return EXIT_NOT_FOUND
    # Hashed before the transaction: Argon2id is slow on purpose, and a locked
    # user row should not wait for it.
    password_hash = await PasswordService().hash(password)
    async with session_factory() as session, session.begin():
        user = await session.scalar(
            select(UserRow)
            .where(UserRow.email_normalized == normalized)
            .with_for_update()
        )
        if user is None:
            print("No account uses that address.", file=err)
            return EXIT_NOT_FOUND
        user.password_hash = password_hash
        user.updated_at = now
        signed_out = int(
            await session.scalar(
                select(func.count())
                .select_from(AuthSessionRow)
                .where(AuthSessionRow.user_id == user.id)
            )
            or 0
        )
        # Refresh tokens cascade from their sessions, so this signs the account
        # out of every device.
        await session.execute(
            delete(AuthSessionRow).where(AuthSessionRow.user_id == user.id)
        )
        still_blocked = user.disabled_at is not None
    print(
        f"{normalized}: password set; {signed_out} session(s) signed out",
        file=out,
    )
    if still_blocked:
        print("The account is still blocked; unblock it to let it sign in.", file=out)
    return EXIT_OK


async def _erase(
    session_factory: AsyncSessionFactory,
    address: str,
    *,
    out: TextIO,
    err: TextIO,
) -> int:
    normalized = _normalized(address)
    if normalized is None:
        print("That is not a valid address.", file=err)
        return EXIT_NOT_FOUND
    async with session_factory() as session, session.begin():
        user_id = await session.scalar(
            select(UserRow.id)
            .where(UserRow.email_normalized == normalized)
            .with_for_update()
        )
        if user_id is None:
            print("No account uses that address.", file=err)
            return EXIT_NOT_FOUND

        # The same verified cascade the scheduled erasure uses (ADR 0030): one
        # definition of what erasing a person means.
        removed = await erase_user(session, user_id)

    total = sum(removed.values())
    print(
        f"{normalized}: erased, with {total} row(s) from {len(removed)} table(s)",
        file=out,
    )
    for name, count in sorted(removed.items()):
        print(f"  {name:<40} {count:>6}", file=out)
    print(
        "\nDaily backups still contain this account until they age out "
        "(MFA_BACKUP_KEEP_DAYS).",
        file=out,
    )
    return EXIT_OK


async def _count(session: AsyncSession, table: Table, user_id: UUID) -> int:
    return int(
        await session.scalar(
            select(func.count()).select_from(table).where(table.c.user_id == user_id)
        )
        or 0
    )


if __name__ == "__main__":
    raise SystemExit(main())
