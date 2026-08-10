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

  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost(
    PlannedCostDraft draft,
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
