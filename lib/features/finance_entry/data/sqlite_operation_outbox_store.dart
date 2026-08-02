import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../domain/finance_entry_models.dart';
import '../domain/operation_outbox.dart';
import 'operation_outbox_codec.dart';
import 'operation_outbox_key_store.dart';
import 'operation_outbox_security_lock_store.dart';
import 'operation_outbox_store.dart';

typedef OperationOutboxDatabasePathProvider = Future<String> Function();
typedef OperationOutboxClock = DateTime Function();
typedef OperationOutboxJitterUnit = double Function();
typedef OperationOutboxLocalIdFactory = String Function();

final class SqliteOperationOutboxStore implements OperationOutboxStore {
  SqliteOperationOutboxStore({
    OperationOutboxKeyStore? keyStore,
    OperationOutboxSecurityLockStore? securityLockStore,
    sqflite.DatabaseFactory? databaseFactory,
    OperationOutboxDatabasePathProvider? databasePathProvider,
    OperationOutboxClock? clock,
    OperationOutboxJitterUnit? jitterUnit,
    OperationOutboxLocalIdFactory? localIdFactory,
    int maxActivePerPrincipal = _defaultMaxActivePerPrincipal,
    int maxActivePerDevice = _defaultMaxActivePerDevice,
    int maxCommandBytes = _defaultMaxCommandBytes,
    int maxPayloadBytes = OperationOutboxCodec.defaultMaxPayloadBytes,
    Duration syncedRetention = _defaultSyncedRetention,
    int maxSyncedPerPrincipal = _defaultMaxSyncedPerPrincipal,
    int cleanupBatchSize = _defaultCleanupBatchSize,
  }) : _keyStore =
           keyStore ?? const FlutterSecureStorageOperationOutboxKeyStore(),
       _securityLockStore =
           securityLockStore ??
           const FlutterSecureStorageOperationOutboxSecurityLockStore(),
       _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _databasePathProvider =
           databasePathProvider ?? _defaultDatabasePathProvider,
       _clock = clock ?? _utcNow,
       _jitterUnit = jitterUnit ?? Random.secure().nextDouble,
       _localIdFactory = localIdFactory ?? _newUuid,
       _maxActivePerPrincipal = maxActivePerPrincipal,
       _maxActivePerDevice = maxActivePerDevice,
       _maxCommandBytes = maxCommandBytes,
       _maxPayloadBytes = maxPayloadBytes,
       _syncedRetention = syncedRetention,
       _maxSyncedPerPrincipal = maxSyncedPerPrincipal,
       _cleanupBatchSize = cleanupBatchSize {
    if (maxActivePerPrincipal <= 0 ||
        maxActivePerDevice < maxActivePerPrincipal ||
        maxCommandBytes <= 0 ||
        maxPayloadBytes < maxCommandBytes ||
        syncedRetention <= Duration.zero ||
        maxSyncedPerPrincipal <= 0 ||
        cleanupBatchSize <= 0) {
      throw ArgumentError('Invalid operation outbox limits.');
    }
  }

  static const int _schemaVersion = 1;
  static const int _masterKeyLength = OperationOutboxCodec.masterKeyLength;
  static const int _defaultMaxActivePerPrincipal = 100;
  static const int _defaultMaxActivePerDevice = 500;
  static const int _defaultMaxCommandBytes = 64 * 1024;
  static const Duration _defaultSyncedRetention = Duration(hours: 24);
  static const int _defaultMaxSyncedPerPrincipal = 100;
  static const int _defaultCleanupBatchSize = 50;
  static const Duration _maximumPersistedRetryDelay = Duration(minutes: 5);
  static const String _databaseFileName = 'operation_outbox_v1.sqlite';
  static const String _table = 'operation_outbox';

  static const Set<OperationOutboxErrorCode> _retryableCodes = {
    OperationOutboxErrorCode.interrupted,
    OperationOutboxErrorCode.offline,
    OperationOutboxErrorCode.timeout,
    OperationOutboxErrorCode.serviceUnavailable,
    OperationOutboxErrorCode.malformedResponse,
    OperationOutboxErrorCode.ambiguousResult,
  };
  static const Set<OperationOutboxErrorCode> _authenticationCodes = {
    OperationOutboxErrorCode.authenticationRequired,
    OperationOutboxErrorCode.sessionChanged,
    OperationOutboxErrorCode.unauthorized,
  };
  static const Set<OperationOutboxErrorCode> _permanentCodes = {
    OperationOutboxErrorCode.invalidCommand,
    OperationOutboxErrorCode.commandConflict,
    OperationOutboxErrorCode.financeRejected,
    OperationOutboxErrorCode.securityBlocked,
    OperationOutboxErrorCode.responseScopeMismatch,
    OperationOutboxErrorCode.corruptPayload,
  };

  final OperationOutboxKeyStore _keyStore;
  final OperationOutboxSecurityLockStore _securityLockStore;
  final sqflite.DatabaseFactory _databaseFactory;
  final OperationOutboxDatabasePathProvider _databasePathProvider;
  final OperationOutboxClock _clock;
  final OperationOutboxJitterUnit _jitterUnit;
  final OperationOutboxLocalIdFactory _localIdFactory;
  final int _maxActivePerPrincipal;
  final int _maxActivePerDevice;
  final int _maxCommandBytes;
  final int _maxPayloadBytes;
  final Duration _syncedRetention;
  final int _maxSyncedPerPrincipal;
  final int _cleanupBatchSize;

  Future<void> _operationQueue = Future<void>.value();
  Future<_OutboxResources>? _resourcesFuture;
  bool _closed = false;
  bool _securityLockChecked = false;
  OperationOutboxErrorCode? _hardLockedCode;

