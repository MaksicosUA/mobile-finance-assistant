import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_repository.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_session_store.dart';
import 'package:mobile_finance_assistant/features/auth/domain/auth_session.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_api.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

void main() {
  group('FinanceEntryRepository', () {
    test('does not call API or refresh without a secure session', () async {
      final api = _ListApi([]);
      var refreshes = 0;
      final repository = FinanceEntryRepository(
        api: api,
        sessionStore: _SessionStore(null),
        refreshSession: () async {
          refreshes += 1;
          return AuthRefreshResult.recovered;
        },
      );

      final result = await repository.listAccounts();

      expect(_failure(result).kind, FinanceEntryFailureKind.unauthenticated);
      expect(api.tokens, isEmpty);
      expect(refreshes, 0);
    });

    test(
      'retries unauthorized exactly once with the rotated access token',
      () async {
        final initial = _session(access: 'old-access', refresh: 'old-refresh');
        final replacement = _session(
          access: 'new-access',
          refresh: 'new-refresh',
        );
        final store = _SessionStore(initial);
        final api = _ListApi([
          _failed(FinanceEntryFailureKind.unauthorized),
          _successSetup(),
        ]);
        var refreshes = 0;
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async {
            refreshes += 1;
            store.session = replacement;
            return AuthRefreshResult.recovered;
          },
        );

        final result = await repository.listAccounts();

        expect(result, isA<FinanceEntrySuccess<FinanceAccountSetup>>());
        expect(api.tokens, ['old-access', 'new-access']);
        expect(refreshes, 1);
      },
    );

    test('evaluates a baseline with the active access token', () async {
      final draft = _baselineDraft();
      final api = _BaselineApi(
        evaluationResults: [_successBaselineEvaluation(draft)],
      );
      final repository = FinanceEntryRepository(
        api: api,
        sessionStore: _SessionStore(
          _session(access: 'active-access', refresh: 'active-refresh'),
        ),
        refreshSession: () async => AuthRefreshResult.recovered,
      );

      final result = await repository.evaluateBaseline(draft);

      expect(result, isA<FinanceEntrySuccess<FinanceBaselineEvaluation>>());
      expect(api.tokens, ['active-access']);
      expect(api.evaluationDrafts, [same(draft)]);
    });

    test(
      'retries a baseline commit once after an authorized token refresh',
      () async {
        final initial = _session(access: 'old-access', refresh: 'old-refresh');
        final replacement = _session(
          access: 'new-access',
          refresh: 'new-refresh',
        );
        final command = _baselineCommand();
        final store = _SessionStore(initial);
        final api = _BaselineApi(
          commitResults: [
            _failedBaseline(FinanceEntryFailureKind.unauthorized),
            _successBaselineCommit(command),
          ],
        );
        var refreshes = 0;
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async {
            refreshes += 1;
            store.session = replacement;
            return AuthRefreshResult.recovered;
          },
        );

        final result = await repository.commitBaseline(command);

        expect(result, isA<FinanceEntrySuccess<FinanceBaselineCommit>>());
        expect(api.tokens, ['old-access', 'new-access']);
        expect(api.commitCommands, [same(command), same(command)]);
        expect(refreshes, 1);
      },
    );

    test(
      'accepts a successful response after a same-account token rotation',
      () async {
        final initial = _session(access: 'old-access', refresh: 'old-refresh');
        final replacement = _session(
          access: 'new-access',
          refresh: 'new-refresh',
        );
        final store = _SessionStore(initial);
        final completer = Completer<FinanceEntryResult<FinanceAccountSetup>>();
        final api = _CompletingListApi(completer);
        var refreshes = 0;
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async {
            refreshes += 1;
            return AuthRefreshResult.recovered;
          },
        );

        final pending = repository.listAccounts();
        await Future<void>.delayed(Duration.zero);
        store.session = replacement;
        completer.complete(_successSetup());
        final result = await pending;

        expect(result, isA<FinanceEntrySuccess<FinanceAccountSetup>>());
        expect(api.tokens, ['old-access']);
        expect(refreshes, 0);
      },
    );

    test(
      'retries unauthorized once with an already-rotated same-account session',
      () async {
        final initial = _session(access: 'old-access', refresh: 'old-refresh');
        final replacement = _session(
          access: 'new-access',
          refresh: 'new-refresh',
        );
        final store = _SessionStore(initial);
        final completer = Completer<FinanceEntryResult<FinanceAccountSetup>>();
        final api = _CompletingListApi(completer, [_successSetup()]);
        var refreshes = 0;
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async {
            refreshes += 1;
            return AuthRefreshResult.recovered;
          },
        );

        final pending = repository.listAccounts();
        await Future<void>.delayed(Duration.zero);
        store.session = replacement;
        completer.complete(_failed(FinanceEntryFailureKind.unauthorized));
        final result = await pending;

        expect(result, isA<FinanceEntrySuccess<FinanceAccountSetup>>());
        expect(api.tokens, ['old-access', 'new-access']);
        expect(refreshes, 0);
      },
    );

    for (final change in const [
      (
        label: 'account scope',
        scope: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        revision: '0123456789abcdef0123456789abcdef',
      ),
      (
        label: 'account revision',
        scope: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        revision: 'fedcba9876543210fedcba9876543210',
      ),
    ]) {
      test(
        'does not resend after the ${change.label} changes in flight',
        () async {
          final initial = _session(
            access: 'old-access',
            refresh: 'old-refresh',
          );
          final switched = _session(
            access: 'other-access',
            refresh: 'other-refresh',
            scope: change.scope,
            revision: change.revision,
          );
          final store = _SessionStore(initial);
          final completer =
              Completer<FinanceEntryResult<FinanceAccountSetup>>();
          final api = _CompletingListApi(completer, [_successSetup()]);
          var refreshes = 0;
          final repository = FinanceEntryRepository(
            api: api,
            sessionStore: store,
            refreshSession: () async {
              refreshes += 1;
              return AuthRefreshResult.recovered;
            },
          );

          final pending = repository.listAccounts();
          await Future<void>.delayed(Duration.zero);
          store.session = switched;
          completer.complete(_failed(FinanceEntryFailureKind.unauthorized));
          final result = await pending;

          expect(_failure(result).kind, FinanceEntryFailureKind.sessionChanged);
          expect(api.tokens, ['old-access']);
          expect(refreshes, 0);
        },
      );
    }

    test('drops a recovered refresh that switched account scope', () async {
      final initial = _session(access: 'old-access', refresh: 'old-refresh');
      final switched = _session(
        access: 'other-access',
        refresh: 'other-refresh',
        scope: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      );
      final store = _SessionStore(initial);
      final api = _ListApi([_failed(FinanceEntryFailureKind.unauthorized)]);
      final repository = FinanceEntryRepository(
        api: api,
        sessionStore: store,
        refreshSession: () async {
          store.session = switched;
          return AuthRefreshResult.recovered;
        },
      );

      final result = await repository.listAccounts();

      expect(_failure(result).kind, FinanceEntryFailureKind.sessionChanged);
      expect(api.tokens, ['old-access']);
    });

    test(
      'never performs a second refresh after retry remains unauthorized',
      () async {
        final initial = _session(access: 'old-access', refresh: 'old-refresh');
        final replacement = _session(
          access: 'new-access',
          refresh: 'new-refresh',
        );
        final store = _SessionStore(initial);
        final api = _ListApi([
          _failed(FinanceEntryFailureKind.unauthorized),
          _failed(FinanceEntryFailureKind.unauthorized),
        ]);
        var refreshes = 0;
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async {
            refreshes += 1;
            store.session = replacement;
            return AuthRefreshResult.recovered;
          },
        );

        final result = await repository.listAccounts();

        expect(_failure(result).kind, FinanceEntryFailureKind.unauthorized);
        expect(api.tokens, ['old-access', 'new-access']);
        expect(refreshes, 1);
      },
    );

    test('guarded commit rejects a mismatched session before API', () async {
      final expected = _session(
        access: 'expected-access',
        refresh: 'expected-refresh',
      );
      final actual = _session(
        access: 'other-access',
        refresh: 'other-refresh',
        scope: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      );
      final api = _OperationApi(const []);
      final repository = FinanceEntryRepository(
        api: api,
        sessionStore: _SessionStore(actual),
        refreshSession: () async => AuthRefreshResult.recovered,
      );
      var preflightCalls = 0;

      final result = await repository.commitOperation(
        _operationCommand(),
        expectedPrincipalScopeId: expected.cacheScopeId,
        expectedSessionRevision: expected.revision,
        preflight: () {
          preflightCalls += 1;
          return null;
        },
      );

      expect(_failure(result).kind, FinanceEntryFailureKind.sessionChanged);
      expect(api.tokens, isEmpty);
      expect(api.commands, isEmpty);
      expect(preflightCalls, 0);
    });

    test(
      'guarded commit rechecks preflight after asynchronous session read',
      () async {
        final session = _session(access: 'old-access', refresh: 'old-refresh');
        final store = _FirstReadGatedSessionStore(session);
        final api = _OperationApi(const []);
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async => AuthRefreshResult.recovered,
        );
        var foreground = true;

        final pending = repository.commitOperation(
          _operationCommand(),
          expectedPrincipalScopeId: session.cacheScopeId,
          expectedSessionRevision: session.revision,
          preflight: () =>
              foreground ? null : FinanceEntryFailureKind.interrupted,
        );
        await store.firstReadStarted.future;
        foreground = false;
        store.releaseFirstRead();

        final result = await pending;

        expect(_failure(result).kind, FinanceEntryFailureKind.interrupted);
        expect(api.tokens, isEmpty);
        expect(api.commands, isEmpty);
      },
    );

    test('guarded commit blocks the retry after a 401 refresh', () async {
      final initial = _session(access: 'old-access', refresh: 'old-refresh');
      final replacement = _session(
        access: 'new-access',
        refresh: 'new-refresh',
      );
      final command = _operationCommand();
      final store = _SessionStore(initial);
      final api = _OperationApi([
        _failedOperation(FinanceEntryFailureKind.unauthorized),
        _successOperation(command, idempotentReplay: true),
      ]);
      var refreshes = 0;
      var preflightCalls = 0;
      final repository = FinanceEntryRepository(
        api: api,
        sessionStore: store,
        refreshSession: () async {
          refreshes += 1;
          store.session = replacement;
          return AuthRefreshResult.recovered;
        },
      );

      final result = await repository.commitOperation(
        command,
        expectedPrincipalScopeId: initial.cacheScopeId,
        expectedSessionRevision: initial.revision,
        preflight: () {
          preflightCalls += 1;
          return preflightCalls == 1
              ? null
              : FinanceEntryFailureKind.interrupted;
        },
      );

      expect(_failure(result).kind, FinanceEntryFailureKind.interrupted);
      expect(api.tokens, ['old-access']);
      expect(api.commands, [same(command)]);
      expect(preflightCalls, 2);
      expect(refreshes, 1);
    });

    test(
      'guarded commit permits a foreground retry after token rotation',
      () async {
        final initial = _session(access: 'old-access', refresh: 'old-refresh');
        final replacement = _session(
          access: 'new-access',
          refresh: 'new-refresh',
        );
        final command = _operationCommand();
        final store = _SessionStore(initial);
        final api = _OperationApi([
          _failedOperation(FinanceEntryFailureKind.unauthorized),
          _successOperation(command, idempotentReplay: true),
        ]);
        var refreshes = 0;
        var preflightCalls = 0;
        final repository = FinanceEntryRepository(
          api: api,
          sessionStore: store,
          refreshSession: () async {
            refreshes += 1;
            store.session = replacement;
            return AuthRefreshResult.recovered;
          },
        );

        final result = await repository.commitOperation(
          command,
          expectedPrincipalScopeId: initial.cacheScopeId,
          expectedSessionRevision: initial.revision,
          preflight: () {
            preflightCalls += 1;
            return null;
          },
        );

        expect(result, isA<FinanceEntrySuccess<FinanceOperationCommit>>());
        expect(api.tokens, ['old-access', 'new-access']);
        expect(api.commands, [same(command), same(command)]);
        expect(preflightCalls, 2);
        expect(refreshes, 1);
      },
    );
  });
}

