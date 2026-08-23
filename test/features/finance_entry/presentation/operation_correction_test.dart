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
import 'package:mobile_finance_assistant/features/finance_entry/presentation/operation_history_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _operationId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _groceriesId = '33333333-3333-4333-8333-333333333333';
const _salaryId = '44444444-4444-4444-8444-444444444444';
const _commandId = '55555555-5555-4555-8555-555555555555';

/// Correcting one confirmed operation from the history (ADR 0023).
///
/// The original is never edited here: saving withdraws it and writes the
/// replacement, and removing withdraws it with nothing in its place.
void main() {
  testWidgets('the correction form opens filled with the operation', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _openCorrection(tester, repository);

    expect(find.byKey(const Key('correction-form')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('correction-amount')))
          .controller
          ?.text,
      '42.00',
    );
    // Its own category is the one already chosen, not a blank picker.
    expect(find.text('Продукты'), findsWidgets);
  });

  testWidgets('saving reviews the replacement and then corrects', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _openCorrection(tester, repository);

    await tester.enterText(find.byKey(const Key('correction-amount')), '12.50');
    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();

    // Reviewed exactly like a new operation before anything is written.
    expect(repository.evaluated, hasLength(1));
    expect(repository.evaluated.single.amount, '12.50');
    final correction = repository.corrections.single;
    expect(correction.targetOperationId, _operationId);
    expect(correction.review.draft.amount, '12.50');
    // The list it came from is stale the moment the ledger changes.
    expect(repository.listCalls, 2);
    expect(find.text('Операция исправлена'), findsOneWidget);
  });

  testWidgets('removing asks first and then withdraws', (tester) async {
    final repository = _FakeRepository();
    await _openCorrection(tester, repository);

    await tester.tap(find.byKey(const Key('correction-remove')));
    await tester.pumpAndSettle();
    // Nothing is withdrawn until the question is answered.
    expect(repository.removals, isEmpty);

    await tester.tap(find.byKey(const Key('confirm-remove-operation')));
    await tester.pumpAndSettle();

    expect(repository.removals.single.targetOperationId, _operationId);
    expect(repository.corrections, isEmpty);
    expect(find.text('Операция удалена'), findsOneWidget);
  });

  testWidgets('a refused replacement writes nothing and says why', (
    tester,
  ) async {
    final repository = _FakeRepository(rejectEvaluation: true);
    await _openCorrection(tester, repository);

    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();

    expect(repository.corrections, isEmpty);
    final message = tester.widget<Text>(
      find.byKey(const Key('correction-message')),
    );
    // A future date is its own sentence rather than a generic refusal.
    expect(message.data, contains('позже сегодняшнего'));
  });

  testWidgets('an operation corrected elsewhere reports itself', (
    tester,
  ) async {
    final repository = _FakeRepository(
      correctionFailure: FinanceEntryErrorCode.operationAlreadyReversed,
    );
    await _openCorrection(tester, repository);

    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();

    // Not the generic failure: the user has to know the list is stale.
    expect(find.textContaining('уже исправили'), findsOneWidget);
  });

  testWidgets('flipping the direction drops a category of the other one', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _openCorrection(tester, repository);

    await tester.tap(find.text('Доход'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('correction-save')));
    await tester.pumpAndSettle();

    // Keeping an expense category on an income would corrupt every later
    // breakdown, and the picker would assert on a value it does not hold.
    expect(tester.takeException(), isNull);
    expect(repository.corrections.single.review.draft.categoryId, isNull);
    expect(
      repository.corrections.single.review.draft.type,
      FinanceOperationType.income,
    );
  });
}