  @override
  Future<OperationOutboxEnqueueResult> enqueueConfirmed({
    required String principalScopeId,
    required FinanceOperationCommitCommand command,
  }) => _serialized(() async {
    final scope = _validateScope(principalScopeId);
    late final FinanceOperationCommitCommand canonicalCommand;
    try {
      canonicalCommand = FinanceOperationCommitCommand.fromJson(
        command.toJson(),
      );
    } on Object {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.invalidCommand,
        'The confirmed command is invalid.',
      );
    }
    final accountId = canonicalCommand.review.draft.accountId;
    if (accountId == null) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.invalidCommand,
        'A canonical account is required before enqueue.',
      );
    }
    final commandBytes = Uint8List.fromList(
      utf8.encode(jsonEncode(canonicalCommand.toJson())),
    );
    try {
      if (commandBytes.length > _maxCommandBytes) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.capacityExceeded,
          'The confirmed command exceeds the local size limit.',
        );
      }
    } finally {
      commandBytes.fillRange(0, commandBytes.length, 0);
    }

    final resources = await _resources();
    await _purgeExpiredSyncedUnlocked(resources);
    final principalTag = await resources.codec.principalTag(scope);
    final accountTag = await resources.codec.financeAccountTag(accountId);
    final commandId = canonicalCommand.review.draft.commandId;
    final commandTag = await resources.codec.commandTag(
      principalScopeId: scope,
      commandId: commandId,
    );
    final digest = await resources.codec.confirmedCommandDigest(
      canonicalCommand,
    );

    return resources.database.transaction((transaction) async {
      final existingRows = await transaction.query(
        _table,
        where: 'principal_tag = ? AND command_tag = ?',
        whereArgs: <Object>[principalTag, commandTag],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existingRow = existingRows.single;
        final existingMetadata = _metadata(existingRow);
        final existingPayload = await _decryptRow(
          existingRow,
          existingMetadata,
          resources.codec,
        );
        if (!_constantTimeEquals(
          existingPayload.confirmedCommandSha256,
          digest,
        )) {
          throw const OperationOutboxException(
            OperationOutboxErrorCode.commandConflict,
            'The command identity already has a different payload.',
          );
        }
        return OperationOutboxEnqueueResult(
          record: _record(metadata: existingMetadata, payload: existingPayload),
          wasExisting: true,
        );
      }

      await _throwIfSecurityLocked(transaction, resources.codec);

      final principalCount = await _countActive(
        transaction,
        where:
            'principal_tag = ? AND '
            '(state <> ? OR home_convergence_pending = 1)',
        whereArgs: <Object>[principalTag, OperationOutboxState.synced.wireName],
      );
      final deviceCount = await _countActive(
        transaction,
        where: '(state <> ? OR home_convergence_pending = 1)',
        whereArgs: <Object>[OperationOutboxState.synced.wireName],
      );
      if (principalCount >= _maxActivePerPrincipal ||
          deviceCount >= _maxActivePerDevice) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.capacityExceeded,
          'The local delivery queue is full.',
        );
      }

      final localId = _validateUuid(_localIdFactory(), 'localId');
      final nowMs = _nowUtc().millisecondsSinceEpoch;
      final metadata = OperationOutboxEnvelopeMetadata(
        localId: localId,
        principalTag: principalTag,
        financeAccountTag: accountTag,
        commandTag: commandTag,
        state: OperationOutboxState.pending,
        transitionSequence: 0,
        createdAtEpochMs: nowMs,
        stateChangedAtEpochMs: nowMs,
        nextAttemptAtEpochMs: nowMs,
        attemptCount: 0,
      );
      final payload = OperationOutboxPayload(
        principalScopeId: scope,
        financeAccountId: accountId,
        commandId: commandId,
        confirmedCommandSha256: digest,
        confirmedCommand: canonicalCommand,
        serverOperationId: null,
      );
      final envelope = await resources.codec.encrypt(
        metadata: metadata,
        payload: payload,
      );
      await transaction.insert(
        _table,
        _rowForInsert(metadata: metadata, envelope: envelope),
        conflictAlgorithm: sqflite.ConflictAlgorithm.abort,
      );
      return OperationOutboxEnqueueResult(
        record: _record(metadata: metadata, payload: payload),
        wasExisting: false,
      );
    });
  });

  @override
  Future<OperationOutboxRecord?> claimNextDue({
    required String principalScopeId,
  }) => _serialized(() async {
    final scope = _validateScope(principalScopeId);
    final resources = await _resources();
    final principalTag = await resources.codec.principalTag(scope);
    return resources.database.transaction((transaction) async {
      await _throwIfSecurityLocked(transaction, resources.codec);
      final rows = await transaction.query(
        _table,
        where: 'principal_tag = ? AND state <> ?',
        whereArgs: <Object>[principalTag, OperationOutboxState.synced.wireName],
        orderBy: 'created_at_epoch_ms ASC, local_id ASC',
      );
      final now = _nowUtc();
      for (final row in rows) {
        final metadata = _metadata(row);
        if (metadata.state == OperationOutboxState.permanentFailure) continue;
        if (metadata.state == OperationOutboxState.draft ||
            metadata.state == OperationOutboxState.awaitingConfirmation ||
            metadata.state == OperationOutboxState.syncing) {
          return null;
        }
        if (metadata.state == OperationOutboxState.retryableFailure) {
          if (metadata.lastErrorCode != null &&
              _authenticationCodes.contains(metadata.lastErrorCode)) {
            return null;
          }
          final dueMs = metadata.nextAttemptAtEpochMs;
          if (dueMs == null) return null;
          final maximumPlausibleDue = now
              .add(_maximumPersistedRetryDelay)
              .millisecondsSinceEpoch;
          if (dueMs > now.millisecondsSinceEpoch &&
              dueMs <= maximumPlausibleDue) {
            return null;
          }
        }
        final payload = await _decryptRow(row, metadata, resources.codec);
        if (payload.principalScopeId != scope) {
          throw const OperationOutboxException(
            OperationOutboxErrorCode.corruptPayload,
            'The outbox principal identity is invalid.',
          );
        }
        final claimed = _copyMetadata(
          metadata,
          state: OperationOutboxState.syncing,
          transitionSequence: metadata.transitionSequence + 1,
          stateChangedAtEpochMs: now.millisecondsSinceEpoch,
          lastAttemptAtEpochMs: now.millisecondsSinceEpoch,
          nextAttemptAtEpochMs: null,
          syncStartedAtEpochMs: now.millisecondsSinceEpoch,
          attemptCount: metadata.attemptCount + 1,
          lastErrorCode: null,
          clearNextAttemptAt: true,
          clearLastErrorCode: true,
        );
        await _updateEncrypted(
          transaction,
          codec: resources.codec,
          previous: metadata,
          next: claimed,
          payload: payload,
        );
        return _record(metadata: claimed, payload: payload);
      }
      return null;
    });
  });

  @override
  Future<OperationOutboxRecord> markRetryableFailure({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
    DateTime? nextAttemptAtUtc,
  }) => _serialized(() async {
    if (!_retryableCodes.contains(errorCode)) {
      throw ArgumentError.value(errorCode, 'errorCode', 'Not retryable.');
    }
    final resources = await _resources();
    return _transitionOwned(
      resources,
      localId: localId,
      principalScopeId: principalScopeId,
      commandId: commandId,
      allowedStates: const <OperationOutboxState>{OperationOutboxState.syncing},
      build: (metadata, payload, now) {
        final due =
            nextAttemptAtUtc?.toUtc() ??
            now.add(
              operationOutboxRetryDelay(
                attemptCount: metadata.attemptCount,
                jitterUnit: _jitterUnit(),
              ),
            );
        if (due.isBefore(now)) {
          throw ArgumentError.value(
            nextAttemptAtUtc,
            'nextAttemptAtUtc',
            'Must not be in the past.',
          );
        }
        return _Transition(
          metadata: _copyMetadata(
            metadata,
            state: OperationOutboxState.retryableFailure,
            transitionSequence: metadata.transitionSequence + 1,
            stateChangedAtEpochMs: now.millisecondsSinceEpoch,
            nextAttemptAtEpochMs: due.millisecondsSinceEpoch,
            syncStartedAtEpochMs: null,
            lastErrorCode: errorCode,
            clearSyncStartedAt: true,
          ),
          payload: payload,
        );
      },
    );
  });

  @override
  Future<OperationOutboxRecord> markAuthenticationPaused({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
  }) => _serialized(() async {
    if (!_authenticationCodes.contains(errorCode)) {
      throw ArgumentError.value(
        errorCode,
        'errorCode',
        'Not an authentication pause.',
      );
    }
    final resources = await _resources();
    return _transitionOwned(
      resources,
      localId: localId,
      principalScopeId: principalScopeId,
      commandId: commandId,
      allowedStates: const <OperationOutboxState>{OperationOutboxState.syncing},
      build: (metadata, payload, now) => _Transition(
        metadata: _copyMetadata(
          metadata,
          state: OperationOutboxState.retryableFailure,
          transitionSequence: metadata.transitionSequence + 1,
          stateChangedAtEpochMs: now.millisecondsSinceEpoch,
          nextAttemptAtEpochMs: null,
          syncStartedAtEpochMs: null,
          lastErrorCode: errorCode,
          clearNextAttemptAt: true,
          clearSyncStartedAt: true,
        ),
        payload: payload,
      ),
    );
  });

  @override
  Future<OperationOutboxRecord> markPermanentFailure({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
  }) => _serialized(() async {
    if (!_permanentCodes.contains(errorCode)) {
      throw ArgumentError.value(errorCode, 'errorCode', 'Not permanent.');
    }
    final resources = await _resources();
    final isSecurityLock = operationOutboxSecurityLockCodes.contains(errorCode);
    if (isSecurityLock) _hardLockedCode = errorCode;
    late final OperationOutboxRecord result;
    try {
      result = await _transitionOwned(
        resources,
        localId: localId,
        principalScopeId: principalScopeId,
        commandId: commandId,
        allowedStates: const <OperationOutboxState>{
          OperationOutboxState.syncing,
        },
        build: (metadata, payload, now) => _Transition(
          metadata: _copyMetadata(
            metadata,
            state: OperationOutboxState.permanentFailure,
            transitionSequence: metadata.transitionSequence + 1,
            stateChangedAtEpochMs: now.millisecondsSinceEpoch,
            nextAttemptAtEpochMs: null,
            syncStartedAtEpochMs: null,
            lastErrorCode: errorCode,
            clearNextAttemptAt: true,
            clearSyncStartedAt: true,
          ),
          payload: payload,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isSecurityLock) {
        await _persistSecurityLockOrThrow(errorCode);
        Error.throwWithStackTrace(
          const OperationOutboxException(
            OperationOutboxErrorCode.locked,
            'The security failure could not be recorded in the outbox.',
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (isSecurityLock) await _persistSecurityLockOrThrow(errorCode);
    return result;
  });

  @override
  Future<OperationOutboxRecord> markSynced({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required String serverOperationId,
  }) => _serialized(() async {
    final canonicalServerOperationId = _validateUuid(
      serverOperationId,
      'serverOperationId',
    );
    final resources = await _resources();
    final result = await _transitionOwned(
      resources,
      localId: localId,
      principalScopeId: principalScopeId,
      commandId: commandId,
      allowedStates: const <OperationOutboxState>{OperationOutboxState.syncing},
      build: (metadata, payload, now) => _Transition(
        metadata: _copyMetadata(
          metadata,
          state: OperationOutboxState.synced,
          transitionSequence: metadata.transitionSequence + 1,
          stateChangedAtEpochMs: now.millisecondsSinceEpoch,
          nextAttemptAtEpochMs: null,
          syncStartedAtEpochMs: null,
          syncedAtEpochMs: now.millisecondsSinceEpoch,
          homeConvergencePending: true,
          lastErrorCode: null,
          clearNextAttemptAt: true,
          clearSyncStartedAt: true,
          clearLastErrorCode: true,
        ),
        payload: OperationOutboxPayload(
          principalScopeId: payload.principalScopeId,
          financeAccountId: payload.financeAccountId,
          commandId: payload.commandId,
          confirmedCommandSha256: payload.confirmedCommandSha256,
          confirmedCommand: null,
          serverOperationId: canonicalServerOperationId,
        ),
      ),
    );
    await _purgeExpiredSyncedUnlocked(resources);
    return result;
  });

  @override
  Future<OperationOutboxRecord> markHomeConverged({
    required String localId,
    required String principalScopeId,
    required String commandId,
  }) => _serialized(() async {
    final resources = await _resources();
    return _transitionOwned(
      resources,
      localId: localId,
      principalScopeId: principalScopeId,
      commandId: commandId,
      allowedStates: const <OperationOutboxState>{OperationOutboxState.synced},
      build: (metadata, payload, now) {
        if (!metadata.homeConvergencePending) {
          return _Transition(metadata: metadata, payload: payload);
        }
        return _Transition(
          metadata: _copyMetadata(
            metadata,
            state: OperationOutboxState.synced,
            transitionSequence: metadata.transitionSequence + 1,
            stateChangedAtEpochMs: now.millisecondsSinceEpoch,
            homeConvergencePending: false,
          ),
          payload: payload,
        );
      },
    );
  });

  @override
  Future<void> resumeAuthentication({required String principalScopeId}) =>
      _serialized(() async {
        final scope = _validateScope(principalScopeId);
        final resources = await _resources();
        final principalTag = await resources.codec.principalTag(scope);
        await resources.database.transaction((transaction) async {
          final rows = await transaction.query(
            _table,
            where: 'principal_tag = ? AND state = ?',
            whereArgs: <Object>[
              principalTag,
              OperationOutboxState.retryableFailure.wireName,
            ],
            orderBy: 'created_at_epoch_ms ASC, local_id ASC',
          );
          final nowMs = _nowUtc().millisecondsSinceEpoch;
          for (final row in rows) {
            final metadata = _metadata(row);
            if (!_authenticationCodes.contains(metadata.lastErrorCode)) {
              continue;
            }
            final payload = await _decryptRow(row, metadata, resources.codec);
            if (payload.principalScopeId != scope) {
              throw const OperationOutboxException(
                OperationOutboxErrorCode.corruptPayload,
                'The outbox principal identity is invalid.',
              );
            }
            final resumed = _copyMetadata(
              metadata,
              state: OperationOutboxState.pending,
              transitionSequence: metadata.transitionSequence + 1,
              stateChangedAtEpochMs: nowMs,
              nextAttemptAtEpochMs: nowMs,
              lastErrorCode: null,
              clearLastErrorCode: true,
            );
            await _updateEncrypted(
              transaction,
              codec: resources.codec,
              previous: metadata,
              next: resumed,
              payload: payload,
            );
          }
        });
      });

  @override
  Future<void> retryNow({required String principalScopeId}) =>
      _serialized(() async {
        final scope = _validateScope(principalScopeId);
        final resources = await _resources();
        final principalTag = await resources.codec.principalTag(scope);
        await resources.database.transaction((transaction) async {
          final rows = await transaction.query(
            _table,
            where: 'principal_tag = ? AND state = ?',
            whereArgs: <Object>[
              principalTag,
              OperationOutboxState.retryableFailure.wireName,
            ],
            orderBy: 'created_at_epoch_ms ASC, local_id ASC',
          );
          final nowMs = _nowUtc().millisecondsSinceEpoch;
          for (final row in rows) {
            final metadata = _metadata(row);
            if (!_retryableCodes.contains(metadata.lastErrorCode)) {
              continue;
            }
            final payload = await _decryptRow(row, metadata, resources.codec);
            if (payload.principalScopeId != scope) {
              throw const OperationOutboxException(
                OperationOutboxErrorCode.corruptPayload,
                'The outbox principal identity is invalid.',
              );
            }
            final pending = _copyMetadata(
              metadata,
              state: OperationOutboxState.pending,
              transitionSequence: metadata.transitionSequence + 1,
              stateChangedAtEpochMs: nowMs,
              nextAttemptAtEpochMs: nowMs,
              lastErrorCode: null,
              clearLastErrorCode: true,
            );
            await _updateEncrypted(
              transaction,
              codec: resources.codec,
              previous: metadata,
              next: pending,
              payload: payload,
            );
          }
        });
      });

  @override
  Future<List<OperationOutboxRecord>> readForPrincipal({
    required String principalScopeId,
  }) => _serialized(() async {
    final scope = _validateScope(principalScopeId);
    final resources = await _resources();
    await _purgeExpiredSyncedUnlocked(resources);
    final principalTag = await resources.codec.principalTag(scope);
    final rows = await resources.database.query(
      _table,
      where: 'principal_tag = ?',
      whereArgs: <Object>[principalTag],
      orderBy: 'created_at_epoch_ms ASC, local_id ASC',
    );
    final records = <OperationOutboxRecord>[];
    for (final row in rows) {
      final record = await _decodeRow(row, resources.codec);
      if (record.principalScopeId != scope) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.corruptPayload,
          'The outbox principal identity is invalid.',
        );
      }
      records.add(record);
    }
    return List<OperationOutboxRecord>.unmodifiable(records);
  });

  @override
  Future<int> recoverInterrupted() => _serialized(() async {
    final resources = await _resources();
    final recoveredOnOpen = resources.takeRecoveredOnOpen();
    return recoveredOnOpen + await _recoverInterruptedUnlocked(resources);
  });

  @override
  Future<int> purgeExpiredSynced() => _serialized(() async {
    final resources = await _resources();
    final purgedOnOpen = resources.takePurgedOnOpen();
    return purgedOnOpen + await _purgeExpiredSyncedUnlocked(resources);
  });

  @override
  Future<void> close() => _serialized(
    () async {
      _closed = true;
      final future = _resourcesFuture;
      _resourcesFuture = null;
      if (future == null) return;
      late final _OutboxResources resources;
      try {
        resources = await future;
      } on Object {
        // Failed initialization closes any partially opened database itself.
        return;
      }
      resources.codec.dispose();
      await resources.database.close();
    },
    allowClosed: true,
    skipSecurityCheck: true,
  );

  Future<OperationOutboxRecord> _transitionOwned(
    _OutboxResources resources, {
    required String localId,
    required String principalScopeId,
    required String commandId,
    required Set<OperationOutboxState> allowedStates,
    required _Transition Function(
      OperationOutboxEnvelopeMetadata metadata,
      OperationOutboxPayload payload,
      DateTime now,
    )
    build,
  }) async {
    final canonicalLocalId = _validateUuid(localId, 'localId');
    final scope = _validateScope(principalScopeId);
    final canonicalCommandId = _validateUuid(commandId, 'commandId');
    final principalTag = await resources.codec.principalTag(scope);
    final commandTag = await resources.codec.commandTag(
      principalScopeId: scope,
      commandId: canonicalCommandId,
    );
    return resources.database.transaction((transaction) async {
      final rows = await transaction.query(
        _table,
        where: 'local_id = ? AND principal_tag = ? AND command_tag = ?',
        whereArgs: <Object>[canonicalLocalId, principalTag, commandTag],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.commandConflict,
          'The outbox command identity was not found.',
        );
      }
      final row = rows.single;
      final metadata = _metadata(row);
      final payload = await _decryptRow(row, metadata, resources.codec);
      if (payload.principalScopeId != scope ||
          payload.commandId != canonicalCommandId) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.corruptPayload,
          'The outbox command identity is invalid.',
        );
      }
      if (!allowedStates.contains(metadata.state)) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.commandConflict,
          'The outbox command is in an incompatible state.',
        );
      }
      final transition = build(metadata, payload, _nowUtc());
      await _updateEncrypted(
        transaction,
        codec: resources.codec,
        previous: metadata,
        next: transition.metadata,
        payload: transition.payload,
      );
      return _record(
        metadata: transition.metadata,
        payload: transition.payload,
      );
    });
  }

  Future<int> _recoverInterruptedUnlocked(_OutboxResources resources) async {
    return resources.database.transaction((transaction) async {
      final rows = await transaction.query(
        _table,
        where: 'state = ?',
        whereArgs: <Object>[OperationOutboxState.syncing.wireName],
        orderBy: 'created_at_epoch_ms ASC, local_id ASC',
      );
      if (rows.isEmpty) return 0;
      final nowMs = _nowUtc().millisecondsSinceEpoch;
      for (final row in rows) {
        final metadata = _metadata(row);
        final payload = await _decryptRow(row, metadata, resources.codec);
        final recovered = _copyMetadata(
          metadata,
          state: OperationOutboxState.retryableFailure,
          transitionSequence: metadata.transitionSequence + 1,
          stateChangedAtEpochMs: nowMs,
          nextAttemptAtEpochMs: nowMs,
          syncStartedAtEpochMs: null,
          lastErrorCode: OperationOutboxErrorCode.interrupted,
          clearSyncStartedAt: true,
        );
        await _updateEncrypted(
          transaction,
          codec: resources.codec,
          previous: metadata,
          next: recovered,
          payload: payload,
        );
      }
      return rows.length;
    });
  }

  Future<int> _purgeExpiredSyncedUnlocked(_OutboxResources resources) async {
    return resources.database.transaction((transaction) async {
      var remaining = _cleanupBatchSize;
      var deleted = 0;
      final cutoffMs = _nowUtc()
          .subtract(_syncedRetention)
          .millisecondsSinceEpoch;
      final expired = await transaction.query(
        _table,
        where:
            'state = ? AND home_convergence_pending = 0 '
            'AND synced_at_epoch_ms <= ?',
        whereArgs: <Object>[OperationOutboxState.synced.wireName, cutoffMs],
        orderBy: 'synced_at_epoch_ms ASC, local_id ASC',
        limit: remaining,
      );
      for (final row in expired) {
        final metadata = _metadata(row);
        final record = await _decodeRow(row, resources.codec);
        if (record.state != OperationOutboxState.synced) {
          throw const OperationOutboxException(
            OperationOutboxErrorCode.corruptPayload,
            'An invalid row was selected for outbox retention.',
          );
        }
        final changed = await transaction.delete(
          _table,
          where: 'local_id = ? AND transition_sequence = ?',
          whereArgs: <Object>[metadata.localId, metadata.transitionSequence],
        );
        deleted += changed;
        remaining -= changed;
      }
      if (remaining <= 0) return deleted;

      final principalCounts = await transaction.rawQuery(
        'SELECT principal_tag, COUNT(*) AS row_count FROM $_table '
        'WHERE state = ? AND home_convergence_pending = 0 '
        'GROUP BY principal_tag HAVING COUNT(*) > ?',
        <Object>[OperationOutboxState.synced.wireName, _maxSyncedPerPrincipal],
      );
      for (final countRow in principalCounts) {
        if (remaining <= 0) break;
        final principalTag = _requiredString(countRow, 'principal_tag');
        final count = _requiredInt(countRow, 'row_count');
        final excess = min(count - _maxSyncedPerPrincipal, remaining);
        final rows = await transaction.query(
          _table,
          where:
              'principal_tag = ? AND state = ? '
              'AND home_convergence_pending = 0',
          whereArgs: <Object>[
            principalTag,
            OperationOutboxState.synced.wireName,
          ],
          orderBy: 'synced_at_epoch_ms ASC, local_id ASC',
          limit: excess,
        );
        for (final row in rows) {
          final metadata = _metadata(row);
          final record = await _decodeRow(row, resources.codec);
          if (record.state != OperationOutboxState.synced) {
            throw const OperationOutboxException(
              OperationOutboxErrorCode.corruptPayload,
              'An invalid row was selected for outbox retention.',
            );
          }
          final changed = await transaction.delete(
            _table,
            where: 'local_id = ? AND transition_sequence = ?',
            whereArgs: <Object>[metadata.localId, metadata.transitionSequence],
          );
          deleted += changed;
          remaining -= changed;
        }
      }
      return deleted;
    });
  }

  Future<void> _updateEncrypted(
    sqflite.DatabaseExecutor transaction, {
    required OperationOutboxCodec codec,
    required OperationOutboxEnvelopeMetadata previous,
    required OperationOutboxEnvelopeMetadata next,
    required OperationOutboxPayload payload,
  }) async {
    final envelope = await codec.encrypt(metadata: next, payload: payload);
    final changed = await transaction.update(
      _table,
      _rowForUpdate(metadata: next, envelope: envelope),
      where: 'local_id = ? AND transition_sequence = ?',
      whereArgs: <Object>[previous.localId, previous.transitionSequence],
      conflictAlgorithm: sqflite.ConflictAlgorithm.abort,
    );
    if (changed != 1) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.commandConflict,
        'The outbox command changed concurrently.',
      );
    }
  }

  Future<void> _throwIfSecurityLocked(
    sqflite.DatabaseExecutor database,
    OperationOutboxCodec codec,
  ) async {
    final permanentRows = await database.query(
      _table,
      where: 'state = ?',
      whereArgs: <Object>[OperationOutboxState.permanentFailure.wireName],
      orderBy: 'created_at_epoch_ms ASC, local_id ASC',
    );
    for (final row in permanentRows) {
      final metadata = _metadata(row);
      await _decryptRow(row, metadata, codec);
      final code = metadata.lastErrorCode;
      if (code != null && operationOutboxSecurityLockCodes.contains(code)) {
        throw OperationOutboxException(
          code,
          'The operation outbox is locked after a security failure.',
        );
      }
    }
  }

  Future<void> _authenticateAllRows(
    sqflite.DatabaseExecutor database,
    OperationOutboxCodec codec,
  ) async {
    final rows = await database.query(
      _table,
      orderBy: 'created_at_epoch_ms ASC, local_id ASC',
    );
    for (final row in rows) {
      final metadata = _metadata(row);
      await _decryptRow(row, metadata, codec);
      final code = metadata.lastErrorCode;
      if (metadata.state == OperationOutboxState.permanentFailure &&
          code != null &&
          operationOutboxSecurityLockCodes.contains(code)) {
        throw OperationOutboxException(
          code,
          'The operation outbox is locked after a security failure.',
        );
      }
    }
  }

  Future<OperationOutboxRecord> _decodeRow(
    Map<String, Object?> row,
    OperationOutboxCodec codec,
  ) async {
    final metadata = _metadata(row);
    final payload = await _decryptRow(row, metadata, codec);
    return _record(metadata: metadata, payload: payload);
  }

  Future<OperationOutboxPayload> _decryptRow(
    Map<String, Object?> row,
    OperationOutboxEnvelopeMetadata metadata,
    OperationOutboxCodec codec,
  ) => codec.decrypt(
    metadata: metadata,
    nonce: _requiredBytes(row, 'nonce'),
    ciphertext: _requiredBytes(row, 'ciphertext'),
    mac: _requiredBytes(row, 'mac'),
  );

  OperationOutboxRecord _record({
    required OperationOutboxEnvelopeMetadata metadata,
    required OperationOutboxPayload payload,
  }) => OperationOutboxRecord(
    localId: metadata.localId,
    principalScopeId: payload.principalScopeId,
    financeAccountId: payload.financeAccountId,
    commandId: payload.commandId,
    state: metadata.state,
    transitionSequence: metadata.transitionSequence,
    createdAtUtc: _dateTime(metadata.createdAtEpochMs),
    stateChangedAtUtc: _dateTime(metadata.stateChangedAtEpochMs),
    lastAttemptAtUtc: _optionalDateTime(metadata.lastAttemptAtEpochMs),
    nextAttemptAtUtc: _optionalDateTime(metadata.nextAttemptAtEpochMs),
    syncStartedAtUtc: _optionalDateTime(metadata.syncStartedAtEpochMs),
    syncedAtUtc: _optionalDateTime(metadata.syncedAtEpochMs),
    attemptCount: metadata.attemptCount,
    lastErrorCode: metadata.lastErrorCode,
    confirmedCommand: payload.confirmedCommand,
    serverOperationId: payload.serverOperationId,
    homeConvergencePending: metadata.homeConvergencePending,
  );

  Future<_OutboxResources> _resources() {
    if (_closed) throw StateError('Operation outbox is closed.');
    return _resourcesFuture ??= _openResourcesResettingOnFailure();
  }

  Future<_OutboxResources> _openResourcesResettingOnFailure() async {
    try {
      return await _openResources();
    } on Object {
      _resourcesFuture = null;
      rethrow;
    }
  }

  Future<_OutboxResources> _openResources() async {
    late final String databasePath;
    try {
      databasePath = await _databasePathProvider();
      if (databasePath.isEmpty || databasePath.contains('\u0000')) {
        throw const FormatException('Invalid database path.');
      }
      await Directory(path.dirname(databasePath)).create(recursive: true);
    } on Object {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.storageUnavailable,
        'The operation outbox path is unavailable.',
      );
    }

    sqflite.Database? openedDatabase;
    try {
      openedDatabase = await _databaseFactory.openDatabase(
        databasePath,
        options: sqflite.OpenDatabaseOptions(
          version: _schemaVersion,
          onConfigure: (database) async {
            // Android rejects statements that return rows through execute().
            // busy_timeout and secure_delete always return their new value, so
            // they must use the query path; foreign_keys returns no rows.
            await database.execute('PRAGMA foreign_keys = ON');
            await database.rawQuery('PRAGMA busy_timeout = 5000');
            await database.rawQuery('PRAGMA secure_delete = ON');
          },
          onCreate: (database, version) => _createSchema(database),
        ),
      );
      await openedDatabase.rawQuery('PRAGMA journal_mode = WAL');
      await openedDatabase.execute('PRAGMA synchronous = FULL');
    } on Object {
      try {
        await openedDatabase?.close();
      } on Object {
        // Preserve the original initialization failure.
      }
      throw const OperationOutboxException(
        OperationOutboxErrorCode.storageUnavailable,
        'The operation outbox database is unavailable.',
      );
    }
    final database = openedDatabase;

    OperationOutboxCodec? codec;
    try {
      final rowCount =
          sqflite.Sqflite.firstIntValue(
            await database.rawQuery('SELECT COUNT(*) FROM $_table'),
          ) ??
          0;
      final keyBytes = await _readOrCreateMasterKey(rowCount: rowCount);
      try {
        codec = await OperationOutboxCodec.create(
          keyBytes,
          maxPayloadBytes: _maxPayloadBytes,
        );
      } finally {
        keyBytes.fillRange(0, keyBytes.length, 0);
      }
      final resources = _OutboxResources(database: database, codec: codec);
      await _authenticateAllRows(database, codec);
      resources.recoveredOnOpen = await _recoverInterruptedUnlocked(resources);
      resources.purgedOnOpen = await _purgeExpiredSyncedUnlocked(resources);
      return resources;
    } on Object {
      codec?.dispose();
      await database.close();
      rethrow;
    }
  }

  Future<Uint8List> _readOrCreateMasterKey({required int rowCount}) async {
    List<int>? stored;
    try {
      stored = await _keyStore.read();
    } on FormatException {
      if (rowCount > 0) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.locked,
          'The encrypted outbox key is missing or invalid.',
        );
      }
      stored = null;
    } on Object {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.storageUnavailable,
        'The outbox key store is unavailable.',
      );
    }
    if (stored != null && stored.length == _masterKeyLength) {
      return Uint8List.fromList(stored);
    }
    if (rowCount > 0) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.locked,
        'The encrypted outbox key is missing or invalid.',
      );
    }

    final generated = Uint8List(_masterKeyLength);
    final random = Random.secure();
    for (var index = 0; index < generated.length; index += 1) {
      generated[index] = random.nextInt(256);
    }
    try {
      await _keyStore.write(generated);
      return Uint8List.fromList(generated);
    } on Object {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.storageUnavailable,
        'The outbox key could not be stored.',
      );
    } finally {
      generated.fillRange(0, generated.length, 0);
    }
  }

  Future<T> _serialized<T>(
    Future<T> Function() operation, {
    bool allowClosed = false,
    bool skipSecurityCheck = false,
  }) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      if (_closed && !allowClosed) {
        completer.completeError(StateError('Operation outbox is closed.'));
        return;
      }
      try {
        if (!skipSecurityCheck) await _ensureSecurityUnlocked();
        completer.complete(await operation());
      } on OperationOutboxException catch (error, stackTrace) {
        final reported = operationOutboxSecurityLockCodes.contains(error.code)
            ? await _durablyLock(error)
            : error;
        completer.completeError(reported, stackTrace);
      } on sqflite.DatabaseException catch (error, stackTrace) {
        completer.completeError(
          const OperationOutboxException(
            OperationOutboxErrorCode.storageUnavailable,
            'The operation outbox database failed.',
          ),
          stackTrace,
        );
      } on FormatException catch (error, stackTrace) {
        final reported = await _durablyLock(
          const OperationOutboxException(
            OperationOutboxErrorCode.corruptPayload,
            'The operation outbox contains invalid data.',
          ),
        );
        completer.completeError(reported, stackTrace);
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _ensureSecurityUnlocked() async {
    final locked = _hardLockedCode;
    if (locked != null) {
      throw OperationOutboxException(
        locked,
        'The operation outbox is locked after a security failure.',
      );
    }
    if (_securityLockChecked) return;
    late final OperationOutboxErrorCode? persisted;
    try {
      persisted = await _securityLockStore.read();
    } on Object {
      _hardLockedCode = OperationOutboxErrorCode.locked;
      throw const OperationOutboxException(
        OperationOutboxErrorCode.locked,
        'The operation outbox security lock is unavailable.',
      );
    }
    _securityLockChecked = true;
    if (persisted == null) return;
    _hardLockedCode = persisted;
    throw OperationOutboxException(
      persisted,
      'The operation outbox is locked after a security failure.',
    );
  }

  Future<OperationOutboxException> _durablyLock(
    OperationOutboxException original,
  ) async {
    try {
      await _persistSecurityLockOrThrow(original.code);
      return original;
    } on OperationOutboxException catch (error) {
      return error;
    }
  }

  Future<void> _persistSecurityLockOrThrow(
    OperationOutboxErrorCode code,
  ) async {
    _hardLockedCode = code;
    try {
      await _securityLockStore.engage(code);
    } on Object {
      _hardLockedCode = OperationOutboxErrorCode.locked;
      throw const OperationOutboxException(
        OperationOutboxErrorCode.locked,
        'The operation outbox security lock could not be persisted.',
      );
    }
  }

  DateTime _nowUtc() => _clock().toUtc();
}

