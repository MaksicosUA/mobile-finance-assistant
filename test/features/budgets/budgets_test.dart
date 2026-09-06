import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/budgets/presentation/budgets_page.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _categoryId = '22222222-2222-4222-8222-222222222222';
const _budgetId = '33333333-3333-4333-8333-333333333333';
const _commandId = '44444444-4444-4444-8444-444444444444';

Map<String, Object?> _budgetJson({
  String budgetId = _budgetId,
  Object? categoryId = _categoryId,
  Object? name = 'Продукты',
  String limit = '400.00',
  String spent = '250.00',
  String remaining = '150.00',
  String planned = '100.00',
  bool overspent = false,
}) {
  return <String, Object?>{
    'budgetId': budgetId,
    'categoryId': categoryId,
    'name': name,
    'limit': limit,
    'spent': spent,
    'remaining': remaining,
    'planned': planned,
    'overspent': overspent,
  };
}

Map<String, Object?> _snapshotJson({
  Object? overall,
  List<Map<String, Object?>>? categories,
}) {
  return <String, Object?>{
    'schemaVersion': '1',
    'period': {'from': '2026-09-01', 'to': '2026-09-30'},
    'currency': 'EUR',
    'overall': overall,
    'categories': categories ?? [_budgetJson()],
  };
}

