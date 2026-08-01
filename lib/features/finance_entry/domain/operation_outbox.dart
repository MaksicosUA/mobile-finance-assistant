import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'finance_entry_models.dart';
import 'finance_entry_result.dart';

/// Local delivery state. It is deliberately separate from the authoritative
/// financial operation status owned by Finance Core.
enum OperationOutboxState {
  draft,
  awaitingConfirmation,
  pending,
  syncing,
  retryableFailure,
  permanentFailure,
  synced,
}

extension OperationOutboxStateWire on OperationOutboxState {
  String get wireName => switch (this) {
    OperationOutboxState.draft => 'draft',
    OperationOutboxState.awaitingConfirmation => 'awaiting_confirmation',
    OperationOutboxState.pending => 'pending',
    OperationOutboxState.syncing => 'syncing',
    OperationOutboxState.retryableFailure => 'retryable_failure',
    OperationOutboxState.permanentFailure => 'permanent_failure',
    OperationOutboxState.synced => 'synced',
  };

  static OperationOutboxState parse(String value) => switch (value) {
    'draft' => OperationOutboxState.draft,
    'awaiting_confirmation' => OperationOutboxState.awaitingConfirmation,
    'pending' => OperationOutboxState.pending,
    'syncing' => OperationOutboxState.syncing,
    'retryable_failure' => OperationOutboxState.retryableFailure,
    'permanent_failure' => OperationOutboxState.permanentFailure,
    'synced' => OperationOutboxState.synced,
    _ => throw const FormatException('Unsupported outbox state.'),
  };
}

/// Safe, bounded local codes. These values may be stored as clear SQLite
/// metadata; they must never include server text, request text, or PII.
enum OperationOutboxErrorCode {
  interrupted,
  offline,
  timeout,
  serviceUnavailable,
  malformedResponse,
  ambiguousResult,
  authenticationRequired,
  sessionChanged,
  unauthorized,
  invalidCommand,
  commandConflict,
  financeRejected,
  securityBlocked,
  responseScopeMismatch,
  locked,
  corruptPayload,
  capacityExceeded,
  storageUnavailable,
}

extension OperationOutboxErrorCodeWire on OperationOutboxErrorCode {
  String get wireName => switch (this) {
    OperationOutboxErrorCode.interrupted => 'interrupted',
    OperationOutboxErrorCode.offline => 'offline',
    OperationOutboxErrorCode.timeout => 'timeout',
    OperationOutboxErrorCode.serviceUnavailable => 'service_unavailable',
    OperationOutboxErrorCode.malformedResponse => 'malformed_response',
    OperationOutboxErrorCode.ambiguousResult => 'ambiguous_result',
    OperationOutboxErrorCode.authenticationRequired =>
      'authentication_required',
    OperationOutboxErrorCode.sessionChanged => 'session_changed',
    OperationOutboxErrorCode.unauthorized => 'unauthorized',
    OperationOutboxErrorCode.invalidCommand => 'invalid_command',
    OperationOutboxErrorCode.commandConflict => 'command_conflict',
    OperationOutboxErrorCode.financeRejected => 'finance_rejected',
    OperationOutboxErrorCode.securityBlocked => 'security_blocked',
    OperationOutboxErrorCode.responseScopeMismatch => 'response_scope_mismatch',
    OperationOutboxErrorCode.locked => 'locked',
    OperationOutboxErrorCode.corruptPayload => 'corrupt_payload',
    OperationOutboxErrorCode.capacityExceeded => 'capacity_exceeded',
    OperationOutboxErrorCode.storageUnavailable => 'storage_unavailable',
  };

