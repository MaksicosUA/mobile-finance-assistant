import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/operation_sync_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_command_id.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/planned_cost_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _planCommandId = '44444444-4444-4444-8444-444444444444';
const _planId = '55555555-5555-4555-8555-555555555555';
const _otherPlanId = '66666666-6666-4666-8666-666666666666';
const _draftHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('PlannedCostController', () {
    test('bounds the picker by the account baseline, never before it', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      // A plan before the baseline could never be confirmed into an operation.
      expect(state.earliestDate, DateTime.utc(2026, 7, 10));
      expect(state.selectedDate, DateTime.utc(2026, 8, 9));
      // A forecast is allowed to sit far in the future; that is the point.
      expect(state.latestDate.isAfter(DateTime.utc(2030)), isTrue);
    });

    test('selecting a date before the baseline is refused locally', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      controller.selectDate(DateTime.utc(2026, 7, 9));

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.selectedDate, DateTime.utc(2026, 8, 9));
      expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
      expect(repository.drafts, isEmpty);
    });

    test('submits a future-dated plan and reports Home convergence', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (draft) => _success(
          PlannedCostCreated(
            plannedCost: _plan(plannedOn: draft.plannedOn),
            idempotentReplay: false,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      controller.setTitle('Аренда');
      controller.setAmount('800,50');
      controller.selectDate(DateTime.utc(2026, 9, 1));
      await controller.submit();

      final draft = repository.drafts.single;
      expect(draft.title, 'Аренда');
      // Russian keyboards produce a comma; the wire contract needs a dot.
      expect(draft.amount, '800.50');
      expect(draft.plannedOn, '2026-09-01');
      expect(draft.accountId, _accountId);
      expect(draft.commandId, _planCommandId);
      expect(
        container.read(plannedCostControllerProvider),
        isA<PlannedCostAccepted>(),
      );
    });

    test('a rejection surfaces its typed issue and keeps the input', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (_) => _rejection(),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();
      controller.setTitle('Аренда');
      controller.setAmount('800.00');

      await controller.submit();

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.isSubmitting, isFalse);
      expect(state.title, 'Аренда');
      expect(
        state.issues.single.code,
        PlannedCostIssueCode.planBeforeAccountBaseline,
      );
    });

    test(
      'a retry replays the same command id rather than adding a plan',
      () async {
        var issued = 0;
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onCreate: (_) => _rejection(),
        );
        final container = _container(
          repository,
          commandIdFactory: () {
            issued += 1;
            return _planCommandId;
          },
        );
        addTearDown(container.dispose);
        final controller = container.read(
          plannedCostControllerProvider.notifier,
        );
        await controller.load();
        controller.setTitle('Аренда');
        controller.setAmount('800.00');

        await controller.submit();
        await controller.submit();

        expect(repository.drafts, hasLength(2));
        expect(
          repository.drafts.first.commandId,
          repository.drafts.last.commandId,
        );
        expect(issued, 1);
      },
    );

    test('editing the input starts a new command', () async {
      var issued = 0;
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onCreate: (_) => _rejection(),
      );
      final container = _container(
        repository,
        commandIdFactory: () {
          issued += 1;
          return _planCommandId;
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();
      controller.setTitle('Аренда');
      controller.setAmount('800.00');
      await controller.submit();

      // Different content must not reuse the identity of the refused command.
      controller.setAmount('900.00');
      await controller.submit();

      expect(issued, 2);
    });

    test('an empty amount never reaches the network', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();
      controller.setTitle('Аренда');

      await controller.submit();

      expect(repository.drafts, isEmpty);
      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.failure?.kind, FinanceEntryFailureKind.invalidInput);
    });

    test(
      'loading also lists outstanding plans and drops settled ones',
      () async {
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          plans: [
            _plan(plannedOn: '2026-09-01'),
            _plan(
              plannedOn: '2026-09-05',
              id: _otherPlanId,
              status: 'cancelled',
            ),
          ],
        );
        final container = _container(repository);
        addTearDown(container.dispose);

        await container.read(plannedCostControllerProvider.notifier).load();

        final state =
            container.read(plannedCostControllerProvider) as PlannedCostEditing;
        // A settled plan is no longer an obligation.
        expect(state.plans, hasLength(1));
        expect(state.plans.single.plannedCostId, _planId);
      },
    );

    test('cancelling removes the plan from the outstanding list', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        plans: [_plan(plannedOn: '2026-09-01')],
        onTransition: (id) => _success(
          PlannedCostSettled(
            plannedCost: _plan(plannedOn: '2026-09-01', status: 'cancelled'),
            idempotentReplay: false,
          ),
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      await controller.cancelPlan(_planId);

      expect(repository.settled, [_planId]);
      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.plans, isEmpty);
      expect(state.settlingId, isNull);
    });

    test('a failed cancellation keeps the plan and reports it', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        plans: [_plan(plannedOn: '2026-09-01')],
        onTransition: (_) => _failureResult<PlannedCostSettled>(
          FinanceEntryFailureKind.serviceUnavailable,
        ),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      await controller.cancelPlan(_planId);

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      // The plan is still outstanding, so it must still be shown.
      expect(state.plans, hasLength(1));
      expect(state.settlingId, isNull);
      expect(state.failure?.kind, FinanceEntryFailureKind.serviceUnavailable);
    });

    test('a listing failure does not block planning', () async {
      final repository = _FailingListRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.plans, isEmpty);
      expect(state.failure, isNull);
    });

    test(
      'confirming records the operation first and only then settles the plan',
      () async {
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          plans: [_plan(plannedOn: '2026-08-01')],
          onTransition: (_) => _success(
            PlannedCostSettled(
              plannedCost: _plan(plannedOn: '2026-08-01', status: 'confirmed'),
              idempotentReplay: false,
            ),
          ),
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          plannedCostControllerProvider.notifier,
        );
        await controller.load();

        await controller.confirmPlan(_plan(plannedOn: '2026-08-01'));

        // The operation is evaluated before anything settles the plan.
        expect(repository.evaluatedDrafts, hasLength(1));
        final draft = repository.evaluatedDrafts.single;
        expect(draft.amount, '800.50');
        // A plan that has already come due is recorded on its planned day.
        expect(draft.occurredOn, '2026-08-01');
        // The operation command is derived from the plan, so a retry replays
        // it instead of charging twice.
        expect(draft.commandId, plannedCostOperationCommandId(_planId));

        final settle = repository.transitions.single;
        expect(settle.transition, PlannedCostTransition.confirm);
        expect(settle.operationCommandId, draft.commandId);
      },
    );

    test(
      'a future-dated plan is recorded today, never in the future',
      () async {
        final repository = _FakeRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          plans: [_plan(plannedOn: '2026-12-01')],
          onTransition: (_) => _success(
            PlannedCostSettled(
              plannedCost: _plan(plannedOn: '2026-12-01', status: 'confirmed'),
              idempotentReplay: false,
            ),
          ),
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          plannedCostControllerProvider.notifier,
        );
        await controller.load();

        await controller.confirmPlan(_plan(plannedOn: '2026-12-01'));

        expect(repository.evaluatedDrafts.single.occurredOn, '2026-08-09');
      },
    );

    test('a rejected operation leaves the plan outstanding', () async {
      final repository = _FakeRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        plans: [_plan(plannedOn: '2026-08-01')],
        evaluationFailure: FinanceEntryFailureKind.serviceUnavailable,
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(plannedCostControllerProvider.notifier);
      await controller.load();

      await controller.confirmPlan(_plan(plannedOn: '2026-08-01'));

      // Nothing settled, so the obligation must still be visible.
      expect(repository.transitions, isEmpty);
      final state =
          container.read(plannedCostControllerProvider) as PlannedCostEditing;
      expect(state.plans, hasLength(1));
      expect(state.settlingId, isNull);
      expect(state.failure, isNotNull);
    });

    test('an unauthorized failure asks for sign-in', () async {
      final repository = _FakeRepository(
        listResults: [
          _failureResult<FinanceAccountSetup>(
            FinanceEntryFailureKind.unauthorized,
          ),
        ],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      expect(
        container.read(plannedCostControllerProvider),
        isA<PlannedCostAuthenticationRequired>(),
      );
    });

    test('a user without an account is told to create one first', () async {
      final repository = _FakeRepository(
        listResults: [_success(_emptySetup())],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(plannedCostControllerProvider.notifier).load();

      final state =
          container.read(plannedCostControllerProvider)
              as PlannedCostUnavailable;
      expect(state.reason, PlannedCostUnavailableReason.accountRequired);
    });
  });
}

