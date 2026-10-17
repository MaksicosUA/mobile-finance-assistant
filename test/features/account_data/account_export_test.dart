import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/platform/file_share.dart';
import 'package:mobile_finance_assistant/features/account_data/application/account_export_controller.dart';
import 'package:mobile_finance_assistant/features/account_data/presentation/account_data_section.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// Taking one's own record out of the app (ADR 0030).
void main() {
  test('both files are written and handed to the share sheet', () async {
    final share = _FakeShare();
    final repository = _FakeRepository();
    final container = _container(repository: repository, share: share);
    addTearDown(container.dispose);

    await container
        .read(accountExportControllerProvider.notifier)
        .exportAndShare();

    expect(
      container.read(accountExportControllerProvider),
      isA<AccountExportShared>(),
    );
    expect(share.freshened, 1, reason: 'an earlier copy must not linger');
    expect(share.shared.map((file) => file.uri.pathSegments.last), [
      'finance-export-2026-10-16.json',
      'operations-2026-10-16.csv',
    ]);
    expect(share.shared.every((file) => file.existsSync()), isTrue);
  });

  test('a failed second file leaves nothing half-exported behind', () async {
    // Half an export reads as a complete one, which is worse than none.
    final share = _FakeShare();
    final container = _container(
      repository: _FakeRepository(
        tableFailure: FinanceEntryFailureKind.serviceUnavailable,
      ),
      share: share,
    );
    addTearDown(container.dispose);

    await container
        .read(accountExportControllerProvider.notifier)
        .exportAndShare();

    final state = container.read(accountExportControllerProvider);
    expect(state, isA<AccountExportFailed>());
    expect(
      (state as AccountExportFailed).reason,
      AccountExportFailure.unavailable,
    );
    expect(share.shared, isEmpty);
    expect(share.cleared, 1);
  });

  test('no connection is reported as such, and nothing is shared', () async {
    final share = _FakeShare();
    final container = _container(
      repository: _FakeRepository(
        recordFailure: FinanceEntryFailureKind.offline,
      ),
      share: share,
    );
    addTearDown(container.dispose);

    await container
        .read(accountExportControllerProvider.notifier)
        .exportAndShare();

    expect(
      (container.read(accountExportControllerProvider) as AccountExportFailed)
          .reason,
      AccountExportFailure.unreachable,
    );
    expect(share.shared, isEmpty);
  });

  test('an ended session asks for a sign-in rather than a retry', () async {
    final container = _container(
      repository: _FakeRepository(
        recordFailure: FinanceEntryFailureKind.unauthenticated,
      ),
      share: _FakeShare(),
    );
    addTearDown(container.dispose);

    await container
        .read(accountExportControllerProvider.notifier)
        .exportAndShare();

    expect(
      (container.read(accountExportControllerProvider) as AccountExportFailed)
          .reason,
      AccountExportFailure.authenticationRequired,
    );
  });

  test('a share sheet that will not open is reported, not swallowed', () async {
    final container = _container(
      repository: _FakeRepository(),
      share: _FakeShare(shareFails: true),
    );
    addTearDown(container.dispose);

    await container
        .read(accountExportControllerProvider.notifier)
        .exportAndShare();

    expect(
      (container.read(accountExportControllerProvider) as AccountExportFailed)
          .reason,
      AccountExportFailure.shareUnavailable,
    );
  });

  testWidgets('Profile offers the export and says when it failed', (
    tester,
  ) async {
    final share = _FakeShare();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppSettingsProvider.overrideWithValue(const AppSettings()),
          financeEntryRepositoryProvider.overrideWithValue(
            _FakeRepository(recordFailure: FinanceEntryFailureKind.offline),
          ),
          fileShareProvider.overrideWithValue(share),
          financeEntryClockProvider.overrideWithValue(
            () => DateTime(2026, 10, 16, 12),
          ),
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
          home: const Scaffold(body: AccountDataSection()),
        ),
      ),
    );

    expect(find.text('Выгрузить мои данные'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-export-data')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Не удалось связаться с сервером'),
      findsOneWidget,
    );
    expect(share.shared, isEmpty);
  });
}

ProviderContainer _container({
  required _FakeRepository repository,
  required _FakeShare share,
}) {
  return ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      fileShareProvider.overrideWithValue(share),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime(2026, 10, 16, 12),
      ),
    ],
  );
}

final class _FakeShare implements FileShare {
  _FakeShare({this.shareFails = false})
    : _root = Directory.systemTemp.createTempSync('mfa-export-test');

  final bool shareFails;
  final Directory _root;
  final List<File> shared = [];
  int freshened = 0;
  int cleared = 0;

  Directory get _exports => Directory('${_root.path}/exports');

  @override
  Future<Directory> freshExportDirectory() async {
    freshened += 1;
    if (_exports.existsSync()) _exports.deleteSync(recursive: true);
    _exports.createSync(recursive: true);
    return _exports;
  }

  @override
  Future<void> clearExports() async {
    cleared += 1;
    if (_exports.existsSync()) _exports.deleteSync(recursive: true);
  }

  @override
  Future<void> share(List<File> files) async {
    if (shareFails) throw const FileShareFailed();
    shared.addAll(files);
  }
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({this.recordFailure, this.tableFailure});

  final FinanceEntryFailureKind? recordFailure;
  final FinanceEntryFailureKind? tableFailure;

  Future<FinanceEntryResult<void>> _write(
    String savePath,
    FinanceEntryFailureKind? failure,
    String body,
  ) async {
    if (failure != null) {
      return FinanceEntryFailureResult<void>(
        FinanceEntryFailure(kind: failure, requestId: 'req_synthetic'),
      );
    }
    File(savePath).writeAsStringSync(body);
    return const FinanceEntrySuccess<void>(
      requestId: 'req_synthetic',
      value: null,
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String savePath,
  }) => _write(savePath, recordFailure, '{"schemaVersion":"1"}');

  @override
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String savePath,
  }) => _write(savePath, tableFailure, '﻿date;type\r\n');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