  static OperationOutboxErrorCode parse(String value) => switch (value) {
    'interrupted' => OperationOutboxErrorCode.interrupted,
    'offline' => OperationOutboxErrorCode.offline,
    'timeout' => OperationOutboxErrorCode.timeout,
    'service_unavailable' => OperationOutboxErrorCode.serviceUnavailable,
    'malformed_response' => OperationOutboxErrorCode.malformedResponse,
    'ambiguous_result' => OperationOutboxErrorCode.ambiguousResult,
    'authentication_required' =>
      OperationOutboxErrorCode.authenticationRequired,
    'session_changed' => OperationOutboxErrorCode.sessionChanged,
    'unauthorized' => OperationOutboxErrorCode.unauthorized,
    'invalid_command' => OperationOutboxErrorCode.invalidCommand,
    'command_conflict' => OperationOutboxErrorCode.commandConflict,
    'finance_rejected' => OperationOutboxErrorCode.financeRejected,
    'security_blocked' => OperationOutboxErrorCode.securityBlocked,
    'response_scope_mismatch' => OperationOutboxErrorCode.responseScopeMismatch,
    'locked' => OperationOutboxErrorCode.locked,
    'corrupt_payload' => OperationOutboxErrorCode.corruptPayload,
    'capacity_exceeded' => OperationOutboxErrorCode.capacityExceeded,
    'storage_unavailable' => OperationOutboxErrorCode.storageUnavailable,
    _ => throw const FormatException('Unsupported outbox error code.'),
  };
}

enum OperationOutboxFailureDisposition {
  retryable,
  authenticationPaused,
  permanent,
}

/// A persisted failure in this set locks delivery for the whole local outbox.
/// Continuing with another command could cross a broken trust/account boundary.
const operationOutboxSecurityLockCodes = <OperationOutboxErrorCode>{
  OperationOutboxErrorCode.securityBlocked,
  OperationOutboxErrorCode.responseScopeMismatch,
  OperationOutboxErrorCode.corruptPayload,
};

@immutable
final class OperationOutboxFailureClassification {
  const OperationOutboxFailureClassification({
    required this.disposition,
    required this.code,
  });

  final OperationOutboxFailureDisposition disposition;
  final OperationOutboxErrorCode code;
}

@immutable
final class OperationOutboxRecord {
  OperationOutboxRecord({
    required this.localId,
    required this.principalScopeId,
    required this.financeAccountId,
    required this.commandId,
    required this.state,
    required this.transitionSequence,
    required this.createdAtUtc,
    required this.stateChangedAtUtc,
    required this.attemptCount,
    required this.confirmedCommand,
    this.homeConvergencePending = false,
    this.lastAttemptAtUtc,
    this.nextAttemptAtUtc,
    this.syncStartedAtUtc,
    this.syncedAtUtc,
    this.lastErrorCode,
    this.serverOperationId,
  }) {
    if (localId.isEmpty ||
        principalScopeId.isEmpty ||
        financeAccountId.isEmpty ||
        commandId.isEmpty ||
        transitionSequence < 0 ||
        attemptCount < 0 ||
        !createdAtUtc.isUtc ||
        !stateChangedAtUtc.isUtc ||
        !<DateTime?>[
          lastAttemptAtUtc,
          nextAttemptAtUtc,
          syncStartedAtUtc,
          syncedAtUtc,
        ].whereType<DateTime>().every((value) => value.isUtc)) {
      throw const FormatException('Invalid outbox record metadata.');
    }
    if (state == OperationOutboxState.synced) {
      if (confirmedCommand != null ||
          serverOperationId == null ||
          syncedAtUtc == null) {
        throw const FormatException('Invalid synced outbox tombstone.');
      }
    } else if (confirmedCommand == null ||
        serverOperationId != null ||
        homeConvergencePending) {
      throw const FormatException('Invalid active outbox payload.');
    }
    if (commandId != (confirmedCommand?.review.draft.commandId ?? commandId)) {
      throw const FormatException('Outbox command identity mismatch.');
    }
  }

