"""Transactional first-party authentication over PostgreSQL."""

from __future__ import annotations

import unicodedata
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Protocol
from uuid import UUID, uuid4

from email_validator import EmailNotValidError, validate_email
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from .database import AsyncSessionFactory
from .db_models import AuthRefreshTokenRow, AuthSessionRow, UserRow
from .passwords import InvalidPassword, PasswordService
from .tokens import (
    AccessTokenCodec,
    InvalidToken,
    hash_refresh_token,
    new_refresh_token,
    refresh_expiry,
    refresh_lifetime_seconds,
    session_absolute_expiry,
)


class AuthenticationRejected(Exception):
    """Generic invalid-credential result with no account oracle details."""


class RegistrationRejected(Exception):
    """The account could not be registered under the public contract."""


class AuthenticationUnavailable(Exception):
    """No configured authentication service is available."""


@dataclass(frozen=True, slots=True, repr=False)
class AuthGrant:
    access_token: str
    refresh_token: str
    access_expires_in: int
    refresh_expires_in: int
    user_id: UUID
    display_name: str
    #: This sign-in cancelled an erasure the person had scheduled (ADR 0030),
    #: so the app can say so in words rather than leave them wondering.
    deletion_cancelled: bool = False


class AuthenticationService(Protocol):
    async def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str,
    ) -> AuthGrant: ...

    async def login(self, *, email: str, password: str) -> AuthGrant: ...

    async def refresh(self, *, refresh_token: str) -> AuthGrant: ...

    async def logout(self, *, refresh_token: str) -> None: ...


class UnavailableAuthenticationService:
    async def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str,
    ) -> AuthGrant:
        del email, password, display_name
        raise AuthenticationUnavailable

    async def login(self, *, email: str, password: str) -> AuthGrant:
        del email, password
        raise AuthenticationUnavailable

    async def refresh(self, *, refresh_token: str) -> AuthGrant:
        del refresh_token
        raise AuthenticationUnavailable

    async def logout(self, *, refresh_token: str) -> None:
        del refresh_token
        raise AuthenticationUnavailable