AuthSession _session({
  required String access,
  required String refresh,
  String scope = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  String revision = '0123456789abcdef0123456789abcdef',
}) {
  return AuthSession(
    accessToken: access,
    refreshToken: refresh,
    accessExpiresAtUtc: DateTime.utc(2026, 7, 29, 1),
    refreshExpiresAtUtc: DateTime.utc(2026, 8, 29),
    cacheScopeId: scope,
    revision: revision,
  );
}

FinanceEntrySuccess<FinanceAccountSetup> _successSetup() {
  return FinanceEntrySuccess(
    requestId: 'req_test',
    value: FinanceAccountSetup(
      canonicalTimezone: null,
      timezoneRevision: 0,
      accounts: const [],
    ),
  );
}

FinanceEntryFailureResult<FinanceAccountSetup> _failed(
  FinanceEntryFailureKind kind,
) {
  return FinanceEntryFailureResult(
    FinanceEntryFailure(kind: kind, requestId: 'req_test'),
  );
}

FinanceEntryFailure _failure<T>(FinanceEntryResult<T> result) =>
    (result as FinanceEntryFailureResult<T>).failure;

FinanceBaselineDraft _baselineDraft() => const FinanceBaselineDraft(
  commandId: '11111111-1111-4111-8111-111111111111',
  accountId: '22222222-2222-4222-8222-222222222222',
  openingBalanceOn: '2026-01-01',
);

