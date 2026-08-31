import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/analytics_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _groceriesId = '11111111-1111-4111-8111-111111111111';
const _carId = '22222222-2222-4222-8222-222222222222';
const _salaryId = '33333333-3333-4333-8333-333333333333';
const _operationId = '44444444-4444-4444-8444-444444444444';

/// The analysed window: totals beside the window before it, the balance line,
/// and the categories side by side.
void main() {
  testWidgets('both directions are reported, each beside what it was', (
    tester,
  ) async {
    await _pump(tester, _FakeRepository());

    expect(find.text('1 500,00 €'), findsWidgets);
    expect(find.text('542,00 €'), findsWidgets);
    // The comparison is the reason a period can be chosen at all.
    expect(find.textContaining('было'), findsWidgets);
  });

  testWidgets('the balance runs from one control point to the other', (
    tester,
  ) async {
    await _pump(tester, _FakeRepository());

    expect(find.byKey(const Key('analytics-balance')), findsOneWidget);
    expect(find.textContaining('30 000,00 €'), findsWidgets);
    expect(find.textContaining('32 200,00 €'), findsWidgets);
  });

  testWidgets('a category that stopped is still listed with its old amount', (
    tester,
  ) async {
    await _pump(tester, _FakeRepository());

    await tester.scrollUntilVisible(
      find.byKey(const Key('analytics-change-$_carId')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // Dropping it would hide exactly the change worth seeing.
    expect(find.text('Автомобиль'), findsOneWidget);
    expect(find.textContaining('было 80,00 €'), findsWidgets);
  });

  testWidgets('choosing another period asks for that window', (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, repository);

    // Four chips do not fit 390 dp, so the last one has to be brought into
    // view before it can be tapped at all.
    final year = find.byKey(const Key('analytics-period-year'));
    await tester.ensureVisible(year);
    await tester.pumpAndSettle();
    await tester.tap(year);
    await tester.pumpAndSettle();

    expect(repository.asked, [
      AnalyticsPeriodKind.month,
      AnalyticsPeriodKind.year,
    ]);
  });

  testWidgets('a window without spending says so instead of drawing nothing', (
    tester,
  ) async {
    await _pump(tester, _FakeRepository(empty: true));

    // Seven zero points are not an empty list, so the chart used to render a
    // blank box that read as a broken screen.
    expect(find.byKey(const Key('analytics-no-spending')), findsOneWidget);
  });

  testWidgets('privacy mode masks every amount on the screen', (tester) async {
    await _pump(tester, _FakeRepository(), privacy: true);

    expect(find.textContaining('1 500'), findsNothing);
    expect(find.textContaining('32 200'), findsNothing);
    expect(find.text('•••••• €'), findsWidgets);
  });

  testWidgets('the window result reads under the chart, above the categories', (
    tester,
  ) async {
    await _pump(tester, _FakeRepository());

    final change = find.byKey(const Key('analytics-balance-change'));
    expect(change, findsOneWidget);
    expect(find.text('за период +2 200,00 €'), findsOneWidget);
    // Under the line that draws it and above the table that explains it.
    expect(
      tester.getTopLeft(change).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('spending-chart-canvas'))).dy,
      ),
    );
    expect(
      tester.getTopLeft(change).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('analytics-expense-changes')))
            .dy,
      ),
    );
  });

  testWidgets('a pull re-reads the same window', (tester) async {
    final repository = _FakeRepository();
    await _pump(tester, repository);

    await tester.fling(
      find.byKey(const Key('analytics-page')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.asked, [
      AnalyticsPeriodKind.month,
      AnalyticsPeriodKind.month,
    ]);
  });

  testWidgets('a failed pull keeps the figures and says so', (tester) async {
    await _pump(tester, _FakeRepository(failRefresh: true));

    await tester.fling(
      find.byKey(const Key('analytics-page')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    // Replacing a readable month with an error page because one read timed
    // out is exactly what a refresh must not do.
    expect(find.byKey(const Key('analytics-failure')), findsNothing);
    expect(find.textContaining('32 200,00 €'), findsWidgets);
    // Which leaves being told as the only way to learn it failed.
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('an arbitrary window is asked for with both of its bounds', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pump(tester, repository);

    final custom = find.byKey(const Key('analytics-period-custom'));
    await tester.ensureVisible(custom);
    await tester.pumpAndSettle();
    await tester.tap(custom);
    await tester.pumpAndSettle();

    // The picker opens on the last 30 days rather than on nothing.
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(repository.asked.last, AnalyticsPeriodKind.custom);
    // A window without both bounds is not a window, and the server refuses it
    // as a bad request rather than guessing.
    expect(repository.customBounds.last.from, isNotNull);
    expect(repository.customBounds.last.to, isNotNull);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    await _pump(
      tester,
      _FakeRepository(failure: FinanceEntryFailureKind.timeout),
    );

    expect(find.byKey(const Key('analytics-failure')), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRepository repository, {
  bool privacy = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
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
        home: Scaffold(
          body: AnalyticsPage(
            onSignInRequested: () async {},
            onOpenAllOperations: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AnalyticsWindow _window({bool empty = false}) => AnalyticsWindow(
  kind: AnalyticsPeriodKind.month,
  periodStart: '2026-08-01',
  periodEnd: '2026-08-31',
  previousStart: '2026-07-01',
  previousEnd: '2026-07-31',
  baseCurrency: 'EUR',
  income: empty ? '0' : '1500.00',
  expense: empty ? '0' : '542.00',
  netFlow: empty ? '0' : '958.00',
  previousIncome: '1200.00',
  previousExpense: '620.00',
  previousNetFlow: '580.00',
  balance: AnalyticsBalanceLine(
    bucket: AnalyticsBucket.day,
    opening: '30000.00',
    closing: '32200.00',
    change: '2200.00',
    points: [
      for (var day = 1; day <= 7; day++)
        AnalyticsTrendPoint(
          date: '2026-08-${day.toString().padLeft(2, '0')}',
          amount: day == 7 ? '32200.00' : '30000.00',
        ),
    ],
  ),
  expenseChanges: empty
      ? const []
      : const [
          AnalyticsCategoryChange(
            categoryId: _groceriesId,
            name: 'Продукты',
            amount: '542.00',
            previousAmount: '540.00',
          ),
          // Spent on last month, not this one: the drop must stay visible.
          AnalyticsCategoryChange(
            categoryId: _carId,
            name: 'Автомобиль',
            amount: '0',
            previousAmount: '80.00',
          ),
        ],
  incomeChanges: empty
      ? const []
      : const [
          AnalyticsCategoryChange(
            categoryId: _salaryId,
            name: 'Зарплата',
            amount: '1500.00',
            previousAmount: '1200.00',
          ),
        ],
);

class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence(PlannedCostRecurrenceDraft draft) =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences() => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence(
    String recurrenceId,
    EndPlannedCostRecurrenceCommand command,
  ) => throw UnimplementedError();

  _FakeRepository({this.failure, this.empty = false, this.failRefresh = false});

  final FinanceEntryFailureKind? failure;
  final bool empty;

  /// Answers the first read and refuses every one after it.
  final bool failRefresh;
  final List<AnalyticsPeriodKind> asked = [];
  final List<({String? from, String? to})> customBounds = [];

  @override
  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
  }) async {
    final kind = failure;
    if (kind != null || (failRefresh && asked.isNotEmpty)) {
      return FinanceEntryFailureResult<AnalyticsWindow>(
        FinanceEntryFailure(
          kind: kind ?? FinanceEntryFailureKind.timeout,
          requestId: 'req_synthetic',
        ),
      );
    }
    asked.add(period);
    customBounds.add((from: from, to: to));
    return FinanceEntrySuccess<AnalyticsWindow>(
      requestId: 'req_synthetic',
      value: _window(empty: empty),
    );
  }

  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) async {
    return FinanceEntrySuccess<OperationHistoryList>(
      requestId: 'req_synthetic',
      value: OperationHistoryList(
        operations: empty
            ? const []
            : [
                OperationHistoryItem(
                  operationId: _operationId,
                  type: FinanceOperationType.expense,
                  amount: '420.00',
                  currency: 'EUR',
                  accountId: null,
                  category: 'Продукты',
                  categoryId: _groceriesId,
                  categoryText: 'Продукты',
                  merchant: null,
                  occurredOn: '2026-08-12',
                  occurredAt: null,
                  source: FinanceOperationSource.manualText,
                  createdAt: '2026-08-12T12:00:00Z',
                ),
              ],
        nextCursor: null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
