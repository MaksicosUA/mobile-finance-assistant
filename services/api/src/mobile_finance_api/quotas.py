"""How much one account may hold.

Nobody's finances come near these numbers. They exist because every list here is
read whole on some request, on a server shared by everyone, so an account that
held a million of anything would slow all the others down. Reached on purpose,
one is an ordinary refusal; the writes are per account, so one person hitting a
limit changes nothing for anybody else.
"""

from __future__ import annotations

from sqlalchemy import Select
from sqlalchemy.ext.asyncio import AsyncSession

MAX_WALLETS = 16
MAX_CATEGORIES = 300
MAX_KEYWORDS = 1000
MAX_ACTIVE_GOALS = 100
MAX_ACTIVE_RULES = 50
MAX_OPEN_PLANS = 500


class QuotaExceeded(Exception):
    """This account already holds as many of these as one account may."""


async def require_room(
    database: AsyncSession,
    count: Select[tuple[int]],
    *,
    limit: int,
    adding: int = 1,
) -> None:
    """Refuse inside the writing transaction, under the lock its caller holds."""

    held = int(await database.scalar(count) or 0)
    if held + adding > limit:
        raise QuotaExceeded
