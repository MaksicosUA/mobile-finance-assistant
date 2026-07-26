# Mobile Finance Assistant

A mobile-first personal finance assistant built with Flutter and FastAPI. This
repository is the clean production-code export: internal tests, product
documents, project memory, and agent instructions are intentionally maintained
outside it.

## Included

- Responsive Home UI for 360–430 dp phones
- Light and dark themes with four accent colors
- Russian localization with an extensible ARB setup
- Balance privacy masking and Android secure-screen protection
- Monthly summary, trend chart, primary goal, upcoming payments, and recent
  confirmed transactions
- Loading, ready, empty, refreshing, partial, offline, expired-session, and
  fatal-error states
- Riverpod state management behind typed repository interfaces
- Dio Home API with correlation IDs, bounded timeouts, typed failures, ETag,
  `If-None-Match`, and stale-while-revalidate cache orchestration
- Versioned AES-256-GCM Home snapshot cache with its key in platform secure
  storage
- Native login and registration flow with secure session restoration
- Self-hosted FastAPI authentication backed by PostgreSQL
- Argon2id password hashing, ten-minute access JWTs, rotating opaque refresh
  tokens, replay detection, and immediate server-side session revocation
- Minimal authenticated `GET /api/v1/home` returning a persistent first-use
  empty state for a newly registered account
- Alembic migrations for accounts and authentication sessions

The repository contains no production credential or real user financial data.
The default Flutter build uses synthetic Home fixtures and does not require an
account. Network builds enable the real authentication gate. Financial writes,
bank synchronization, speech-to-text, and full chat are not part of this slice.

## Project layout

- `lib/app/` — application shell, themes, settings, and privacy bridge
- `lib/features/auth/` — authentication application, data, domain, and UI
- `lib/features/home/` — Home domain, API/cache, application, and presentation
- `lib/l10n/` — localization source and generated delegates
- `assets/fixtures/` — synthetic runtime Home fixture
- `contracts/home/v1/` — versioned Home response schema
- `services/api/` — FastAPI service, PostgreSQL adapters, and Alembic migrations
- `android/` and `ios/` — native Flutter hosts

## Run the fixture app

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter run
```

Deterministic Home scenarios remain available for UI development:

```bash
flutter run --dart-define=HOME_FIXTURE=empty
flutter run --dart-define=HOME_SCENARIO=partial
flutter run --dart-define=HOME_SCENARIO=offline
flutter run --dart-define=HOME_SCENARIO=auth
flutter run --dart-define=HOME_SCENARIO=fatal
flutter run --dart-define=HOME_SCENARIO=refresh_failure
```

## Run the authenticated API

Requirements: Python 3.12, `uv`, and PostgreSQL 16 or newer. Create an empty
database and supply all credentials through the environment. Never commit the
values.

```bash
export MFA_DATABASE_URL='postgresql+asyncpg://USER:PASSWORD@127.0.0.1:5432/DATABASE'
export MFA_AUTH_JWT_SECRET="$(openssl rand -hex 32)"

uv sync --frozen --project services/api
uv run --project services/api \
  alembic -c services/api/alembic.ini upgrade head
uv run --project services/api \
  uvicorn mobile_finance_api.runtime:app --host 127.0.0.1 --port 8000
```

`mobile_finance_api.runtime:app` refuses to start without both required
environment variables. The library entrypoint `mobile_finance_api.main:app`
remains deliberately fail-closed for adapter-based tests and embedding.

Then run the mobile network build against an HTTPS endpoint:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=HOME_API_TIMEZONE=Europe/Berlin
```

For a USB-connected Android test device or emulator, debug builds can use
loopback through ADB. Release builds still require HTTPS.

```bash
adb reverse tcp:8000 tcp:8000
flutter run \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=HOME_API_TIMEZONE=Europe/Berlin
```

Access and refresh tokens, their expiry metadata, the opaque account cache
scope, and a session revision are stored as one versioned value in platform
secure storage. SharedPreferences stores only theme mode, accent, and the
privacy preference.

## Authentication security boundary

- Passwords use Argon2id with explicit memory/time/parallelism parameters.
- Access JWT verification pins algorithm, issuer, audience, token type, user,
  session, token ID, issued-at, not-before, and expiry claims.
- Refresh tokens contain 256 bits of randomness; PostgreSQL stores only their
  SHA-256 digests.
- A refresh token is single-use. Reuse revokes its whole server-side session,
  including any successor produced by a concurrent request.
- Logout is idempotent and invalidates both refresh and otherwise unexpired
  access tokens through the server-side session check.
- Authentication responses are marked `no-store`; API code has no payload or
  credential logging interceptor.

TLS and distributed rate limiting are required before exposing the service to
the public Internet. Email verification, password reset, MFA, signing-key
rotation, and old-session cleanup are intentionally deferred.

## Runtime dependencies

Mobile dependencies are open source and require no paid service: Riverpod,
Dio, `flutter_secure_storage`, `cryptography`, `path_provider`, and
`shared_preferences`. Backend dependencies are FastAPI, Pydantic, SQLAlchemy,
asyncpg, Alembic, argon2-cffi, PyJWT, email-validator, Uvicorn, and tzdata.

The minimum supported mobile platform versions are Android 24 and iOS 13.