final class _OutboxResources {
  _OutboxResources({required this.database, required this.codec});

  final sqflite.Database database;
  final OperationOutboxCodec codec;
  int recoveredOnOpen = 0;
  int purgedOnOpen = 0;

  int takeRecoveredOnOpen() {
    final value = recoveredOnOpen;
    recoveredOnOpen = 0;
    return value;
  }

  int takePurgedOnOpen() {
    final value = purgedOnOpen;
    purgedOnOpen = 0;
    return value;
  }
}

final class _Transition {
  const _Transition({required this.metadata, required this.payload});

  final OperationOutboxEnvelopeMetadata metadata;
  final OperationOutboxPayload payload;
}

Future<void> _createSchema(sqflite.Database database) async {
  await database.execute('''
CREATE TABLE operation_outbox (
  local_id TEXT PRIMARY KEY NOT NULL,
  principal_tag TEXT NOT NULL,
  finance_account_tag TEXT NOT NULL,
  command_tag TEXT NOT NULL,
  envelope_version INTEGER NOT NULL,
  payload_version INTEGER NOT NULL,
  state TEXT NOT NULL,
  transition_sequence INTEGER NOT NULL,
  created_at_epoch_ms INTEGER NOT NULL,
  state_changed_at_epoch_ms INTEGER NOT NULL,
  last_attempt_at_epoch_ms INTEGER,
  next_attempt_at_epoch_ms INTEGER,
  sync_started_at_epoch_ms INTEGER,
  synced_at_epoch_ms INTEGER,
  home_convergence_pending INTEGER NOT NULL,
  attempt_count INTEGER NOT NULL,
  last_error_code TEXT,
  nonce BLOB NOT NULL,
  ciphertext BLOB NOT NULL,
  mac BLOB NOT NULL,
  UNIQUE (principal_tag, command_tag),
  CHECK (length(principal_tag) = 43),
  CHECK (length(finance_account_tag) = 43),
  CHECK (length(command_tag) = 43),
  CHECK (envelope_version = 1),
  CHECK (payload_version = 1),
  CHECK (state IN (
    'draft', 'awaiting_confirmation', 'pending', 'syncing',
    'retryable_failure', 'permanent_failure', 'synced'
  )),
  CHECK (transition_sequence >= 0),
  CHECK (created_at_epoch_ms >= 0),
  CHECK (state_changed_at_epoch_ms >= created_at_epoch_ms),
  CHECK (attempt_count >= 0),
  CHECK (home_convergence_pending IN (0, 1)),
  CHECK (state = 'synced' OR home_convergence_pending = 0),
  CHECK (last_error_code IS NULL OR last_error_code IN (
    'interrupted', 'offline', 'timeout', 'service_unavailable',
    'malformed_response', 'ambiguous_result', 'authentication_required',
    'session_changed', 'unauthorized', 'invalid_command', 'command_conflict',
    'finance_rejected', 'security_blocked', 'response_scope_mismatch',
    'locked', 'corrupt_payload', 'capacity_exceeded', 'storage_unavailable'
  )),
  CHECK (length(nonce) = 12),
  CHECK (length(ciphertext) > 0),
  CHECK (length(mac) = 16)
)
''');
  await database.execute(
    'CREATE INDEX operation_outbox_principal_fifo_idx ON operation_outbox '
    '(principal_tag, created_at_epoch_ms, local_id)',
  );
  await database.execute(
    'CREATE INDEX operation_outbox_synced_retention_idx ON operation_outbox '
    '(state, synced_at_epoch_ms)',
  );
}

