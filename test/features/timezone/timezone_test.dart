import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/canonical_timezone.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/timezone/domain/timezone_options.dart';
import 'package:mobile_finance_assistant/features/timezone/presentation/timezone_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';

void main() {
  // --- the catalogue ---------------------------------------------------------

  test('a zone is found by its city or its identifier, in either case', () {
    const kyiv = TimezoneOption('Europe/Kyiv', 'Киев');

    expect(kyiv.matches('киев'), isTrue);
    expect(kyiv.matches('KYIV'), isTrue);
    expect(kyiv.matches('europe/k'), isTrue);
    expect(kyiv.matches('  '), isTrue);
    expect(kyiv.matches('Лиссабон'), isFalse);
  });

  test('every offered zone is one the server would accept', () {
    for (final option in timezoneOptions) {
      expect(isUsableTimezoneName(option.id), isTrue, reason: option.id);
      expect(option.label, isNotEmpty);
    }
    final ids = timezoneOptions.map((option) => option.id).toSet();
    expect(ids.length, timezoneOptions.length);
  });

  // --- the contract ----------------------------------------------------------

  test('a correction names the account, the zone and the moment', () {
    final command = FinanceTimezoneCommand(
      commandId: '22222222-2222-4222-8222-222222222222',
      accountId: _accountId,
      canonicalTimezone: 'Europe/Kyiv',
      requestedAt: DateTime.utc(2026, 9, 2, 10, 30),
    );

    expect(command.toJson(), {
      'schemaVersion': '1',
      'commandId': '22222222-2222-4222-8222-222222222222',
      'accountId': _accountId,
      'canonicalTimezone': 'Europe/Kyiv',
      'requestedAt': '2026-09-02T10:30:00.000Z',
    });
  });

  test('an unusable zone never reaches the wire', () {
    for (final unusable in const ['', ' ', 'Factory', 'localtime']) {
      expect(
        () => FinanceTimezoneCommand(
          commandId: '22222222-2222-4222-8222-222222222222',
          accountId: _accountId,
          canonicalTimezone: unusable,
          requestedAt: DateTime.utc(2026, 9, 2),
        ),
        throwsFormatException,
        reason: unusable,
      );
    }
  });

  test('a settled correction reports at least the first revision', () {
    final settled = FinanceTimezoneCorrected.fromJson(const {
      'schemaVersion': '1',
      'idempotentReplay': false,
      'accountId': _accountId,
      'canonicalTimezone': 'Europe/Kyiv',
      'timezoneRevision': 2,
    });

    expect(settled.timezoneRevision, 2);
    expect(settled.canonicalTimezone, 'Europe/Kyiv');
    expect(
      () => FinanceTimezoneCorrected.fromJson(const {
        'schemaVersion': '1',
        'idempotentReplay': false,
        'accountId': _accountId,
        'canonicalTimezone': 'Europe/Kyiv',
        'timezoneRevision': 0,
      }),
      throwsFormatException,
    );
  });

  test('a refusal names the field it is about', () {
    expect(
      FinanceTimezoneIssue.fromJson(const {
        'code': 'TIMEZONE_UNCHANGED',
        'field': 'canonicalTimezone',
      }).code,
      FinanceTimezoneIssueCode.timezoneUnchanged,
    );
    expect(
      () => FinanceTimezoneIssue.fromJson(const {
        'code': 'TIMEZONE_UNCHANGED',
        'field': 'openingBalanceOn',
      }),
      throwsFormatException,
    );
  });

  // --- the screen ------------------------------------------------------------

  testWidgets('the zone in force is named and cannot be re-picked', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository());

    expect(find.byKey(const Key('timezone-current')), findsOneWidget);
    expect(find.textContaining('Europe/Berlin'), findsWidgets);

    final finder = find.byKey(const Key('timezone-option-Europe/Berlin'));
    await tester.scrollUntilVisible(finder, 120, scrollable: _listScrollable());
    expect(tester.widget<ListTile>(finder).enabled, isFalse);
  });

  testWidgets('the phone’s own zone is offered first', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepository(),
      deviceTimezone: 'Europe/Kyiv',
    );

    expect(find.text('ПОЯС ТЕЛЕФОНА'), findsOneWidget);
    final first = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(first.key, const Key('timezone-option-Europe/Kyiv'));
  });

  testWidgets('search narrows the list', (tester) async {
    await _pump(tester, repository: _FakeRepository());

    await tester.enterText(find.byKey(const Key('timezone-search')), 'Киев');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('timezone-option-Europe/Kyiv')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('timezone-option-Europe/Rome')), findsNothing);
  });

  testWidgets('nothing is sent until it is confirmed', (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, repository: repository);

    await _tapZone(tester, 'Europe/Kyiv');
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(repository.corrections, isEmpty);
  });

  testWidgets('a confirmed correction is sent and adopted', (tester) async {
    final repository = _FakeRepository();
    final container = await _pump(tester, repository: repository);

    await _tapZone(tester, 'Europe/Kyiv');
    await tester.tap(find.byKey(const Key('timezone-confirm')));
    await tester.pumpAndSettle();

    expect(repository.corrections.single.canonicalTimezone, 'Europe/Kyiv');
    // The client follows the account, not the compile-time default.
    expect(container.read(canonicalTimezoneProvider), 'Europe/Kyiv');
    expect(find.textContaining('Киев'), findsWidgets);
  });

  testWidgets('a refusal is explained in its own words', (tester) async {
    final repository = _FakeRepository(
      rejection: FinanceTimezoneIssueCode.timezoneBehindRecordedOperations,
    );
    final container = await _pump(tester, repository: repository);

    await _tapZone(tester, 'Europe/Lisbon');
    await tester.tap(find.byKey(const Key('timezone-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('пропала бы из баланса'), findsOneWidget);
    // Nothing moved, so nothing is adopted.
    expect(container.read(canonicalTimezoneProvider), 'Europe/Berlin');
  });

  testWidgets('a failed load offers a retry rather than an empty list', (
    tester,
  ) async {
    final repository = _FakeRepository(
      loadFailure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.serviceUnavailable,
        requestId: 'req_synthetic_timezone',
      ),
    );
    await _pump(tester, repository: repository);

    expect(find.byKey(const Key('timezone-load-error')), findsOneWidget);
  });

  testWidgets('a user without an account is told so, not shown a picker', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository(hasAccount: false));

    expect(find.byKey(const Key('timezone-account-required')), findsOneWidget);
    expect(find.byKey(const Key('timezone-list')), findsNothing);
  });

  testWidgets('the list survives 200 percent text', (tester) async {
    await _pump(tester, repository: _FakeRepository(), textScale: 2);

    expect(tester.takeException(), isNull);
  });
}

