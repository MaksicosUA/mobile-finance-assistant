"""Bounded Argon2id password hashing outside the ASGI event loop."""

from __future__ import annotations

import asyncio
from collections.abc import Callable

from argon2 import PasswordHasher, Type
from argon2.exceptions import InvalidHashError, VerificationError
from starlette.concurrency import run_in_threadpool

#: One Argon2 run takes 19 MiB and most of a core for a moment. The host has two
#: cores, shared with the database, so a burst has to wait in line, and a line
#: longer than a few seconds is answered "later" instead of waiting at all.
_CONCURRENT_HASHES = 2
_MAXIMUM_WAITING = 16
_MINIMUM_PASSWORD_LENGTH = 12
_MAXIMUM_PASSWORD_LENGTH = 128
_MAXIMUM_PASSWORD_BYTES = 1024


class InvalidPassword(ValueError):
    """Raised when a password violates the bounded input contract."""


class PasswordServiceBusy(Exception):
    """Too many password operations are already waiting."""


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
        self._slots = asyncio.Semaphore(_CONCURRENT_HASHES)
        self._waiting = 0

    async def _in_turn[T](self, work: Callable[..., T], *arguments: str) -> T:
        if self._waiting >= _MAXIMUM_WAITING:
            raise PasswordServiceBusy
        self._waiting += 1
        try:
            async with self._slots:
                return await run_in_threadpool(work, *arguments)
        finally:
            self._waiting -= 1

    async def hash(self, password: str) -> str:
        validate_password(password)
        return await self._in_turn(self._hasher.hash, password)

    async def verify(self, password: str, encoded_hash: str | None) -> bool:
        try:
            validate_password(password)
        except InvalidPassword:
            # Still consume one Argon2 operation to reduce account/timing oracles.
            await self._in_turn(
                self._verify_safely,
                self._dummy_hash,
                "not-a-real-account-password-2",
            )
            return False
        candidate_hash = encoded_hash if encoded_hash is not None else self._dummy_hash
        return await self._in_turn(
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


def validate_password(password: str) -> None:
    if not (_MINIMUM_PASSWORD_LENGTH <= len(password) <= _MAXIMUM_PASSWORD_LENGTH):
        raise InvalidPassword
    if len(password.encode("utf-8")) > _MAXIMUM_PASSWORD_BYTES:
        raise InvalidPassword
