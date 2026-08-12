"""Strict versioned contract for the profile read.

One request answers the whole screen: who is signed in, and the durable facts
of their account. The identity does not come from the authentication response
on purpose — that is held in memory and is gone after an app restart, while
this survives it.
"""

from __future__ import annotations

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class ProfileApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, populate_by_name=True)


class ProfileUser(ProfileApiModel):
    id: UUID
    display_name: str = Field(alias="displayName", min_length=1, max_length=100)
    # The sign-in identifier, shown so a user can tell which account they are
    # in. It is never logged and never leaves this authenticated response.
    email: EmailStr


class ProfileAccount(ProfileApiModel):
    """The durable facts of the account, not its balance.

    No money here: a balance belongs on Home, and a second place reporting it
    is a second thing that can disagree.
    """

    id: UUID
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    # The canonical reporting timezone every local date is resolved in
    # (ADR 0010), and the baseline every operation must follow (ADR 0016).
    canonical_timezone: str = Field(alias="canonicalTimezone", max_length=128)
    opening_balance_on: date = Field(alias="openingBalanceOn")


class ProfileResponse(ProfileApiModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    user: ProfileUser
    # Null until the account is bootstrapped: a registered user without an
    # account is a real state, not an error.
    account: ProfileAccount | None = None


ProfileErrorCode = Literal["PROFILE_UNAVAILABLE"]


class ProfileErrorDetail(ProfileApiModel):
    code: ProfileErrorCode


class ProfileErrorResponse(ProfileApiModel):
    detail: ProfileErrorDetail
