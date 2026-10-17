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
import 'package:mobile_finance_assistant/features/finance_entry/presentation/savings_goal_page.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _goalCommandId = '44444444-4444-4444-8444-444444444444';
const _goalId = '55555555-5555-4555-8555-555555555555';
const _contributionId = '77777777-7777-4777-8777-777777777777';

void main() {
  testWidgets('an empty screen says so instead of showing a bare form', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    expect(find.byKey(const Key('savings-goal-list-empty')), findsOneWidget);
    expect(find.byKey(const Key('savings-goal-create-form')), findsNothing);
    expect(find.byKey(const Key('savings-goal-start-create')), findsOneWidget);
  });

  testWidgets('the create form fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(tester, repository: _FakeRepository(), textScale: 2);
    await tester.tap(find.byKey(const Key('savings-goal-start-create')));
    await tester.pumpAndSettle();

    // At 200% the form is taller than the viewport, so what matters is that
    // every control stays reachable by scrolling and nothing overflows.
    await tester.scrollUntilVisible(
      find.byKey(const Key('savings-goal-submit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('savings-goal-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a goal card fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(
      tester,
      repository: _FakeRepository(goals: [_goal(currentAmount: '1500')]),
      textScale: 2,
    );

    expect(find.byKey(const Key('savings-goal-card-$_goalId')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('savings-goal-withdraw-$_goalId')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a goal shows both amounts, never progress alone', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        goals: [_goal(currentAmount: '1500', progressPercent: '50')],
      ),
    );

    // The bar repeats the numbers; the numbers are what the user can act on.
    expect(
      find.byKey(const Key('savings-goal-amounts-$_goalId')),
      findsOneWidget,
    );
    expect(find.textContaining('1500'), findsWidgets);
    expect(find.textContaining('3000.00'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('an achieved goal is stated in words, not colour alone', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        goals: [
          _goal(
            currentAmount: '3000.00',
            progressPercent: '100',
            achieved: true,
          ),
        ],
      ),
    );

    expect(
      find.byKey(const Key('savings-goal-achieved-$_goalId')),
      findsOneWidget,
    );
  });

  testWidgets('a deposit sends the typed amount and shows the new total', (
    tester,
  ) async {
    final repository = _FakeRepository(
      goals: [_goal()],
      onContribution: (goalId, command) => _success(
        GoalContributionRecorded(
          contribution: _contribution(command),
          goal: _goal(currentAmount: '500', progressPercent: '16.66'),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('savings-goal-amount-$_goalId')),
      '500',
    );
    await tester.tap(find.byKey(const Key('savings-goal-deposit-$_goalId')));
    await tester.pumpAndSettle();

    expect(repository.contributions.single.$2.amount, '500');
    expect(
      repository.contributions.single.$2.direction,
      GoalContributionDirection.deposit,
    );
    expect(find.textContaining('500'), findsWidgets);
  });

  testWidgets('a refused withdrawal explains why in words', (tester) async {
    final repository = _FakeRepository(
      goals: [_goal(currentAmount: '100')],
      onContribution: (goalId, command) =>
          FinanceEntryFailureResult<GoalContributionRecorded>(
            FinanceEntryFailure(
              kind: FinanceEntryFailureKind.rejected,
              requestId: 'req_synthetic_goal',
              code: FinanceEntryErrorCode.goalRejected,
              goalIssues: const [
                SavingsGoalIssue(
                  code: SavingsGoalIssueCode.withdrawalExceedsGoalBalance,
                  field: 'amount',
                ),
              ],
            ),
          ),
    );
    await _pumpPage(tester, repository: repository);

    await tester.enterText(
      find.byKey(const Key('savings-goal-amount-$_goalId')),
      '200',
    );
    await tester.tap(find.byKey(const Key('savings-goal-withdraw-$_goalId')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('savings-goal-message')), findsOneWidget);
  });

  testWidgets('cancelling a goal removes its card', (tester) async {
    final repository = _FakeRepository(
      goals: [_goal()],
      onCancel: (goalId) => _success(
        SavingsGoalCancelled(
          goal: _goal(status: 'cancelled'),
          idempotentReplay: false,
        ),
      ),
    );
    await _pumpPage(tester, repository: repository);

    final cancel = find.byKey(const Key('savings-goal-cancel-$_goalId'));
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(repository.cancelled, [_goalId]);
    expect(find.byKey(const Key('savings-goal-card-$_goalId')), findsNothing);
    expect(find.byKey(const Key('savings-goal-list-empty')), findsOneWidget);
  });

  testWidgets('a user without an account is told to create one', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository(hasAccount: false));

    expect(find.byKey(const Key('savings-goal-unavailable')), findsOneWidget);
    expect(find.byKey(const Key('savings-goal-ready')), findsNothing);
  });

  testWidgets('a load failure offers a retry', (tester) async {
    final repository = _FakeRepository(
      listFailure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.serviceUnavailable,
        requestId: 'req_synthetic_goal',
      ),
    );

    await _pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('savings-goal-failure')), findsOneWidget);
    expect(repository.listCalls, 1);
  });
  testWidgets('a pull re-reads the goals without resetting the screen', (
    tester,
  ) async {
    final repository = _FakeRepository(goals: [_goal(currentAmount: '1500')]);
    await _pumpPage(tester, repository: repository);

    await tester.fling(
      find.byKey(const Key('savings-goal-ready')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.goalListCalls, 2);
    // The account is not read again: a pull asks for the list, and rebuilding
    // the screen would discard a goal being described.
    expect(repository.listCalls, 1);
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
        financeCommandIdFactoryProvider.overrideWithValue(() => _goalCommandId),
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
        home: SavingsGoalPage(onSignInRequested: () async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FinanceEntrySuccess<T> _success<T>(T value) =>
    FinanceEntrySuccess<T>(requestId: 'req_synthetic_goal', value: value);

SavingsGoal _goal({
  String id = _goalId,
  String status = 'active',
  String currentAmount = '0',
  String progressPercent = '0',
  bool achieved = false,
}) => SavingsGoal(
  goalId: id,
  accountId: _accountId,
  title: 'Отпуск',
  targetAmount: '3000.00',
  currentAmount: currentAmount,
  monthlyContribution: '250.00',
  currency: 'EUR',
  targetOn: '2027-06-01',
  status: status,
  achieved: achieved,
  progressPercent: progressPercent,
);

GoalContribution _contribution(GoalContributionCommand command) =>
    GoalContribution(
      contributionId: _contributionId,
      goalId: _goalId,
      direction: command.direction,
      amount: command.amount,
      currency: 'EUR',
      occurredOn: '2026-08-09',
    );

final class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String savePath,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String savePath,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer(
    FinanceTransferDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer(
    FinanceTransferCommitCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone(
    FinanceTimezoneCommand command,
  ) => throw UnimplementedError();
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

  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) => throw UnimplementedError();

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

  @override
  Future<FinanceEntryResult<OperationCorrected>> correctOperation(
    OperationCorrectionCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<OperationRemoved>> removeOperation(
    OperationRemovalCommand command,
  ) => throw UnimplementedError();

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
  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  }) => throw UnimplementedError();
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
  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords(
    String categoryId,
  ) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords(
    String categoryId,
    List<String> keywords,
  ) => throw UnimplementedError();
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
  _FakeRepository({
    this.hasAccount = true,
    this.listFailure,
    this.goals = const [],
    this.onContribution,
    this.onCancel,
  });

  final bool hasAccount;
  final FinanceEntryFailure? listFailure;
  final List<SavingsGoal> goals;
  final FinanceEntryResult<GoalContributionRecorded> Function(
    String,
    GoalContributionCommand,
  )?
  onContribution;
  final FinanceEntryResult<SavingsGoalCancelled> Function(String)? onCancel;
  final List<(String, GoalContributionCommand)> contributions = [];
  final List<String> cancelled = [];
  int listCalls = 0;
  int goalListCalls = 0;

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    listCalls += 1;
    final failure = listFailure;
    if (failure != null) {
      return FinanceEntryFailureResult<FinanceAccountSetup>(failure);
    }
    return _success(
      FinanceAccountSetup(
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
                  isDefault: true,
                  confirmedAt: '2026-07-10T10:00:00.000Z',
                  createdAt: '2026-07-10T10:00:00.000Z',
                ),
              ]
            : const [],
      ),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals() async {
    goalListCalls += 1;
    return _success(SavingsGoalList(evaluatedOn: '2026-08-09', goals: goals));
  }

  @override
  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution(
    String goalId,
    GoalContributionCommand command,
  ) async {
    contributions.add((goalId, command));
    final handler = onContribution;
    if (handler == null) throw UnimplementedError();
    return handler(goalId, command);
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal(
    String goalId,
    FinanceGoalCancelCommand command,
  ) async {
    cancelled.add(goalId);
    final handler = onCancel;
    if (handler == null) throw UnimplementedError();
    return handler(goalId);
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal(
    SavingsGoalDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  ) => throw UnimplementedError();

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
