# Mobile Finance Assistant

A mobile-first personal finance assistant built with Flutter. This repository
contains production application source and a synthetic runtime Home fixture;
internal tests, product documents, and project-memory files are intentionally
not part of this clean export.

## Included

- Responsive Home UI for 360–430 dp phones
- Light and dark themes with four accent colors
- Russian localization with an extensible ARB setup
- Balance privacy masking and Android secure-screen protection
- Monthly summary, trend chart, primary goal, upcoming payments, and recent
  confirmed transactions
- Loading, ready, empty, refreshing, partial, offline, expired-session, and
  fatal-error states
- Riverpod state management behind a `HomeRepository` interface
- Typed read-only Home API with correlation IDs, bounded timeouts, typed
  failures, ETag, and `If-None-Match`
- Cache-first stale-while-revalidate orchestration with bounded retry and an
  explicit invalidation hook after a confirmed operation
- Versioned AES-256-GCM Home snapshot cache with its key held in platform
  secure storage
- Decimal-string money validation

All bundled financial data is synthetic. No backend, bank provider,
speech-to-text service, token, or production credential is bundled.

## Project layout

- `lib/app/` — application shell, themes, settings, and privacy bridge
- `lib/features/home/` — Home domain, API/cache, application, and presentation
  layers
- `lib/l10n/` — localization source and generated delegates
- `assets/fixtures/` — synthetic runtime fixture
- `contracts/home/v1/` — versioned Home response schema
- `android/` and `ios/` — native Flutter hosts

## Run locally

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter run
```

The default build uses the synthetic runtime fixture. A compliant read-only
Home service can be selected without changing widgets:

```bash
flutter run \
  --dart-define=HOME_API_BASE_URL=https://api.example.com \
  --dart-define=HOME_API_TIMEZONE=Europe/Berlin
```

The future authentication flow writes a bearer token and stable opaque account
scope through `SecureHomeSessionStore`; both live as one platform-secure value,
never in SharedPreferences. If a verified session scope is unavailable,
encrypted snapshot persistence is deliberately disabled to prevent
cross-account cache reuse.

Deterministic scenarios can be selected at compile time:

```bash
flutter run --dart-define=HOME_FIXTURE=empty
flutter run --dart-define=HOME_SCENARIO=partial
flutter run --dart-define=HOME_SCENARIO=offline
flutter run --dart-define=HOME_SCENARIO=auth
flutter run --dart-define=HOME_SCENARIO=fatal
flutter run --dart-define=HOME_SCENARIO=refresh_failure
```

Offline and authentication fixture scenarios remain available for deterministic
UI review. A real token refresh flow and the minimal FastAPI service are not
implemented in this repository.

## Runtime dependencies

- `dio` — typed HTTP transport (MIT)
- `flutter_secure_storage` — platform-protected key storage (BSD-3-Clause)
- `cryptography` — authenticated AES-GCM encryption (Apache-2.0)
- `path_provider` — application cache location (BSD-3-Clause)

These packages are open source and require no paid runtime service. The minimum
supported platform versions are Android 24 and iOS 13.
