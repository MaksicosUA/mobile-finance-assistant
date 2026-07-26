"""Fail-closed runtime configuration loaded exclusively from the environment."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True, slots=True, repr=False)
class RuntimeSettings:
    database_url: str
    jwt_secret: bytes
    jwt_issuer: str
    jwt_audience: str


def load_runtime_settings() -> RuntimeSettings | None:
    """Load production adapters, or keep the module app deliberately unavailable.

    An entirely absent auth configuration preserves the existing fail-closed
    development/import behavior. A partial or malformed configuration is an
    operator error and stops startup instead of silently weakening security.
    """

    database_url = os.environ.get("MFA_DATABASE_URL")
    raw_secret = os.environ.get("MFA_AUTH_JWT_SECRET")
    if database_url is None and raw_secret is None:
        return None
    if not database_url or not raw_secret:
        raise RuntimeError("Incomplete authentication runtime configuration")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("MFA_DATABASE_URL must use postgresql+asyncpg")

    jwt_secret = raw_secret.encode("utf-8")
    if len(jwt_secret) < 32:
        raise RuntimeError("MFA_AUTH_JWT_SECRET must contain at least 32 bytes")

    issuer = _bounded_setting(
        "MFA_AUTH_JWT_ISSUER",
        default="mobile-finance-assistant",
    )
    audience = _bounded_setting(
        "MFA_AUTH_JWT_AUDIENCE",
        default="mobile-finance-assistant-api",
    )
    return RuntimeSettings(
        database_url=database_url,
        jwt_secret=jwt_secret,
        jwt_issuer=issuer,
        jwt_audience=audience,
    )


def require_runtime_settings() -> RuntimeSettings:
    """Require complete settings for the explicit production entrypoint."""

    settings = load_runtime_settings()
    if settings is None:
        raise RuntimeError("MFA_DATABASE_URL and MFA_AUTH_JWT_SECRET are required")
    return settings


def _bounded_setting(name: str, *, default: str) -> str:
    value = os.environ.get(name, default)
    if (
        value != value.strip()
        or not value
        or len(value) > 128
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    ):
        raise RuntimeError(f"{name} is invalid")
    return value
