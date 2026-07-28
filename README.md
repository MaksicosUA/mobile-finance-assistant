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
- Authenticated `GET /api/v1/home` returning a persistent first-use empty state
  or the newest account-scoped PostgreSQL Home projection
- Immutable, versioned Home read-model tables keyed by exact IANA timezone,
  with Decimal money, explicit month boundaries, Finance consistency checks,
  ordered child blocks, and stable ETag representations
- Versioned `expense`/`income` operation evaluation and confirmed-commit API
  with strict decimal-string money and captured IANA timezone semantics
- Deterministic Finance Core validation with account-scoped command
  idempotency, authoritative PostgreSQL operations, audit events, and a
  transactional server outbox
- Explicit first-account bootstrap with an immutable signed opening balance,
  one authoritative default EUR account, and a canonical IANA timezone stored
  on the authenticated user profile
- Owned-account allocation for every new operation, protected by database
  ownership/currency constraints and commit-time revalidation
- Alembic migrations for accounts, authentication sessions, Home read
  projections, and authoritative finance operations

The repository contains no production credential or real user financial data.
The default Flutter build uses synthetic Home fixtures and does not require an
account. Network builds enable the real authentication gate. The API exposes
bounded first-account and confirmed-operation write paths, but the Flutter UI
does not yet call them, and the API does not yet consume either server outbox.
A future deterministic projector will derive Home balances from the immutable
opening baseline plus confirmed operations. Home balance projection, mobile
account/operation entry, offline command storage, bank synchronization,
speech-to-text, and full chat are not part of this slice.

## Project layout

- `lib/app/` — application shell, themes, settings, and privacy bridge
- `lib/features/auth/` — authentication application, data, domain, and UI
- `lib/features/home/` — Home domain, API/cache, application, and presentation
- `lib/l10n/` — localization source and generated delegates
- `assets/fixtures/` — synthetic runtime Home fixture
- `contracts/home/v1/` — versioned Home response schema
- `contracts/finance/v1/` — versioned Finance account and operation schemas
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

An authenticated user first creates the only v1 Finance account through an
explicit review-and-confirm flow:

- `GET /api/v1/accounts` returns the authoritative setup state;
- `POST /api/v1/accounts/evaluate` validates a strict account draft and returns
  `REJECT` or a canonical `NEEDS_CONFIRMATION` draft hash;
- `POST /api/v1/accounts/commit` atomically stores the account, the user's
  canonical timezone, a hash-only audit event, and a minimal outbox event. An
  exact retry returns the same account with `idempotentReplay: true`.

Account v1 supports exactly one active default account in `EUR`. Its signed
decimal-string `openingBalance` is the account stock at the start of
`openingBalanceOn` in `canonicalTimezone`; it is immutable and is never treated
as income, expense, or a recent operation. Registration remains identity-only.
The checked-in account contract is regenerated with:

```bash
PYTHONPATH=services/api/src uv run --project services/api \
  python services/api/tool/generate_account_contract.py
```

Authenticated operation writes then use two endpoints:

- `POST /api/v1/operations/evaluate` returns `REJECT` or a canonical
  `NEEDS_CONFIRMATION` draft hash without writing financial state;
- `POST /api/v1/operations/commit` revalidates the confirmed draft and returns
  `ACCEPT`, with `idempotentReplay: true` for an identical retry.

Operation v1 accepts only positive decimal-string `expense` and `income`
amounts in `EUR`; other currencies fail closed until a verified ISO registry
and exchange-rate policy exist. It resolves `today`/`yesterday` from the
captured UTC instant and captured IANA timezone, which remains distinct from
the user's canonical timezone while travelling. Every new operation requires
an explicit active `accountId` owned by the authenticated user; the server
never substitutes a default implicitly. Legacy unallocated rows remain
auditable and replayable but are excluded from authoritative balances. The
checked-in operation contract is regenerated with:

```bash
PYTHONPATH=services/api/src uv run --project services/api \
  python services/api/tool/generate_operation_contract.py
```

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
tool/build_android_network_debug.sh --install
```

The script always supplies the authenticated API defines and writes the
distinct artifact
`build/app/outputs/flutter-apk/mobile-finance-assistant-network-debug.apk`.
Running a plain `flutter build apk` intentionally creates the fixture build and
must not be installed over an account-testing build.

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
