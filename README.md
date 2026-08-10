# Mobile Finance Assistant

A mobile-first personal finance assistant built with Flutter and FastAPI. This
repository holds the production source and both test suites. Product documents,
project memory, and agent instructions are intentionally maintained outside it.

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
- Authenticated `GET /api/v2/home` returning a persistent first-use empty state
  or the newest account-scoped PostgreSQL Home projection; `/api/v1/home`
  remains a fail-closed compatibility contract for representable revisions
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
- Native Flutter review-and-confirm flow for first-account setup and structured
  online income/expense entry, with exact command retries and bounded Home
  projection convergence
- Account-scoped encrypted SQLite outbox for confirmed operation commands,
  with enqueue-before-network delivery, persisted retry/backoff, process-death
  recovery, and exact idempotent replay after reconnect
- Owned-account allocation for every new operation, protected by database
  ownership/currency constraints and commit-time revalidation
- Deterministic PostgreSQL outbox consumer that rebuilds immutable Home
  revisions from the opening baseline and confirmed allocated operations
- Alembic migrations for accounts, authentication sessions, Home read
  projections, and authoritative finance operations

The repository contains no production credential or real user financial data.
The default Flutter build uses synthetic Home fixtures and does not require an
account. Network builds enable the real authentication gate. The API exposes
bounded first-account and confirmed-operation write paths, and the standalone
projector consumes both server outboxes. The network Flutter build calls the
account and operation endpoints through an explicit manual review flow.
Cold-start offline drafting/evaluation, bank synchronization, speech-to-text,
AI extraction, and full chat are not part of this slice.

## Project layout

- `lib/app/` — application shell, themes, settings, and privacy bridge
- `lib/features/auth/` — authentication application, data, domain, and UI
- `lib/features/finance_entry/` — account and operation review/confirm flow,
  plus encrypted delivery of confirmed operations
- `lib/features/home/` — Home domain, API/cache, application, and presentation
- `lib/l10n/` — localization source and generated delegates
- `assets/fixtures/` — synthetic runtime Home fixture
- `contracts/home/v1/` — frozen original Home compatibility schema
- `contracts/home/v2/` — current Home schema with authoritative date-only and
  nullable operation facts
- `contracts/finance/v1/` — versioned Finance account and operation schemas
- `services/api/` — FastAPI service, PostgreSQL adapters, and Alembic migrations
- `test/` — Flutter unit, widget, golden, and contract tests
- `services/api/tests/` — backend tests; `*_postgres_e2e.py` scripts need a
  live database and are not collected by default
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

Run the projector as a separate process; do not attach it to the FastAPI
lifespan. It needs only `MFA_DATABASE_URL`, recalculates each affected Home from
authoritative rows, and publishes the revision plus outbox acknowledgements in
one transaction.

```bash
PYTHONPATH=services/api/src uv run --project services/api \
  python -m mobile_finance_api.projector_runtime --once

# Or poll continuously under a process supervisor:
PYTHONPATH=services/api/src uv run --project services/api \
  python -m mobile_finance_api.projector_runtime

# Privacy-safe process health: 0 healthy, 1 degraded, 2 unavailable.
PYTHONPATH=services/api/src uv run --project services/api \
  python -m mobile_finance_api.projector_runtime --check-health
```

The reconciliation pass creates at most one revision per canonical local day,
so the seven-day trend and month boundary advance without a new operation.
Outbox payloads remain identifier-only; the projector reloads all money and
dates from PostgreSQL rather than applying event deltas.

Only one projector becomes leader through a PostgreSQL advisory lease. A
background heartbeat guards long work and cancels it if leadership is lost.
Strictly invalid outbox contracts use durable `2, 4, 8, ...` second retries,
capped at five minutes, and enter an in-place dead-letter state on the eighth
failure. The dedicated validation counter starts at zero during migration and
never reinterprets legacy delivery attempts. A failed user stream stays
fail-closed without preventing ready streams for other users. There is no
operator requeue API yet.

The worker also removes at most 100 eligible Home snapshot roots per cleanup
cycle while retaining every revision younger than 30 days and the newest two
per user/timezone/month series. Authoritative accounts, operations, audit, and
outbox rows are never retention targets. A deployment process manager is still
required to restart the worker and call `--check-health`.

Migration `0006_projector_supervision` is intentionally not rolling-compatible
with the old writers. For an existing local database, first stop both the API
and projector, take and verify a PostgreSQL backup, run `alembic upgrade head`,
and only then start the new API and projector. Do not run old application
processes against the upgraded outbox constraints.

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

After explicit confirmation, Flutter encrypts and persists the exact commit
command before the first HTTP request. A transient failure, lost response, or
process restart keeps the command pending and retries the same `commandId`,
draft hash, fields, and confirmation time. A pending command never changes the
displayed balance. Only a strict server `ACCEPT` marks it synced and triggers a
separate Home convergence. The first version of this outbox does not evaluate
new commands without a network connection and does not run an OS background
worker while the application is suspended.

Operation v1 accepts only positive decimal-string `expense` and `income`
amounts in `EUR`; other currencies fail closed until a verified ISO registry
and exchange-rate policy exist. It resolves `today`/`yesterday` from the
captured UTC instant and captured IANA timezone, which remains distinct from
the user's canonical timezone while travelling. Every new operation requires
an explicit active `accountId` owned by the authenticated user; the server
never substitutes a default implicitly. Legacy unallocated rows remain
auditable and replayable but are excluded from authoritative balances.

