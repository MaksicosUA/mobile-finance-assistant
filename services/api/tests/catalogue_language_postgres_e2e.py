"""Opt-in PostgreSQL E2E: a catalogue written in the language asked for (ADR 0034).

Run against a disposable database:

    MFA_TEST_DATABASE_URL=<isolated-url> PYTHONPATH=src .venv/bin/python \
        tests/catalogue_language_postgres_e2e.py

It proves what the in-memory tests cannot: that every language's seeded words
get past the database's own checks, that the header reaches the transaction
that writes them, and that a sentence in that language then finds its category
through the real read path. A second wallet must not seed anything, whatever
language it asks for.
"""

from __future__ import annotations

import asyncio
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from mobile_finance_api.account_core import AccountCore
from mobile_finance_api.auth import PostgresCurrentUserAuthenticator
from mobile_finance_api.auth_service import PostgresAuthenticationService
from mobile_finance_api.category_contracts import (
    CatalogueLanguage,
    seeded_categories,
    seeded_category_keywords,
)
from mobile_finance_api.database import AsyncSessionFactory, create_database
from mobile_finance_api.db_models import FinanceCategoryRow
from mobile_finance_api.main import create_app
from mobile_finance_api.passwords import PasswordService
from mobile_finance_api.postgres_category_repository import (
    PostgresCategoryRepository,
)
from mobile_finance_api.postgres_finance_account_repository import (
    PostgresFinanceAccountRepository,
)
from mobile_finance_api.tokens import AccessTokenCodec

DATABASE_URL = os.environ["MFA_TEST_DATABASE_URL"]
JWT_SECRET = "test-only-catalogue-language-secret-32-bytes"
API_ROOT = Path(__file__).resolve().parents[1]
OPENING_ON = (datetime.now(UTC) - timedelta(days=60)).date()

_SENTENCES: dict[CatalogueLanguage, tuple[str, str]] = {
    "ru": ("Потратил 12,50 на продукты", "Продукты"),
    "uk": ("Витратив 200 гривень на продукти", "Продукти"),
    "en": ("Spent 12.50 on groceries", "Groceries"),
    "de": ("12,50 Euro für Lebensmittel", "Lebensmittel"),
}


def _migrate() -> None:
    os.environ["MFA_DATABASE_URL"] = DATABASE_URL
    config = Config(str(API_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(API_ROOT / "migrations"))
    config.set_main_option("sqlalchemy.url", DATABASE_URL)
    command.upgrade(config, "head")


def _application(*, session_factory: AsyncSessionFactory, tokens: AccessTokenCodec):
    accounts = PostgresFinanceAccountRepository(session_factory=session_factory)
    return create_app(
        current_user_authenticator=PostgresCurrentUserAuthenticator(
            session_factory=session_factory,
            access_tokens=tokens,
        ),
        authentication_service=PostgresAuthenticationService(
            session_factory=session_factory,
            password_service=PasswordService(),
            access_tokens=tokens,
        ),
        account_core=AccountCore(repository=accounts),
        category_repository=PostgresCategoryRepository(session_factory=session_factory),
    )


async def _open_wallet(
    client: AsyncClient, *, headers: dict[str, str], currency: str
) -> None:
    draft = {
        "schemaVersion": "1",
        "commandId": str(uuid4()),
        "name": f"Synthetic {currency}",
        "currency": currency,
        "openingBalance": "1000.00",
        "openingBalanceOn": OPENING_ON.isoformat(),
        "canonicalTimezone": "Europe/Berlin",
    }
    evaluation = await client.post(
        "/api/v1/accounts/evaluate", json={"draft": draft}, headers=headers
    )
    assert evaluation.status_code == 200, evaluation.text
    commit = await client.post(
        "/api/v1/accounts/commit",
        json={
            "schemaVersion": "1",
            "draft": draft,
            "draftHash": evaluation.json()["draftHash"],
            "confirmedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        },
        headers=headers,
    )
    assert commit.status_code == 201, commit.text


async def _scenario(session_factory: AsyncSessionFactory) -> None:
    tokens = AccessTokenCodec(
        secret=JWT_SECRET.encode(),
        issuer="mobile-finance-assistant-test",
        audience="mobile-finance-api-test",
    )
    app = _application(session_factory=session_factory, tokens=tokens)
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        for language, (sentence, expected) in _SENTENCES.items():
            register = await client.post(
                "/api/v1/auth/register",
                json={
                    "email": f"{language}-{uuid4().hex[:8]}@example.com",
                    "password": "synthetic-password-123",
                    "displayName": "Synthetic",
                },
            )
            assert register.status_code == 201, register.text
            user_id = UUID(register.json()["user"]["id"])
            headers = {
                "Authorization": f"Bearer {register.json()['accessToken']}",
                "Accept-Language": language,
            }

            await _open_wallet(client, headers=headers, currency="EUR")

            listed = await client.get("/api/v1/categories", headers=headers)
            assert listed.status_code == 200, listed.text
            names = {row["name"] for row in listed.json()["categories"]}
            assert names == {row.name for row in seeded_categories(language)}, names

            # Every category, because each one's words have to fit the stored
            # shape, and a seeded word a check refuses would fail the bootstrap.
            vocabulary = seeded_category_keywords(language)
            for category in listed.json()["categories"]:
                keywords = await client.get(
                    f"/api/v1/categories/{category['categoryId']}/keywords",
                    headers=headers,
                )
                assert keywords.status_code == 200, keywords.text
                key = next(
                    row.system_key
                    for row in seeded_categories(language)
                    if row.name == category["name"]
                    and row.direction == category["direction"]
                )
                assert set(keywords.json()["keywords"]) == set(vocabulary.get(key, ()))

            parsed = await client.post(
                "/api/v1/operations/parse",
                json={
                    "schemaVersion": "1",
                    "text": sentence,
                    "capturedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
                    "capturedTimezone": "Europe/Berlin",
                },
                headers=headers,
            )
            assert parsed.status_code == 200, parsed.text
            category_id = parsed.json()["proposal"]["categoryId"]
            found = next(
                row["name"]
                for row in listed.json()["categories"]
                if row["categoryId"] == category_id
            )
            assert found == expected, found

            # A later wallet belongs to the same profile and seeds nothing,
            # even when the app's language has changed since.
            await _open_wallet(
                client,
                headers={**headers, "Accept-Language": "fr"},
                currency="USD",
            )
            async with session_factory() as database:
                count = await database.scalar(
                    select(func.count())
                    .select_from(FinanceCategoryRow)
                    .where(FinanceCategoryRow.user_id == user_id)
                )
            assert count == len(seeded_categories(language)), count


def main() -> None:
    _migrate()
    _, session_factory = create_database(DATABASE_URL)
    asyncio.run(_scenario(session_factory))
    print("catalogue language PostgreSQL E2E passed")


if __name__ == "__main__":
    main()
