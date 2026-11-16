"""A recovery code: what a person keeps to get back in without the password.

The server sends no mail and never proves an address belongs to anyone
(ADR 0024), so a forgotten password cannot be reset by a link. A code the person
was shown once, and kept somewhere, is the proof instead (ADR 0035).

The code is made here, never chosen by the person, so it carries 100 bits and a
plain digest is enough to store it: there is nothing to guess offline. Only the
digest is kept.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
from dataclasses import dataclass

#: Crockford's alphabet: no I, L, O or U, so nothing in a code can be read as
#: something else when it is copied by hand from paper.
_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
_GROUPS = 4
_GROUP_LENGTH = 5
_LENGTH = _GROUPS * _GROUP_LENGTH
#: What people type for a character the alphabet leaves out.
_MISREAD = str.maketrans({"O": "0", "I": "1", "L": "1"})
#: Whatever a keyboard puts between the groups: a hyphen, the dashes a phone
#: substitutes for one, or a space.
_SEPARATORS = str.maketrans("", "", " \t-‐‑‒–—−")
_DOMAIN = b"mfa-recovery-code-v1:"
DIGEST_BYTES = hashlib.sha256().digest_size
#: The longest text worth reading as a code, separators included.
MAXIMUM_INPUT_LENGTH = 64


class InvalidRecoveryCode(ValueError):
    """The text is not shaped like a code this server could have issued."""


@dataclass(frozen=True, slots=True, repr=False)
class RecoveryCodeMaterial:
    #: Shown to the person once, and stored nowhere.
    value: str
    digest: bytes


def new_recovery_code() -> RecoveryCodeMaterial:
    canonical = "".join(secrets.choice(_ALPHABET) for _ in range(_LENGTH))
    value = "-".join(
        canonical[start : start + _GROUP_LENGTH]
        for start in range(0, _LENGTH, _GROUP_LENGTH)
    )
    return RecoveryCodeMaterial(value=value, digest=_digest(canonical))


def hash_recovery_code(text: str) -> bytes:
    """The digest of a code as a person typed it, however they spaced it."""

    if len(text) > MAXIMUM_INPUT_LENGTH:
        raise InvalidRecoveryCode
    canonical = text.translate(_SEPARATORS).upper().translate(_MISREAD)
    if len(canonical) != _LENGTH or any(
        character not in _ALPHABET for character in canonical
    ):
        raise InvalidRecoveryCode
    return _digest(canonical)


def same_digest(stored: bytes | None, candidate: bytes | None) -> bool:
    """Compare without telling a near miss from a far one by how long it took."""

    # An account with no code, or text that is not a code, is still compared
    # against something, so neither answers faster than a wrong code does.
    blank = bytes(DIGEST_BYTES)
    matches = hmac.compare_digest(
        stored if stored is not None else blank,
        candidate if candidate is not None else blank,
    )
    return matches and stored is not None and candidate is not None


def _digest(canonical: str) -> bytes:
    return hashlib.sha256(_DOMAIN + canonical.encode("ascii")).digest()
