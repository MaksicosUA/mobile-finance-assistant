"""Several wallets, one currency each (ADR 0029).

Nothing here converts anything. What these tests hold is the shape of a profile
that owns more than one account: exactly one of them is the default, every one
of them draws its months in the same zone, and the profile's base currency
follows the default rather than whichever row the database returned first.
"""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

import pytest

from mobile_finance_api.account_core import AccountPersistenceUnavailable
from mobile_finance_api.db_models import FinanceAccountRow, UserRow
from mobile_finance_api.home_projection import HomeProjectionInvariantError
from mobile_finance_api.postgres_finance_account_repository import (
    _default_account,
    _require_consistent_profile,
)
from mobile_finance_api.postgres_home_projector import _validate_profile

_USER_ID = UUID("11111111-1111-4111-8111-111111111111")
_EURO_ID = UUID("22222222-2222-4222-8222-222222222222")
_HRYVNIA_ID = UUID("33333333-3333-4333-8333-333333333333")
_AT = datetime(2026, 9, 6, 12, 0, tzinfo=UTC)
_ZONE = "Europe/Berlin"


def _user(*, base_currency: str = "EUR", timezone: str | None = _ZONE) -> UserRow:
    return UserRow(
        id=_USER_ID,
        email_normalized="someone@example.test",
        password_hash="argon2",
        display_name="Someone",
        base_currency=base_currency,
        canonical_timezone=timezone,
        timezone_revision=1 if timezone else 0,
        created_at=_AT,
        updated_at=_AT,
        disabled_at=None,
    )


def _wallet(
    *,
    account_id: UUID,
    currency: str,
    is_default: bool,
    timezone: str = _ZONE,
    user_id: UUID = _USER_ID,
) -> FinanceAccountRow:
    return FinanceAccountRow(
        id=account_id,
        user_id=user_id,
        command_id=account_id,
        command_payload_hash=b"\x00" * 32,
        schema_version="1",
        name="Кошелёк",
        currency=currency,
        opening_balance=Decimal("0"),
        opening_balance_on=_AT.date(),
        opening_timezone=timezone,
        status="active",
        is_default=is_default,
        confirmed_at=_AT,
        created_at=_AT,
    )


def _euro() -> FinanceAccountRow:
    return _wallet(account_id=_EURO_ID, currency="EUR", is_default=True)


def _hryvnia(**changes: object) -> FinanceAccountRow:
    return _wallet(
        account_id=_HRYVNIA_ID,
        currency="UAH",
        is_default=False,
        **changes,  # type: ignore[arg-type]
    )


# --- the set of wallets -------------------------------------------------------


def test_a_second_wallet_in_another_currency_is_a_consistent_profile() -> None:
    _require_consistent_profile(user=_user(), accounts=(_euro(), _hryvnia()))


def test_the_default_is_found_rather_than_taken_from_the_first_row() -> None:
    # The database returns rows in no promised order, and "the account" used to
    # mean accounts[0].
    assert _default_account((_hryvnia(), _euro())).id == _EURO_ID


def test_exactly_one_wallet_is_the_default() -> None:
    for accounts in (
        (_euro(), _wallet(account_id=_HRYVNIA_ID, currency="UAH", is_default=True)),
        (_hryvnia(),),
    ):
        with pytest.raises(AccountPersistenceUnavailable):
            _require_consistent_profile(user=_user(), accounts=accounts)


def test_the_base_currency_follows_the_default_wallet() -> None:
    with pytest.raises(AccountPersistenceUnavailable):
        _require_consistent_profile(
            user=_user(base_currency="UAH"),
            accounts=(_euro(), _hryvnia()),
        )


def test_every_wallet_draws_its_months_in_the_same_zone() -> None:
    """Months must not depend on which wallet is read (ADR 0028, ADR 0029)."""

    with pytest.raises(AccountPersistenceUnavailable):
        _require_consistent_profile(
            user=_user(),
            accounts=(_euro(), _hryvnia(timezone="Europe/Kyiv")),
        )


def test_a_foreign_wallet_is_not_this_profile() -> None:
    with pytest.raises(AccountPersistenceUnavailable):
        _require_consistent_profile(
            user=_user(),
            accounts=(
                _euro(),
                _hryvnia(user_id=UUID("44444444-4444-4444-8444-444444444444")),
            ),
        )


# --- what the projector will run over ----------------------------------------


def test_the_projector_accepts_a_wallet_in_another_currency() -> None:
    """A wallet's projection reports that wallet's money.

    Its currency is therefore its own, and comparing it against the profile's
    base currency — which follows the default wallet — would dead-letter every
    wallet that is not the default one.
    """

    _validate_profile(user=_user(), account=_hryvnia())


def test_the_projector_still_refuses_a_wallet_from_another_zone() -> None:
    with pytest.raises(HomeProjectionInvariantError):
        _validate_profile(user=_user(), account=_hryvnia(timezone="Europe/Kyiv"))
