"""Strict JSON contracts for first-party mobile authentication."""

from __future__ import annotations

from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StringConstraints

EmailInput = Annotated[
    str,
    StringConstraints(min_length=3, max_length=320),
]
PasswordInput = Annotated[SecretStr, Field(min_length=1, max_length=128)]
DisplayNameInput = Annotated[
    str,
    StringConstraints(min_length=1, max_length=100),
]
RefreshTokenInput = Annotated[SecretStr, Field(min_length=1, max_length=128)]


class AuthApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class RegisterRequest(AuthApiModel):
    email: EmailInput
    password: PasswordInput
    display_name: DisplayNameInput = Field(alias="displayName")


class LoginRequest(AuthApiModel):
    email: EmailInput
    password: PasswordInput


class RefreshRequest(AuthApiModel):
    refresh_token: RefreshTokenInput = Field(alias="refreshToken")


class LogoutRequest(AuthApiModel):
    refresh_token: RefreshTokenInput = Field(alias="refreshToken")


class AuthUserResponse(AuthApiModel):
    id: UUID
    display_name: str = Field(alias="displayName")


class AuthTokenResponse(AuthApiModel):
    access_token: str = Field(alias="accessToken", repr=False)
    refresh_token: str = Field(alias="refreshToken", repr=False)
    token_type: Literal["Bearer"] = Field(default="Bearer", alias="tokenType")
    access_expires_in: int = Field(alias="accessExpiresIn", gt=0, le=3600)
    refresh_expires_in: int = Field(alias="refreshExpiresIn", gt=0)
    cache_scope_id: str = Field(alias="cacheScopeId")
    user: AuthUserResponse
    #: True when this sign-in cancelled a scheduled erasure (ADR 0030). Added
    #: after clients shipped; they read the token fields they know and ignore
    #: the rest, so an older app simply does not mention it.
    deletion_cancelled: bool = Field(default=False, alias="deletionCancelled")