FinanceBaselineCommitCommand _baselineCommand() {
  return FinanceBaselineCommitCommand.fromReview(
    review: FinanceBaselineNeedsConfirmation(
      draft: _baselineDraft(),
      currentOpeningBalanceOn: '2026-07-29',
      earliestOperationOn: null,
      draftHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    confirmedAt: DateTime.utc(2026, 8, 9, 12),
  );
}

FinanceEntrySuccess<FinanceBaselineEvaluation> _successBaselineEvaluation(
  FinanceBaselineDraft draft,
) {
  return FinanceEntrySuccess<FinanceBaselineEvaluation>(
    requestId: 'req_test_baseline_evaluation',
    value: FinanceBaselineNeedsConfirmation(
      draft: draft,
      currentOpeningBalanceOn: '2026-07-29',
      earliestOperationOn: null,
      draftHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
  );
}

FinanceEntryFailureResult<FinanceBaselineCommit> _failedBaseline(
  FinanceEntryFailureKind kind,
) => FinanceEntryFailureResult<FinanceBaselineCommit>(
  FinanceEntryFailure(kind: kind, requestId: 'req_test_baseline_failure'),
);

FinanceEntrySuccess<FinanceBaselineCommit> _successBaselineCommit(
  FinanceBaselineCommitCommand command,
) {
  final draft = command.draft;
  return FinanceEntrySuccess<FinanceBaselineCommit>(
    requestId: 'req_test_baseline_commit',
    value: FinanceBaselineCommit(
      idempotentReplay: false,
      previousOpeningBalanceOn: '2026-07-29',
      account: FinanceAccount(
        accountId: draft.accountId,
        userId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        commandId: draft.commandId,
        name: 'Synthetic account',
        currency: 'EUR',
        openingBalance: '0.00',
        openingBalanceOn: draft.openingBalanceOn,
        openingTimezone: 'Europe/Berlin',
        isDefault: true,
        confirmedAt: command.confirmedAt,
        createdAt: '2026-07-29T12:00:01.000Z',
      ),
    ),
  );
}

FinanceOperationCommitCommand _operationCommand() {
  final draft = FinanceOperationDraft.fromJson(<String, Object?>{
    'schemaVersion': '1',
    'commandId': '11111111-1111-4111-8111-111111111111',
    'type': 'expense',
    'amount': '35.00',
    'currency': 'EUR',
    'accountId': '22222222-2222-4222-8222-222222222222',
    'category': 'groceries',
    'merchant': 'Synthetic shop',
    'capturedAt': '2026-07-29T10:00:00.000Z',
    'capturedTimezone': 'Europe/Berlin',
    'sourceExpression': null,
    'dateResolverVersion': 'calendar-relative-v1',
    'occurredOn': '2026-07-29',
    'occurredAt': null,
    'source': 'manual_text',
  });
  return FinanceOperationCommitCommand.fromReview(
    review: FinanceOperationNeedsConfirmation(
      draft: draft,
      draftHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    confirmedAt: DateTime.utc(2026, 7, 29, 12),
  );
}

FinanceEntryFailureResult<FinanceOperationCommit> _failedOperation(
  FinanceEntryFailureKind kind,
) => FinanceEntryFailureResult<FinanceOperationCommit>(
  FinanceEntryFailure(kind: kind, requestId: 'req_test_operation_failure'),
);

FinanceEntrySuccess<FinanceOperationCommit> _successOperation(
  FinanceOperationCommitCommand command, {
  required bool idempotentReplay,
}) {
  final draft = command.review.draft;
  return FinanceEntrySuccess<FinanceOperationCommit>(
    requestId: 'req_test_operation_success',
    value: FinanceOperationCommit(
      idempotentReplay: idempotentReplay,
      operation: CommittedFinanceOperation(
        operationId: '33333333-3333-4333-8333-333333333333',
        userId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        commandId: draft.commandId,
        type: draft.type,
        amount: draft.amount,
        currency: draft.currency,
        accountId: draft.accountId,
        category: draft.category,
        categoryId: null,
        merchant: draft.merchant,
        capturedAt: draft.capturedAt,
        capturedTimezone: draft.capturedTimezone,
        sourceExpression: draft.sourceExpression,
        dateResolverVersion: draft.dateResolverVersion,
        occurredOn: draft.occurredOn,
        occurredAt: draft.occurredAt,
        source: draft.source,
        confirmedAt: command.confirmedAt,
        createdAt: '2026-07-29T12:00:01.000Z',
      ),
    ),
  );
}

class _ListApi implements FinanceEntryApiClient {
  @override
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String accessToken,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String accessToken,
    required String savePath,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String accessToken,
    required String savePath,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String accessToken,
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer({
    required String accessToken,
    required FinanceTransferDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer({
    required String accessToken,
    required FinanceTransferCommitCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone({
    required String accessToken,
    required FinanceTimezoneCommand command,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets({
    required String accessToken,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget({
    required String accessToken,
    required SetBudgetCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget({
    required String accessToken,
    required String budgetId,
    required RemoveBudgetCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate({
    required String accessToken,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String accessToken,
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence({
    required String accessToken,
    required PlannedCostRecurrenceDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences({required String accessToken}) =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence({
    required String accessToken,
    required String recurrenceId,
    required EndPlannedCostRecurrenceCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<OperationCorrected>> correctOperation({
    required String accessToken,
    required OperationCorrectionCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<OperationRemoved>> removeOperation({
    required String accessToken,
    required OperationRemovalCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories({
    required String accessToken,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories({
    required String accessToken,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics({
    required String accessToken,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required String accessToken,
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<UserProfile>> readProfile({
    required String accessToken,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String accessToken,
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords({
    required String accessToken,
    required String categoryId,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords({
    required String accessToken,
    required String categoryId,
    required List<String> keywords,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required String accessToken,
    required int limit,
    String? cursor,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory({
    required String accessToken,
    required CreateCategoryCommand command,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory({
    required String accessToken,
    required String categoryId,
    required RenameCategoryCommand command,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory({
    required String accessToken,
    required String categoryId,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory({
    required String accessToken,
    required String categoryId,
  }) => throw UnimplementedError();
  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal({
    required String accessToken,
    required SavingsGoalDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals({
    required String accessToken,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution({
    required String accessToken,
    required String goalId,
    required GoalContributionCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal({
    required String accessToken,
    required String goalId,
    required FinanceGoalCancelCommand command,
  }) => throw UnimplementedError();
  _ListApi(List<FinanceEntryResult<FinanceAccountSetup>> results)
    : _results = List.of(results);

  final List<FinanceEntryResult<FinanceAccountSetup>> _results;
  final List<String> tokens = [];

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts({
    required String accessToken,
  }) async {
    tokens.add(accessToken);
    return _results.removeAt(0);
  }

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount({
    required String accessToken,
    required FinanceAccountCommitCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost({
    required String accessToken,
    required PlannedCostDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts({
    required String accessToken,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost({
    required String accessToken,
    required String plannedCostId,
    required PlannedCostTransitionCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline({
    required String accessToken,
    required FinanceBaselineDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline({
    required String accessToken,
    required FinanceBaselineCommitCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation({
    required String accessToken,
    required FinanceOperationCommitCommand command,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount({
    required String accessToken,
    required FinanceAccountDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation({
    required String accessToken,
    required FinanceOperationDraft draft,
  }) => throw UnimplementedError();
}

final class _OperationApi extends _ListApi {
  _OperationApi(List<FinanceEntryResult<FinanceOperationCommit>> results)
    : _operationResults = List.of(results),
      super(const []);

  final List<FinanceEntryResult<FinanceOperationCommit>> _operationResults;
  final List<FinanceOperationCommitCommand> commands = [];

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation({
    required String accessToken,
    required FinanceOperationCommitCommand command,
  }) async {
    tokens.add(accessToken);
    commands.add(command);
    return _operationResults.removeAt(0);
  }
}

final class _BaselineApi extends _ListApi {
  _BaselineApi({
    List<FinanceEntryResult<FinanceBaselineEvaluation>> evaluationResults =
        const [],
    List<FinanceEntryResult<FinanceBaselineCommit>> commitResults = const [],
  }) : _evaluationResults = List.of(evaluationResults),
       _commitResults = List.of(commitResults),
       super(const []);

  final List<FinanceEntryResult<FinanceBaselineEvaluation>> _evaluationResults;
  final List<FinanceEntryResult<FinanceBaselineCommit>> _commitResults;
  final List<FinanceBaselineDraft> evaluationDrafts = [];
  final List<FinanceBaselineCommitCommand> commitCommands = [];

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline({
    required String accessToken,
    required FinanceBaselineDraft draft,
  }) async {
    tokens.add(accessToken);
    evaluationDrafts.add(draft);
    return _evaluationResults.removeAt(0);
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline({
    required String accessToken,
    required FinanceBaselineCommitCommand command,
  }) async {
    tokens.add(accessToken);
    commitCommands.add(command);
    return _commitResults.removeAt(0);
  }
}

final class _CompletingListApi extends _ListApi {
  _CompletingListApi(
    this.completer, [
    List<FinanceEntryResult<FinanceAccountSetup>> subsequent = const [],
  ]) : _subsequent = List.of(subsequent),
       super(const []);

  final Completer<FinanceEntryResult<FinanceAccountSetup>> completer;
  final List<FinanceEntryResult<FinanceAccountSetup>> _subsequent;
  bool _firstRequest = true;

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts({
    required String accessToken,
  }) {
    tokens.add(accessToken);
    if (_firstRequest) {
      _firstRequest = false;
      return completer.future;
    }
    return Future.value(_subsequent.removeAt(0));
  }
}

final class _SessionStore implements AuthSessionStore {
  _SessionStore(this.session);

  AuthSession? session;

  @override
  Future<AuthSession?> readAuthSession() async => session;

  @override
  Future<HomeSessionSnapshot?> readSession() async {
    final value = session;
    if (value == null) return null;
    return HomeSessionSnapshot(
      accessToken: value.accessToken,
      cacheScopeId: value.cacheScopeId,
      revision: value.revision,
    );
  }

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<bool> clearSessionForAccountScope(String expectedCacheScopeId) async {
    if (session?.cacheScopeId != expectedCacheScopeId) return false;
    session = null;
    return true;
  }

  @override
  Future<bool> clearSessionIfCurrent(AuthSession expectedSession) async {
    if (!expectedSession.isSameSession(session)) return false;
    session = null;
    return true;
  }

  @override
  Future<AuthSession> rotateAuthenticatedSession({
    required AuthTokenBundle tokens,
    required AuthSession expectedSession,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> saveAuthenticatedSession(AuthTokenBundle tokens) =>
      throw UnimplementedError();
}

final class _FirstReadGatedSessionStore extends _SessionStore {
  _FirstReadGatedSessionStore(super.session);

  final firstReadStarted = Completer<void>();
  final _firstReadRelease = Completer<void>();
  var _readCalls = 0;

  void releaseFirstRead() => _firstReadRelease.complete();

  @override
  Future<AuthSession?> readAuthSession() async {
    _readCalls += 1;
    if (_readCalls == 1) {
      firstReadStarted.complete();
      await _firstReadRelease.future;
    }
    return session;
  }
}
