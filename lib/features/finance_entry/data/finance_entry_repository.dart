import '../../auth/data/auth_repository.dart';
import '../../auth/data/auth_session_store.dart';
import '../../auth/domain/auth_session.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_api.dart';

typedef FinanceSessionRefresh = Future<AuthRefreshResult> Function();
typedef FinanceCommitPreflight = FinanceEntryFailureKind? Function();

abstract interface class FinanceEntryRepositoryClient {
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts();

  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  );

  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  );

  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  );

  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  );

  /// Redraw where this account's months fall (ADR 0028).
  ///
  /// No commit preflight and no delivery outbox: nothing here moves money, so
  /// there is no accepted financial write to replay (ADR 0009).
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone(
    FinanceTimezoneCommand command,
  );

  /// Decide a movement between two wallets without moving anything (ADR 0029).
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer(
    FinanceTransferDraft draft,
  );

  /// Move it, exactly once for one command identity.
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer(
    FinanceTransferCommitCommand command,
  );

  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  );

  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts();

  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  );

  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence(PlannedCostRecurrenceDraft draft);

  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences();

  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence(
    String recurrenceId,
    EndPlannedCostRecurrenceCommand command,
  );

  Future<FinanceEntryResult<FinanceCategoryList>> listCategories();

  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  });

  Future<FinanceEntryResult<OperationCorrected>> correctOperation(
    OperationCorrectionCommand command,
  );

  Future<FinanceEntryResult<OperationRemoved>> removeOperation(
    OperationRemovalCommand command,
  );

  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics();

  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  });

  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets();

  Future<FinanceEntryResult<BudgetWritten>> setBudget(SetBudgetCommand command);

  Future<FinanceEntryResult<BudgetWritten>> removeBudget(
    String budgetId,
    RemoveBudgetCommand command,
  );

  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate();

  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String savePath,
    required void Function(int received, int total) onProgress,
  });

  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String savePath,
  });

  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String savePath,
  });

  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String password,
  });

  Future<FinanceEntryResult<UserProfile>> readProfile();

  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  });

  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  });

  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories();

  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory(
    CreateCategoryCommand command,
  );

  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory(
    String categoryId,
    RenameCategoryCommand command,
  );

  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory(
    String categoryId,
  );

  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory(
    String categoryId,
  );

  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords(
    String categoryId,
  );

  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords(
    String categoryId,
    List<String> keywords,
  );

  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal(
    SavingsGoalDraft draft,
  );

  Future<FinanceEntryResult<SavingsGoalList>> listGoals();

  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution(
    String goalId,
    GoalContributionCommand command,
  );

  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal(
    String goalId,
    FinanceGoalCancelCommand command,
  );

  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  );

  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  });
}