The mobile client obtains the UTC instant, current OS IANA timezone, its local
date, and the canonical reporting-zone date atomically through a narrow native
Android/iOS bridge. If the platform cannot provide a strict portable timezone
context, the client sends no Finance command and never falls back to the
canonical reporting timezone.

The checked-in operation contract is regenerated with:

```bash
PYTHONPATH=services/api/src uv run --project services/api \
  python services/api/tool/generate_operation_contract.py
```

An intended future payment is a *planned cost*, a separate forecast entity that
never moves the authoritative balance (ADR 0018):

- `POST /api/v1/planned-costs` records one plan, idempotent on `commandId`;
- `POST /api/v1/planned-costs/{id}/transition` moves it once to `confirmed`,
  `skipped`, or `cancelled`;
- `GET /api/v1/planned-costs` lists plans and reports the local `evaluatedOn`
  date used to derive `isDue`.

A planned amount is excluded from balance, monthly income and expense, net
flow, and the trend series. `isDue` is derived at read time from the account's
canonical timezone and is never stored. A plan may not precede the account
baseline, because such a plan could never be confirmed into a legal operation.

Confirming a plan does not create money on this path. The client first commits
a normal operation through `/api/v1/operations/*`, then reports that
`operationCommandId` on the transition; the server resolves it to the stored
operation and fails closed with `CONFIRMING_OPERATION_MISSING` when none
exists. Committing the operation first is deliberate: a lost transition leaves
a visible outstanding plan, while the reverse order could hide a real payment.

Planned-cost changes write an identifier-only event to a separate
`planned_cost_outbox_events` table. The Home projector does not consume it yet;
the rows accumulate so the upcoming-payments slice needs no backfill. The
checked-in planned cost contract is regenerated with:

```bash
PYTHONPATH=services/api/src uv run --project services/api \
  python services/api/tool/generate_planned_cost_contract.py
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

The script requires a clean, non-shallow Git worktree, always supplies the
authenticated API defines, and writes the distinct artifact
`build/app/outputs/flutter-apk/mobile-finance-assistant-network-debug.apk`.
Running a plain `flutter build apk` intentionally creates the fixture build and
must not be installed over an account-testing build.

To reproduce both deliverable variants from one committed revision, run:

```bash
tool/build_android_apks.sh
```

The Android SDK `apkanalyzer` must be available through `PATH`,
`ANDROID_SDK_ROOT`/`ANDROID_HOME`, or `APKANALYZER_BIN`. The build stops unless
both APK manifests contain the resolved version.

## Android APK versioning

Deliverable APK versions are derived from committed source and are never
written back to Git by a build. The numeric component after `+` in
`pubspec.yaml` is a version-code epoch. The resolver calculates:

```text
versionCode = pubspec epoch * 1,000,000 + reachable Git commit count
versionName = pubspec x.y.z + "." + versionCode
```

Each deliverable commit must descend from the previous deliverable commit.
Consequently its reachable commit count, `versionCode`, and `versionName` are
higher. Rebuilding the same SHA produces the same version, including in local
and GitHub builds. Fixture and network APKs are resolved once and receive the
same version. Concurrent sibling-branch artifacts are previews and do not form
one ordered Android upgrade chain.

`tool/resolve_android_build_version.sh` rejects shallow history, an uncommitted
worktree, malformed source versions, a build-epoch decrease anywhere in the
reachable history, and Android version-code overflow. Push builds also require
the new revision to descend from the preceding revision of that branch. Commit
the intended source before producing a deliverable APK; do not replace the
resolver with timestamps or local counters.

## GitHub Actions APKs

Every push, and each manual workflow run, performs the locked dependency,
localization, formatting, and analysis checks, then runs both test suites, then
builds and manifest-verifies both debug APKs. `flutter test` and `pytest` are
mandatory gates: a failing test produces no APK. The `fixture-debug` APK uses
synthetic Home data; the `network-debug` APK enables authentication and the
real API. Checkout uses full Git history and the version is resolved once, so
both variants of a revision share one version.

Only the `network-debug` APK is published, only from `main`, and only for
7 days. Two universal ~170 MiB APKs per run with 14-day retention exhausted the
Actions storage quota, which then failed runs whose checks, tests, and builds
had all passed. Narrowing publication does not weaken the gate: every branch
still builds and verifies both APKs, it simply does not store them.

The published artifact carries a SHA-256 checksum and
`android-build-version.txt` with the source SHA and resolved version. CI signs
with an ephemeral debug key, so installing a CI APK over a locally built one
forces an uninstall that clears the session and the encrypted operation outbox.
Registered-account testing therefore uses `tool/build_android_network_debug.sh`,
which signs with the stable local debug keystore and upgrades in place.

The network build reads the non-secret repository variables
`ANDROID_DEBUG_API_BASE_URL` and `HOME_API_TIMEZONE`. Without them it uses
`http://127.0.0.1:8000` and `Europe/Berlin`, suitable for `adb reverse`. Never
put credentials, tokens, or other secrets in these variables or Dart defines:
their values are compiled into the APK.

GitHub-hosted runners generate an ephemeral debug signing key. APKs from
different workflow runs therefore cannot be assumed to support
`adb install -r`; a stable CI-only key stored in GitHub encrypted secrets is
required before relying on in-place upgrades that retain application data.

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
Dio, `flutter_secure_storage`, `cryptography`, `sqflite`, `path`,
`path_provider`, and `shared_preferences`. Backend dependencies are FastAPI,
Pydantic, SQLAlchemy, asyncpg, Alembic, argon2-cffi, PyJWT, email-validator,
Uvicorn, and tzdata.

The minimum supported mobile platform versions are Android 24 and iOS 13.
