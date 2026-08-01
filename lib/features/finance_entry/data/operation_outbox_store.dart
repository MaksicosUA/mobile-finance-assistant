import '../domain/finance_entry_models.dart';
import '../domain/operation_outbox.dart';

abstract interface class OperationOutboxStore {
  /// Persists the exact confirmed server-canonical command before any commit
  /// request. An exact duplicate returns the existing row; a different payload
  /// for the same command identity fails closed.
  Future<OperationOutboxEnqueueResult> enqueueConfirmed({
    required String principalScopeId,
    required FinanceOperationCommitCommand command,
  });

  /// Atomically claims the oldest eligible row for one authenticated principal.
  Future<OperationOutboxRecord?> claimNextDue({
    required String principalScopeId,
  });

  Future<OperationOutboxRecord> markRetryableFailure({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
    DateTime? nextAttemptAtUtc,
  });

  Future<OperationOutboxRecord> markAuthenticationPaused({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
  });

  Future<OperationOutboxRecord> markPermanentFailure({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
  });

  Future<OperationOutboxRecord> markSynced({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required String serverOperationId,
  });

  /// Durably acknowledges that Home was refreshed after this accepted write.
  /// Repeating the transition is safe and never resends the Finance command.
  Future<OperationOutboxRecord> markHomeConverged({
    required String localId,
    required String principalScopeId,
    required String commandId,
  });

  /// Makes auth-paused rows eligible again for the same principal only.
  Future<void> resumeAuthentication({required String principalScopeId});

  /// Makes transport-retryable rows immediately eligible. Permanent and
  /// authentication-paused commands remain untouched.
  Future<void> retryNow({required String principalScopeId});

  Future<List<OperationOutboxRecord>> readForPrincipal({
    required String principalScopeId,
  });

  /// Returns the number of stale `syncing` rows recovered after process death.
  Future<int> recoverInterrupted();

  /// Returns the number of bounded, expired synced tombstones removed.
  Future<int> purgeExpiredSynced();

  Future<void> close();
}
