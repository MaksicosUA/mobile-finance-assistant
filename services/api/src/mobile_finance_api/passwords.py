"""Bounded Argon2id password hashing outside the ASGI event loop."""

from __future__ import annotations

from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerificationError
from starlette.concurrency import run_in_threadpool

_MINIMUM_PASSWORD_LENGTH = 12
_MAXIMUM_PASSWORD_LENGTH = 128
_MAXIMUM_PASSWORD_BYTES = 1024


class InvalidPassword(ValueError):
    """Raised when a password violates the bounded input contract."""


class PasswordService:
    """Hash and verify passwords with an explicit stable Argon2id policy."""

    def __init__(self) -> None:
        self._hasher = PasswordHasher(
            time_cost=2,
            memory_cost=19_456,
            parallelism=1,
            hash_len=32,
            salt_len=16,
            type=Type.ID,
        )
        # Unknown accounts execute the same memory-hard primitive as real ones.
        # This value is not a credential and never leaves process memory.
        self._dummy_hash = self._hasher.hash("not-a-real-account-password")

    async def hash(self, password: str) -> str:
        _validate_password(password)
        return await run_in_threadpool(self._hasher.hash, password)

    async def verify(self, password: str, encoded_hash: str | None) -> bool:
        try:
            _validate_password(password)
        except InvalidPassword:
            # Still consume one Argon2 operation to reduce account/timing oracles.
            await run_in_threadpool(
                self._verify_safely,
                self._dummy_hash,
                "not-a-real-account-password-2",
            )
            return False
        candidate_hash = encoded_hash if encoded_hash is not None else self._dummy_hash
        return await run_in_threadpool(
            self._verify_safely,
            candidate_hash,
            password,
        )

    def needs_rehash(self, encoded_hash: str) -> bool:
        try:
            return self._hasher.check_needs_rehash(encoded_hash)
        except InvalidHashError:
            return True

    def _verify_safely(self, encoded_hash: str, password: str) -> bool:
        try:
            return self._hasher.verify(encoded_hash, password)
        except (InvalidHashError, VerificationError):
            return False


def _validate_password(password: str) -> None:
    if not (_MINIMUM_PASSWORD_LENGTH <= len(password) <= _MAXIMUM_PASSWORD_LENGTH):
        raise InvalidPassword
    if len(password.encode("utf-8")) > _MAXIMUM_PASSWORD_BYTES:
        raise InvalidPassword