Future<void> _tapZone(WidgetTester tester, String id) async {
  final finder = find.byKey(Key('timezone-option-$id'));
  await tester.scrollUntilVisible(finder, 120, scrollable: _listScrollable());
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _listScrollable() => find.descendant(
  of: find.byKey(const Key('timezone-list')),
  matching: find.byType(Scrollable),
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
  String? deviceTimezone,
  double textScale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 9, 2, 10, 30),
      ),
      financeCaptureContextSourceProvider.overrideWithValue(
        _FakeCaptureSource(deviceTimezone),
      ),
      initialAppSettingsProvider.overrideWithValue(const AppSettings()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(AppAccent.teal),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: const TimezonePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

final class _FakeCaptureSource implements FinanceCaptureContextSource {
  const _FakeCaptureSource(this.deviceTimezone);

  final String? deviceTimezone;

  @override
  Future<FinanceCaptureContext> capture({required String canonicalTimezone}) {
    final zone = deviceTimezone;
    if (zone == null) {
      // What a desktop test host does, and what the controller must survive.
      return Future.error(
        UnsupportedError('Finance capture context is unavailable.'),
      );
    }
    return Future.value(
      FinanceCaptureContext.fromPlatformValue({
        'capturedAtUtc': '2026-09-02T10:30:00Z',
        'osTimezone': zone,
        'osLocalDate': '2026-09-02',
        'canonicalTimezone': canonicalTimezone,
        'canonicalLocalDate': '2026-09-02',
      }, expectedCanonicalTimezone: canonicalTimezone),
    );
  }
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({this.hasAccount = true, this.loadFailure, this.rejection});

  final bool hasAccount;
  final FinanceEntryFailure? loadFailure;
  final FinanceTimezoneIssueCode? rejection;
  static const canonicalTimezone = 'Europe/Berlin';
  final List<FinanceTimezoneCommand> corrections = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    final failure = loadFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<FinanceAccountSetup>(failure);
    }
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic_timezone',
      value: FinanceAccountSetup(
        canonicalTimezone: hasAccount ? canonicalTimezone : null,
        timezoneRevision: hasAccount ? 1 : 0,
        accounts: [
          if (hasAccount)
            FinanceAccount(
              accountId: _accountId,
              userId: '77777777-7777-4777-8777-777777777777',
              commandId: '88888888-8888-4888-8888-888888888888',
              name: 'Основной',
              currency: 'EUR',
              openingBalance: '1000.00',
              openingBalanceOn: '2026-01-01',
              openingTimezone: canonicalTimezone,
              isDefault: true,
              confirmedAt: '2026-01-01T10:00:00.000Z',
              createdAt: '2026-01-01T10:00:00.000Z',
            ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone(
    FinanceTimezoneCommand command,
  ) async {
    corrections.add(command);
    final refusal = rejection;
    if (refusal != null) {
      return FinanceEntryFailureResult<FinanceTimezoneCorrected>(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.rejected,
          requestId: 'req_synthetic_timezone',
          code: FinanceEntryErrorCode.timezoneRejected,
          timezoneIssues: [FinanceTimezoneIssue(code: refusal)],
        ),
      );
    }
    return FinanceEntrySuccess<FinanceTimezoneCorrected>(
      requestId: 'req_synthetic_timezone',
      value: FinanceTimezoneCorrected(
        accountId: command.accountId,
        canonicalTimezone: command.canonicalTimezone,
        timezoneRevision: 2,
        idempotentReplay: false,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