  final String localId;
  final String principalScopeId;
  final String financeAccountId;
  final String commandId;
  final OperationOutboxState state;
  final int transitionSequence;
  final DateTime createdAtUtc;
  final DateTime stateChangedAtUtc;
  final DateTime? lastAttemptAtUtc;
  final DateTime? nextAttemptAtUtc;
  final DateTime? syncStartedAtUtc;
  final DateTime? syncedAtUtc;
  final int attemptCount;
  final OperationOutboxErrorCode? lastErrorCode;
  final FinanceOperationCommitCommand? confirmedCommand;
  final String? serverOperationId;
  final bool homeConvergencePending;

  bool get isActive => state != OperationOutboxState.synced;
}

@immutable
final class OperationOutboxEnqueueResult {
  const OperationOutboxEnqueueResult({
    required this.record,
    required this.wasExisting,
  });

  final OperationOutboxRecord record;
  final bool wasExisting;
}

final class OperationOutboxException implements Exception {
  const OperationOutboxException(this.code, [this.safeMessage]);

  final OperationOutboxErrorCode code;
  final String? safeMessage;

  @override
  String toString() => safeMessage == null
      ? 'OperationOutboxException(${code.wireName})'
      : 'OperationOutboxException(${code.wireName}): $safeMessage';
}

/// Maps a typed transport/domain failure to a local delivery decision.
///
/// The string-based switch deliberately fails safe for future additive failure
/// kinds. Unknown and user-cancelled results are ambiguous and remain retryable.
OperationOutboxFailureClassification classifyOperationOutboxFailure(
  FinanceEntryFailure failure,
) => switch (failure.kind.name) {
  'invalidInput' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.permanent,
    code: OperationOutboxErrorCode.invalidCommand,
  ),
  'conflict' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.permanent,
    code: OperationOutboxErrorCode.commandConflict,
  ),
  'rejected' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.permanent,
    code: OperationOutboxErrorCode.financeRejected,
  ),
  'securityFailure' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.permanent,
    code: OperationOutboxErrorCode.securityBlocked,
  ),
  'unauthenticated' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.authenticationPaused,
    code: OperationOutboxErrorCode.authenticationRequired,
  ),
  'sessionChanged' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.authenticationPaused,
    code: OperationOutboxErrorCode.sessionChanged,
  ),
  'interrupted' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.retryable,
    code: OperationOutboxErrorCode.interrupted,
  ),
  'unauthorized' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.authenticationPaused,
    code: OperationOutboxErrorCode.unauthorized,
  ),
  'offline' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.retryable,
    code: OperationOutboxErrorCode.offline,
  ),
  'timeout' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.retryable,
    code: OperationOutboxErrorCode.timeout,
  ),
  'serviceUnavailable' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.retryable,
    code: OperationOutboxErrorCode.serviceUnavailable,
  ),
  'malformedResponse' => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.retryable,
    code: OperationOutboxErrorCode.malformedResponse,
  ),
  _ => const OperationOutboxFailureClassification(
    disposition: OperationOutboxFailureDisposition.retryable,
    code: OperationOutboxErrorCode.ambiguousResult,
  ),
};

/// Persisted bounded exponential backoff with a deterministic injectable jitter
/// sample in [0, 1]. Attempt one waits around two seconds and the final delay
/// never exceeds five minutes.
Duration operationOutboxRetryDelay({
  required int attemptCount,
  required double jitterUnit,
}) {
  if (attemptCount < 1) {
    throw ArgumentError.value(
      attemptCount,
      'attemptCount',
      'Must be positive.',
    );
  }
  if (!jitterUnit.isFinite || jitterUnit < 0 || jitterUnit > 1) {
    throw ArgumentError.value(jitterUnit, 'jitterUnit', 'Must be in [0, 1].');
  }
  final baseSeconds = attemptCount >= 9 ? 300 : 2 * (1 << (attemptCount - 1));
  final factor = 0.8 + (0.4 * jitterUnit);
  final jitteredMilliseconds = (baseSeconds * factor * 1000).round();
  return Duration(milliseconds: math.min(300000, jitteredMilliseconds));
}
