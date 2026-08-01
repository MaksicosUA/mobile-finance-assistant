import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_session_store.dart';
import '../../auth/domain/auth_session.dart';
import '../../home/application/home_controller.dart';
import '../data/operation_outbox_store.dart';
import '../data/sqlite_operation_outbox_store.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import '../domain/operation_outbox.dart';
import 'finance_entry_dependencies.dart';

typedef OperationSyncClock = DateTime Function();
typedef OperationSyncJitter = double Function();

final operationSyncClockProvider = Provider<OperationSyncClock>(
  (_) => DateTime.now,
);

final operationSyncJitterProvider = Provider<OperationSyncJitter>((_) {
  final random = Random.secure();
  return random.nextDouble;
});

final operationHomeConvergenceRetryDelayProvider = Provider<Duration>(
  (_) => const Duration(seconds: 30),
);

final operationOutboxStoreProvider = Provider<OperationOutboxStore>((ref) {
  final store = SqliteOperationOutboxStore();
  ref.onDispose(() => unawaited(store.close()));
  return store;
});

enum OperationSyncPhase {
  idle,
  synchronizing,
  homeConvergencePending,
  pending,
  retryableFailure,
  authenticationRequired,
  attentionRequired,
  locked,
}

@immutable
final class OperationSyncState {
  const OperationSyncState({
    required this.phase,
    this.activeCount = 0,
    this.permanentFailureCount = 0,
    this.homeConvergenceCount = 0,
    this.lastSafeError,
  });

  const OperationSyncState.idle()
    : phase = OperationSyncPhase.idle,
      activeCount = 0,
      permanentFailureCount = 0,
      homeConvergenceCount = 0,
      lastSafeError = null;

  final OperationSyncPhase phase;
  final int activeCount;
  final int permanentFailureCount;
  final int homeConvergenceCount;
  final OperationOutboxErrorCode? lastSafeError;

  bool get hasLocalOperations =>
      activeCount > 0 || permanentFailureCount > 0 || homeConvergenceCount > 0;
}

sealed class OperationDeliveryResult {
  const OperationDeliveryResult();
}

abstract interface class OperationDeliveryCoordinator {
  Future<OperationDeliveryResult> enqueueAndSynchronize({
    required String expectedPrincipalScopeId,
    required FinanceOperationCommitCommand command,
    void Function(FinanceOperationCommit commit)? onAccepted,
  });
}

final class OperationDeliveryAccepted extends OperationDeliveryResult {
  const OperationDeliveryAccepted({
    required this.commit,
    required this.homeStatus,
  });

  final FinanceOperationCommit commit;
  final AcceptedWriteHomeConvergenceResult homeStatus;
}

final class OperationDeliveryAlreadySynced extends OperationDeliveryResult {
  const OperationDeliveryAlreadySynced(this.serverOperationId);

  final String serverOperationId;
}

final class OperationDeliveryQueued extends OperationDeliveryResult {
  const OperationDeliveryQueued({required this.code});

  final OperationOutboxErrorCode? code;
}

final class OperationDeliveryPermanentFailure extends OperationDeliveryResult {
  const OperationDeliveryPermanentFailure(this.code);

  final OperationOutboxErrorCode code;
}

final class OperationDeliveryAuthenticationRequired
    extends OperationDeliveryResult {
  const OperationDeliveryAuthenticationRequired();
}

final class OperationDeliveryStorageFailure extends OperationDeliveryResult {
  const OperationDeliveryStorageFailure(this.code);

  final OperationOutboxErrorCode code;
}

final operationSyncControllerProvider =
    NotifierProvider<OperationSyncController, OperationSyncState>(
      OperationSyncController.new,
    );

final operationDeliveryCoordinatorProvider =
    Provider<OperationDeliveryCoordinator>(
      (ref) => ref.read(operationSyncControllerProvider.notifier),
    );