class PostgresAuthenticationService:
    def __init__(
        self,
        *,
        session_factory: AsyncSessionFactory,
        password_service: PasswordService,
        access_tokens: AccessTokenCodec,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._passwords = password_service
        self._access_tokens = access_tokens
        self._clock = clock or _utc_now

    async def register(
        self,
        *,
        email: str,
        password: str,
        display_name: str,
    ) -> AuthGrant:
        try:
            normalized_email = normalize_email(email)
            normalized_name = _normalize_display_name(display_name)
            password_hash = await self._passwords.hash(password)
        except (EmailNotValidError, InvalidPassword, ValueError) as error:
            raise RegistrationRejected from error

        now = _aware_utc(self._clock())
        user = UserRow(
            id=uuid4(),
            email_normalized=normalized_email,
            password_hash=password_hash,
            display_name=normalized_name,
            base_currency="EUR",
            created_at=now,
            updated_at=now,
            disabled_at=None,
        )
        try:
            async with self._session_factory() as database:
                async with database.begin():
                    database.add(user)
                    # User/session mappings intentionally avoid ORM
                    # relationships, so make their FK order explicit.
                    await database.flush()
                    session, raw_refresh, refresh_expires_at = await _new_session(
                        database=database,
                        user_id=user.id,
                        now=now,
                    )
        except IntegrityError as error:
            raise RegistrationRejected from error
        return self._grant(
            user=user,
            session=session,
            raw_refresh=raw_refresh,
            refresh_expires_at=refresh_expires_at,
            now=now,
        )

    async def login(self, *, email: str, password: str) -> AuthGrant:
        try:
            normalized_email = normalize_email(email)
        except EmailNotValidError:
            normalized_email = "invalid-login-identifier@invalid.invalid"

        async with self._session_factory() as database:
            user = await database.scalar(
                select(UserRow).where(UserRow.email_normalized == normalized_email)
            )
        password_matches = await self._passwords.verify(
            password,
            None if user is None else user.password_hash,
        )
        if user is None or not password_matches or user.disabled_at is not None:
            raise AuthenticationRejected

        replacement_hash: str | None = None
        if self._passwords.needs_rehash(user.password_hash):
            replacement_hash = await self._passwords.hash(password)

        now = _aware_utc(self._clock())
        async with self._session_factory() as database:
            async with database.begin():
                locked_user = await database.scalar(
                    select(UserRow).where(UserRow.id == user.id).with_for_update()
                )
                if (
                    locked_user is None
                    or locked_user.disabled_at is not None
                    or locked_user.password_hash != user.password_hash
                ):
                    raise AuthenticationRejected
                if replacement_hash is not None:
                    locked_user.password_hash = replacement_hash
                    locked_user.updated_at = now
                # Signing in during the week cancels a requested erasure
                # (ADR 0030). The operator's block is a different fact and was
                # already refused above; it is never cleared here.
                deletion_cancelled = locked_user.deletion_requested_at is not None
                if deletion_cancelled:
                    locked_user.deletion_requested_at = None
                    locked_user.deletion_due_at = None
                    locked_user.updated_at = now
                session, raw_refresh, refresh_expires_at = await _new_session(
                    database=database,
                    user_id=locked_user.id,
                    now=now,
                )
        return self._grant(
            user=locked_user,
            session=session,
            raw_refresh=raw_refresh,
            refresh_expires_at=refresh_expires_at,
            now=now,
            deletion_cancelled=deletion_cancelled,
        )

    async def refresh(self, *, refresh_token: str) -> AuthGrant:
        try:
            token_digest = hash_refresh_token(refresh_token)
        except InvalidToken as error:
            raise AuthenticationRejected from error

        now = _aware_utc(self._clock())
        rejected = False
        grant_parts: tuple[UserRow, AuthSessionRow, str, datetime] | None = None
        async with self._session_factory() as database:
            async with database.begin():
                row = (
                    await database.execute(
                        select(AuthRefreshTokenRow, AuthSessionRow, UserRow)
                        .join(
                            AuthSessionRow,
                            AuthSessionRow.id == AuthRefreshTokenRow.session_id,
                        )
                        .join(UserRow, UserRow.id == AuthSessionRow.user_id)
                        .where(AuthRefreshTokenRow.token_hash == token_digest)
                        .with_for_update(of=(AuthRefreshTokenRow, AuthSessionRow))
                    )
                ).one_or_none()
                if row is None:
                    rejected = True
                else:
                    token, session, user = row
                    if session.revoked_at is not None or user.disabled_at is not None:
                        rejected = True
                    elif token.consumed_at is not None or token.revoked_at is not None:
                        await _revoke_session(
                            database=database,
                            session=session,
                            now=now,
                            reason="reuse_detected",
                        )
                        rejected = True
                    elif min(session.absolute_expires_at, token.expires_at) <= now + (
                        timedelta(seconds=self._access_tokens.lifetime_seconds)
                    ):
                        await _revoke_session(
                            database=database,
                            session=session,
                            now=now,
                            reason="expired",
                        )
                        rejected = True
                    else:
                        successor = new_refresh_token()
                        successor_expiry = refresh_expiry(
                            now=now,
                            absolute_expiry=session.absolute_expires_at,
                        )
                        token.consumed_at = now
                        session.last_seen_at = now
                        database.add(
                            AuthRefreshTokenRow(
                                id=uuid4(),
                                session_id=session.id,
                                token_hash=successor.digest,
                                parent_token_id=token.id,
                                created_at=now,
                                expires_at=successor_expiry,
                                consumed_at=None,
                                revoked_at=None,
                            )
                        )
                        grant_parts = (
                            user,
                            session,
                            successor.value,
                            successor_expiry,
                        )
        # This happens after transaction exit so reuse/expiry revocation is
        # committed before the public 401 is raised.
        if rejected or grant_parts is None:
            raise AuthenticationRejected
        user, session, raw_refresh, refresh_expires_at = grant_parts
        return self._grant(
            user=user,
            session=session,
            raw_refresh=raw_refresh,
            refresh_expires_at=refresh_expires_at,
            now=now,
        )

    async def logout(self, *, refresh_token: str) -> None:
        try:
            token_digest = hash_refresh_token(refresh_token)
        except InvalidToken:
            return

        now = _aware_utc(self._clock())
        async with self._session_factory() as database:
            async with database.begin():
                row = (
                    await database.execute(
                        select(AuthRefreshTokenRow, AuthSessionRow)
                        .join(
                            AuthSessionRow,
                            AuthSessionRow.id == AuthRefreshTokenRow.session_id,
                        )
                        .where(AuthRefreshTokenRow.token_hash == token_digest)
                        .with_for_update(of=(AuthRefreshTokenRow, AuthSessionRow))
                    )
                ).one_or_none()
                if row is None:
                    return
                _, session = row
                await _revoke_session(
                    database=database,
                    session=session,
                    now=now,
                    reason="logout",
                )

    def _grant(
        self,
        *,
        user: UserRow,
        session: AuthSessionRow,
        raw_refresh: str,
        refresh_expires_at: datetime,
        now: datetime,
        deletion_cancelled: bool = False,
    ) -> AuthGrant:
        return AuthGrant(
            access_token=self._access_tokens.issue(
                user_id=user.id,
                session_id=session.id,
                now=now,
            ),
            refresh_token=raw_refresh,
            access_expires_in=self._access_tokens.lifetime_seconds,
            refresh_expires_in=refresh_lifetime_seconds(
                now=now,
                expires_at=refresh_expires_at,
            ),
            user_id=user.id,
            display_name=user.display_name,
            deletion_cancelled=deletion_cancelled,
        )


async def _new_session(
    *,
    database: AsyncSession,
    user_id: UUID,
    now: datetime,
) -> tuple[AuthSessionRow, str, datetime]:
    # Kept as a small internal unit so account creation and login cannot drift.
    absolute_expiry = session_absolute_expiry(now)
    session = AuthSessionRow(
        id=uuid4(),
        user_id=user_id,
        created_at=now,
        last_seen_at=now,
        absolute_expires_at=absolute_expiry,
        revoked_at=None,
        revocation_reason=None,
    )
    refresh = new_refresh_token()
    expires_at = refresh_expiry(now=now, absolute_expiry=absolute_expiry)
    database.add(session)
    # The mappings intentionally expose no ORM relationship objects. Flush the
    # session row explicitly so SQLAlchemy cannot schedule its dependent
    # refresh-token insert first.
    await database.flush()
    database.add(
        AuthRefreshTokenRow(
            id=uuid4(),
            session_id=session.id,
            token_hash=refresh.digest,
            parent_token_id=None,
            created_at=now,
            expires_at=expires_at,
            consumed_at=None,
            revoked_at=None,
        )
    )
    return session, refresh.value, expires_at


async def _revoke_session(
    *,
    database: AsyncSession,
    session: AuthSessionRow,
    now: datetime,
    reason: str,
) -> None:
    if session.revoked_at is None:
        session.revoked_at = now
        session.revocation_reason = reason
    await database.execute(
        update(AuthRefreshTokenRow)
        .where(
            AuthRefreshTokenRow.session_id == session.id,
            AuthRefreshTokenRow.revoked_at.is_(None),
        )
        .values(revoked_at=now)
    )


def normalize_email(value: str) -> str:
    result = validate_email(
        value,
        check_deliverability=False,
        allow_smtputf8=False,
    )
    if result.ascii_email is None:
        raise EmailNotValidError("An ASCII-compatible email is required")
    return result.ascii_email.casefold()


def _normalize_display_name(value: str) -> str:
    result = unicodedata.normalize("NFC", value.strip())
    if not result or len(result) > 100 or not result.isprintable():
        raise ValueError("Invalid display name")
    return result


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("A timezone-aware clock is required")
    return value.astimezone(UTC)


def _utc_now() -> datetime:
    return datetime.now(UTC)
