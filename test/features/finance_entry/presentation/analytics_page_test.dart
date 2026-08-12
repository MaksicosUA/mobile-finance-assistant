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
const _salaryId = '22222222-2222-4222-8222-222222222222';
const _operationId = '33333333-3333-4333-8333-333333333333';

void main() {
  testWidgets('a month shows both directions, not only spending', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    // The whole reason this screen exists in its current shape: income is a
    // first-class line, not a footnote under expenses.
    expect(find.text('1 500,00 €'), findsWidgets);
    expect(find.text('542,00 €'), findsWidgets);
    expect(find.text('Расходы по категориям'), findsOneWidget);
    expect(find.text('Доходы по категориям'), findsOneWidget);
  });

  testWidgets('a breakdown names its categories and their shares', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    expect(
      find.byKey(const Key('analytics-row-$_groceriesId')),
      findsOneWidget,
    );
    expect(find.text('Продукты'), findsOneWidget);
    // The share is written out, so the bar carries no meaning on its own.
    expect(find.text('77.49%'), findsOneWidget);
  });

  testWidgets('uncategorized spending is labelled, not left blank', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    expect(find.byKey(const Key('analytics-row-none')), findsOneWidget);
    // Hiding it would make the lines stop adding up to the total above them.
    expect(find.text('Без категории'), findsWidgets);
  });

  testWidgets('privacy mode masks every amount and share', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository(), privacy: true);

    expect(find.textContaining('542'), findsNothing);
    expect(find.textContaining('1 500'), findsNothing);
    expect(find.text('77.49%'), findsNothing);
    expect(find.text('•••••• €'), findsWidgets);
  });

  testWidgets('the newest operations are here, with a way to see them all', (
    tester,
  ) async {
    var opened = 0;
    await _pumpPage(
      tester,
      repository: _FakeRepository(),
      onOpenAllOperations: () => opened += 1,
    );

    // The list builds lazily, so the block has to be scrolled to before it
    // exists at all.
    await tester.scrollUntilVisible(
      find.byKey(const Key('analytics-all-operations')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Последние операции'), findsOneWidget);
    await tester.tap(find.byKey(const Key('analytics-all-operations')));

    expect(opened, 1);
  });

  testWidgets('losing the operations list does not hide the totals', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(failRecentOperations: true),
    );

    // The month is the point of this screen; a secondary block failing must
    // not take it down.
    expect(find.byKey(const Key('analytics-page')), findsOneWidget);
    expect(find.text('Расходы по категориям'), findsOneWidget);
  });

  testWidgets('an unreadable month offers a retry', (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        failure: FinanceEntryFailureKind.serviceUnavailable,
      ),
    );

    expect(find.byKey(const Key('analytics-failure')), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('an empty month renders without failing', (tester) async {
    await _pumpPage(tester, repository: _FakeRepository(empty: true));

    expect(find.byKey(const Key('analytics-page')), findsOneWidget);
    expect(find.text('За этот месяц записей нет'), findsWidgets);
  });

  testWidgets('the screen fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(tester, repository: _FakeRepository(), textScale: 2);

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  bool privacy = false,
  double textScale = 1,
  VoidCallback? onOpenAllOperations,
}) async {
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: Scaffold(
          body: AnalyticsPage(
            onSignInRequested: () async {},
            onOpenAllOperations: onOpenAllOperations ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AnalyticsSummary _summary({bool empty = false}) => AnalyticsSummary(
  periodStart: '2026-08-01',
  periodEnd: '2026-08-31',
  baseCurrency: 'EUR',
  income: empty ? '0' : '1500.00',
  expense: empty ? '0' : '542.00',
  netFlow: empty ? '0' : '958.00',
  trendTotal: empty ? '0' : '542.00',
  expenseByCategory: empty
      ? const []
      : const [
          AnalyticsCategoryTotal(
            categoryId: _groceriesId,
            name: 'Продукты',
            amount: '420.00',
            sharePercent: '77.49',
          ),
          // No link at all: the screen must still name this line.
          AnalyticsCategoryTotal(
            categoryId: null,
            name: null,
            amount: '122.00',
            sharePercent: '22.50',
          ),
        ],
  incomeByCategory: empty
      ? const []
      : const [
          AnalyticsCategoryTotal(
            categoryId: _salaryId,
            name: 'Зарплата',
            amount: '1500.00',
            sharePercent: '100.00',
          ),
        ],
  trendPoints: [
    for (var day = 6; day <= 12; day++)
      AnalyticsTrendPoint(
        date: '2026-08-${day.toString().padLeft(2, '0')}',
        amount: day == 12 && !empty ? '542.00' : '0',
      ),
  ],
);

class _FakeRepository implements FinanceEntryRepositoryClient {
  _FakeRepository({
    this.failure,
    this.failRecentOperations = false,
    this.empty = false,
  });

  final FinanceEntryFailureKind? failure;
  final bool failRecentOperations;
  final bool empty;

  @override
  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics() async {
    if (failure != null) {
      return FinanceEntryFailureResult<AnalyticsSummary>(
        FinanceEntryFailure(kind: failure!, requestId: 'req_synthetic'),
      );
    }
    return FinanceEntrySuccess<AnalyticsSummary>(
      requestId: 'req_synthetic',
      value: _summary(empty: empty),
    );
  }

  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) async {
    if (failRecentOperations) {
      return FinanceEntryFailureResult<OperationHistoryList>(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.timeout,
          requestId: 'req_synthetic',
        ),
      );
    }
    return FinanceEntrySuccess<OperationHistoryList>(
      requestId: 'req_synthetic',
      value: OperationHistoryList(
        operations: empty
            ? const []
            : const [
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