Map<String, Object?> _rowForInsert({
  required OperationOutboxEnvelopeMetadata metadata,
  required OperationOutboxEncryptedEnvelope envelope,
}) => <String, Object?>{
  'local_id': metadata.localId,
  'principal_tag': metadata.principalTag,
  'finance_account_tag': metadata.financeAccountTag,
  'command_tag': metadata.commandTag,
  'envelope_version': OperationOutboxCodec.envelopeVersion,
  'payload_version': OperationOutboxCodec.payloadVersion,
  ..._rowForUpdate(metadata: metadata, envelope: envelope),
};

Map<String, Object?> _rowForUpdate({
  required OperationOutboxEnvelopeMetadata metadata,
  required OperationOutboxEncryptedEnvelope envelope,
}) => <String, Object?>{
  'state': metadata.state.wireName,
  'transition_sequence': metadata.transitionSequence,
  'created_at_epoch_ms': metadata.createdAtEpochMs,
  'state_changed_at_epoch_ms': metadata.stateChangedAtEpochMs,
  'last_attempt_at_epoch_ms': metadata.lastAttemptAtEpochMs,
  'next_attempt_at_epoch_ms': metadata.nextAttemptAtEpochMs,
  'sync_started_at_epoch_ms': metadata.syncStartedAtEpochMs,
  'synced_at_epoch_ms': metadata.syncedAtEpochMs,
  'attempt_count': metadata.attemptCount,
  'home_convergence_pending': metadata.homeConvergencePending ? 1 : 0,
  'last_error_code': metadata.lastErrorCode?.wireName,
  'nonce': envelope.nonce,
  'ciphertext': envelope.ciphertext,
  'mac': envelope.mac,
};

