"""Stable validation for user-supplied IANA timezone identifiers."""

from __future__ import annotations

from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

# tzdb ships these implementation-oriented names, but none is a stable user
# profile identifier. In particular, ``localtime`` may resolve differently on
# another host after a restart or deployment.
_UNSTABLE_TIMEZONE_KEYS = frozenset({"Factory", "localtime", "posixrules"})


def validated_iana_timezone(value: str) -> ZoneInfo:
    if (
        not value
        or len(value) > 128
        or value != value.strip()
        or value in _UNSTABLE_TIMEZONE_KEYS
        or any(ord(character) < 0x20 or ord(character) == 0x7F for character in value)
    ):
        raise ValueError("invalid IANA timezone")
    try:
        return ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError) as error:
        raise ValueError("invalid IANA timezone") from error


def validated_iana_timezone_key(value: str) -> str:
    return validated_iana_timezone(value).key
