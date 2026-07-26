"""Short-lived signed access JWTs and hashed opaque refresh tokens."""

from __future__ import annotations

import base64
import hashlib
import re
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

import jwt
from jwt import InvalidTokenError

_ACCESS_TTL = timedelta(seconds=600)
_REFRESH_IDLE_TTL = timedelta(days=30)
_SESSION_ABSOLUTE_TTL = timedelta(days=90)
_REFRESH_PATTERN = re.compile(r"^mfa_rt1_[A-Za-z0-9_-]{43}$")


@dataclass(frozen=True, slots=True)
class AccessClaims:
    user_id: UUID
    session_id: UUID


@dataclass(frozen=True, slots=True, repr=False)
class RefreshTokenMaterial:
    value: str
    digest: bytes


class AccessTokenCodec:
    def __init__(self, *, secret: bytes, issuer: str, audience: str) -> None:
        if len(secret) < 32:
            raise ValueError("The JWT secret must contain at least 32 bytes")
        self._secret = secret
        self._issuer = issuer
        self._audience = audience

    @property
    def lifetime_seconds(self) -> int:
        return int(_ACCESS_TTL.total_seconds())

    def issue(self, *, user_id: UUID, session_id: UUID, now: datetime) -> str:
        issued_at = _utc(now)
        payload: dict[str, Any] = {
            "iss": self._issuer,
            "aud": self._audience,
            "sub": str(user_id),
            "sid": str(session_id),
            "jti": str(uuid4()),
            "token_use": "access",
            "iat": issued_at,
            "nbf": issued_at,
            "exp": issued_at + _ACCESS_TTL,
        }
        return jwt.encode(
            payload,
            self._secret,
            algorithm="HS256",
            headers={"typ": "at+jwt"},
        )

    def decode(self, token: str) -> AccessClaims:
        try:
            header = jwt.get_unverified_header(token)
            if header.get("alg") != "HS256" or header.get("typ") != "at+jwt":
                raise ValueError("Unexpected JWT header")
            payload = jwt.decode(
                token,
                self._secret,
                algorithms=["HS256"],
                audience=self._audience,
                issuer=self._issuer,
                leeway=5,
                options={
                    "require": [
                        "iss",
                        "aud",
                        "sub",
                        "sid",
                        "jti",
                        "token_use",
                        "iat",
                        "nbf",
                        "exp",
                    ],
                },
            )
            if payload.get("token_use") != "access":
                raise ValueError("Unexpected JWT token type")
            _required_uuid(payload, "jti")
            return AccessClaims(
                user_id=_required_uuid(payload, "sub"),
                session_id=_required_uuid(payload, "sid"),
            )
        except (InvalidTokenError, TypeError, ValueError) as error:
            raise InvalidToken from error


class InvalidToken(ValueError):
    pass


def new_refresh_token() -> RefreshTokenMaterial:
    encoded = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=")
    value = f"mfa_rt1_{encoded.decode('ascii')}"
    return RefreshTokenMaterial(value=value, digest=hash_refresh_token(value))


def hash_refresh_token(value: str) -> bytes:
    if _REFRESH_PATTERN.fullmatch(value) is None:
        raise InvalidToken
    return hashlib.sha256(value.encode("ascii")).digest()


def refresh_expiry(*, now: datetime, absolute_expiry: datetime) -> datetime:
    return min(_utc(now) + _REFRESH_IDLE_TTL, _utc(absolute_expiry))


def session_absolute_expiry(now: datetime) -> datetime:
    return _utc(now) + _SESSION_ABSOLUTE_TTL


def refresh_lifetime_seconds(*, now: datetime, expires_at: datetime) -> int:
    return max(0, int((_utc(expires_at) - _utc(now)).total_seconds()))


def _required_uuid(payload: dict[str, Any], name: str) -> UUID:
    value = payload.get(name)
    if not isinstance(value, str):
        raise ValueError(f"JWT {name} must be a string")
    return UUID(value)


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("A timezone-aware timestamp is required")
    return value.astimezone(UTC)