ProviderContainer _container(
  _FakeRepository repository, {
  String Function()? commandIdFactory,
  OperationDeliveryResult? delivery,
}) {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 9, 12),
      ),
      financeCommandIdFactoryProvider.overrideWithValue(
        commandIdFactory ?? () => _planCommandId,
      ),
      financeCaptureContextSourceProvider.overrideWithValue(
        const _FixedCaptureContextSource(),
      ),
      operationDeliveryCoordinatorProvider.overrideWithValue(
        _FakeDeliveryCoordinator(delivery),
      ),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
    ],
  );
  container.listen(
    plannedCostControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

FinanceEntrySuccess<T> _success<T>(T value) => FinanceEntrySuccess<T>(
  requestId: 'req_synthetic_planned_cost',
  value: value,
);

FinanceEntryFailureResult<T> _failureResult<T>(FinanceEntryFailureKind kind) =>
    FinanceEntryFailureResult<T>(
      FinanceEntryFailure(kind: kind, requestId: 'req_synthetic_planned_cost'),
    );

FinanceEntryFailureResult<PlannedCostCreated> _rejection() =>
    FinanceEntryFailureResult<PlannedCostCreated>(
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
    );

FinanceAccountSetup _setup(FinanceAccount account) => FinanceAccountSetup(
  canonicalTimezone: configuredHomeApiTimezone,
  timezoneRevision: 1,
  accounts: [account],
);

FinanceAccountSetup _emptySetup() => FinanceAccountSetup(
  canonicalTimezone: null,
  timezoneRevision: 0,
  accounts: const [],
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

PlannedCost _plan({
  required String plannedOn,
  String id = _planId,
  String status = 'planned',
}) => PlannedCost(
  plannedCostId: id,
  accountId: _accountId,
  amount: '800.50',
  currency: 'EUR',
  title: 'Аренда',
  plannedOn: plannedOn,
  status: status,
  isDue: false,
);

class _FailingListRepository extends _FakeRepository {
  _FailingListRepository({super.listResults});

  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() async {
    return _failureResult<PlannedCostList>(
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
    List<FinanceEntryResult<FinanceAccountSetup>> listResults = const [],
    this.onCreate,
    this.plans = const [],
    this.onTransition,
    this.evaluationFailure,
  }) : _listResults = List.of(listResults);

  final List<FinanceEntryResult<FinanceAccountSetup>> _listResults;
  final FinanceEntryResult<PlannedCostCreated> Function(PlannedCostDraft)?
  onCreate;
  final List<PlannedCost> plans;
  final FinanceEntryResult<PlannedCostSettled> Function(String)? onTransition;
  final FinanceEntryFailureKind? evaluationFailure;
  final List<PlannedCostDraft> drafts = [];
  final List<String> settled = [];
  final List<FinanceOperationDraft> evaluatedDrafts = [];
  final List<PlannedCostTransitionCommand> transitions = [];
  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() async {
    return _success(PlannedCostList(evaluatedOn: '2026-08-09', plans: plans));
  }

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  ) async {
    settled.add(plannedCostId);
    transitions.add(command);
    final handler = onTransition;
    if (handler == null) throw UnimplementedError();
    return handler(plannedCostId);
  }

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    return _listResults.removeAt(0);
  }

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) async {
    drafts.add(draft);
    final handler = onCreate;
    if (handler == null) throw UnimplementedError();
    return handler(draft);
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
  ) async {
    evaluatedDrafts.add(draft);
    final failure = evaluationFailure;
    if (failure != null) {
      return _failureResult<FinanceOperationEvaluation>(failure);
    }
    return _success<FinanceOperationEvaluation>(
      FinanceOperationNeedsConfirmation(draft: draft, draftHash: _draftHash),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) => throw UnimplementedError();
}

final class _FakeDeliveryCoordinator implements OperationDeliveryCoordinator {
  _FakeDeliveryCoordinator(this._result);

  final OperationDeliveryResult? _result;
  final List<FinanceOperationCommitCommand> commands = [];

  @override
  Future<OperationDeliveryResult> enqueueAndSynchronize({
    required String expectedPrincipalScopeId,
    required FinanceOperationCommitCommand command,
    void Function(FinanceOperationCommit commit)? onAccepted,
  }) async {
    commands.add(command);
    return _result ??
        const OperationDeliveryAlreadySynced('operation-already-synced');
  }
}

final class _FixedCaptureContextSource implements FinanceCaptureContextSource {
  const _FixedCaptureContextSource();

  @override
  Future<FinanceCaptureContext> capture({
    required String canonicalTimezone,
  }) async => FinanceCaptureContext.fromPlatformValue({
    'capturedAtUtc': '2026-08-09T12:00:00.000Z',
    'osTimezone': configuredHomeApiTimezone,
    'osLocalDate': '2026-08-09',
    'canonicalTimezone': configuredHomeApiTimezone,
    'canonicalLocalDate': '2026-08-09',
  }, expectedCanonicalTimezone: configuredHomeApiTimezone);
}

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
