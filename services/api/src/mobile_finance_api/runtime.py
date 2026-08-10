"""Explicit PostgreSQL-backed ASGI entrypoint.

Unlike ``mobile_finance_api.main:app``, importing this module requires complete
runtime auth configuration and fails immediately when secrets are absent.
"""

from __future__ import annotations

from .account_core import AccountCore
from .auth import PostgresCurrentUserAuthenticator
from .auth_service import PostgresAuthenticationService
from .config import require_runtime_settings
from .database import create_database
from .finance_core import FinanceCore
from .main import create_app
from .passwords import PasswordService
from .planned_cost_core import PlannedCostCore
from .postgres_finance_account_repository import PostgresFinanceAccountRepository
from .postgres_finance_repository import PostgresFinanceOperationRepository
from .postgres_home_repository import PostgresHomeRepository
from .postgres_planned_cost_repository import PostgresPlannedCostRepository
from .tokens import AccessTokenCodec

settings = require_runtime_settings()
engine, session_factory = create_database(settings.database_url)
access_tokens = AccessTokenCodec(
    secret=settings.jwt_secret,
    issuer=settings.jwt_issuer,
    audience=settings.jwt_audience,
)
finance_accounts = PostgresFinanceAccountRepository(
    session_factory=session_factory,
)

app = create_app(
    home_repository=PostgresHomeRepository(
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
    account_core=AccountCore(repository=finance_accounts),
    finance_core=FinanceCore(
        repository=PostgresFinanceOperationRepository(
            session_factory=session_factory,
        ),
        account_directory=finance_accounts,
    ),
    planned_cost_core=PlannedCostCore(
        repository=PostgresPlannedCostRepository(
            session_factory=session_factory,
        ),
    ),
    database_engine=engine,
)
