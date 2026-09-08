import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/transfers/presentation/transfer_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _euro = '11111111-1111-4111-8111-111111111111';
const _hryvnia = '22222222-2222-4222-8222-222222222222';
const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  testWidgets('the rate follows from the two amounts as they are typed', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository());

    await tester.enterText(
      find.byKey(const Key('transfer-from-amount')),
      '100.00',
    );
    await tester.enterText(
      find.byKey(const Key('transfer-to-amount')),
      '4800.00',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer-rate')), findsOneWidget);
    expect(find.textContaining('1 EUR = 48.0000 UAH'), findsOneWidget);
    // And it says where the number came from, because it did not come from
    // the internet (ADR 0029).
    expect(find.textContaining('следует из двух сумм'), findsOneWidget);
  });

  testWidgets('no rate is shown before both amounts exist', (tester) async {
    await _pump(tester, repository: _FakeRepository());

    await tester.enterText(
      find.byKey(const Key('transfer-from-amount')),
      '100.00',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer-rate')), findsNothing);
  });

  testWidgets('a reviewed transfer is confirmed and reported', (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, repository: repository);

    await _fill(tester);
    await tester.tap(find.byKey(const Key('transfer-review')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('transfer-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer-accepted')), findsOneWidget);
    expect(repository.committed, hasLength(1));
    // Both amounts, as they were witnessed. Nothing is converted.
    expect(find.textContaining('100,00'), findsOneWidget);
    expect(find.textContaining('4 800,00'), findsOneWidget);
  });

  testWidgets('editing an amount takes the confirmation away', (tester) async {
    // A confirmation must never outlive the draft it was given for.
    await _pump(tester, repository: _FakeRepository());

    await _fill(tester);
    await tester.tap(find.byKey(const Key('transfer-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transfer-confirm')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('transfer-to-amount')),
      '4900.00',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('transfer-confirm')), findsNothing);
    expect(find.byKey(const Key('transfer-review')), findsOneWidget);
  });

  testWidgets('a refusal is explained in its own words', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        rejection: FinanceTransferIssueCode.futureOccurredDate,
      ),
    );

    await _fill(tester);
    await tester.tap(find.byKey(const Key('transfer-review')));
    await tester.pumpAndSettle();

    expect(find.textContaining('в будущем'), findsOneWidget);
    expect(find.byKey(const Key('transfer-confirm')), findsNothing);
  });

  testWidgets('one wallet is not enough to transfer between', (tester) async {
    await _pump(tester, repository: _FakeRepository(walletCount: 1));

    expect(
      find.byKey(const Key('transfer-second-wallet-required')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('transfer-form')), findsNothing);
  });
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('transfer-from-amount')),
    '100.00',
  );
  await tester.enterText(
    find.byKey(const Key('transfer-to-amount')),
    '4800.00',
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
}) async {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 9, 8, 12),
      ),
      financeCommandIdFactoryProvider.overrideWithValue(
        () => '33333333-3333-4333-8333-333333333333',
      ),
      financeCaptureContextSourceProvider.overrideWithValue(
        const _FixedCapture(),
      ),
      initialAppSettingsProvider.overrideWithValue(const AppSettings()),
      // A settled transfer refreshes Home. Here that read answers at once and
      // schedules nothing: this test is about the transfer, not about Home.
      homeRepositoryProvider.overrideWithValue(const _SilentHomeRepository()),
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
        home: const TransferPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FinanceAccount _wallet({
  required String id,
  required String currency,
  required String name,
  required bool isDefault,
}) => FinanceAccount(
  accountId: id,
  userId: '77777777-7777-4777-8777-777777777777',
  commandId: '88888888-8888-4888-8888-888888888888',
  name: name,
  currency: currency,
  openingBalance: '1000.00',
  openingBalanceOn: '2026-01-01',
  openingTimezone: 'Europe/Berlin',
  isDefault: isDefault,
  confirmedAt: '2026-01-01T10:00:00.000Z',
  createdAt: '2026-01-01T10:00:00.000Z',
);

final class _SilentHomeRepository implements HomeRepository {
  const _SilentHomeRepository();

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    return const HomeFailureResult(
      type: HomeFailureType.unknown,
      requestId: 'req_synthetic_home',
    );
  }
}

final class _FixedCapture implements FinanceCaptureContextSource {
  const _FixedCapture();

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': '2026-09-08T12:00:00.000Z',
    'osTimezone': canonicalTimezone,
    'osLocalDate': '2026-09-08',
    'canonicalTimezone': canonicalTimezone,
    'canonicalLocalDate': '2026-09-08',
  }, expectedCanonicalTimezone: canonicalTimezone);
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({this.walletCount = 2, this.rejection});

  final int walletCount;
  final FinanceTransferIssueCode? rejection;
  final List<FinanceTransferCommitCommand> committed = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic_transfer',
      value: FinanceAccountSetup(
        canonicalTimezone: 'Europe/Berlin',
        timezoneRevision: 1,
        accounts: [
          _wallet(
            id: _euro,
            currency: 'EUR',
            name: 'Основной',
            isDefault: true,
          ),
          if (walletCount > 1)
            _wallet(
              id: _hryvnia,
              currency: 'UAH',
              name: 'Гривна',
              isDefault: false,
            ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer(
    FinanceTransferDraft draft,
  ) async {
    final refusal = rejection;
    if (refusal != null) {
      return FinanceEntrySuccess<FinanceTransferEvaluation>(
        requestId: 'req_synthetic_transfer',
        value: FinanceTransferRejected(
          issues: [FinanceTransferIssue(code: refusal, field: 'occurredOn')],
        ),
      );
    }
    return FinanceEntrySuccess<FinanceTransferEvaluation>(
      requestId: 'req_synthetic_transfer',
      value: FinanceTransferNeedsConfirmation(draft: draft, draftHash: _hash),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer(
    FinanceTransferCommitCommand command,
  ) async {
    committed.add(command);
    return FinanceEntrySuccess<FinanceTransferCommitted>(
      requestId: 'req_synthetic_transfer',
      value: FinanceTransferCommitted(
        transferId: '44444444-4444-4444-8444-444444444444',
        idempotentReplay: false,
        fromAmount: command.draft.fromAmount,
        fromCurrency: command.draft.fromCurrency,
        toAmount: command.draft.toAmount,
        toCurrency: command.draft.toCurrency,
        occurredOn: command.draft.occurredOn,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