/// Authenticated in-memory orchestration for Finance entry requests.
///
/// Credentials are read from the shared secure session store for each request;
/// no token, draft, amount, or server response is retained by this repository.
final class FinanceEntryRepository implements FinanceEntryRepositoryClient {
  FinanceEntryRepository({
    required FinanceEntryApiClient api,
    required AuthSessionStore sessionStore,
    required FinanceSessionRefresh refreshSession,
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _api = api,
       // ignore: prefer_initializing_formals
       _sessionStore = sessionStore,
       // ignore: prefer_initializing_formals
       _refreshSession = refreshSession;

  final FinanceEntryApiClient _api;
  final AuthSessionStore _sessionStore;
  final FinanceSessionRefresh _refreshSession;

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() {
    return _authorized(
      (accessToken) => _api.listAccounts(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) {
    return _authorized(
      (accessToken) =>
          _api.evaluateAccount(accessToken: accessToken, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) {
    return _authorized(
      (accessToken) =>
          _api.commitAccount(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) {
    return _authorized(
      (accessToken) =>
          _api.evaluateBaseline(accessToken: accessToken, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) {
    return _authorized(
      (accessToken) =>
          _api.commitBaseline(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone(
    FinanceTimezoneCommand command,
  ) {
    return _authorized(
      (accessToken) =>
          _api.correctTimezone(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer(
    FinanceTransferDraft draft,
  ) {
    return _authorized(
      (accessToken) =>
          _api.evaluateTransfer(accessToken: accessToken, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer(
    FinanceTransferCommitCommand command,
  ) {
    // No delivery outbox: a transfer creates no income and no expense, so it
    // is not the accepted financial write ADR 0009 exists for.
    return _authorized(
      (accessToken) =>
          _api.commitTransfer(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
  ) {
    // A plan is a forecast, so it needs no commit preflight: nothing here can
    // change the authoritative balance (ADR 0018).
    return _authorized(
      (accessToken) =>
          _api.createPlannedCost(accessToken: accessToken, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts() {
    return _authorized(
      (accessToken) => _api.listPlannedCosts(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost(
    String plannedCostId,
    PlannedCostTransitionCommand command,
  ) {
    return _authorized(
      (accessToken) => _api.transitionPlannedCost(
        accessToken: accessToken,
        plannedCostId: plannedCostId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence(PlannedCostRecurrenceDraft draft) {
    // Like a one-off plan, a rule is a forecast and needs no commit preflight:
    // nothing it writes changes the authoritative balance (ADR 0018, 0025).
    return _authorized(
      (accessToken) => _api.createPlannedCostRecurrence(
        accessToken: accessToken,
        draft: draft,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences() {
    return _authorized(
      (accessToken) =>
          _api.listPlannedCostRecurrences(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence(
    String recurrenceId,
    EndPlannedCostRecurrenceCommand command,
  ) {
    return _authorized(
      (accessToken) => _api.endPlannedCostRecurrence(
        accessToken: accessToken,
        recurrenceId: recurrenceId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories() {
    return _authorized(
      (accessToken) => _api.listCategories(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required int limit,
    String? cursor,
  }) {
    return _authorized(
      (accessToken) => _api.listOperations(
        accessToken: accessToken,
        limit: limit,
        cursor: cursor,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<OperationCorrected>> correctOperation(
    OperationCorrectionCommand command,
  ) {
    return _authorized(
      (accessToken) =>
          _api.correctOperation(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<OperationRemoved>> removeOperation(
    OperationRemovalCommand command,
  ) {
    return _authorized(
      (accessToken) =>
          _api.removeOperation(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics() {
    return _authorized(
      (accessToken) => _api.readAnalytics(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords(
    String categoryId,
  ) {
    return _authorized(
      (accessToken) => _api.listCategoryKeywords(
        accessToken: accessToken,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords(
    String categoryId,
    List<String> keywords,
  ) {
    // A keyword is a label, not money: no commit preflight (ADR 0020).
    return _authorized(
      (accessToken) => _api.replaceCategoryKeywords(
        accessToken: accessToken,
        categoryId: categoryId,
        keywords: keywords,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  }) {
    return _authorized(
      (accessToken) => _api.readAnalyticsWindow(
        accessToken: accessToken,
        period: period,
        from: from,
        to: to,
        accountId: accountId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets() {
    return _authorized(
      (accessToken) => _api.readBudgets(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget(
    SetBudgetCommand command,
  ) {
    return _authorized(
      (accessToken) =>
          _api.setBudget(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget(
    String budgetId,
    RemoveBudgetCommand command,
  ) {
    return _authorized(
      (accessToken) => _api.removeBudget(
        accessToken: accessToken,
        budgetId: budgetId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate() {
    return _authorized(
      (accessToken) => _api.readAppUpdate(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) {
    return _authorized(
      (accessToken) => _api.downloadAppRelease(
        accessToken: accessToken,
        savePath: savePath,
        onProgress: onProgress,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String savePath,
  }) {
    return _authorized(
      (accessToken) => _api.downloadAccountExport(
        accessToken: accessToken,
        savePath: savePath,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String savePath,
  }) {
    return _authorized(
      (accessToken) => _api.downloadOperationsTable(
        accessToken: accessToken,
        savePath: savePath,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String password,
  }) {
    // Not retried after a refresh: a password is asked of a person once, and a
    // replayed erasure request is not something to do on their behalf.
    return _authorized(
      (accessToken) => _api.requestAccountDeletion(
        accessToken: accessToken,
        password: password,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<UserProfile>> readProfile() {
    return _authorized(
      (accessToken) => _api.readProfile(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) {
    // Reading a sentence writes nothing, so this needs none of the commit
    // preflight a financial command does (ADR 0022).
    return _authorized(
      (accessToken) => _api.parseOperationText(
        accessToken: accessToken,
        text: text,
        capturedAt: capturedAt,
        capturedTimezone: capturedTimezone,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) {
    return _authorized(
      (accessToken) => _api.parseTransferText(
        accessToken: accessToken,
        text: text,
        capturedAt: capturedAt,
        capturedTimezone: capturedTimezone,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories() {
    return _authorized(
      (accessToken) => _api.listManagedCategories(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory(
    CreateCategoryCommand command,
  ) {
    // A category is a label, so none of these writes need the commit preflight
    // a financial command does: nothing here can change a balance (ADR 0020).
    return _authorized(
      (accessToken) =>
          _api.createCategory(accessToken: accessToken, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory(
    String categoryId,
    RenameCategoryCommand command,
  ) {
    return _authorized(
      (accessToken) => _api.renameCategory(
        accessToken: accessToken,
        categoryId: categoryId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory(
    String categoryId,
  ) {
    return _authorized(
      (accessToken) => _api.archiveCategory(
        accessToken: accessToken,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory(
    String categoryId,
  ) {
    return _authorized(
      (accessToken) => _api.restoreCategory(
        accessToken: accessToken,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal(
    SavingsGoalDraft draft,
  ) {
    // A goal and its ledger are earmarks, so they need no commit preflight:
    // nothing here can change the authoritative balance (ADR 0019).
    return _authorized(
      (accessToken) => _api.createGoal(accessToken: accessToken, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals() {
    return _authorized(
      (accessToken) => _api.listGoals(accessToken: accessToken),
    );
  }

  @override
  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution(
    String goalId,
    GoalContributionCommand command,
  ) {
    return _authorized(
      (accessToken) => _api.recordGoalContribution(
        accessToken: accessToken,
        goalId: goalId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal(
    String goalId,
    FinanceGoalCancelCommand command,
  ) {
    return _authorized(
      (accessToken) => _api.cancelGoal(
        accessToken: accessToken,
        goalId: goalId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) {
    return _authorized(
      (accessToken) =>
          _api.evaluateOperation(accessToken: accessToken, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) {
    return _authorized(
      (accessToken) =>
          _api.commitOperation(accessToken: accessToken, command: command),
      expectedPrincipalScopeId: expectedPrincipalScopeId,
      expectedSessionRevision: expectedSessionRevision,
      preflight: preflight,
    );
  }

  Future<FinanceEntryResult<T>> _authorized<T>(
    Future<FinanceEntryResult<T>> Function(String accessToken) request, {
    String? expectedPrincipalScopeId,
    String? expectedSessionRevision,
    FinanceCommitPreflight? preflight,
  }) async {
    final initial = await _readSession();
    if (initial == null) {
      return _repositoryFailure(FinanceEntryFailureKind.unauthenticated);
    }

    final initialBlock = _requestBoundaryFailure(
      initial,
      expectedPrincipalScopeId: expectedPrincipalScopeId,
      expectedSessionRevision: expectedSessionRevision,
      preflight: preflight,
    );
    if (initialBlock != null) return _repositoryFailure(initialBlock);
    // No await may be inserted between the synchronous preflight above and
    // starting the API Future. Account-change hooks advance their epoch before
    // replacing secure credentials, so the caller can close that race here.
    final first = await request(initial.accessToken);
    final continuityAfterFirst = await _sessionContinuity(initial);
    if (continuityAfterFirst == _SessionContinuity.changed) {
      return _repositoryFailure(FinanceEntryFailureKind.sessionChanged);
    }
    if (!_isUnauthorized(first)) return first;

    if (continuityAfterFirst == _SessionContinuity.exact) {
      AuthRefreshResult refreshResult;
      try {
        refreshResult = await _refreshSession();
      } on Object {
        return _repositoryFailure(FinanceEntryFailureKind.serviceUnavailable);
      }
      switch (refreshResult) {
        case AuthRefreshResult.invalid:
          return _repositoryFailure(FinanceEntryFailureKind.unauthorized);
        case AuthRefreshResult.transientFailure:
          return _repositoryFailure(FinanceEntryFailureKind.serviceUnavailable);
        case AuthRefreshResult.sessionChanged:
          return _repositoryFailure(FinanceEntryFailureKind.sessionChanged);
        case AuthRefreshResult.recovered:
          break;
      }
    }

    final replacement = await _readSession();
    if (replacement == null) {
      return _repositoryFailure(FinanceEntryFailureKind.unauthorized);
    }
    if (!_isSameAccountSession(initial, replacement)) {
      return _repositoryFailure(FinanceEntryFailureKind.sessionChanged);
    }

    final retryBlock = _requestBoundaryFailure(
      replacement,
      expectedPrincipalScopeId: expectedPrincipalScopeId,
      expectedSessionRevision: expectedSessionRevision,
      preflight: preflight,
    );
    if (retryBlock != null) return _repositoryFailure(retryBlock);
    // Keep this call adjacent to the synchronous guard for the same reason as
    // the first request above. It also protects the post-refresh retry.
    final retry = await request(replacement.accessToken);
    if (await _sessionContinuity(replacement) == _SessionContinuity.changed) {
      return _repositoryFailure(FinanceEntryFailureKind.sessionChanged);
    }
    return retry;
  }

  Future<AuthSession?> _readSession() async {
    try {
      return await _sessionStore.readAuthSession();
    } on Object {
      return null;
    }
  }

  Future<_SessionContinuity> _sessionContinuity(AuthSession expected) async {
    final current = await _readSession();
    if (expected.isSameSession(current)) return _SessionContinuity.exact;
    if (current != null && _isSameAccountSession(expected, current)) {
      return _SessionContinuity.sameAccountRotated;
    }
    return _SessionContinuity.changed;
  }
}

FinanceEntryFailureKind? _requestBoundaryFailure(
  AuthSession session, {
  required String? expectedPrincipalScopeId,
  required String? expectedSessionRevision,
  required FinanceCommitPreflight? preflight,
}) {
  final guarded =
      expectedPrincipalScopeId != null ||
      expectedSessionRevision != null ||
      preflight != null;
  if (!guarded) return null;
  if (expectedPrincipalScopeId == null ||
      expectedSessionRevision == null ||
      preflight == null ||
      session.cacheScopeId != expectedPrincipalScopeId ||
      session.revision != expectedSessionRevision) {
    return FinanceEntryFailureKind.sessionChanged;
  }
  try {
    return preflight();
  } on Object {
    return FinanceEntryFailureKind.sessionChanged;
  }
}

enum _SessionContinuity { exact, sameAccountRotated, changed }

bool _isUnauthorized<T>(FinanceEntryResult<T> result) {
  return result is FinanceEntryFailureResult<T> &&
      result.failure.kind == FinanceEntryFailureKind.unauthorized;
}

bool _isSameAccountSession(AuthSession before, AuthSession after) {
  return before.cacheScopeId == after.cacheScopeId &&
      before.revision == after.revision;
}

FinanceEntryFailureResult<T> _repositoryFailure<T>(
  FinanceEntryFailureKind kind,
) {
  return FinanceEntryFailureResult<T>(
    FinanceEntryFailure(kind: kind, requestId: 'req_local_finance_session'),
  );
}
