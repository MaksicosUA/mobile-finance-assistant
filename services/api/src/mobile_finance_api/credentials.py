"""A person's own password: changing it, and getting back in without it (ADR 0035).

Three things happen here and nowhere else. A signed-in person changes their
password. A signed-in person is given a recovery code, once, after proving they
know the password. And someone who is signed out replaces a forgotten password by
presenting that code.

The code is spent by using it: a reset writes the next one in the same
transaction and hands it back, so an account is never left without a way in.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from email_validator import EmailNotValidError
from sqlalchemy import delete, select

from .auth_service import normalize_email
from .database import AsyncSessionFactory
from .db_models import AuthSessionRow, UserRow
from .passwords import InvalidPassword, PasswordService, validate_password
from .recovery_codes import (
    InvalidRecoveryCode,
    hash_recovery_code,
    new_recovery_code,
    same_digest,
)

_LOGGER = logging.getLogger(__name__)
#: Looked up when the address given is not an address at all, so that request
#: does the same work as one for an address nobody owns.
_NO_SUCH_ADDRESS = "invalid-login-identifier@invalid.invalid"


class CredentialsUnavailable(Exception):
    """The store could not safely read or change a credential."""


class CurrentPasswordRejected(Exception):
    """The password given to confirm the request did not match."""


class NewPasswordRejected(Exception):
    """The new password is outside what the server accepts."""


class RecoveryRejected(Exception):
    """The address and code did not open an account. Which of them, is not said."""


@dataclass(frozen=True, slots=True, repr=False)
class IssuedRecoveryCode:
    #: Returned once to the person it belongs to; only its digest is stored.
    value: str
    created_at: datetime


class PostgresCredentialRepository:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        passwords: PasswordService,
    ) -> None:
        self._session_factory = session_factory
        self._passwords = passwords

    async def recovery_code_created_at(self, *, user_id: UUID) -> datetime | None:
        """When the person's current code was issued, or None if they have none."""

        async with self._session_factory() as database:
            row = (
                await database.execute(
                    select(UserRow.id, UserRow.recovery_code_created_at).where(
                        UserRow.id == user_id
                    )
                )
            ).one_or_none()
        if row is None:
            raise CredentialsUnavailable
        created_at: datetime | None = row.recovery_code_created_at
        return created_at

    async def issue_recovery_code(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> IssuedRecoveryCode:
        """Replace the person's recovery code and return the new one, once.

        The password is asked because the code is as good as the password: an
        unlocked phone alone must not be enough to mint one. It is checked before
        the row is locked (Argon2 is slow on purpose) and the hash is compared
        again under the lock, so a password changed in between cannot slip by.
        """

        stored = await self._stored_password_hash(user_id)
        if not await self._passwords.verify(password, stored):
            raise CurrentPasswordRejected
        code = new_recovery_code()
        async with self._session_factory() as database, database.begin():
            user = await database.scalar(
                select(UserRow).where(UserRow.id == user_id).with_for_update()
            )
            if user is None or user.password_hash != stored:
                raise CurrentPasswordRejected
            user.recovery_code_hash = code.digest
            user.recovery_code_created_at = now
            user.updated_at = now
        return IssuedRecoveryCode(value=code.value, created_at=now)

    async def change_password(
        self,
        *,
        user_id: UUID,
        session_id: UUID | None,
        current_password: str,
        new_password: str,
        now: datetime,
    ) -> None:
        """Set a new password and sign out every device but the one asking.

        The recovery code is left alone: it is a second key, and changing one key
        says nothing about the other.
        """

        _require_acceptable(new_password)
        stored = await self._stored_password_hash(user_id)
        if not await self._passwords.verify(current_password, stored):
            raise CurrentPasswordRejected
        replacement = await self._passwords.hash(new_password)
        async with self._session_factory() as database, database.begin():
            user = await database.scalar(
                select(UserRow).where(UserRow.id == user_id).with_for_update()
            )
            if user is None or user.password_hash != stored:
                raise CurrentPasswordRejected
            user.password_hash = replacement
            user.updated_at = now
            # Whoever else holds a session got it with the old password, and a
            # changed password is how a person takes those back. Refresh tokens
            # hang off their sessions and go with them.
            others = delete(AuthSessionRow).where(AuthSessionRow.user_id == user_id)
            if session_id is not None:
                others = others.where(AuthSessionRow.id != session_id)
            await database.execute(others)

    async def reset_password(
        self,
        *,
        email: str,
        recovery_code: str,
        new_password: str,
        now: datetime,
    ) -> IssuedRecoveryCode:
        """Replace a forgotten password, given the address and its recovery code.

        An unknown address, a wrong code, an account that never asked for a code
        and one the operator has blocked are all the same refusal, reached by the
        same work: this answers nobody's question about who has an account. The
        new password is hashed only after the code has matched, so a guess costs
        the server a lookup and a comparison, never an Argon2 run.
        """

        _require_acceptable(new_password)
        try:
            normalized = normalize_email(email)
        except EmailNotValidError:
            normalized = _NO_SUCH_ADDRESS
        try:
            candidate: bytes | None = hash_recovery_code(recovery_code)
        except InvalidRecoveryCode:
            candidate = None

        async with self._session_factory() as database:
            found = (
                await database.execute(
                    select(
                        UserRow.id,
                        UserRow.recovery_code_hash,
                        UserRow.disabled_at,
                    ).where(UserRow.email_normalized == normalized)
                )
            ).one_or_none()
        matches = same_digest(
            None if found is None else found.recovery_code_hash,
            candidate,
        )
        if found is None or not matches or found.disabled_at is not None:
            raise RecoveryRejected

        replacement = await self._passwords.hash(new_password)
        successor = new_recovery_code()
        async with self._session_factory() as database, database.begin():
            user = await database.scalar(
                select(UserRow).where(UserRow.id == found.id).with_for_update()
            )
            # Compared again under the lock: two resets with one code must not
            # both succeed, and the operator may have blocked the account since.
            if (
                user is None
                or user.disabled_at is not None
                or not same_digest(user.recovery_code_hash, candidate)
            ):
                raise RecoveryRejected
            user.password_hash = replacement
            # The code that was just typed into a phone is spent. Its successor
            # is written with the password, so there is never a moment when the
            # account has a new password and no way back in.
            user.recovery_code_hash = successor.digest
            user.recovery_code_created_at = now
            user.updated_at = now
            # Nobody who was signed in with the forgotten password stays so.
            await database.execute(
                delete(AuthSessionRow).where(AuthSessionRow.user_id == user.id)
            )
        # No identifier: that a reset happened is worth seeing, whose is not.
        _LOGGER.info("A password was reset with a recovery code")
        return IssuedRecoveryCode(value=successor.value, created_at=now)

    async def _stored_password_hash(self, user_id: UUID) -> str | None:
        async with self._session_factory() as database:
            stored: str | None = await database.scalar(
                select(UserRow.password_hash).where(UserRow.id == user_id)
            )
        return stored


class UnavailableCredentialRepository:
    async def recovery_code_created_at(self, *, user_id: UUID) -> datetime | None:
        del user_id
        raise CredentialsUnavailable

    async def issue_recovery_code(
        self, *, user_id: UUID, password: str, now: datetime
    ) -> IssuedRecoveryCode:
        del user_id, password, now
        raise CredentialsUnavailable

    async def change_password(
        self,
        *,
        user_id: UUID,
        session_id: UUID | None,
        current_password: str,
        new_password: str,
        now: datetime,
    ) -> None:
        del user_id, session_id, current_password, new_password, now
        raise CredentialsUnavailable

    async def reset_password(
        self,
        *,
        email: str,
        recovery_code: str,
        new_password: str,
        now: datetime,
    ) -> IssuedRecoveryCode:
        del email, recovery_code, new_password, now
        raise CredentialsUnavailable


def _require_acceptable(password: str) -> None:
    try:
        validate_password(password)
    except InvalidPassword:
        raise NewPasswordRejected from None
