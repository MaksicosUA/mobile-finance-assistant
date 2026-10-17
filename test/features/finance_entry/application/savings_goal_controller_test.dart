import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/savings_goal_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _goalCommandId = '44444444-4444-4444-8444-444444444444';
const _goalId = '55555555-5555-4555-8555-555555555555';
const _otherGoalId = '66666666-6666-4666-8666-666666666666';
const _contributionId = '77777777-7777-4777-8777-777777777777';

void main() {
  group('SavingsGoalController', () {
    test('bounds the target picker by the account baseline', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(savingsGoalControllerProvider.notifier).load();

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      expect(state.earliestDate, DateTime.utc(2026, 7, 10));
      // A deadline is normally ahead, so a year out needs no picking.
      expect(state.selectedDate, DateTime.utc(2027, 8, 9));
      expect(state.goals, isEmpty);
    });

    test('a target before the baseline is refused locally', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.selectTargetDate(DateTime.utc(2026, 7, 9));

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      expect(state.selectedDate, DateTime.utc(2027, 8, 9));
      expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
      expect(repository.drafts, isEmpty);
    });

    test('creates a goal and normalizes a comma decimal separator', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (draft) => _success(
          SavingsGoalCreated(
            goal: _goal(targetOn: draft.targetOn),
            idempotentReplay: false,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.startCreating();
      controller.setTitle('  Отпуск  ');
      controller.setTargetAmount('3000,50');
      controller.setMonthlyContribution('250,00');
      await controller.submit();

      final draft = repository.drafts.single;
      expect(draft.title, 'Отпуск');
      expect(draft.targetAmount, '3000.50');
      expect(draft.monthlyContribution, '250.00');
      expect(draft.currency, 'EUR');

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      expect(state.goals.single.goalId, _goalId);
      // The form closes and empties, so a second tap cannot resubmit it.
      expect(state.isCreating, isFalse);
      expect(state.title, isEmpty);
    });

    test(
      'an undeclared monthly intent is omitted, never sent as zero',
      () async {
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onCreate: (draft) => _success(
            SavingsGoalCreated(
              goal: _goal(targetOn: draft.targetOn),
              idempotentReplay: false,
            ),
          ),
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          savingsGoalControllerProvider.notifier,
        );
        await controller.load();

        controller.startCreating();
        controller.setTitle('Отпуск');
        controller.setTargetAmount('3000.00');
        await controller.submit();

        expect(repository.drafts.single.monthlyContribution, isNull);
      },
    );

    test('a retried creation replays the same command id', () async {
      var attempt = 0;
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (draft) {
          attempt += 1;
          if (attempt == 1) {
            return _failureResult<SavingsGoalCreated>(
              FinanceEntryFailureKind.timeout,
            );
          }
          return _success(
            SavingsGoalCreated(
              goal: _goal(targetOn: draft.targetOn),
              idempotentReplay: true,
            ),
          );
        },
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.startCreating();
      controller.setTitle('Отпуск');
      controller.setTargetAmount('3000.00');
      await controller.submit();
      await controller.submit();

      // The same identity is what makes the retry a replay rather than a
      // second goal.
      expect(repository.drafts.map((draft) => draft.commandId).toSet(), {
        _goalCommandId,
      });
    });

    test('editing after a failure mints a new command id', () async {
      final ids = <String>[
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        _goalCommandId,
      ];
      var index = 0;
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (draft) =>
            _failureResult<SavingsGoalCreated>(FinanceEntryFailureKind.timeout),
      );
      final container = _container(
        repository,
        commandIdFactory: () => ids[index++ % ids.length],
      );
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.startCreating();
      controller.setTitle('Отпуск');
      controller.setTargetAmount('3000.00');
      await controller.submit();
      // Different content must not reuse the identity: that would be a
      // conflict rather than a correction.
      controller.setTargetAmount('4000.00');
      await controller.submit();

      expect(
        repository.drafts.first.commandId,
        isNot(repository.drafts.last.commandId),
      );
    });

    test(
      'a deposit shows the server total, not a locally recomputed one',
      () async {
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          goals: [_goal(currentAmount: '0')],
          onContribution: (goalId, command) => _success(
            GoalContributionRecorded(
              contribution: _contribution(command),
              goal: _goal(currentAmount: '500', progressPercent: '16.66'),
              idempotentReplay: false,
            ),
          ),
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          savingsGoalControllerProvider.notifier,
        );
        await controller.load();

        controller.setContributionAmount('500');
        await controller.recordContribution(
          _goal(currentAmount: '0'),
          GoalContributionDirection.deposit,
        );

        final state =
            container.read(savingsGoalControllerProvider) as SavingsGoalReady;
        expect(state.goals.single.currentAmount, '500');
        expect(state.goals.single.progressPercent, '16.66');
        // The field empties so the same amount cannot be deposited twice by a
        // stray second tap.
        expect(state.contributionAmount, isEmpty);
        expect(repository.contributions.single.$2.amount, '500');
        expect(
          repository.contributions.single.$2.direction,
          GoalContributionDirection.deposit,
        );
        // Omitted on purpose: only the server knows the account-local date.
        expect(repository.contributions.single.$2.occurredOn, isNull);
      },
    );

    test('a retried deposit replays the same entry identity', () async {
      var attempt = 0;
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        goals: [_goal()],
        onContribution: (goalId, command) {
          attempt += 1;
          if (attempt == 1) {
            return _failureResult<GoalContributionRecorded>(
              FinanceEntryFailureKind.timeout,
            );
          }
          return _success(
            GoalContributionRecorded(
              contribution: _contribution(command),
              goal: _goal(currentAmount: '500'),
              idempotentReplay: true,
            ),
          );
        },
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.setContributionAmount('500');
      await controller.recordContribution(
        _goal(),
        GoalContributionDirection.deposit,
      );
      await controller.recordContribution(
        _goal(),
        GoalContributionDirection.deposit,
      );

      // A second identity here would deposit the same money twice.
      expect(
        repository.contributions.map((entry) => entry.$2.commandId).toSet(),
        {_goalCommandId},
      );
    });

    test('a refused withdrawal surfaces its typed issue', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
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
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.setContributionAmount('200');
      await controller.recordContribution(
        _goal(currentAmount: '100'),
        GoalContributionDirection.withdrawal,
      );

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      expect(
        state.issues.single.code,
        SavingsGoalIssueCode.withdrawalExceedsGoalBalance,
      );
      expect(state.busyGoalId, isNull);
      // The goal keeps the balance the server still reports.
      expect(state.goals.single.currentAmount, '100');
    });

    test('cancelling removes the goal from the pursued list', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        goals: [
          _goal(),
          _goal(id: _otherGoalId, targetOn: '2028-01-01'),
        ],
        onCancel: (goalId) => _success(
          SavingsGoalCancelled(
            goal: _goal(status: 'cancelled'),
            idempotentReplay: false,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      await controller.cancelGoal(_goalId);

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      expect(state.goals.map((goal) => goal.goalId), [_otherGoalId]);
      expect(state.busyGoalId, isNull);
    });

    test('only active goals are listed', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        goals: [
          _goal(),
          _goal(id: _otherGoalId, status: 'cancelled'),
        ],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(savingsGoalControllerProvider.notifier).load();

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      expect(state.goals.map((goal) => goal.goalId), [_goalId]);
    });

    test('goals stay ordered by nearest deadline after a write', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        goals: [_goal(id: _otherGoalId, targetOn: '2028-01-01')],
        onCreate: (draft) => _success(
          SavingsGoalCreated(
            goal: _goal(targetOn: '2027-01-01'),
            idempotentReplay: false,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(savingsGoalControllerProvider.notifier);
      await controller.load();

      controller.startCreating();
      controller.setTitle('Отпуск');
      controller.setTargetAmount('3000.00');
      await controller.submit();

      final state =
          container.read(savingsGoalControllerProvider) as SavingsGoalReady;
      // Same order Home derives its primary goal from.
      expect(state.goals.map((goal) => goal.goalId), [_goalId, _otherGoalId]);
    });

    test('a failing goal list never blocks creating one', () async {
      final repository = _FailingListRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(savingsGoalControllerProvider.notifier).load();

      final state = container.read(savingsGoalControllerProvider);
      expect(state, isA<SavingsGoalReady>());
      expect((state as SavingsGoalReady).goals, isEmpty);
    });

    test('an unauthenticated session asks for sign-in', () async {
      final repository = _FakeRepository(
        listResults: [
          _failureResult<FinanceAccountSetup>(
            FinanceEntryFailureKind.unauthenticated,
          ),
        ],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(savingsGoalControllerProvider.notifier).load();

      expect(
        container.read(savingsGoalControllerProvider),
        isA<SavingsGoalAuthenticationRequired>(),
      );
    });

    test('an account is required before a goal can exist', () async {
      final repository = _FakeRepository(listResults: [_success(_setup(null))]);
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(savingsGoalControllerProvider.notifier).load();

      final state = container.read(savingsGoalControllerProvider);
      expect(state, isA<SavingsGoalUnavailable>());
      expect(
        (state as SavingsGoalUnavailable).reason,
        SavingsGoalUnavailableReason.accountRequired,
      );
    });
  });
}