Future<void> _openCorrection(
  WidgetTester tester,
  _FakeRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 8, 22, 10),
        ),
        financeCommandIdFactoryProvider.overrideWithValue(() => _commandId),
        financeCaptureContextSourceProvider.overrideWithValue(
          const _FixedCapture(),
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
        home: OperationHistoryPage(onSignInRequested: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('history-row-$_operationId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('history-detail-correct')));
  await tester.pumpAndSettle();
}

final class _FixedCapture implements FinanceCaptureContextSource {
  const _FixedCapture();

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': '2026-08-22T10:00:00.000Z',
    'osTimezone': configuredHomeApiTimezone,
    'osLocalDate': '2026-08-22',
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': '2026-08-22',
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({this.rejectEvaluation = false, this.correctionFailure});

  final bool rejectEvaluation;
  final FinanceEntryErrorCode? correctionFailure;
  final List<FinanceOperationDraft> evaluated = [];
  final List<OperationCorrectionCommand> corrections = [];
  final List<OperationRemovalCommand> removals = [];
  int listCalls = 0;

  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) async {
    listCalls += 1;
    return FinanceEntrySuccess<OperationHistoryList>(
      requestId: 'req_synthetic',
      value: OperationHistoryList(
        operations: const [
          OperationHistoryItem(
            operationId: _operationId,
            type: FinanceOperationType.expense,
            amount: '42.00',
            currency: 'EUR',
            accountId: _accountId,
            category: 'Продукты',
            categoryId: _groceriesId,
            categoryText: 'Продукты',
            merchant: null,
            occurredOn: '2026-08-20',
            occurredAt: null,
            source: FinanceOperationSource.manualText,
            createdAt: '2026-08-20T12:00:00Z',
          ),
        ],
        nextCursor: null,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic',
      value: FinanceAccountSetup(
        canonicalTimezone: configuredHomeApiTimezone,
        timezoneRevision: 1,
        accounts: const [
          FinanceAccount(
            accountId: _accountId,
            userId: '66666666-6666-4666-8666-666666666666',
            commandId: '77777777-7777-4777-8777-777777777777',
            name: 'Основной счёт',
            currency: 'EUR',
            openingBalance: '1000.00',
            openingBalanceOn: '2026-07-01',
            openingTimezone: configuredHomeApiTimezone,
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
        categories: const [
          FinanceCategory(
            categoryId: _groceriesId,
            name: 'Продукты',
            direction: FinanceOperationType.expense,
            systemKey: 'groceries',
          ),
          FinanceCategory(
            categoryId: _salaryId,
            name: 'Зарплата',
            direction: FinanceOperationType.income,
            systemKey: 'salary',
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) async {
    evaluated.add(draft);
    if (rejectEvaluation) {
      return FinanceEntrySuccess<FinanceOperationEvaluation>(
        requestId: 'req_synthetic',
        value: FinanceOperationRejected(
          draft: draft,
          issues: const [
            FinanceIssue(
              code: FinanceIssueCode.futureOccurredDate,
              field: FinanceIssueField.occurredOn,
            ),
          ],
        ),
      );
    }
    return FinanceEntrySuccess<FinanceOperationEvaluation>(
      requestId: 'req_synthetic',
      value: FinanceOperationNeedsConfirmation(
        draft: draft,
        draftHash: 'a' * 64,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<OperationCorrected>> correctOperation(
    OperationCorrectionCommand command,
  ) async {
    final code = correctionFailure;
    if (code != null) {
      return FinanceEntryFailureResult<OperationCorrected>(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.conflict,
          requestId: 'req_synthetic',
          code: code,
        ),
      );
    }
    corrections.add(command);
    return FinanceEntrySuccess<OperationCorrected>(
      requestId: 'req_synthetic',
      value: OperationCorrected(
        idempotentReplay: false,
        reversal: _reversal(
          replacement: '88888888-8888-4888-8888-888888888888',
        ),
        operation: _committed(command.review.draft),
      ),
    );
  }

  @override
  Future<FinanceEntryResult<OperationRemoved>> removeOperation(
    OperationRemovalCommand command,
  ) async {
    removals.add(command);
    return FinanceEntrySuccess<OperationRemoved>(
      requestId: 'req_synthetic',
      value: OperationRemoved(
        idempotentReplay: false,
        reversal: _reversal(replacement: null),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

OperationReversal _reversal({required String? replacement}) {
  return OperationReversal(
    reversalId: '99999999-9999-4999-8999-999999999999',
    operationId: _operationId,
    replacementOperationId: replacement,
    commandId: _commandId,
    confirmedAt: '2026-08-22T10:00:00Z',
    createdAt: '2026-08-22T10:00:00Z',
  );
}

CommittedFinanceOperation _committed(FinanceOperationDraft draft) {
  return CommittedFinanceOperation(
    operationId: '88888888-8888-4888-8888-888888888888',
    userId: '66666666-6666-4666-8666-666666666666',
    commandId: draft.commandId,
    type: draft.type,
    amount: draft.amount,
    currency: draft.currency,
    accountId: draft.accountId,
    category: draft.category,
    categoryId: draft.categoryId,
    merchant: draft.merchant,
    capturedAt: draft.capturedAt,
    capturedTimezone: draft.capturedTimezone,
    sourceExpression: draft.sourceExpression,
    dateResolverVersion: draft.dateResolverVersion,
    occurredOn: draft.occurredOn,
    occurredAt: draft.occurredAt,
    source: draft.source,
    confirmedAt: '2026-08-22T10:00:00Z',
    createdAt: '2026-08-22T10:00:00Z',
  );
}
