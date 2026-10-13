import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app_version.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/app_update/application/app_update_controller.dart';
import 'package:mobile_finance_assistant/features/app_update/data/app_update_installer.dart';
import 'package:mobile_finance_assistant/features/app_update/data/app_update_schedule_store.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/app_update/presentation/app_update_section.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _installedCode = 3000139;

Map<String, Object?> _releaseJson({
  int versionCode = 3000140,
  String versionName = '0.1.16.3000140',
  Object? notes = 'Повторяющиеся траты',
}) {
  return <String, Object?>{
    'versionCode': versionCode,
    'versionName': versionName,
    'sizeBytes': 59 * 1024 * 1024,
    'sha256': 'a' * 64,
    'notes': notes,
    'publishedAt': '2026-08-31T22:00:00Z',
  };
}

AppRelease _release({int versionCode = 3000140}) =>
    AppRelease.fromJson(_releaseJson(versionCode: versionCode));

void main() {
  // --- the manifest the server sends ----------------------------------------

  test('a manifest with no release is a normal answer', () {
    final manifest = AppUpdateManifest.fromJson(<String, Object?>{
      'schemaVersion': '1',
      'release': null,
    });

    expect(manifest.release, isNull);
  });

  test('an unknown key in a release is refused rather than ignored', () {
    expect(
      () => AppRelease.fromJson({..._releaseJson(), 'installSilently': true}),
      throwsFormatException,
    );
  });

  test('a digest that is not a sha256 is refused', () {
    expect(
      () => AppRelease.fromJson({..._releaseJson(), 'sha256': 'nope'}),
      throwsFormatException,
    );
  });

  test('an absurd size is refused', () {
    expect(
      () => AppRelease.fromJson({
        ..._releaseJson(),
        'sizeBytes': 2 * 1024 * 1024 * 1024,
      }),
      throwsFormatException,
    );
  });

  test('the same version is not newer, and neither is an older one', () {
    // Android refuses a downgrade anyway; offering one only produces a
    // failure the user has to read.
    expect(
      _release(versionCode: _installedCode).isNewerThan(_installedCode),
      isFalse,
    );
    expect(_release(versionCode: 3000138).isNewerThan(_installedCode), isFalse);
    expect(_release(versionCode: 3000140).isNewerThan(_installedCode), isTrue);
  });

  test('the installed version code is read out of the delivered name', () {
    // One number, resolved once for the Android manifest (ADR 0013). This is
    // the same source, not a second one.
    expect(installedVersionCode, isNull, reason: 'a test build has no define');
  });

  // --- checking --------------------------------------------------------------

  testWidgets('nothing published reads as up to date', (tester) async {
    final repository = _FakeRepository(release: null);
    await _pump(tester, repository: repository);

    await _tapCheck(tester);

    expect(find.byKey(const Key('app-update-up-to-date')), findsOneWidget);
  });

  testWidgets('a build older than the installed one is not offered', (
    tester,
  ) async {
    final repository = _FakeRepository(release: _releaseJson(versionCode: 3));
    await _pump(tester, repository: repository);

    await _tapCheck(tester);

    expect(find.byKey(const Key('app-update-up-to-date')), findsOneWidget);
    expect(find.byKey(const Key('app-update-download')), findsNothing);
  });

  testWidgets('a newer build is offered with its version and size', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository(release: _releaseJson()));

    await _tapCheck(tester);

    expect(find.byKey(const Key('app-update-available')), findsOneWidget);
    expect(find.textContaining('0.1.16.3000140'), findsOneWidget);
    expect(find.textContaining('59.0'), findsOneWidget);
    expect(find.textContaining('Повторяющиеся траты'), findsOneWidget);
  });

  testWidgets('an unreachable server says so and offers a retry', (
    tester,
  ) async {
    final repository = _FakeRepository(
      checkFailure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.offline,
        requestId: 'req_synthetic_update',
      ),
    );
    await _pump(tester, repository: repository);

    await _tapCheck(tester);

    expect(find.byKey(const Key('app-update-failed')), findsOneWidget);
    expect(find.byKey(const Key('app-update-retry')), findsOneWidget);
  });

  // --- downloading and installing --------------------------------------------

  testWidgets('nothing is downloaded before Android allows installing', (
    tester,
  ) async {
    final repository = _FakeRepository(release: _releaseJson());
    final installer = _FakeInstaller(canInstallResult: false);
    await _pump(tester, repository: repository, installer: installer);

    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();

    // 57 MB fetched only to be refused is a waste of someone's data.
    expect(repository.downloads, isEmpty);
    expect(
      find.byKey(const Key('app-update-needs-permission')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('app-update-open-settings')), findsOneWidget);
  });

  testWidgets('a download that does not match its digest is deleted', (
    tester,
  ) async {
    final installer = _FakeInstaller(digestMatches: false);
    await _pump(
      tester,
      repository: _FakeRepository(release: _releaseJson()),
      installer: installer,
    );

    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-update-failed')), findsOneWidget);
    expect(find.textContaining('повреждённым'), findsOneWidget);
    // Handing it over would only produce a refusal after another dialog.
    expect(installer.installed, isEmpty);
    expect(installer.downloadedFileExists, isFalse);
  });

  testWidgets('a verified download is handed to the system installer', (
    tester,
  ) async {
    final installer = _FakeInstaller();
    await _pump(
      tester,
      repository: _FakeRepository(release: _releaseJson()),
      installer: installer,
    );

    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();

    expect(installer.installed, hasLength(1));
    expect(find.byKey(const Key('app-update-handed-over')), findsOneWidget);
  });

  testWidgets('pressing again does not delete the package Android is reading', (
    tester,
  ) async {
    // Issue 0010. Android reads the handed-over file on its own schedule, for
    // 57 MB, while this app considers the hand-off finished. Someone who
    // cannot tell a slow download from a stalled one presses again — and the
    // download used to start by deleting the file under the open installer,
    // which Android then reports as «Приложение не установлено».
    final installer = _FakeInstaller();
    final repository = _FakeRepository(release: _releaseJson());
    await _pump(tester, repository: repository, installer: installer);

    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();
    final handed = installer.installed.single;
    expect(handed.existsSync(), isTrue);

    // Exactly what the owner did: checked again, was offered the same build,
    // and pressed download a second time.
    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();

    expect(handed.existsSync(), isTrue);
    expect(repository.downloads, hasLength(1));
    // Offered again rather than fetched again: the expensive half is done.
    expect(installer.installed, hasLength(2));
  });

  testWidgets('the handed-over state offers the installer again', (
    tester,
  ) async {
    final installer = _FakeInstaller();
    final repository = _FakeRepository(release: _releaseJson());
    await _pump(tester, repository: repository, installer: installer);

    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('app-update-open-installer')));
    await tester.pumpAndSettle();

    expect(installer.installed, hasLength(2));
    expect(repository.downloads, hasLength(1));
  });

  testWidgets('an installer that will not open is reported, not swallowed', (
    tester,
  ) async {
    final installer = _FakeInstaller(installFails: true);
    await _pump(
      tester,
      repository: _FakeRepository(release: _releaseJson()),
      installer: installer,
    );

    await _tapCheck(tester);
    await tester.tap(find.byKey(const Key('app-update-download')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-update-failed')), findsOneWidget);
    expect(find.byKey(const Key('app-update-retry')), findsOneWidget);
  });

  testWidgets('the section fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      repository: _FakeRepository(release: _releaseJson()),
      textScale: 2,
    );
    await _tapCheck(tester);

    expect(tester.takeException(), isNull);
  });

  // --- the weekly check (ADR 0026 amendment) --------------------------------

  test('a check is skipped while nobody is signed in', () async {
    final repository = _FakeRepository(release: _releaseJson());
    final schedule = _RecordingSchedule();
    final container = _container(
      repository: repository,
      schedule: schedule,
      signedIn: false,
    );
    addTearDown(container.dispose);

    await container.read(appUpdateControllerProvider.notifier).checkIfDue();

    expect(repository.checks, 0);
    expect(container.read(appUpdateControllerProvider), isA<AppUpdateIdle>());
  });

  test('a check inside the week is skipped', () async {
    final repository = _FakeRepository(release: _releaseJson());
    final schedule = _RecordingSchedule(
      last: _now.subtract(const Duration(days: 2)),
    );
    final container = _container(repository: repository, schedule: schedule);
    addTearDown(container.dispose);

    await container.read(appUpdateControllerProvider.notifier).checkIfDue();

    expect(repository.checks, 0);
  });

  test('a week later the check runs and reports what it found', () async {
    final repository = _FakeRepository(release: _releaseJson());
    final schedule = _RecordingSchedule(
      last: _now.subtract(const Duration(days: 8)),
    );
    final container = _container(repository: repository, schedule: schedule);
    addTearDown(container.dispose);

    await container.read(appUpdateControllerProvider.notifier).checkIfDue();

    expect(repository.checks, 1);
    expect(
      container.read(appUpdateControllerProvider),
      isA<AppUpdateAvailable>(),
    );
    expect(schedule.recorded, [_now]);
  });

  test('a quiet check that finds nothing says nothing', () async {
    // "Up to date" is an answer to a question nobody asked.
    final repository = _FakeRepository(release: null);
    final schedule = _RecordingSchedule(
      last: _now.subtract(const Duration(days: 8)),
    );
    final container = _container(repository: repository, schedule: schedule);
    addTearDown(container.dispose);

    await container.read(appUpdateControllerProvider.notifier).checkIfDue();

    expect(repository.checks, 1);
    expect(container.read(appUpdateControllerProvider), isA<AppUpdateIdle>());
  });

  test(
    'a failed quiet check is silent and does not consume the week',
    () async {
      final repository = _FakeRepository(
        checkFailure: FinanceEntryFailure(
          kind: FinanceEntryFailureKind.offline,
          requestId: 'req_synthetic_update',
        ),
      );
      final schedule = _RecordingSchedule(
        last: _now.subtract(const Duration(days: 8)),
      );
      final container = _container(repository: repository, schedule: schedule);
      addTearDown(container.dispose);

      await container.read(appUpdateControllerProvider.notifier).checkIfDue();

      // Nobody asked, so nobody is told; and a week offline must not eat the
      // week's check.
      expect(container.read(appUpdateControllerProvider), isA<AppUpdateIdle>());
      expect(schedule.recorded, isEmpty);
    },
  );

  test('a first run with no record checks immediately', () async {
    final repository = _FakeRepository(release: _releaseJson());
    final schedule = _RecordingSchedule();
    final container = _container(repository: repository, schedule: schedule);
    addTearDown(container.dispose);

    await container.read(appUpdateControllerProvider.notifier).checkIfDue();

    expect(repository.checks, 1);
  });
}

