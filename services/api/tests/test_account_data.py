"""Taking one's own data along (ADR 0030).

The export is complete by construction, not by care: every table the schema has
is either carried or left out with a stated reason, and adding a table without
deciding which fails here.
"""

from __future__ import annotations

import asyncio
import csv
import io
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID

from httpx import ASGITransport, AsyncClient

from mobile_finance_api.account_data import (
    DELETION_GRACE,
    EXCLUDED_TABLES,
    EXPORTED_TABLES,
    OPERATIONS_CSV_COLUMNS,
    WITHHELD_COLUMNS,
    AccountDataUnavailable,
    PasswordRejected,
    operations_table,
    plain,
    user_tables,
)
from mobile_finance_api.auth import AuthenticatedUser
from mobile_finance_api.auth_service import AuthGrant
from mobile_finance_api.db_models import Base
from mobile_finance_api.main import create_app

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_AUTH = {"Authorization": "Bearer synthetic-token"}


# --- coverage: complete by construction --------------------------------------


def test_every_table_is_either_exported_or_excluded_with_a_reason() -> None:
    every = {table.name for table in Base.metadata.sorted_tables}
    exported = set(EXPORTED_TABLES)
    excluded = set(EXCLUDED_TABLES)

    assert exported.isdisjoint(excluded)
    # A table added to the schema and to neither list fails here: someone must
    # decide whether it is the person's data before it ships.
    assert every - exported - excluded == set()
    assert (exported | excluded) - every == set(), "a listed table does not exist"
    assert all(reason.strip() for reason in EXCLUDED_TABLES.values())


def test_every_table_holding_a_persons_rows_is_accounted_for() -> None:
    held = {table.name for table in user_tables()}

    assert held <= set(EXPORTED_TABLES) | set(EXCLUDED_TABLES)


def test_the_password_hash_never_leaves() -> None:
    users = Base.metadata.tables["users"]

    assert "password_hash" in users.c
    assert "password_hash" in WITHHELD_COLUMNS["users"]
    for table, columns in WITHHELD_COLUMNS.items():
        assert columns <= set(Base.metadata.tables[table].c.keys()), table


def test_credentials_are_excluded_not_exported() -> None:
    for credential in ("auth_sessions", "auth_refresh_tokens"):
        assert credential in EXCLUDED_TABLES
        assert credential not in EXPORTED_TABLES


# --- values: what was stored, without its padding ----------------------------


def test_a_stored_decimal_loses_its_column_padding_and_nothing_else() -> None:
    assert plain(Decimal("12.500000000000000000")) == "12.5"
    assert plain(Decimal("100.000000000000000000")) == "100"
    assert plain(Decimal("-0.070000000000000000")) == "-0.07"
    assert plain(Decimal("0E-18")) == "0"
    # Never an exponent, which a spreadsheet or a person would misread.
    assert plain(Decimal("1E+3")) == "1000"


def test_times_dates_and_identifiers_are_plain_text() -> None:
    moment = datetime(2026, 10, 16, 9, 30, tzinfo=UTC)

    assert plain(moment) == "2026-10-16T09:30:00Z"
    assert plain(date(2026, 10, 16)) == "2026-10-16"
    assert plain(_USER_ID) == str(_USER_ID)
    assert plain({"nested": [Decimal("1.50")]}) == {"nested": ["1.5"]}
    assert plain(None) is None
    assert plain(True) is True


# --- the spreadsheet -----------------------------------------------------------


def _line(
    *,
    amount: str = "12.500000000000000000",
    category: str | None = "Продукты",
    merchant: str | None = None,
    counts: bool = True,
) -> tuple[date, str, Decimal, str, str, str | None, str | None, bool, datetime]:
    return (
        date(2026, 10, 1),
        "expense",
        Decimal(amount),
        "EUR",
        "Основной",
        category,
        merchant,
        counts,
        datetime(2026, 10, 1, 8, 0, tzinfo=UTC),
    )


def test_the_spreadsheet_opens_in_a_european_excel() -> None:
    table = operations_table([_line()])

    assert table.startswith("﻿"), "without the mark Excel guesses the encoding"
    header, row, *_ = table.removeprefix("﻿").split("\r\n")
    assert header == ";".join(OPERATIONS_CSV_COLUMNS)
    assert row.split(";") == [
        "2026-10-01",
        "expense",
        "12,50",
        "EUR",
        "Основной",
        "Продукты",
        "",
        "active",
        "2026-10-01T08:00:00Z",
    ]


