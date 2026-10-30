"""A download link for someone who does not have the app yet (ADR 0026).

The update path behind the bearer token updates an *installed* app. It cannot
deliver a first install, because the token comes from the app: a person with no
copy has no way to fetch one. This is the other door — a capability URL that is
unguessable and carries its own expiry inside a signature, so nothing has to be
stored, cleaned up, or migrated.

**Revocation is all-or-nothing, deliberately.** Rotating the secret invalidates
every link ever issued; there is no way to withdraw one and keep another. At the
scale this serves — people who were chosen and invited — re-issuing a second
link is cheaper than a table, a repository and a migration, and a story that
simple cannot rot. The expiry is what limits a link that got somewhere it
should not have.

What the link hands over is the same signed APK the authenticated route serves.
It is not a credential: registration stays closed to an allowlist (ADR 0024), so
installing the app grants nothing until someone is invited separately.
"""

from __future__ import annotations

import hmac
from base64 import urlsafe_b64encode
from datetime import datetime
from hashlib import sha256

#: Pins the signature to this purpose, so a secret shared with anything else
#: could not be replayed across features.
_CONTEXT = b"mfa-app-download-link:v1"

#: Below this a signature is not worth the name.
MINIMUM_SECRET_BYTES = 32

#: A signed link is `<unix seconds>.<43 base64url characters>`. Nothing longer
#: is worth parsing, and bounding it first keeps unauthenticated input cheap.
_MAXIMUM_LINK_LENGTH = 64


def sign_download_link(*, secret: bytes, expires_at: datetime) -> str:
    """Return the opaque segment of a download URL valid until `expires_at`."""

    if len(secret) < MINIMUM_SECRET_BYTES:
        raise ValueError("download link secret is too short")
    if expires_at.tzinfo is None:
        raise ValueError("expiry must be timezone-aware")
    expires = str(int(expires_at.timestamp()))
    return f"{expires}.{_signature(secret=secret, expires=expires)}"


def verify_download_link(*, secret: bytes, link: str, now: datetime) -> bool:
    """Whether `link` was signed with `secret` and has not expired yet.

    Every failure — malformed, forged, expired — is one answer. The caller
    turns all of them into the same refusal a deployment with nothing published
    gives, so the URL cannot be used to learn which part was wrong.
    """

    if len(secret) < MINIMUM_SECRET_BYTES:
        return False
    if not link or len(link) > _MAXIMUM_LINK_LENGTH or not link.isascii():
        return False
    expires, separator, signature = link.partition(".")
    if not separator or not expires.isdigit() or len(expires) > 12:
        return False
    expected = _signature(secret=secret, expires=expires)
    if not hmac.compare_digest(expected, signature):
        return False
    if now.tzinfo is None:
        raise ValueError("the current instant must be timezone-aware")
    return now.timestamp() < int(expires)


def _signature(*, secret: bytes, expires: str) -> str:
    digest = hmac.new(
        secret,
        _CONTEXT + b":" + expires.encode("ascii"),
        sha256,
    ).digest()
    return urlsafe_b64encode(digest).decode("ascii").rstrip("=")