OperationOutboxEnvelopeMetadata _metadata(Map<String, Object?> row) {
  if (_requiredInt(row, 'envelope_version') !=
          OperationOutboxCodec.envelopeVersion ||
      _requiredInt(row, 'payload_version') !=
          OperationOutboxCodec.payloadVersion) {
    throw const FormatException('Unsupported outbox envelope version.');
  }
  final lastError = switch (row['last_error_code']) {
    null => null,
    final String value => value,
    _ => throw const FormatException('Invalid last_error_code.'),
  };
  return OperationOutboxEnvelopeMetadata(
    localId: _requiredString(row, 'local_id'),
    principalTag: _requiredString(row, 'principal_tag'),
    financeAccountTag: _requiredString(row, 'finance_account_tag'),
    commandTag: _requiredString(row, 'command_tag'),
    state: OperationOutboxStateWire.parse(_requiredString(row, 'state')),
    transitionSequence: _requiredInt(row, 'transition_sequence'),
    createdAtEpochMs: _requiredInt(row, 'created_at_epoch_ms'),
    stateChangedAtEpochMs: _requiredInt(row, 'state_changed_at_epoch_ms'),
    lastAttemptAtEpochMs: _optionalInt(row, 'last_attempt_at_epoch_ms'),
    nextAttemptAtEpochMs: _optionalInt(row, 'next_attempt_at_epoch_ms'),
    syncStartedAtEpochMs: _optionalInt(row, 'sync_started_at_epoch_ms'),
    syncedAtEpochMs: _optionalInt(row, 'synced_at_epoch_ms'),
    attemptCount: _requiredInt(row, 'attempt_count'),
    homeConvergencePending: _requiredSqliteBoolean(
      row,
      'home_convergence_pending',
    ),
    lastErrorCode: lastError == null
        ? null
        : OperationOutboxErrorCodeWire.parse(lastError),
  );
}

