import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/finance_entry_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _groceriesId = '44444444-4444-4444-8444-444444444444';

/// Entering an operation by writing a sentence (ADR 0022).
///
/// The sentence fills the form. It never records anything: the confirmation
/// below is still what writes the operation.
void main() {
  testWidgets('a sentence fills the form and does not record anything', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 12,50 на продукты вчера',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('operation-amount')))
          .controller
          ?.text,
      '12.50',
    );
    expect(find.textContaining('Продукты'), findsWidgets);
    // Nothing was evaluated or committed: reading a sentence is not a write.
    expect(repository.evaluated, 0);
    expect(repository.parsed, hasLength(1));
  });

  testWidgets('the capture pair travels so the day is the user own', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 10 сегодня',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    // The phone is in Los Angeles and the account reports in Berlin; the
    // server resolves the day from these two, never from server wall clock.
    final call = repository.parsed.single;
    expect(call.capturedAt, '2026-07-29T10:00:00.000Z');
    expect(call.capturedTimezone, 'America/Los_Angeles');
  });

  testWidgets('a gap names the field the parser refused to guess', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(
        amount: null,
        gaps: const [OperationParseGap.amountNotFound],
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Купил продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('operation-sentence-result')), findsOneWidget);
    expect(find.textContaining('Сумму не нашёл'), findsOneWidget);
  });

  testWidgets('a missing amount does not erase what the user already typed', (
    tester,
  ) async {
    final repository = _FakeRepository(
      proposal: _proposal(
        amount: null,
        gaps: const [OperationParseGap.amountNotFound],
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(find.byKey(const Key('operation-amount')), '99.00');
    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Купил продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('operation-amount')))
          .controller
          ?.text,
      '99.00',
    );
  });

  testWidgets('a failed parse says so and leaves the form usable', (
    tester,
  ) async {
    final repository = _FakeRepository(
      failure: FinanceEntryFailureKind.serviceUnavailable,
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('operation-sentence')),
      'Потратил 12 на продукты',
    );
    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('operation-sentence-error')), findsOneWidget);
    // The structured form is untouched, so a broken parser never blocks
    // recording money.
    expect(find.byKey(const Key('operation-amount')), findsOneWidget);
    expect(find.byKey(const Key('operation-evaluate')), findsOneWidget);
  });

  testWidgets('an empty sentence is refused without a request', (tester) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.tap(find.byKey(const Key('operation-sentence-parse')));
    await tester.pumpAndSettle();

    expect(repository.parsed, isEmpty);
    expect(find.byKey(const Key('operation-sentence-error')), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
        financeEntryRepositoryProvider.overrideWithValue(repository),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 7, 29, 10),
        ),
        financeCaptureContextSourceProvider.overrideWithValue(
          const _FixedCapture(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        home: Scaffold(
          body: FinanceEntryPage(
            onBackHome: _ignore,
            onSignInRequested: _ignore,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _ignore() {}

OperationProposal _proposal({
  String? amount = '12.50',
  List<OperationParseGap> gaps = const [],
}) {
  return OperationProposal(
    type: FinanceOperationType.expense,
    amount: amount,
    currency: 'EUR',
    occurredOn: '2026-07-28',
    sourceExpression: 'вчера',
    categoryId: _groceriesId,
    category: 'продукты',
    gaps: gaps,
  );
}

final class _FixedCapture implements FinanceCaptureContextSource {
  const _FixedCapture();

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': '2026-07-29T10:00:00.000Z',
    'osTimezone': 'America/Los_Angeles',
    'osLocalDate': '2026-07-29',
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': '2026-07-29',
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({OperationProposal? proposal, this.failure})
    : proposal = proposal ?? _proposal();

  final OperationProposal proposal;
  final FinanceEntryFailureKind? failure;
  final List<({String text, String capturedAt, String capturedTimezone})>
  parsed = [];
  int evaluated = 0;

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic',
      value: FinanceAccountSetup(
        canonicalTimezone: 'Europe/Berlin',
        timezoneRevision: 1,
        accounts: const [
          FinanceAccount(
            accountId: '11111111-1111-4111-8111-111111111111',
            userId: '22222222-2222-4222-8222-222222222222',
            commandId: '33333333-3333-4333-8333-333333333333',
            name: 'Основной счёт',
            currency: 'EUR',
            openingBalance: '100.00',
            openingBalanceOn: '2026-07-01',
            openingTimezone: 'Europe/Berlin',
            confirmedAt: '2026-07-01T08:00:00Z',
            createdAt: '2026-07-01T08:00:00Z',
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories() async {
    return FinanceEntrySuccess<FinanceCategoryList>(
      requestId: 'req_synthetic',
      value: FinanceCategoryList(
        categories: [
          const FinanceCategory(
            categoryId: _groceriesId,
            name: 'Продукты',
            direction: FinanceOperationType.expense,
            systemKey: null,
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) async {
    parsed.add((
      text: text,
      capturedAt: capturedAt,
      capturedTimezone: capturedTimezone,
    ));
    final kind = failure;
    if (kind != null) {
      return FinanceEntryFailureResult<OperationProposal>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic'),
      );
    }
    return FinanceEntrySuccess<OperationProposal>(
      requestId: 'req_synthetic',
      value: proposal,
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) async {
    evaluated += 1;
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