def test_a_withdrawn_operation_says_so() -> None:
    row = operations_table([_line(counts=False)]).split("\r\n")[1]

    assert row.split(";")[7] == "withdrawn"


def test_an_amount_keeps_digits_it_really_has() -> None:
    row = operations_table([_line(amount="0.125")]).split("\r\n")[1]

    assert row.split(";")[2] == "0,125"


def test_words_that_look_like_a_formula_stay_words() -> None:
    """A category typed as a formula must not run when the file is opened."""

    table = operations_table([_line(category='=HYPERLINK("x")', merchant="+1 shop")])
    row = list(csv.reader(io.StringIO(table.removeprefix("\ufeff")), delimiter=";"))[1]

    assert row[5] == '\'=HYPERLINK("x")'
    assert row[6] == "'+1 shop"


# --- the routes ------------------------------------------------------------------


class _StaticAuthenticator:
    async def authenticate(self, access_token: str) -> AuthenticatedUser:
        del access_token
        return AuthenticatedUser(subject=str(_USER_ID), display_name="Synthetic")


class _FakeData:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.requested: list[UUID] = []

    async def export(
        self, *, user_id: UUID, exported_at: datetime
    ) -> dict[str, object]:
        self.requested.append(user_id)
        if self.fail:
            raise AccountDataUnavailable("Продукты 12.50 secret-detail")
        return {
            "schemaVersion": "1",
            "exportedAt": plain(exported_at),
            "tables": {"users": [{"id": str(user_id)}]},
        }

    async def operations_csv(self, *, user_id: UUID) -> str:
        self.requested.append(user_id)
        if self.fail:
            raise AccountDataUnavailable("Продукты 12.50 secret-detail")
        return operations_table([_line()])


def _get(path: str, *, data: _FakeData, authenticated: bool = True) -> object:
    async def scenario() -> object:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            account_data_repository=data,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            return await client.get(path, headers=_AUTH if authenticated else {})

    return asyncio.run(scenario())


def test_the_export_answers_only_for_the_caller() -> None:
    data = _FakeData()
    response = _get("/api/v1/account/export", data=data)

    assert response.status_code == 200, response.text  # type: ignore[attr-defined]
    assert data.requested == [_USER_ID]
    assert response.headers["cache-control"] == "no-store"  # type: ignore[attr-defined]
    assert response.json()["tables"]["users"] == [{"id": str(_USER_ID)}]  # type: ignore[attr-defined]


def test_the_spreadsheet_is_served_as_one() -> None:
    response = _get("/api/v1/account/export/operations.csv", data=_FakeData())

    assert response.status_code == 200  # type: ignore[attr-defined]
    assert response.headers["content-type"].startswith("text/csv")  # type: ignore[attr-defined]
    assert response.headers["cache-control"] == "no-store"  # type: ignore[attr-defined]
    assert response.content.startswith("﻿".encode())  # type: ignore[attr-defined]


def test_nothing_is_exported_without_signing_in() -> None:
    data = _FakeData()
    for path in ("/api/v1/account/export", "/api/v1/account/export/operations.csv"):
        response = _get(path, data=data, authenticated=False)
        assert response.status_code == 401  # type: ignore[attr-defined]
    assert data.requested == []


def test_a_failure_never_echoes_what_it_was_reading() -> None:
    for path in ("/api/v1/account/export", "/api/v1/account/export/operations.csv"):
        response = _get(path, data=_FakeData(fail=True))
        assert response.status_code == 503  # type: ignore[attr-defined]
        assert response.json() == {  # type: ignore[attr-defined]
            "detail": {"code": "ACCOUNT_DATA_UNAVAILABLE"}
        }
        assert "Продукты" not in response.text  # type: ignore[attr-defined]
        assert "secret-detail" not in response.text  # type: ignore[attr-defined]


# --- scheduled erasure -----------------------------------------------------------