class OperationSyncController extends Notifier<OperationSyncState>
    implements OperationDeliveryCoordinator {
  static const int _maximumCandidatesPerDrain = 20;

  Future<void> _drainQueue = Future<void>.value();
  Timer? _retryTimer;
  var _generation = 0;
  var _foreground = false;
  var _initializationScheduled = false;
  final Map<String, void Function(FinanceOperationCommit commit)>
  _acceptanceCallbacks = {};

  OperationOutboxStore get _store => ref.read(operationOutboxStoreProvider);
  AuthSessionStore get _sessionStore => ref.read(authSessionStoreProvider);
  DateTime get _now => ref.read(operationSyncClockProvider)().toUtc();

  @override
  OperationSyncState build() {
    ref.watch(authAccountEpochProvider);
    final generation = ++_generation;
    _retryTimer?.cancel();
    ref.onDispose(() {
      _generation += 1;
      _retryTimer?.cancel();
      _acceptanceCallbacks.clear();
    });
    if (_initializationScheduled) {
      scheduleMicrotask(() async {
        if (generation == _generation && _foreground) {
          await synchronize(resumeAuthentication: true);
        }
      });
    } else {
      _initializationScheduled = true;
      scheduleMicrotask(() => _initialize(generation));
    }
    return const OperationSyncState.idle();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      _retryTimer?.cancel();
      return;
    }
    unawaited(synchronize(resumeAuthentication: true));
  }

  @override
  Future<OperationDeliveryResult> enqueueAndSynchronize({
    required String expectedPrincipalScopeId,
    required FinanceOperationCommitCommand command,
    void Function(FinanceOperationCommit commit)? onAccepted,
  }) async {
    final commandId = command.review.draft.commandId;
    FinanceOperationCommit? acceptedCommit;
    void accepted(FinanceOperationCommit commit) {
      acceptedCommit = commit;
      onAccepted?.call(commit);
    }

    _acceptanceCallbacks[commandId] = accepted;
    try {
      final result = await _enqueueAndSynchronize(
        expectedPrincipalScopeId: expectedPrincipalScopeId,
        command: command,
      );
      final durableAcceptance = acceptedCommit;
      if (durableAcceptance != null && result is! OperationDeliveryAccepted) {
        return OperationDeliveryAccepted(
          commit: durableAcceptance,
          homeStatus: AcceptedWriteHomeConvergenceResult.failed,
        );
      }
      return result;
    } finally {
      if (identical(_acceptanceCallbacks[commandId], accepted)) {
        _acceptanceCallbacks.remove(commandId);
      }
    }
  }

  Future<OperationDeliveryResult> _enqueueAndSynchronize({
    required String expectedPrincipalScopeId,
    required FinanceOperationCommitCommand command,
  }) async {
    final session = await _readSession();
    if (session == null ||
        session.cacheScopeId != expectedPrincipalScopeId ||
        command.review.draft.accountId == null) {
      return const OperationDeliveryAuthenticationRequired();
    }

    late final OperationOutboxEnqueueResult enqueued;
    try {
      enqueued = await _store.enqueueConfirmed(
        principalScopeId: expectedPrincipalScopeId,
        command: command,
      );
    } on OperationOutboxException catch (error) {
      _setStorageFailure(error.code);
      return _storageFailure(error.code);
    } on Object {
      return const OperationDeliveryStorageFailure(
        OperationOutboxErrorCode.storageUnavailable,
      );
    }

    final existing = enqueued.record;
    if (existing.state == OperationOutboxState.synced) {
      return OperationDeliveryAlreadySynced(existing.serverOperationId!);
    }
    if (existing.state == OperationOutboxState.permanentFailure) {
      return OperationDeliveryPermanentFailure(
        existing.lastErrorCode ?? OperationOutboxErrorCode.invalidCommand,
      );
    }

    late _DrainBatch batch;
    try {
      batch = await _serializedDrain(expectedPrincipalScopeId);
    } on OperationOutboxException catch (error) {
      _setStorageFailure(error.code);
      return _deliveryAfterDurableEnqueueFailure(error.code);
    } on Object {
      _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
      return const OperationDeliveryQueued(
        code: OperationOutboxErrorCode.storageUnavailable,
      );
    }
    var result = batch.results[command.review.draft.commandId];
    if (result != null) return result;

    // The enqueue can race with an already finishing serialized drain. Inspect
    // once and run one more bounded cycle if the new row is still eligible.
    late final OperationOutboxRecord? record;
    try {
      record = await _recordForCommand(
        principalScopeId: expectedPrincipalScopeId,
        commandId: command.review.draft.commandId,
      );
    } on OperationOutboxException catch (error) {
      _setStorageFailure(error.code);
      return _deliveryAfterDurableEnqueueFailure(error.code);
    } on Object {
      _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
      return const OperationDeliveryQueued(
        code: OperationOutboxErrorCode.storageUnavailable,
      );
    }
    if (record == null) {
      _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
      return const OperationDeliveryQueued(
        code: OperationOutboxErrorCode.storageUnavailable,
      );
    }
    if (_foreground &&
        (record.state == OperationOutboxState.pending ||
            (record.state == OperationOutboxState.retryableFailure &&
                record.nextAttemptAtUtc != null &&
                !record.nextAttemptAtUtc!.isAfter(_now)))) {
      try {
        batch = await _serializedDrain(expectedPrincipalScopeId);
      } on OperationOutboxException catch (error) {
        _setStorageFailure(error.code);
        return _deliveryAfterDurableEnqueueFailure(error.code);
      } on Object {
        _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
        return const OperationDeliveryQueued(
          code: OperationOutboxErrorCode.storageUnavailable,
        );
      }
      result = batch.results[command.review.draft.commandId];
      if (result != null) return result;
    }
    return _deliveryFromRecord(record);
  }

  Future<void> synchronize({bool resumeAuthentication = false}) async {
    if (!_foreground || !ref.mounted) return;
    final session = await _readSession();
    if (!ref.mounted || !_foreground) return;
    if (session == null) {
      _retryTimer?.cancel();
      state = const OperationSyncState(
        phase: OperationSyncPhase.authenticationRequired,
      );
      return;
    }
    try {
      await _serializedDrain(
        session.cacheScopeId,
        resumeAuthentication: resumeAuthentication,
      );
    } on OperationOutboxException catch (error) {
      if (ref.mounted) _setStorageFailure(error.code);
    } on Object {
      if (ref.mounted) {
        _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
      }
    }
  }

  Future<void> retryNow() async {
    if (!ref.mounted) return;
    final session = await _readSession();
    if (!ref.mounted) return;
    if (session == null) {
      state = const OperationSyncState(
        phase: OperationSyncPhase.authenticationRequired,
      );
      return;
    }
    try {
      await _serializedDrain(
        session.cacheScopeId,
        resumeAuthentication: true,
        retryImmediately: true,
      );
    } on OperationOutboxException catch (error) {
      _setStorageFailure(error.code);
    } on Object {
      _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
    }
  }

  Future<void> _initialize(int generation) async {
    try {
      await _store.recoverInterrupted();
      await _store.purgeExpiredSynced();
    } on OperationOutboxException catch (error) {
      if (generation == _generation) _setStorageFailure(error.code);
      return;
    } on Object {
      if (generation == _generation) {
        _setStorageFailure(OperationOutboxErrorCode.storageUnavailable);
      }
      return;
    }
    if (generation == _generation && _foreground) {
      await synchronize(resumeAuthentication: true);
    }
  }

  Future<_DrainBatch> _serializedDrain(
    String principalScopeId, {
    bool resumeAuthentication = false,
    bool retryImmediately = false,
  }) {
    final completer = Completer<_DrainBatch>();
    _drainQueue = _drainQueue.then((_) async {
      try {
        // A previous drain may have completed its HTTP request but failed its
        // SQLite transition. Recovery is serialized with every future drain so
        // manual retry/resume can recover without a process restart, while an
        // actually in-flight request can never be recovered concurrently.
        await _store.recoverInterrupted();
        if (resumeAuthentication) {
          await _store.resumeAuthentication(principalScopeId: principalScopeId);
        }
        if (retryImmediately) {
          await _store.retryNow(principalScopeId: principalScopeId);
        }
        completer.complete(await _drain(principalScopeId));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<_DrainBatch> _drain(String principalScopeId) async {
    final generation = _generation;
    final accountEpoch = ref.read(authAccountEpochProvider);
    final results = <String, OperationDeliveryResult>{};
    var acceptedAny = false;
    if (!_foreground) return _DrainBatch(results);

    for (var index = 0; index < _maximumCandidatesPerDrain; index += 1) {
      if (!_foreground || generation != _generation) break;
      final before = await _readSession();
      if (generation != _generation ||
          before == null ||
          before.cacheScopeId != principalScopeId) {
        break;
      }

      final record = await _store.claimNextDue(
        principalScopeId: principalScopeId,
      );
      if (record == null) break;
      if (generation == _generation) {
        // Do not announce a Finance send until an actually sendable row has
        // been claimed. A restart may contain only a server-accepted durable
        // Home-convergence marker, which must never be described as awaiting
        // server confirmation in UI or accessibility announcements.
        state = OperationSyncState(
          phase: OperationSyncPhase.synchronizing,
          activeCount: state.activeCount,
          permanentFailureCount: state.permanentFailureCount,
          homeConvergenceCount: state.homeConvergenceCount,
        );
      }
      final command = record.confirmedCommand;
      if (command == null ||
          command.review.draft.accountId != record.financeAccountId) {
        final failed = await _store.markPermanentFailure(
          localId: record.localId,
          principalScopeId: principalScopeId,
          commandId: record.commandId,
          errorCode: OperationOutboxErrorCode.corruptPayload,
        );
        results[record.commandId] = OperationDeliveryPermanentFailure(
          failed.lastErrorCode!,
        );
        break;
      }

      final immediatelyBeforeSend = await _readSession();
      if (generation != _generation ||
          !_sameAccountRevision(before, immediatelyBeforeSend)) {
        await _store.markAuthenticationPaused(
          localId: record.localId,
          principalScopeId: principalScopeId,
          commandId: record.commandId,
          errorCode: OperationOutboxErrorCode.sessionChanged,
        );
        results[record.commandId] = const OperationDeliveryQueued(
          code: OperationOutboxErrorCode.sessionChanged,
        );
        break;
      }
      if (!_foreground) {
        await _store.markRetryableFailure(
          localId: record.localId,
          principalScopeId: principalScopeId,
          commandId: record.commandId,
          errorCode: OperationOutboxErrorCode.interrupted,
        );
        results[record.commandId] = const OperationDeliveryQueued(
          code: OperationOutboxErrorCode.interrupted,
        );
        break;
      }

      late final FinanceEntryResult<FinanceOperationCommit> response;
      try {
        response = await ref
            .read(financeEntryRepositoryDependencyProvider)
            .commitOperation(
              command,
              expectedPrincipalScopeId: principalScopeId,
              expectedSessionRevision: immediatelyBeforeSend!.revision,
              preflight: () {
                if (!ref.mounted ||
                    generation != _generation ||
                    ref.read(authAccountEpochProvider) != accountEpoch) {
                  return FinanceEntryFailureKind.sessionChanged;
                }
                if (!_foreground) {
                  return FinanceEntryFailureKind.interrupted;
                }
                return null;
              },
            );
      } on Object {
        final nextAttempt = _now.add(
          operationOutboxRetryDelay(
            attemptCount: record.attemptCount,
            jitterUnit: ref.read(operationSyncJitterProvider)(),
          ),
        );
        await _store.markRetryableFailure(
          localId: record.localId,
          principalScopeId: principalScopeId,
          commandId: record.commandId,
          errorCode: OperationOutboxErrorCode.ambiguousResult,
          nextAttemptAtUtc: nextAttempt,
        );
        results[record.commandId] = const OperationDeliveryQueued(
          code: OperationOutboxErrorCode.ambiguousResult,
        );
        break;
      }
      final after = await _readSession();
      if (generation != _generation || !_sameAccountRevision(before, after)) {
        await _store.markAuthenticationPaused(
          localId: record.localId,
          principalScopeId: principalScopeId,
          commandId: record.commandId,
          errorCode: OperationOutboxErrorCode.sessionChanged,
        );
        results[record.commandId] = const OperationDeliveryQueued(
          code: OperationOutboxErrorCode.sessionChanged,
        );
        break;
      }

      switch (response) {
        case FinanceEntrySuccess(:final value):
          if (value.operation.userId != principalScopeId) {
            await _store.markPermanentFailure(
              localId: record.localId,
              principalScopeId: principalScopeId,
              commandId: record.commandId,
              errorCode: OperationOutboxErrorCode.responseScopeMismatch,
            );
            results[record.commandId] = const OperationDeliveryPermanentFailure(
              OperationOutboxErrorCode.responseScopeMismatch,
            );
            break;
          }
          await _store.markSynced(
            localId: record.localId,
            principalScopeId: principalScopeId,
            commandId: record.commandId,
            serverOperationId: value.operation.operationId,
          );
          acceptedAny = true;
          final acceptanceCallback = _acceptanceCallbacks.remove(
            record.commandId,
          );
          if (acceptanceCallback != null) {
            try {
              acceptanceCallback(value);
            } on Object {
              // Delivery is already durable. Presentation callbacks cannot
              // alter or roll back authoritative acceptance.
            }
          }
          results[record.commandId] = OperationDeliveryAccepted(
            commit: value,
            homeStatus: AcceptedWriteHomeConvergenceResult.failed,
          );
          break;
        case FinanceEntryFailureResult(:final failure):
          final classification = classifyOperationOutboxFailure(failure);
          switch (classification.disposition) {
            case OperationOutboxFailureDisposition.retryable:
              final nextAttempt = _now.add(
                operationOutboxRetryDelay(
                  attemptCount: record.attemptCount,
                  jitterUnit: ref.read(operationSyncJitterProvider)(),
                ),
              );
              await _store.markRetryableFailure(
                localId: record.localId,
                principalScopeId: principalScopeId,
                commandId: record.commandId,
                errorCode: classification.code,
                nextAttemptAtUtc: nextAttempt,
              );
              results[record.commandId] = OperationDeliveryQueued(
                code: classification.code,
              );
              break;
            case OperationOutboxFailureDisposition.authenticationPaused:
              await _store.markAuthenticationPaused(
                localId: record.localId,
                principalScopeId: principalScopeId,
                commandId: record.commandId,
                errorCode: classification.code,
              );
              results[record.commandId] = OperationDeliveryQueued(
                code: classification.code,
              );
              break;
            case OperationOutboxFailureDisposition.permanent:
              await _store.markPermanentFailure(
                localId: record.localId,
                principalScopeId: principalScopeId,
                commandId: record.commandId,
                errorCode: classification.code,
              );
              results[record.commandId] = OperationDeliveryPermanentFailure(
                classification.code,
              );
              break;
          }
          break;
      }

      final outcome = results[record.commandId];
      if (outcome is OperationDeliveryQueued ||
          (outcome is OperationDeliveryPermanentFailure &&
              const {
                OperationOutboxErrorCode.securityBlocked,
                OperationOutboxErrorCode.responseScopeMismatch,
                OperationOutboxErrorCode.corruptPayload,
              }.contains(outcome.code))) {
        break;
      }
    }

    AcceptedWriteHomeConvergenceResult? homeStatus;
    final pendingHomeConvergence = await _pendingHomeConvergenceRecords(
      principalScopeId,
    );
    if (pendingHomeConvergence.isNotEmpty) {
      if (generation == _generation) {
        state = OperationSyncState(
          phase: OperationSyncPhase.homeConvergencePending,
          activeCount: state.activeCount,
          permanentFailureCount: state.permanentFailureCount,
          homeConvergenceCount: pendingHomeConvergence.length,
        );
      }
      // Home is refreshed once for the entire batch. A failure here never
      // changes any row back from synced and never resends a Finance command.
      homeStatus = await _convergePendingHome(
        principalScopeId,
        pendingHomeConvergence,
        generation: generation,
        accountEpoch: accountEpoch,
      );
    }
    if (acceptedAny) {
      homeStatus ??= AcceptedWriteHomeConvergenceResult.failed;
      for (final entry in results.entries.toList(growable: false)) {
        if (entry.value case OperationDeliveryAccepted(:final commit)) {
          results[entry.key] = OperationDeliveryAccepted(
            commit: commit,
            homeStatus: homeStatus,
          );
        }
      }
    }

    await _refreshState(principalScopeId, generation: generation);
    return _DrainBatch(results);
  }

  Future<void> _refreshState(
    String principalScopeId, {
    required int generation,
  }) async {
    final session = await _readSession();
    if (generation != _generation ||
        session == null ||
        session.cacheScopeId != principalScopeId) {
      return;
    }
    final records = await _store.readForPrincipal(
      principalScopeId: principalScopeId,
    );
    if (generation != _generation) return;

    final active = records.where((record) => record.isActive).toList();
    final permanent = active
        .where(
          (record) => record.state == OperationOutboxState.permanentFailure,
        )
        .toList();
    final securityLocked = permanent.where(
      (record) =>
          operationOutboxSecurityLockCodes.contains(record.lastErrorCode),
    );
    final authPaused = active.where(
      (record) =>
          record.state == OperationOutboxState.retryableFailure &&
          record.nextAttemptAtUtc == null,
    );
    final retryable = active.where(
      (record) =>
          record.state == OperationOutboxState.retryableFailure &&
          record.nextAttemptAtUtc != null,
    );
    final pending = active.where(
      (record) => record.state == OperationOutboxState.pending,
    );
    final pendingHomeConvergence = records.where(
      (record) =>
          record.state == OperationOutboxState.synced &&
          record.homeConvergencePending,
    );

    final phase = securityLocked.isNotEmpty
        ? OperationSyncPhase.locked
        : permanent.isNotEmpty
        ? OperationSyncPhase.attentionRequired
        : authPaused.isNotEmpty
        ? OperationSyncPhase.authenticationRequired
        : retryable.isNotEmpty
        ? OperationSyncPhase.retryableFailure
        : active.isNotEmpty
        ? OperationSyncPhase.pending
        : pendingHomeConvergence.isNotEmpty
        ? OperationSyncPhase.homeConvergencePending
        : OperationSyncPhase.idle;
    final safeError = securityLocked.isNotEmpty
        ? securityLocked.first.lastErrorCode
        : permanent.isNotEmpty
        ? permanent.first.lastErrorCode
        : authPaused.isNotEmpty
        ? authPaused.first.lastErrorCode
        : retryable.isNotEmpty
        ? retryable.first.lastErrorCode
        : null;
    state = OperationSyncState(
      phase: phase,
      activeCount: active.length,
      permanentFailureCount: permanent.length,
      homeConvergenceCount: pendingHomeConvergence.length,
      lastSafeError: safeError,
    );
    if (pending.isNotEmpty &&
        securityLocked.isEmpty &&
        authPaused.isEmpty &&
        retryable.isEmpty) {
      _scheduleImmediateDrain();
    } else {
      _scheduleNearestRetry(<DateTime>[
        ...retryable.map((record) => record.nextAttemptAtUtc!),
        if (pendingHomeConvergence.isNotEmpty)
          _now.add(ref.read(operationHomeConvergenceRetryDelayProvider)),
      ]);
    }
  }

  void _scheduleImmediateDrain() {
    _retryTimer?.cancel();
    if (!_foreground) return;
    _retryTimer = Timer(Duration.zero, () => unawaited(synchronize()));
  }

  void _scheduleNearestRetry(Iterable<DateTime> candidates) {
    _retryTimer?.cancel();
    if (!_foreground || candidates.isEmpty) return;
    final next = candidates.reduce(
      (left, right) => left.isBefore(right) ? left : right,
    );
    final delay = next.difference(_now);
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      unawaited(synchronize());
    });
  }

  Future<AuthSession?> _readSession() async {
    try {
      return await _sessionStore.readAuthSession();
    } on Object {
      return null;
    }
  }

  Future<List<OperationOutboxRecord>> _pendingHomeConvergenceRecords(
    String principalScopeId,
  ) async {
    final records = await _store.readForPrincipal(
      principalScopeId: principalScopeId,
    );
    return records
        .where(
          (record) =>
              record.state == OperationOutboxState.synced &&
              record.homeConvergencePending,
        )
        .toList(growable: false);
  }

  Future<AcceptedWriteHomeConvergenceResult> _convergePendingHome(
    String principalScopeId,
    List<OperationOutboxRecord> records, {
    required int generation,
    required int accountEpoch,
  }) async {
    final before = await _readSession();
    if (!_foreground ||
        generation != _generation ||
        ref.read(authAccountEpochProvider) != accountEpoch ||
        before?.cacheScopeId != principalScopeId) {
      return AcceptedWriteHomeConvergenceResult.sessionChanged;
    }
    try {
      final result = await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite(
            requestPreflight: () {
              if (!ref.mounted || !_foreground || generation != _generation) {
                return false;
              }
              return ref.read(authAccountEpochProvider) == accountEpoch;
            },
          );
      if (result != AcceptedWriteHomeConvergenceResult.updated) return result;

      final after = await _readSession();
      if (!_foreground ||
          generation != _generation ||
          ref.read(authAccountEpochProvider) != accountEpoch ||
          !_sameAccountRevision(before, after)) {
        return AcceptedWriteHomeConvergenceResult.sessionChanged;
      }
      for (final record in records) {
        await _store.markHomeConverged(
          localId: record.localId,
          principalScopeId: principalScopeId,
          commandId: record.commandId,
        );
      }
      return AcceptedWriteHomeConvergenceResult.updated;
    } on Object {
      return AcceptedWriteHomeConvergenceResult.failed;
    }
  }

  Future<OperationOutboxRecord?> _recordForCommand({
    required String principalScopeId,
    required String commandId,
  }) async {
    final records = await _store.readForPrincipal(
      principalScopeId: principalScopeId,
    );
    for (final record in records) {
      if (record.commandId == commandId) return record;
    }
    return null;
  }

  OperationDeliveryResult _deliveryFromRecord(OperationOutboxRecord record) {
    return switch (record.state) {
      OperationOutboxState.synced => OperationDeliveryAlreadySynced(
        record.serverOperationId!,
      ),
      OperationOutboxState.permanentFailure =>
        OperationDeliveryPermanentFailure(
          record.lastErrorCode ?? OperationOutboxErrorCode.invalidCommand,
        ),
      OperationOutboxState.retryableFailure ||
      OperationOutboxState.pending ||
      OperationOutboxState.syncing => OperationDeliveryQueued(
        code: record.lastErrorCode,
      ),
      OperationOutboxState.draft || OperationOutboxState.awaitingConfirmation =>
        const OperationDeliveryStorageFailure(
          OperationOutboxErrorCode.corruptPayload,
        ),
    };
  }

  OperationDeliveryResult _storageFailure(OperationOutboxErrorCode code) {
    if (code == OperationOutboxErrorCode.commandConflict ||
        code == OperationOutboxErrorCode.locked ||
        operationOutboxSecurityLockCodes.contains(code)) {
      return OperationDeliveryPermanentFailure(code);
    }
    return OperationDeliveryStorageFailure(code);
  }

  OperationDeliveryResult _deliveryAfterDurableEnqueueFailure(
    OperationOutboxErrorCode code,
  ) {
    if (code == OperationOutboxErrorCode.locked ||
        operationOutboxSecurityLockCodes.contains(code)) {
      return OperationDeliveryPermanentFailure(code);
    }
    return OperationDeliveryQueued(code: code);
  }

  void _setStorageFailure(OperationOutboxErrorCode code) {
    if (!ref.mounted) return;
    _retryTimer?.cancel();
    state = OperationSyncState(
      phase:
          code == OperationOutboxErrorCode.locked ||
              operationOutboxSecurityLockCodes.contains(code)
          ? OperationSyncPhase.locked
          : OperationSyncPhase.attentionRequired,
      activeCount: state.activeCount,
      permanentFailureCount: state.permanentFailureCount,
      homeConvergenceCount: state.homeConvergenceCount,
      lastSafeError: code,
    );
  }
}

final class _DrainBatch {
  const _DrainBatch(this.results);

  final Map<String, OperationDeliveryResult> results;
}

bool _sameAccountRevision(AuthSession? expected, AuthSession? current) =>
    expected != null &&
    current != null &&
    expected.cacheScopeId == current.cacheScopeId &&
    expected.revision == current.revision;
