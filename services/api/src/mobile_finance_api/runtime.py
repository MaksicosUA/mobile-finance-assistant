"""Explicit PostgreSQL-backed ASGI entrypoint.

Unlike ``mobile_finance_api.main:app``, importing this module requires complete
runtime auth configuration and fails immediately when secrets are absent.
"""

from __future__ import annotations

from .auth import PostgresCurrentUserAuthenticator
from .auth_service import PostgresAuthenticationService
from .config import require_runtime_settings
from .database import create_database
from .main import create_app
from .passwords import PasswordService
from .postgres_home_repository import PostgresEmptyHomeRepository
from .tokens import AccessTokenCodec

settings = require_runtime_settings()
engine, session_factory = create_database(settings.database_url)
access_tokens = AccessTokenCodec(
    secret=settings.jwt_secret,
    issuer=settings.jwt_issuer,
    audience=settings.jwt_audience,
)

app = create_app(
    home_repository=PostgresEmptyHomeRepository(
        session_factory=session_factory,
    ),
    current_user_authenticator=PostgresCurrentUserAuthenticator(
        session_factory=session_factory,
        access_tokens=access_tokens,
    ),
    authentication_service=PostgresAuthenticationService(
        session_factory=session_factory,
        password_service=PasswordService(),
        access_tokens=access_tokens,
    ),
    database_engine=engine,
)