class _FakeDeletion(_FakeData):
    def __init__(self, *, reject: bool = False, fail: bool = False) -> None:
        super().__init__(fail=fail)
        self.reject = reject
        self.passwords: list[str] = []

    async def request_deletion(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> datetime:
        self.requested.append(user_id)
        self.passwords.append(password)
        if self.reject:
            raise PasswordRejected
        if self.fail:
            raise AccountDataUnavailable("secret-detail")
        return now + DELETION_GRACE


def _post_deletion(
    body: object, *, data: _FakeDeletion, authenticated: bool = True
) -> object:
    async def scenario() -> object:
        app = create_app(
            current_user_authenticator=_StaticAuthenticator(),
            account_data_repository=data,
        )
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            return await client.post(
                "/api/v1/account/deletion",
                json=body,
                headers=_AUTH if authenticated else {},
            )

    return asyncio.run(scenario())


_PASSWORD = "synthetic-password-123"


def test_a_confirmed_request_schedules_erasure_a_week_out() -> None:
    data = _FakeDeletion()
    response = _post_deletion({"schemaVersion": "1", "password": _PASSWORD}, data=data)

    assert response.status_code == 202, response.text  # type: ignore[attr-defined]
    assert data.requested == [_USER_ID]
    assert data.passwords == [_PASSWORD]
    due = datetime.fromisoformat(
        response.json()["deletionDueAt"].replace("Z", "+00:00")  # type: ignore[attr-defined]
    )
    assert timedelta(days=6, hours=23) < due - datetime.now(UTC) <= DELETION_GRACE


def test_a_wrong_password_is_forbidden_never_unauthorized() -> None:
    """A 401 would tell the app its session expired and sign the person out."""

    response = _post_deletion(
        {"schemaVersion": "1", "password": "not-the-password"},
        data=_FakeDeletion(reject=True),
    )

    assert response.status_code == 403  # type: ignore[attr-defined]
    assert response.json() == {"detail": {"code": "PASSWORD_REJECTED"}}  # type: ignore[attr-defined]


def test_a_malformed_request_never_echoes_the_password() -> None:
    data = _FakeDeletion()
    secret = "x" * 200  # past the length limit, so validation refuses it
    response = _post_deletion({"schemaVersion": "1", "password": secret}, data=data)

    assert response.status_code == 422  # type: ignore[attr-defined]
    assert response.json() == {"detail": {"code": "MALFORMED_ACCOUNT_REQUEST"}}  # type: ignore[attr-defined]
    assert secret not in response.text  # type: ignore[attr-defined]
    assert data.requested == []


def test_nobody_schedules_an_erasure_without_signing_in() -> None:
    data = _FakeDeletion()
    response = _post_deletion(
        {"schemaVersion": "1", "password": _PASSWORD},
        data=data,
        authenticated=False,
    )

    assert response.status_code == 401  # type: ignore[attr-defined]
    assert data.requested == []


def test_an_unavailable_store_says_so_and_nothing_more() -> None:
    response = _post_deletion(
        {"schemaVersion": "1", "password": _PASSWORD},
        data=_FakeDeletion(fail=True),
    )

    assert response.status_code == 503  # type: ignore[attr-defined]
    assert "secret-detail" not in response.text  # type: ignore[attr-defined]


def test_sign_in_says_when_it_cancelled_an_erasure() -> None:
    """Older apps ignore the field; this one can tell the person in words."""

    class _Service:
        async def login(self, *, email: str, password: str) -> AuthGrant:
            del email, password
            return AuthGrant(
                access_token="synthetic-access-token-value",
                refresh_token="synthetic-refresh-token-value",
                access_expires_in=900,
                refresh_expires_in=2_592_000,
                user_id=_USER_ID,
                display_name="Synthetic",
                deletion_cancelled=True,
            )

    async def scenario() -> object:
        app = create_app(authentication_service=_Service())  # type: ignore[arg-type]
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as client:
            return await client.post(
                "/api/v1/auth/login",
                json={"email": "owner@example.com", "password": _PASSWORD},
            )

    response = asyncio.run(scenario())

    assert response.status_code == 200, response.text  # type: ignore[attr-defined]
    assert response.json()["deletionCancelled"] is True  # type: ignore[attr-defined]


def test_a_grant_cancels_nothing_unless_it_says_so() -> None:
    grant = AuthGrant(
        access_token="a",
        refresh_token="r",
        access_expires_in=900,
        refresh_expires_in=2_592_000,
        user_id=_USER_ID,
        display_name="Synthetic",
    )

    assert grant.deletion_cancelled is False
