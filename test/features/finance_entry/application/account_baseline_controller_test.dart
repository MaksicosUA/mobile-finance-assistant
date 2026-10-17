import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/network/api_config.dart';
import 'package:mobile_finance_assistant/core/platform/finance_capture_context.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/account_baseline_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _accountCommandId = '33333333-3333-4333-8333-333333333333';
const _baselineCommandId = '44444444-4444-4444-8444-444444444444';
const _draftHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  group('AccountBaselineController', () {
    test('loads strict 1900..current minus one day editing bounds', () async {
      final repository = _FakeFinanceEntryRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
      );
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(accountBaselineControllerProvider.notifier).load();

      final state =
          container.read(accountBaselineControllerProvider)
              as AccountBaselineEditing;
      expect(state.account.openingBalanceOn, '2026-07-10');
      expect(state.earliestDate, DateTime.utc(1900));
      expect(state.latestDate, DateTime.utc(2026, 7, 9));
      expect(state.selectedDate, DateTime.utc(2026, 7, 9));
      expect(state.failure, isNull);
      expect(state.issues, isEmpty);
    });

    test(
      'selection enforces bounds and evaluation creates one command id',
      () async {
        var commandIds = 0;
        final repository = _FakeFinanceEntryRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onEvaluateBaseline: (draft) => _success(
            FinanceBaselineNeedsConfirmation(
              draft: draft,
              currentOpeningBalanceOn: '2026-07-10',
              earliestOperationOn: null,
              draftHash: _draftHash,
            ),
          ),
        );
        final container = _container(
          repository,
          commandIdFactory: () {
            commandIds += 1;
            return _baselineCommandId;
          },
        );
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();

        controller.selectDate(DateTime.utc(2026, 7, 10));

        final invalid =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineEditing;
        expect(invalid.selectedDate, DateTime.utc(2026, 7, 9));
        expect(invalid.failure?.kind, FinanceEntryFailureKind.invalidInput);
        expect(commandIds, 0);
        expect(repository.baselineDrafts, isEmpty);

        controller.selectDate(DateTime.utc(2026, 7, 1));
        await controller.evaluate();

        final reviewing =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineReviewing;
        expect(commandIds, 1);
        expect(repository.baselineDrafts, hasLength(1));
        expect(reviewing.review.draft.commandId, _baselineCommandId);
        expect(reviewing.review.draft.accountId, _accountId);
        expect(reviewing.review.draft.openingBalanceOn, '2026-07-01');
      },
    );

    test('commit retry reuses the exact command and confirmedAt', () async {
      late final _FakeFinanceEntryRepository repository;
      repository = _FakeFinanceEntryRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
        onCommitBaseline: (command) => repository.baselineCommands.length == 1
            ? _failure<FinanceBaselineCommit>(
                FinanceEntryFailureKind.serviceUnavailable,
              )
            : _success(_commit(command, previous: '2026-07-10')),
      );
      final clock = _SequenceClock([
        DateTime.utc(2026, 8, 9, 10),
        DateTime.utc(2026, 8, 9, 11),
      ]);
      final container = _container(
        repository,
        clock: clock.call,
        commandIdFactory: () => _baselineCommandId,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        accountBaselineControllerProvider.notifier,
      );
      await controller.load();
      controller.selectDate(DateTime.utc(2026, 7, 1));
      await controller.evaluate();

      await controller.confirm();

      final failed =
          container.read(accountBaselineControllerProvider)
              as AccountBaselineReviewing;
      expect(failed.failure?.kind, FinanceEntryFailureKind.serviceUnavailable);
      final firstCommand = repository.baselineCommands.single;

      await controller.confirm();

      expect(repository.baselineCommands, hasLength(2));
      expect(repository.baselineCommands.last, same(firstCommand));
      expect(repository.baselineCommands.last.toJson(), firstCommand.toJson());
      expect(firstCommand.confirmedAt, '2026-08-09T10:00:00.000Z');
      expect(clock.calls, 1);
      expect(
        container.read(accountBaselineControllerProvider),
        isA<AccountBaselineAccepted>(),
      );
    });

    test(
      'accepted commit is retained while delayed Home convergence completes',
      () async {
        final home = _BlockingHomeRepository();
        addTearDown(home.releaseInvalidation);
        final repository = _FakeFinanceEntryRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
          onCommitBaseline: (command) =>
              _success(_commit(command, previous: '2026-07-10')),
        );
        final container = _container(
          repository,
          commandIdFactory: () => _baselineCommandId,
          homeRepository: home,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();
        controller.selectDate(DateTime.utc(2026, 7, 1));
        await controller.evaluate();
        final financeSubscription = container.listen(
          financeEntryControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(financeSubscription.close);
        await container.read(financeEntryControllerProvider.notifier).load();
        expect(
          container.read(financeEntryControllerProvider),
          isA<FinanceOperationEditing>(),
        );

        await controller.confirm();

        final accepted =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineAccepted;
        expect(accepted.homeStatus, AccountBaselineHomeStatus.pending);
        expect(accepted.commit.account.openingBalanceOn, '2026-07-01');
        expect(home.invalidations, 1);
        expect(home.fetches, 0);
        expect(
          container.read(financeEntryControllerProvider),
          isA<FinanceEntryLoading>(),
        );

        home.releaseInvalidation();
        await _pumpUntil(
          container,
          () =>
              (container.read(accountBaselineControllerProvider)
                      as AccountBaselineAccepted)
                  .homeStatus !=
              AccountBaselineHomeStatus.pending,
        );

        final converged =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineAccepted;
        expect(converged.homeStatus, AccountBaselineHomeStatus.failed);
        expect(converged.commit, same(accepted.commit));
        expect(home.fetches, 1);
      },
    );

    test(
      'commit-time rejection discards review and reloads authoritative account',
      () async {
        final issue = const FinanceBaselineIssue(
          code: FinanceBaselineIssueCode.baselineAfterExistingOperation,
        );
        final rejection = FinanceEntryFailure(
          kind: FinanceEntryFailureKind.rejected,
          requestId: 'req_baseline_rejected',
          code: FinanceEntryErrorCode.baselineRejected,
          baselineIssues: [issue],
        );
        final repository = _FakeFinanceEntryRepository(
          listResults: [
            _success(_setup(_account('2026-07-10'))),
            _success(_setup(_account('2026-07-05'))),
          ],
          onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
          onCommitBaseline: (_) =>
              FinanceEntryFailureResult<FinanceBaselineCommit>(rejection),
        );
        final container = _container(
          repository,
          commandIdFactory: () => _baselineCommandId,
        );
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();
        controller.selectDate(DateTime.utc(2026, 7, 1));
        await controller.evaluate();

        await controller.confirm();

        expect(repository.listCalls, 2);
        final editing =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineEditing;
        expect(editing.account.openingBalanceOn, '2026-07-05');
        expect(editing.latestDate, DateTime.utc(2026, 7, 4));
        expect(editing.selectedDate, DateTime.utc(2026, 7, 4));
        expect(editing.failure, same(rejection));
        expect(editing.issues, [same(issue)]);
      },
    );

    test(
      'evaluation account unavailable reloads into unavailable state',
      () async {
        final repository = _FakeFinanceEntryRepository(
          listResults: [
            _success(_setup(_account('2026-07-10'))),
            _success(_emptySetup()),
          ],
          onEvaluateBaseline: (_) => _accountUnavailable(),
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();
        controller.selectDate(DateTime.utc(2026, 7, 1));

        await controller.evaluate();

        expect(repository.listCalls, 2);
        final unavailable =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineUnavailable;
        expect(
          unavailable.reason,
          AccountBaselineUnavailableReason.accountRequired,
        );
      },
    );

    test(
      'evaluation with a changed current baseline reloads authoritative account',
      () async {
        final repository = _FakeFinanceEntryRepository(
          listResults: [
            _success(_setup(_account('2026-07-10'))),
            _success(_setup(_account('2026-07-08'))),
          ],
          onEvaluateBaseline: (draft) => _review(draft, '2026-07-09'),
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();
        controller.selectDate(DateTime.utc(2026, 7, 1));

        await controller.evaluate();

        expect(repository.listCalls, 2);
        final editing =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineEditing;
        expect(editing.account.openingBalanceOn, '2026-07-08');
        expect(editing.latestDate, DateTime.utc(2026, 7, 7));
        expect(editing.failure, isNull);
      },
    );

    test('commit account unavailable reloads into unavailable state', () async {
      final repository = _FakeFinanceEntryRepository(
        listResults: [
          _success(_setup(_account('2026-07-10'))),
          _success(_emptySetup()),
        ],
        onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
        onCommitBaseline: (_) => _accountUnavailable(),
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        accountBaselineControllerProvider.notifier,
      );
      await controller.load();
      controller.selectDate(DateTime.utc(2026, 7, 1));
      await controller.evaluate();

      await controller.confirm();

      expect(repository.listCalls, 2);
      final unavailable =
          container.read(accountBaselineControllerProvider)
              as AccountBaselineUnavailable;
      expect(
        unavailable.reason,
        AccountBaselineUnavailableReason.accountRequired,
      );
    });

    test(
      'tampered immutable account receipt fails before Home invalidation',
      () async {
        final home = _BlockingHomeRepository();
        addTearDown(home.releaseInvalidation);
        final repository = _FakeFinanceEntryRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
          onCommitBaseline: (command) => _success(
            _commit(
              command,
              previous: '2026-07-10',
              account: _account(
                command.draft.openingBalanceOn,
                name: 'Подменённый счёт',
              ),
            ),
          ),
        );
        final container = _container(repository, homeRepository: home);
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();
        controller.selectDate(DateTime.utc(2026, 7, 1));
        await controller.evaluate();

        await controller.confirm();

        final reviewing =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineReviewing;
        expect(
          reviewing.failure?.kind,
          FinanceEntryFailureKind.malformedResponse,
        );
        expect(home.invalidations, 0);
        expect(home.fetches, 0);
      },
    );

    test(
      'commit previous date must match the loaded and reviewed baseline',
      () async {
        final home = _BlockingHomeRepository();
        addTearDown(home.releaseInvalidation);
        final repository = _FakeFinanceEntryRepository(
          listResults: [_success(_setup(_account('2026-07-10')))],
          onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
          onCommitBaseline: (command) =>
              _success(_commit(command, previous: '2026-07-09')),
        );
        final container = _container(repository, homeRepository: home);
        addTearDown(container.dispose);
        final controller = container.read(
          accountBaselineControllerProvider.notifier,
        );
        await controller.load();
        controller.selectDate(DateTime.utc(2026, 7, 1));
        await controller.evaluate();

        await controller.confirm();

        final reviewing =
            container.read(accountBaselineControllerProvider)
                as AccountBaselineReviewing;
        expect(
          reviewing.failure?.kind,
          FinanceEntryFailureKind.malformedResponse,
        );
        expect(home.invalidations, 0);
        expect(home.fetches, 0);
      },
    );

    test('account epoch ignores a late accepted baseline commit', () async {
      final pendingCommit =
          Completer<FinanceEntryResult<FinanceBaselineCommit>>();
      final home = _BlockingHomeRepository();
      addTearDown(home.releaseInvalidation);
      final repository = _FakeFinanceEntryRepository(
        listResults: [_success(_setup(_account('2026-07-10')))],
        onEvaluateBaseline: (draft) => _review(draft, '2026-07-10'),
        onCommitBaseline: (_) => pendingCommit.future,
      );
      final container = _container(
        repository,
        commandIdFactory: () => _baselineCommandId,
        homeRepository: home,
      );
      addTearDown(container.dispose);
      final controller = container.read(
        accountBaselineControllerProvider.notifier,
      );
      await controller.load();
      controller.selectDate(DateTime.utc(2026, 7, 1));
      await controller.evaluate();

      final confirmation = controller.confirm();
      expect(repository.baselineCommands, hasLength(1));
      container.read(authAccountEpochProvider.notifier).advance();
      await container.pump();
      expect(
        container.read(accountBaselineControllerProvider),
        isA<AccountBaselineLoading>(),
      );

      pendingCommit.complete(
        _success(
          _commit(repository.baselineCommands.single, previous: '2026-07-10'),
        ),
      );
      await confirmation;

      expect(
        container.read(accountBaselineControllerProvider),
        isA<AccountBaselineLoading>(),
      );
      expect(home.invalidations, 0);
      expect(home.fetches, 0);
    });

    test('load exposes controlled auth and minimum-date states', () async {
      final unauthorized = _FakeFinanceEntryRepository(
        listResults: [
          _failure<FinanceAccountSetup>(FinanceEntryFailureKind.unauthorized),
        ],
      );
      final authContainer = _container(unauthorized);
      addTearDown(authContainer.dispose);

      await authContainer
          .read(accountBaselineControllerProvider.notifier)
          .load();

      expect(
        authContainer.read(accountBaselineControllerProvider),
        isA<AccountBaselineAuthenticationRequired>(),
      );

      final minimum = _FakeFinanceEntryRepository(
        listResults: [_success(_setup(_account('1900-01-01')))],
      );
      final minimumContainer = _container(minimum);
      addTearDown(minimumContainer.dispose);

      await minimumContainer
          .read(accountBaselineControllerProvider.notifier)
          .load();

      final unavailable =
          minimumContainer.read(accountBaselineControllerProvider)
              as AccountBaselineUnavailable;
      expect(unavailable.reason, AccountBaselineUnavailableReason.minimumDate);
    });
  });
}

