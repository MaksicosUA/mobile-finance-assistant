import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_version.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/data/finance_entry_repository.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';
import '../data/app_update_installer.dart';
import '../data/app_update_schedule_store.dart';
import 'app_update_state.dart';

export 'app_update_state.dart';

/// The Android `versionCode` this build was delivered as.
///
/// A provider rather than a direct read so a test can state which build it is
/// pretending to be: a `flutter test` carries no delivery define and would
/// otherwise always be "nothing to compare against".
final installedVersionCodeProvider = Provider<int?>(
  (ref) => installedVersionCode,
);

/// The clock the weekly interval is measured against.
final updateClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final appUpdateControllerProvider =
    NotifierProvider.autoDispose<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );

/// Checks for a newer build and hands it to the system installer (ADR 0026).
///
/// Nothing here runs on its own. There is no periodic check and none on
/// launch: the person who wants an update is the person who pressed the
/// button, and an update prompt appearing over someone's finances because a
/// timer expired is the app interrupting rather than answering.
class AppUpdateController extends Notifier<AppUpdateState> {
  bool _busy = false;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  AppUpdateInstaller get _installer => ref.read(appUpdateInstallerProvider);

  @override
  AppUpdateState build() {
    ref.watch(authAccountEpochProvider);
    _busy = false;
    return const AppUpdateIdle();
  }

  /// Asks the server at most once a week, at start-up, and says nothing
  /// unless it has something to say.
  ///
  /// A quiet check that finds nothing leaves the screen exactly as it was: the
  /// person did not ask, so they are not told. A failure is silent for the same
  /// reason, and the timestamp advances only on success — a week offline must
  /// not consume the week's check.
  Future<void> checkIfDue() async {
    if (_busy) return;
    if (ref.read(authControllerProvider) is! AuthSignedIn) return;
    final store = ref.read(appUpdateScheduleStoreProvider);
    final now = ref.read(updateClockProvider)();
    try {
      final last = await store.lastCheckedAt();
      if (last != null && now.toUtc().difference(last) < updateCheckInterval) {
        return;
      }
    } on Object {
      return;
    }
    if (!ref.mounted) return;

    _busy = true;
    try {
      final result = await ref
          .read(financeEntryRepositoryProvider)
          .readAppUpdate();
      if (!ref.mounted) return;
      if (result case FinanceEntrySuccess(:final value)) {
        await store.recordCheckedAt(now);
        if (!ref.mounted) return;
        final derived = _stateFor(value.release);
        // Only an actual update is worth interrupting the screen's own state
        // for; "up to date" is an answer to a question nobody asked.
        if (derived is AppUpdateAvailable) state = derived;
      }
    } on Object {
      return;
    } finally {
      _busy = false;
    }
  }

  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    state = const AppUpdateChecking();
    try {
      final result = await _repository.readAppUpdate();
      if (!ref.mounted) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = _stateFor(value.release);
        case FinanceEntryFailureResult(:final failure):
          state = AppUpdateFailed(_reasonFor(failure));
      }
    } on Object {
      if (ref.mounted) {
        state = const AppUpdateFailed(AppUpdateFailureReason.unreachable);
      }
    } finally {
      _busy = false;
    }
  }

  /// Downloads the offered build, verifies it, and opens the installer.
  Future<void> downloadAndInstall(AppRelease release) async {
    if (_busy) return;
    _busy = true;
    state = AppUpdateDownloading(release: release, receivedBytes: 0);
    File? package;
    try {
      if (!await _installer.canInstall()) {
        // Nothing is downloaded until the permission exists: 57 MB fetched to
        // then be refused is a waste of someone's data.
        if (ref.mounted) state = AppUpdateNeedsPermission(release);
        return;
      }
      final directory = await _installer.downloadDirectory();
      package = File('${directory.path}/${release.versionName}.apk');
      if (package.existsSync()) package.deleteSync();

      final result = await _repository.downloadAppRelease(
        savePath: package.path,
        onProgress: (received, _) {
          if (!ref.mounted) return;
          final current = state;
          if (current is! AppUpdateDownloading) return;
          state = AppUpdateDownloading(
            release: release,
            receivedBytes: received,
          );
        },
      );
      if (!ref.mounted) return;
      if (result case FinanceEntryFailureResult(:final failure)) {
        _discard(package);
        state = AppUpdateFailed(_reasonFor(failure), release: release);
        return;
      }

      final intact = await _installer.matchesDigest(
        file: package,
        sha256: release.sha256,
      );
      if (!ref.mounted) return;
      if (!intact) {
        // A file that does not match what was published is deleted rather than
        // offered: handing it to the installer would only produce a refusal
        // after another confirmation.
        _discard(package);
        state = AppUpdateFailed(
          AppUpdateFailureReason.corruptedDownload,
          release: release,
        );
        return;
      }

      await _installer.install(package);
      if (ref.mounted) state = AppUpdateHandedToInstaller(release);
    } on AppUpdateInstallFailed {
      if (ref.mounted) {
        state = AppUpdateFailed(
          AppUpdateFailureReason.installerUnavailable,
          release: release,
        );
      }
    } on Object {
      if (package != null) _discard(package);
      if (ref.mounted) {
        state = AppUpdateFailed(
          AppUpdateFailureReason.unreachable,
          release: release,
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> openPermissionSettings() async {
    await _installer.openPermissionSettings();
  }

  AppUpdateState _stateFor(AppRelease? release) {
    final installed = ref.read(installedVersionCodeProvider);
    if (release == null) return const AppUpdateUpToDate();
    // A development build carries no version code, so there is nothing to
    // compare against and nothing to offer.
    if (installed == null) return const AppUpdateUpToDate();
    return release.isNewerThan(installed)
        ? AppUpdateAvailable(release)
        : const AppUpdateUpToDate();
  }

  /// Removes a download that will not be installed.
  ///
  /// Synchronous on purpose: unlinking one file is a syscall, and leaving an
  /// await on the failure path meant the state after it could be observed
  /// before it was reached.
  static void _discard(File package) {
    try {
      if (package.existsSync()) package.deleteSync();
    } on Object {
      return;
    }
  }

  static AppUpdateFailureReason _reasonFor(FinanceEntryFailure failure) {
    if (failure.kind == FinanceEntryFailureKind.unauthenticated ||
        failure.kind == FinanceEntryFailureKind.sessionChanged) {
      return AppUpdateFailureReason.authenticationRequired;
    }
    return switch (failure.kind) {
      FinanceEntryFailureKind.offline ||
      FinanceEntryFailureKind.timeout => AppUpdateFailureReason.unreachable,
      _ => AppUpdateFailureReason.serverUnavailable,
    };
  }
}
