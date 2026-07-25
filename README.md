# Mobile Finance Assistant

A mobile-first personal finance assistant built with Flutter. The current
release contains the Home foundation and deterministic Home states backed by a
versioned synthetic contract fixture.

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
- Decimal-string money validation

All bundled financial data is synthetic. The application does not currently
connect to a backend, bank provider, speech-to-text service, or production
authentication system.

## Project layout

- `lib/app/` — application shell, themes, settings, and privacy bridge
- `lib/features/home/` — Home domain, data, application, and presentation layers
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

Deterministic scenarios can be selected at compile time:

```bash
flutter run --dart-define=HOME_FIXTURE=empty
flutter run --dart-define=HOME_SCENARIO=partial
flutter run --dart-define=HOME_SCENARIO=offline
flutter run --dart-define=HOME_SCENARIO=auth
flutter run --dart-define=HOME_SCENARIO=fatal
flutter run --dart-define=HOME_SCENARIO=refresh_failure
```

Offline and authentication scenarios are simulated outcomes. Persistent cache,
ETag handling, secure token storage, and real session refresh belong to the next
implementation stage.
