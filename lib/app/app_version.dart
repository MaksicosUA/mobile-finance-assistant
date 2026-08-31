/// The build the user is looking at, shown on the profile screen.
///
/// Deliberately not a package dependency. The number that matters is the one
/// the delivery script already resolves for the Android manifest (ADR 0013),
/// so it passes the same value in rather than a second source computing its
/// own answer. It exists because working out which build is on a phone
/// repeatedly meant reading a manifest instead of the app.
///
/// A `flutter run` or a widget test carries no define and falls back to the
/// pubspec version, which [appVersionFallback] pins and a test asserts, so the
/// two cannot drift apart silently.
library;

/// The `version:` field of `pubspec.yaml`, without its build metadata.
const String appVersionFallback = '0.1.15';

const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: appVersionFallback,
);