final _now = DateTime.utc(2026, 9, 1, 9);

ProviderContainer _container({
  required _FakeRepository repository,
  required _RecordingSchedule schedule,
  bool signedIn = true,
}) {
  return ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      appUpdateScheduleStoreProvider.overrideWithValue(schedule),
      appUpdateInstallerProvider.overrideWithValue(_FakeInstaller()),
      installedVersionCodeProvider.overrideWithValue(_installedCode),
      updateClockProvider.overrideWithValue(() => _now),
      authControllerProvider.overrideWith(
        () => signedIn ? _SignedInAuth() : _SignedOutAuth(),
      ),
    ],
  );
}

final class _SignedInAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn();
}

final class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedOut();
}

final class _RecordingSchedule implements AppUpdateScheduleStore {
  _RecordingSchedule({this.last});

  final DateTime? last;
  final List<DateTime> recorded = [];

  @override
  Future<DateTime?> lastCheckedAt() async => last;

  @override
  Future<void> recordCheckedAt(DateTime moment) async => recorded.add(moment);
}

Future<void> _tapCheck(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('profile-check-update')));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
  _FakeInstaller? installer,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        appUpdateInstallerProvider.overrideWithValue(
          installer ?? _FakeInstaller(),
        ),
        installedVersionCodeProvider.overrideWithValue(_installedCode),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: AppUpdateSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeInstaller implements AppUpdateInstaller {
  _FakeInstaller({
    this.canInstallResult = true,
    this.digestMatches = true,
    this.installFails = false,
  }) : _directory = Directory.systemTemp.createTempSync('mfa-update-test');

  final bool canInstallResult;
  final bool digestMatches;
  final bool installFails;
  final Directory _directory;
  final List<File> installed = [];
  File? _lastDownload;

  bool get downloadedFileExists => _lastDownload?.existsSync() ?? false;

  @override
  Future<bool> canInstall() async => canInstallResult;

  @override
  Future<bool> openPermissionSettings() async => true;

  @override
  Future<Directory> downloadDirectory() async => _directory;

  @override
  Future<bool> matchesDigest({
    required File file,
    required String sha256,
  }) async {
    _lastDownload = file;
    return digestMatches;
  }

  @override
  Future<void> install(File package) async {
    if (installFails) throw const AppUpdateInstallFailed();
    installed.add(package);
  }
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget(
    SetBudgetCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget(
    String budgetId,
    RemoveBudgetCommand command,
  ) => throw UnimplementedError();

  _FakeRepository({this.release, this.checkFailure});

  final Map<String, Object?>? release;
  final FinanceEntryFailure? checkFailure;
  final List<String> downloads = [];
  int checks = 0;

  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate() async {
    checks += 1;
    final failure = checkFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<AppUpdateManifest>(failure);
    }
    return FinanceEntrySuccess<AppUpdateManifest>(
      requestId: 'req_synthetic_update',
      value: AppUpdateManifest.fromJson(<String, Object?>{
        'schemaVersion': '1',
        'release': release,
      }),
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) async {
    downloads.add(savePath);
    File(savePath).writeAsBytesSync(const [1, 2, 3]);
    onProgress(3, 3);
    return const FinanceEntrySuccess<void>(
      requestId: 'req_synthetic_update',
      value: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