void main() {
  // --- the contract ----------------------------------------------------------

  test('a named ceiling must carry its category', () {
    expect(
      () => Budget.fromJson(_budgetJson(categoryId: null)),
      throwsFormatException,
    );
    expect(
      () => Budget.fromJson(_budgetJson(name: null)),
      throwsFormatException,
    );
  });

  test('the overall ceiling carries neither', () {
    final overall = Budget.fromJson(_budgetJson(categoryId: null, name: null));

    expect(overall.isOverall, isTrue);
  });

  test('going over is a negative remainder, not a floor at zero', () {
    final budget = Budget.fromJson(
      _budgetJson(spent: '500.00', remaining: '-100.00', overspent: true),
    );

    expect(budget.remaining, '-100.00');
    expect(budget.overspent, isTrue);
  });

  test('a ceiling of zero is not a ceiling', () {
    expect(
      () => Budget.fromJson(_budgetJson(limit: '0')),
      throwsFormatException,
    );
  });

  test('an unknown key is refused rather than ignored', () {
    expect(
      () => Budget.fromJson({..._budgetJson(), 'rollover': true}),
      throwsFormatException,
    );
  });

  // --- the screen ------------------------------------------------------------

  testWidgets('no ceilings says so and offers to set one', (tester) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        snapshot: _snapshotJson(categories: const []),
      ),
    );

    expect(find.byKey(const Key('budgets-empty')), findsOneWidget);
    expect(find.byKey(const Key('budgets-add')), findsOneWidget);
  });

  testWidgets('a ceiling reports what is left, and the plan separately', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeRepository(snapshot: _snapshotJson()));

    // 400 limit, 250 spent, 100 planned leaves 150 — not 50. The plan is a
    // forecast and never enters the number that states fact.
    expect(find.textContaining('150,00'), findsOneWidget);
    expect(find.byKey(const Key('budget-planned-$_budgetId')), findsOneWidget);
    expect(find.textContaining('100,00'), findsOneWidget);
  });

  testWidgets('going over is said in words, not only in colour', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        snapshot: _snapshotJson(
          categories: [
            _budgetJson(spent: '500.00', remaining: '-100.00', overspent: true),
          ],
        ),
      ),
    );

    expect(find.textContaining('Перерасход'), findsOneWidget);
  });

  testWidgets('privacy mode masks a ceiling like every other amount', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(snapshot: _snapshotJson()),
      privacy: true,
    );

    expect(find.textContaining('400'), findsNothing);
    expect(find.textContaining('••••'), findsWidgets);
  });

  testWidgets('the overall ceiling is shown beside the category ones', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        snapshot: _snapshotJson(
          overall: _budgetJson(
            budgetId: '55555555-5555-4555-8555-555555555555',
            categoryId: null,
            name: null,
            limit: '2000.00',
            spent: '900.00',
            remaining: '1100.00',
            planned: '0',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('budget-overall')), findsOneWidget);
    expect(find.byKey(const Key('budget-$_budgetId')), findsOneWidget);
  });

  testWidgets('setting a ceiling sends the limit and nothing derived', (
    tester,
  ) async {
    final repository = _FakeRepository(
      snapshot: _snapshotJson(categories: const []),
    );
    await _pump(tester, repository: repository);

    await tester.tap(find.byKey(const Key('budgets-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('budget-editor-limit')),
      '400,50',
    );
    await tester.tap(find.byKey(const Key('budget-editor-save')));
    await tester.pumpAndSettle();

    expect(repository.written, hasLength(1));
    // A comma is what a Russian keyboard offers; the wire takes a decimal
    // point, and the client never sends a spent or a remainder.
    expect(repository.written.single.limit, '400.50');
    expect(repository.written.single.toJson().keys, isNot(contains('spent')));
  });

  testWidgets('removing a ceiling asks first', (tester) async {
    final repository = _FakeRepository(snapshot: _snapshotJson());
    await _pump(tester, repository: repository);

    await tester.tap(find.byKey(const Key('budget-remove-$_budgetId')));
    await tester.pumpAndSettle();
    expect(repository.removed, isEmpty);

    await tester.tap(find.byKey(const Key('confirm-remove-budget')));
    await tester.pumpAndSettle();

    expect(repository.removed, [_budgetId]);
  });

  testWidgets('a failed read offers a pull rather than a blank page', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        readFailure: FinanceEntryFailure(
          kind: FinanceEntryFailureKind.serviceUnavailable,
          requestId: 'req_synthetic_budget',
        ),
      ),
    );

    expect(find.byKey(const Key('budgets-failure')), findsOneWidget);
  });

  testWidgets('the screen fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      repository: _FakeRepository(snapshot: _snapshotJson()),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
  bool privacy = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        financeCommandIdFactoryProvider.overrideWithValue(() => _commandId),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 1, 12),
        ),
        initialAppSettingsProvider.overrideWithValue(
          AppSettings(privacyMode: privacy),
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: BudgetsPage(onSignInRequested: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({this.snapshot, this.readFailure});

  final Map<String, Object?>? snapshot;
  final FinanceEntryFailure? readFailure;
  final List<SetBudgetCommand> written = [];
  final List<String> removed = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic_budget',
      value: FinanceAccountSetup(
        canonicalTimezone: 'Europe/Berlin',
        timezoneRevision: 1,
        accounts: [
          FinanceAccount(
            accountId: _accountId,
            userId: '77777777-7777-4777-8777-777777777777',
            commandId: '88888888-8888-4888-8888-888888888888',
            name: 'Основной',
            currency: 'EUR',
            openingBalance: '1000.00',
            openingBalanceOn: '2026-01-01',
            openingTimezone: 'Europe/Berlin',
            isDefault: true,
            confirmedAt: '2026-01-01T10:00:00.000Z',
            createdAt: '2026-01-01T10:00:00.000Z',
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories() async {
    return FinanceEntrySuccess<FinanceCategoryList>(
      requestId: 'req_synthetic_budget',
      value: FinanceCategoryList(
        categories: const [
          FinanceCategory(
            categoryId: '66666666-6666-4666-8666-666666666666',
            name: 'Транспорт',
            direction: FinanceOperationType.expense,
            systemKey: null,
          ),
        ],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets() async {
    final failure = readFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<BudgetsSnapshot>(failure);
    }
    return FinanceEntrySuccess<BudgetsSnapshot>(
      requestId: 'req_synthetic_budget',
      value: BudgetsSnapshot.fromJson(snapshot!),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget(
    SetBudgetCommand command,
  ) async {
    written.add(command);
    return FinanceEntrySuccess<BudgetWritten>(
      requestId: 'req_synthetic_budget',
      value: BudgetWritten(budgetId: _budgetId, categoryId: command.categoryId),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget(
    String budgetId,
    RemoveBudgetCommand command,
  ) async {
    removed.add(budgetId);
    return FinanceEntrySuccess<BudgetWritten>(
      requestId: 'req_synthetic_budget',
      value: BudgetWritten(budgetId: budgetId),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