ProviderContainer _container(
  _FakeFinanceEntryRepository repository, {
  DateTime Function()? clock,
  String Function()? commandIdFactory,
  HomeRepository? homeRepository,
}) {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      financeEntryClockProvider.overrideWithValue(
        clock ?? () => DateTime.utc(2026, 8, 9, 12),
      ),
      financeCommandIdFactoryProvider.overrideWithValue(
        commandIdFactory ?? () => _baselineCommandId,
      ),
      financeCaptureContextSourceProvider.overrideWithValue(
        const _FixedFinanceCaptureContextSource(),
      ),
      if (homeRepository != null)
        homeRepositoryProvider.overrideWithValue(homeRepository),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
    ],
  );
  container.listen(
    accountBaselineControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

Future<void> _pumpUntil(
  ProviderContainer container,
  bool Function() condition,
) async {
  for (var index = 0; index < 20 && !condition(); index += 1) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }
  expect(condition(), isTrue);
}

FinanceEntrySuccess<T> _success<T>(T value) => FinanceEntrySuccess<T>(
  requestId: 'req_synthetic_account_baseline',
  value: value,
);

FinanceEntryFailureResult<T> _failure<T>(FinanceEntryFailureKind kind) =>
    FinanceEntryFailureResult<T>(
      FinanceEntryFailure(
        kind: kind,
        requestId: 'req_synthetic_account_baseline_failure',
      ),
    );