ProviderContainer _container(
  _FakeRepository repository, {
  String Function()? commandIdFactory,
}) {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 9, 12),
      ),
      financeCommandIdFactoryProvider.overrideWithValue(
        commandIdFactory ?? () => _goalCommandId,
      ),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
    ],
  );
  container.listen(
    savingsGoalControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

FinanceEntrySuccess<T> _success<T>(T value) =>
    FinanceEntrySuccess<T>(requestId: 'req_synthetic_goal', value: value);

FinanceEntryFailureResult<T> _failureResult<T>(FinanceEntryFailureKind kind) =>
    FinanceEntryFailureResult<T>(
      FinanceEntryFailure(kind: kind, requestId: 'req_synthetic_goal'),
    );

FinanceAccountSetup _setup(FinanceAccount? account) => FinanceAccountSetup(
  canonicalTimezone: account == null ? null : configuredHomeApiTimezone,
  timezoneRevision: account == null ? 0 : 1,
  accounts: account == null ? const [] : [account],
);

FinanceAccount _account(String openingBalanceOn) => FinanceAccount(
  accountId: _accountId,
  userId: _userId,
  commandId: _accountCommandId,
  name: 'Тестовый счёт',
  currency: 'EUR',
  openingBalance: '100.00',
  openingBalanceOn: openingBalanceOn,
  openingTimezone: configuredHomeApiTimezone,
  isDefault: true,
  confirmedAt: '2026-07-10T10:00:00.000Z',
  createdAt: '2026-07-10T10:00:00.000Z',
);

SavingsGoal _goal({
  String id = _goalId,
  String targetOn = '2027-06-01',
  String status = 'active',
  String currentAmount = '0',
  String progressPercent = '0',
}) => SavingsGoal(
  goalId: id,
  accountId: _accountId,
  title: 'Отпуск',
  targetAmount: '3000.00',
  currentAmount: currentAmount,
  monthlyContribution: '250.00',
  currency: 'EUR',
  targetOn: targetOn,
  status: status,
  achieved: false,
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

class _FailingListRepository extends _FakeRepository {
  _FailingListRepository({super.listResults});

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals() async {
    return _failureResult<SavingsGoalList>(
      FinanceEntryFailureKind.serviceUnavailable,
    );
  }
}

class _FakeRepository implements FinanceEntryRepositoryClient {
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
    List<FinanceEntryResult<FinanceAccountSetup>> listResults = const [],
    this.onCreate,
    this.onContribution,
    this.onCancel,
    this.goals = const [],
  }) : _listResults = List.of(listResults);

  final List<FinanceEntryResult<FinanceAccountSetup>> _listResults;
  final FinanceEntryResult<SavingsGoalCreated> Function(SavingsGoalDraft)?
  onCreate;
  final FinanceEntryResult<GoalContributionRecorded> Function(
    String,
    GoalContributionCommand,
  )?
  onContribution;
  final FinanceEntryResult<SavingsGoalCancelled> Function(String)? onCancel;
  final List<SavingsGoal> goals;
  final List<SavingsGoalDraft> drafts = [];
  final List<(String, GoalContributionCommand)> contributions = [];
  final List<String> cancelled = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return _listResults.removeAt(0);
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal(
    SavingsGoalDraft draft,
  ) async {
    drafts.add(draft);
    final handler = onCreate;
    if (handler == null) throw UnimplementedError();
    return handler(draft);
  }

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals() async {
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

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