OperationOutboxEnvelopeMetadata _copyMetadata(
  OperationOutboxEnvelopeMetadata value, {
  required OperationOutboxState state,
  required int transitionSequence,
  required int stateChangedAtEpochMs,
  int? lastAttemptAtEpochMs,
  int? nextAttemptAtEpochMs,
  int? syncStartedAtEpochMs,
  int? syncedAtEpochMs,
  int? attemptCount,
  OperationOutboxErrorCode? lastErrorCode,
  bool? homeConvergencePending,
  bool clearLastAttemptAt = false,
  bool clearNextAttemptAt = false,
  bool clearSyncStartedAt = false,
  bool clearSyncedAt = false,
  bool clearLastErrorCode = false,
}) {
  final monotonicStateChangedAt = max(
    stateChangedAtEpochMs,
    value.stateChangedAtEpochMs,
  );
  final effectiveSyncedAt = clearSyncedAt
      ? null
      : syncedAtEpochMs == null
      ? value.syncedAtEpochMs
      : max(syncedAtEpochMs, monotonicStateChangedAt);
  return OperationOutboxEnvelopeMetadata(
    localId: value.localId,
    principalTag: value.principalTag,
    financeAccountTag: value.financeAccountTag,
    commandTag: value.commandTag,
    state: state,
    transitionSequence: transitionSequence,
    createdAtEpochMs: value.createdAtEpochMs,
    stateChangedAtEpochMs: monotonicStateChangedAt,
    lastAttemptAtEpochMs: clearLastAttemptAt
        ? null
        : lastAttemptAtEpochMs ?? value.lastAttemptAtEpochMs,
    nextAttemptAtEpochMs: clearNextAttemptAt
        ? null
        : nextAttemptAtEpochMs ?? value.nextAttemptAtEpochMs,
    syncStartedAtEpochMs: clearSyncStartedAt
        ? null
        : syncStartedAtEpochMs ?? value.syncStartedAtEpochMs,
    syncedAtEpochMs: effectiveSyncedAt,
    attemptCount: attemptCount ?? value.attemptCount,
    homeConvergencePending:
        homeConvergencePending ?? value.homeConvergencePending,
    lastErrorCode: clearLastErrorCode
        ? null
        : lastErrorCode ?? value.lastErrorCode,
  );
}

