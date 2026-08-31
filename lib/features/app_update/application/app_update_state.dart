import 'package:flutter/foundation.dart';

import '../../finance_entry/domain/finance_entry_models.dart';

/// States of the update check a person starts by pressing a button (ADR 0026).
///
/// There is no automatic check. Nothing here happens unless someone asks for
/// it, which is also why every state is one a person is looking at.
sealed class AppUpdateState {
  const AppUpdateState();
}

/// Nothing has been asked yet.
final class AppUpdateIdle extends AppUpdateState {
  const AppUpdateIdle();
}

final class AppUpdateChecking extends AppUpdateState {
  const AppUpdateChecking();
}

/// The server has nothing newer than what is installed.
final class AppUpdateUpToDate extends AppUpdateState {
  const AppUpdateUpToDate();
}

@immutable
final class AppUpdateAvailable extends AppUpdateState {
  const AppUpdateAvailable(this.release);

  final AppRelease release;
}

@immutable
final class AppUpdateDownloading extends AppUpdateState {
  const AppUpdateDownloading({
    required this.release,
    required this.receivedBytes,
  });

  final AppRelease release;
  final int receivedBytes;

  /// Null until the first bytes arrive, so the interface shows motion rather
  /// than a percentage it had to invent.
  double? get progress =>
      release.sizeBytes <= 0 ? null : receivedBytes / release.sizeBytes;
}

/// The file is downloaded, verified, and handed to the system installer.
///
/// Whether it is actually installed is the installer's answer, given to the
/// user in its own dialog — this app never learns it.
@immutable
final class AppUpdateHandedToInstaller extends AppUpdateState {
  const AppUpdateHandedToInstaller(this.release);

  final AppRelease release;
}

/// Android will not let this app ask to install anything until the user grants
/// it once, in system settings.
@immutable
final class AppUpdateNeedsPermission extends AppUpdateState {
  const AppUpdateNeedsPermission(this.release);

  final AppRelease release;
}

enum AppUpdateFailureReason {
  /// The check or the download did not reach the server.
  unreachable,

  /// The server answered, but not with a usable release.
  serverUnavailable,

  /// The download arrived and did not match the published digest.
  corruptedDownload,

  /// The system installer refused to open.
  installerUnavailable,

  authenticationRequired,
}

@immutable
final class AppUpdateFailed extends AppUpdateState {
  const AppUpdateFailed(this.reason, {this.release});

  final AppUpdateFailureReason reason;

  /// Present when the failure happened after something was found, so the
  /// screen can offer to try that same version again.
  final AppRelease? release;
}