FinanceEntryFailureResult<T> _accountUnavailable<T>() =>
    FinanceEntryFailureResult<T>(
      FinanceEntryFailure(
        kind: FinanceEntryFailureKind.conflict,
        requestId: 'req_synthetic_account_unavailable',
        code: FinanceEntryErrorCode.accountUnavailable,
      ),
    );

FinanceEntrySuccess<FinanceBaselineEvaluation> _review(
  FinanceBaselineDraft draft,
  String currentOpeningBalanceOn,
) => _success<FinanceBaselineEvaluation>(
  FinanceBaselineNeedsConfirmation(
    draft: draft,
    currentOpeningBalanceOn: currentOpeningBalanceOn,
    earliestOperationOn: null,
    draftHash: _draftHash,
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

FinanceAccount _account(
  String openingBalanceOn, {
  String name = 'Тестовый счёт',
}) => FinanceAccount(
  accountId: _accountId,
  userId: _userId,
  commandId: _accountCommandId,
  name: name,
  currency: 'EUR',
  openingBalance: '100.00',
  openingBalanceOn: openingBalanceOn,
  openingTimezone: configuredHomeApiTimezone,
  isDefault: true,
  confirmedAt: '2026-07-10T08:00:00.000Z',
  createdAt: '2026-07-10T08:00:01.000Z',
);

FinanceBaselineCommit _commit(
  FinanceBaselineCommitCommand command, {
  required String previous,
  FinanceAccount? account,
}) => FinanceBaselineCommit(
  idempotentReplay: false,
  previousOpeningBalanceOn: previous,
  account: account ?? _account(command.draft.openingBalanceOn),
);

typedef _BaselineEvaluationHandler =
    FutureOr<FinanceEntryResult<FinanceBaselineEvaluation>> Function(
      FinanceBaselineDraft draft,
    );
typedef _BaselineCommitHandler =
    FutureOr<FinanceEntryResult<FinanceBaselineCommit>> Function(
      FinanceBaselineCommitCommand command,
    );

final class _FakeFinanceEntryRepository
    implements FinanceEntryRepositoryClient {
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
  _FakeFinanceEntryRepository({
    required this.listResults,
    this.onEvaluateBaseline,
    this.onCommitBaseline,
  });

  final List<FinanceEntryResult<FinanceAccountSetup>> listResults;
  final _BaselineEvaluationHandler? onEvaluateBaseline;
  final _BaselineCommitHandler? onCommitBaseline;
  final List<FinanceBaselineDraft> baselineDrafts = [];
  final List<FinanceBaselineCommitCommand> baselineCommands = [];
  int listCalls = 0;
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
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() async {
    final index = listCalls < listResults.length
        ? listCalls
        : listResults.length - 1;
    final result = listResults[index];
    listCalls += 1;
    return result;
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) async {
    baselineDrafts.add(draft);
    final handler = onEvaluateBaseline;
    if (handler == null) throw StateError('Unexpected baseline evaluation.');
    return await handler(draft);
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) async {
    baselineCommands.add(command);
    final handler = onCommitBaseline;
    if (handler == null) throw StateError('Unexpected baseline commit.');
    return await handler(command);
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) => throw StateError('Unexpected account evaluation.');

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) => throw StateError('Unexpected account commit.');

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) => throw StateError('Unexpected operation evaluation.');

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) => throw StateError('Unexpected operation commit.');
}

final class _SequenceClock {
  _SequenceClock(this.values);

  final List<DateTime> values;
  int calls = 0;

  DateTime call() => values[calls++];
}

final class _FixedFinanceCaptureContextSource
    implements FinanceCaptureContextSource {
  const _FixedFinanceCaptureContextSource();

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

final class _BlockingHomeRepository
    implements HomeRepository, HomeCacheInvalidator {
  final Completer<void> _invalidation = Completer<void>();
  int invalidations = 0;
  int fetches = 0;

  void releaseInvalidation() {
    if (!_invalidation.isCompleted) _invalidation.complete();
  }

  @override
  Future<void> invalidateHomeCache() async {
    invalidations += 1;
    await _invalidation.future;
  }

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    fetches += 1;
    return const HomeFailureResult(
      type: HomeFailureType.unknown,
      requestId: 'req_synthetic_home_failure',
    );
  }
}

final class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<void> clearSession() async {}

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;
}