Future<int> _countActive(
  sqflite.DatabaseExecutor database, {
  required String where,
  required List<Object> whereArgs,
}) async =>
    sqflite.Sqflite.firstIntValue(
      await database.rawQuery(
        'SELECT COUNT(*) FROM operation_outbox WHERE $where',
        whereArgs,
      ),
    ) ??
    0;

String _requiredString(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

int _requiredInt(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! int) throw FormatException('Invalid $key.');
  return value;
}

int? _optionalInt(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('Invalid $key.');
  return value;
}

bool _requiredSqliteBoolean(Map<String, Object?> row, String key) =>
    switch (_requiredInt(row, key)) {
      0 => false,
      1 => true,
      _ => throw FormatException('Invalid $key.'),
    };

Uint8List _requiredBytes(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! List<int>) throw FormatException('Invalid $key.');
  return Uint8List.fromList(value);
}

DateTime _dateTime(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);

DateTime? _optionalDateTime(int? epochMs) =>
    epochMs == null ? null : _dateTime(epochMs);

String _validateScope(String value) {
  if (value.isEmpty ||
      value.length > 512 ||
      value != value.trim() ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw ArgumentError.value(value, 'principalScopeId', 'Invalid scope.');
  }
  return value;
}

String _validateUuid(String value, String name) {
  if (!_uuidPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'Invalid UUID.');
  }
  return value;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _constantTimeEquals(String left, String right) {
  var difference = left.length ^ right.length;
  final maximum = max(left.length, right.length);
  for (var index = 0; index < maximum; index += 1) {
    difference |=
        (index < left.length ? left.codeUnitAt(index) : 0) ^
        (index < right.length ? right.codeUnitAt(index) : 0);
  }
  return difference == 0;
}

DateTime _utcNow() => DateTime.now().toUtc();

Future<String> _defaultDatabasePathProvider() async {
  final directory = await getApplicationSupportDirectory();
  return path.join(
    directory.path,
    SqliteOperationOutboxStore._databaseFileName,
  );
}

String _newUuid() {
  final bytes = Uint8List(16);
  final random = Random.secure();
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = random.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  bytes.fillRange(0, bytes.length, 0);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
