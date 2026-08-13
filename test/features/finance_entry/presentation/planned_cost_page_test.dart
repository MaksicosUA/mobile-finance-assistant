import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/planned_cost_page.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _planCommandId = '44444444-4444-4444-8444-444444444444';
const _planId = '55555555-5555-4555-8555-555555555555';

void main() {
  testWidgets('editing form fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(tester, repository: _FakeRepository(), textScale: 2);

    expect(find.byKey(const Key('planned-cost-editing')), findsOneWidget);
    expect(find.byKey(const Key('planned-cost-title')), findsOneWidget);

    // At 200% the form is taller than the viewport, so what matters is that
    // every control stays reachable by scrolling and nothing overflows.
    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-cost-submit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('planned-cost-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a user without an account is told to create one', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository(hasAccount: false));

    expect(find.byKey(const Key('planned-cost-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('planned-cost-editing')), findsNothing);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final repository = _FakeRepository(
      listFailure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.serviceUnavailable,
        requestId: 'req_synthetic_planned_cost',
      ),
    );

    await _pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('planned-cost-failure')), findsOneWidget);
    expect(repository.listCalls, 1);
  });

  testWidgets('a refused plan explains the baseline bound', (tester) async {
    final repository = _FakeRepository(
      createResult: FinanceEntryFailureResult<PlannedCostCreated>(
        FinanceEntryFailure(
          kind: FinanceEntryFailureKind.rejected,
          requestId: 'req_synthetic_planned_cost',
          code: FinanceEntryErrorCode.plannedCostRejected,
          plannedCostIssues: const [
            PlannedCostIssue(
              code: PlannedCostIssueCode.planBeforeAccountBaseline,
              field: 'plannedOn',
            ),
          ],
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Аренда',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '800.00',
    );
    await tester.tap(find.byKey(const Key('planned-cost-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('planned-cost-message')), findsOneWidget);
    // The refusal names the actual cause instead of a bare error.
    expect(find.textContaining('начала учёта'), findsOneWidget);
  });

  testWidgets('an accepted plan says it does not change the balance', (
    tester,
  ) async {
    final repository = _FakeRepository(
      createResult: FinanceEntrySuccess<PlannedCostCreated>(
        requestId: 'req_synthetic_planned_cost',
        value: const PlannedCostCreated(
          plannedCost: PlannedCost(
            plannedCostId: _planId,
            accountId: _accountId,
            amount: '800.00',
            currency: 'EUR',
            title: 'Аренда',
            plannedOn: '2026-09-01',
            status: 'planned',
            isDue: false,
          ),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('planned-cost-title')),
      'Аренда',
    );
    await tester.enterText(
      find.byKey(const Key('planned-cost-amount')),
      '800.00',
    );
    await tester.tap(find.byKey(const Key('planned-cost-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('planned-cost-accepted')), findsOneWidget);
    expect(find.textContaining('не влияет на баланс'), findsOneWidget);
    expect(find.byKey(const Key('planned-cost-home-status')), findsOneWidget);
  });

  testWidgets('outstanding plans are listed and can be cancelled', (
    tester,
  ) async {
    final repository = _FakeRepository(
      plans: const [
        PlannedCost(
          plannedCostId: _planId,
          accountId: _accountId,
          amount: '800.00',
          currency: 'EUR',
          title: 'Аренда',
          plannedOn: '2026-09-01',
          status: 'planned',
          isDue: false,
        ),
      ],
      settleResult: FinanceEntrySuccess<PlannedCostSettled>(
        requestId: 'req_synthetic_planned_cost',
        value: const PlannedCostSettled(
          plannedCost: PlannedCost(
            plannedCostId: _planId,
            accountId: _accountId,
            amount: '800.00',
            currency: 'EUR',
            title: 'Аренда',
            plannedOn: '2026-09-01',
            status: 'cancelled',
            isDue: false,
          ),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    final row = find.byKey(const Key('planned-cost-plan-$_planId'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(row, findsOneWidget);

    final cancel = find.byKey(const Key('planned-cost-cancel-$_planId'));
    await tester.scrollUntilVisible(
      cancel,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel, warnIfMissed: true);
    await tester.pumpAndSettle();

    expect(repository.settled, [_planId]);
    expect(find.byKey(const Key('planned-cost-list-empty')), findsOneWidget);
  });

  testWidgets('an empty plan list says so instead of showing nothing', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    await tester.scrollUntilVisible(
      find.byKey(const Key('planned-cost-list-empty')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('planned-cost-list-empty')), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        financeCommandIdFactoryProvider.overrideWithValue(() => _planCommandId),
        financeEntryClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 8, 9, 12),
        ),
        homeRepositoryProvider.overrideWithValue(const _FirstUseHome()),
        homeSessionStoreProvider.overrideWithValue(
          const _NullHomeSessionStore(),
        ),
        acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
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
        home: PlannedCostPage(onSignInRequested: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<UserProfile>> readProfile() =>
      throw UnimplementedError();
  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory(
    CreateCategoryCommand command,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory(
    String categoryId,
    RenameCategoryCommand command,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory(
    String categoryId,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory(
    String categoryId,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal(
    SavingsGoalDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution(
    String goalId,
    GoalContributionCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal(
    String goalId,
    FinanceGoalCancelCommand command,
  ) => throw UnimplementedError();
  _FakeRepository({
    this.hasAccount = true,
    this.listFailure,
    this.createResult,
    this.plans = const [],
    this.settleResult,
  });

  final List<PlannedCost> plans;
  final FinanceEntryResult<PlannedCostSettled>? settleResult;
  final List<String> settled = [];
  final bool hasAccount;
  final FinanceEntryFailure? listFailure;
  final FinanceEntryResult<PlannedCostCreated>? createResult;
  final List<PlannedCostDraft> drafts = [];
  int listCalls = 0;
  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() async {
    return FinanceEntrySuccess<PlannedCostList>(
      requestId: 'req_synthetic_planned_cost',
      value: PlannedCostList(evaluatedOn: '2026-08-09', plans: plans),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  ) async {
    settled.add(plannedCostId);
    final result = settleResult;
    if (result == null) throw UnimplementedError();
    return result;
  }

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    listCalls += 1;
    final failure = listFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<FinanceAccountSetup>(failure);
    }
    return FinanceEntrySuccess<FinanceAccountSetup>(
      requestId: 'req_synthetic_planned_cost',
      value: FinanceAccountSetup(
        canonicalTimezone: hasAccount ? configuredHomeApiTimezone : null,
        timezoneRevision: hasAccount ? 1 : 0,
        accounts: hasAccount
            ? [
                FinanceAccount(
                  accountId: _accountId,
                  userId: _userId,
                  commandId: _accountCommandId,
                  name: 'Тестовый счёт',
                  currency: 'EUR',
                  openingBalance: '100.00',
                  openingBalanceOn: '2026-07-10',
                  openingTimezone: configuredHomeApiTimezone,
                  confirmedAt: '2026-07-10T10:00:00.000Z',
                  createdAt: '2026-07-10T10:00:00.000Z',
                ),
              ]
            : const [],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) async {
    drafts.add(draft);
    final result = createResult;
    if (result == null) throw UnimplementedError();
    return result;
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) => throw UnimplementedError();
}

class _FirstUseHome implements HomeRepository, HomeCacheInvalidator {
  const _FirstUseHome();

  @override
  Future<void> invalidateHomeCache() async {}

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    return HomeFirstUseResult(
      HomeFirstUseData(userName: 'Тест', availableActions: const {}),
    );
  }
}

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
