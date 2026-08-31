"""Fail-closed runtime configuration loaded exclusively from the environment."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True, repr=False)
class RuntimeSettings:
    database_url: str
    jwt_secret: bytes
    jwt_issuer: str
    jwt_audience: str


def require_database_url() -> str:
    """Return the validated PostgreSQL URL needed by non-HTTP workers."""

    database_url = os.environ.get("MFA_DATABASE_URL")
    if not database_url:
        raise RuntimeError("MFA_DATABASE_URL is required")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("MFA_DATABASE_URL must use postgresql+asyncpg")
    return database_url


def load_registration_allowlist() -> frozenset[str] | None:
    """Who may create an account, read from the environment.

    Three states, and the middle one is deliberate:

    * unset — registration is open, which is what a local run and every test
      expect;
    * set and empty — registration is closed to everyone, an explicit decision
      rather than an accident;
    * set with addresses — only those may register.

    Addresses are compared case-insensitively and trimmed, because an invite
    typed with a capital letter is the same invite.
    """

    raw = os.environ.get("MFA_AUTH_REGISTRATION_ALLOWLIST")
    if raw is None:
        return None
    return frozenset(
        entry.strip().casefold() for entry in raw.split(",") if entry.strip()
    )


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


def load_release_directory() -> Path | None:
    """Where published Android builds live, if this deployment publishes any.

    Unset means the deployment does not distribute the app, which is a valid
    state. Set-but-broken is not: once someone intends to publish, a directory
    that cannot be read has to be visible rather than reported as "up to date"
    (ADR 0026).
    """

    raw = os.environ.get("MFA_RELEASE_DIR")
    if raw is None:
        return None
    directory = raw.strip()
    if not directory:
        return None
    return Path(directory)
