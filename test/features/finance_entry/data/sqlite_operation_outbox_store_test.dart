import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/operation_outbox_key_store.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/operation_outbox_security_lock_store.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/sqlite_operation_outbox_store.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/operation_outbox.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('SqliteOperationOutboxStore', () {
    late Directory directory;
    late String databasePath;
    late _MemoryKeyStore keyStore;
    late _MemorySecurityLockStore securityLockStore;
    late _MutableClock clock;
    late _IdSequence ids;
    late SqliteOperationOutboxStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mfa-outbox-test-');
      databasePath = '${directory.path}/operation_outbox.sqlite';
      keyStore = _MemoryKeyStore();
      securityLockStore = _MemorySecurityLockStore();
      clock = _MutableClock(DateTime.utc(2026, 7, 29, 10, 2));
      ids = _IdSequence();
      store = _store(
        databasePath: databasePath,
        keyStore: keyStore,
        securityLockStore: securityLockStore,
        clock: clock,
        ids: ids,
      );
    });

    tearDown(() async {
      await store.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('Android secure storage never auto-resets the outbox namespace', () {
      final options = operationOutboxSecureStorage.aOptions.toMap();

      expect(options['resetOnError'], 'false');
      expect(
        options['storageNamespace'],
        'mobile_finance_assistant_operation_outbox_v1',
      );
    });

    test(
      'enqueues once, preserves FIFO retry, and scrubs synced payload',
      () async {
        final command = _command();

        final first = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: command,
        );
        final duplicate = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: command,
        );

        expect(first.wasExisting, isFalse);
        expect(first.record.state, OperationOutboxState.pending);
        expect(duplicate.wasExisting, isTrue);
        expect(duplicate.record.localId, first.record.localId);
        expect(
          await store.readForPrincipal(principalScopeId: _otherPrincipal),
          isEmpty,
        );

        final claimed = await store.claimNextDue(principalScopeId: _principal);
        expect(claimed?.state, OperationOutboxState.syncing);
        expect(claimed?.attemptCount, 1);
        final retrying = await store.markRetryableFailure(
          localId: claimed!.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          errorCode: OperationOutboxErrorCode.timeout,
        );
        expect(retrying.state, OperationOutboxState.retryableFailure);
        expect(
          retrying.nextAttemptAtUtc,
          clock.now.add(const Duration(seconds: 2)),
        );
        expect(await store.claimNextDue(principalScopeId: _principal), isNull);

        await store.retryNow(principalScopeId: _principal);
        final reclaimed = await store.claimNextDue(
          principalScopeId: _principal,
        );
        expect(reclaimed?.attemptCount, 2);
        final synced = await store.markSynced(
          localId: reclaimed!.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          serverOperationId: _operationId,
        );

        expect(synced.state, OperationOutboxState.synced);
        expect(synced.confirmedCommand, isNull);
        expect(synced.serverOperationId, _operationId);
        expect(synced.homeConvergencePending, isTrue);
        final replay = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: command,
        );
        expect(replay.wasExisting, isTrue);
        expect(replay.record.state, OperationOutboxState.synced);
      },
    );

    test(
      'Home convergence marker survives restart and acknowledgement',
      () async {
        final queued = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        await store.claimNextDue(principalScopeId: _principal);
        final synced = await store.markSynced(
          localId: queued.record.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          serverOperationId: _operationId,
        );
        expect(synced.homeConvergencePending, isTrue);
        await store.close();

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        final afterRestart = (await store.readForPrincipal(
          principalScopeId: _principal,
        )).single;
        expect(afterRestart.state, OperationOutboxState.synced);
        expect(afterRestart.homeConvergencePending, isTrue);

        final converged = await store.markHomeConverged(
          localId: afterRestart.localId,
          principalScopeId: _principal,
          commandId: _commandId,
        );
        expect(converged.state, OperationOutboxState.synced);
        expect(converged.homeConvergencePending, isFalse);
        await store.close();

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        final acknowledgedAfterRestart = (await store.readForPrincipal(
          principalScopeId: _principal,
        )).single;
        expect(acknowledgedAfterRestart.state, OperationOutboxState.synced);
        expect(acknowledgedAfterRestart.homeConvergencePending, isFalse);
      },
    );

    test(
      'auth pause is resumed separately and security failure is permanent',
      () async {
        final command = _command();
        final queued = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: command,
        );
        await store.claimNextDue(principalScopeId: _principal);
        await store.markAuthenticationPaused(
          localId: queued.record.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          errorCode: OperationOutboxErrorCode.authenticationRequired,
        );

        await store.retryNow(principalScopeId: _principal);
        expect(await store.claimNextDue(principalScopeId: _principal), isNull);
        await store.resumeAuthentication(principalScopeId: _principal);
        final reclaimed = await store.claimNextDue(
          principalScopeId: _principal,
        );
        final failed = await store.markPermanentFailure(
          localId: reclaimed!.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          errorCode: OperationOutboxErrorCode.securityBlocked,
        );

        expect(failed.state, OperationOutboxState.permanentFailure);
        expect(
          securityLockStore.code,
          OperationOutboxErrorCode.securityBlocked,
        );
        await expectLater(
          store.retryNow(principalScopeId: _principal),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.securityBlocked,
            ),
          ),
        );
        await expectLater(
          store.claimNextDue(principalScopeId: _principal),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.securityBlocked,
            ),
          ),
        );
        await expectLater(
          store.enqueueConfirmed(
            principalScopeId: _principal,
            command: _command(commandId: _otherCommandId),
          ),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.securityBlocked,
            ),
          ),
        );
      },
    );

    test('clock rollback cannot corrupt or strand a queued command', () async {
      final queued = await store.enqueueConfirmed(
        principalScopeId: _principal,
        command: _command(),
      );
      clock.now = clock.now.subtract(const Duration(days: 2));

      final claimed = await store.claimNextDue(principalScopeId: _principal);

      expect(claimed?.localId, queued.record.localId);
      expect(claimed?.state, OperationOutboxState.syncing);
      expect(claimed?.stateChangedAtUtc, queued.record.stateChangedAtUtc);
      final retrying = await store.markRetryableFailure(
        localId: claimed!.localId,
        principalScopeId: _principal,
        commandId: _commandId,
        errorCode: OperationOutboxErrorCode.timeout,
      );
      expect(retrying.state, OperationOutboxState.retryableFailure);

      clock.now = clock.now.subtract(const Duration(days: 30));
      expect(await store.claimNextDue(principalScopeId: _principal), isNotNull);
    });

    test('recovers syncing after restart and locks on a missing key', () async {
      await store.enqueueConfirmed(
        principalScopeId: _principal,
        command: _command(),
      );
      await store.claimNextDue(principalScopeId: _principal);
      await store.close();

      store = _store(
        databasePath: databasePath,
        keyStore: keyStore,
        securityLockStore: securityLockStore,
        clock: clock,
        ids: ids,
      );
      expect(await store.recoverInterrupted(), 1);
      final recovered = (await store.readForPrincipal(
        principalScopeId: _principal,
      )).single;
      expect(recovered.state, OperationOutboxState.retryableFailure);
      expect(recovered.lastErrorCode, OperationOutboxErrorCode.interrupted);
      expect(recovered.attemptCount, 1);
      await store.close();

      await keyStore.delete();
      store = _store(
        databasePath: databasePath,
        keyStore: keyStore,
        securityLockStore: securityLockStore,
        clock: clock,
        ids: ids,
      );
      await expectLater(
        store.readForPrincipal(principalScopeId: _principal),
        throwsA(
          isA<OperationOutboxException>().having(
            (error) => error.code,
            'code',
            OperationOutboxErrorCode.locked,
          ),
        ),
      );
      expect(await File(databasePath).length(), greaterThan(0));
    });

    test(
      'SQLite database and WAL expose no command, identity, or master key',
      () async {
        await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );

        final files = directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.contains('operation_outbox.sqlite'))
            .toList();
        expect(files, isNotEmpty);
        final storedBytes = <int>[
          for (final file in files) ...await file.readAsBytes(),
        ];
        for (final marker in <List<int>>[
          utf8.encode('731.42'),
          utf8.encode('Synthetic Merchant Marker'),
          utf8.encode('Synthetic Category Marker'),
          utf8.encode('synthetic source expression marker'),
          utf8.encode(_principal),
          utf8.encode(_accountId),
          utf8.encode(_commandId),
          keyStore.key!,
        ]) {
          expect(_containsSubsequence(storedBytes, marker), isFalse);
        }
      },
    );

    test('fails closed at capacity without replacing an active row', () async {
      await store.close();
      store = _store(
        databasePath: databasePath,
        keyStore: keyStore,
        securityLockStore: securityLockStore,
        clock: clock,
        ids: ids,
        maxActivePerPrincipal: 1,
      );
      await store.enqueueConfirmed(
        principalScopeId: _principal,
        command: _command(),
      );

      await expectLater(
        store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(commandId: _otherCommandId),
        ),
        throwsA(
          isA<OperationOutboxException>().having(
            (error) => error.code,
            'code',
            OperationOutboxErrorCode.capacityExceeded,
          ),
        ),
      );
      expect(
        await store.readForPrincipal(principalScopeId: _principal),
        hasLength(1),
      );
    });

    test(
      'pending Home convergence consumes capacity until acknowledged',
      () async {
        await store.close();
        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
          maxActivePerPrincipal: 1,
        );
        final queued = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        await store.claimNextDue(principalScopeId: _principal);
        final synced = await store.markSynced(
          localId: queued.record.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          serverOperationId: _operationId,
        );

        await expectLater(
          store.enqueueConfirmed(
            principalScopeId: _principal,
            command: _command(commandId: _otherCommandId),
          ),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.capacityExceeded,
            ),
          ),
        );

        await store.markHomeConverged(
          localId: synced.localId,
          principalScopeId: _principal,
          commandId: _commandId,
        );
        final next = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(commandId: _otherCommandId),
        );
        expect(next.record.state, OperationOutboxState.pending);
      },
    );

    test(
      'retention authenticates clear metadata before deleting a row',
      () async {
        await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        await store.close();
        final raw = await databaseFactoryFfi.openDatabase(databasePath);
        await raw.update('operation_outbox', <String, Object?>{
          'state': OperationOutboxState.synced.wireName,
          'synced_at_epoch_ms': 0,
        });
        await raw.close();

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        await expectLater(
          store.readForPrincipal(principalScopeId: _principal),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.corruptPayload,
            ),
          ),
        );
        await store.close();

        final verification = await databaseFactoryFfi.openDatabase(
          databasePath,
        );
        final counts = await verification.rawQuery(
          'SELECT COUNT(*) AS row_count FROM operation_outbox',
        );
        final rowCount = counts.single['row_count'];
        await verification.close();
        expect(rowCount, 1);
      },
    );

    test(
      'tampered ciphertext durably locks every principal across restart',
      () async {
        await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        await store.close();
        final raw = await databaseFactoryFfi.openDatabase(databasePath);
        final row = (await raw.query('operation_outbox')).single;
        final ciphertext = Uint8List.fromList(row['ciphertext']! as Uint8List);
        ciphertext[0] ^= 0x01;
        await raw.update('operation_outbox', <String, Object?>{
          'ciphertext': ciphertext,
        });
        await raw.close();

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        await expectLater(
          store.readForPrincipal(principalScopeId: _principal),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.corruptPayload,
            ),
          ),
        );
        expect(securityLockStore.code, OperationOutboxErrorCode.corruptPayload);
        await store.close();

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        await expectLater(
          store.enqueueConfirmed(
            principalScopeId: _otherPrincipal,
            command: _command(commandId: _otherCommandId),
          ),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.corruptPayload,
            ),
          ),
        );
        await expectLater(
          store.claimNextDue(principalScopeId: _otherPrincipal),
          throwsA(isA<OperationOutboxException>()),
        );
      },
    );

    test(
      'failed lock-marker write still re-detects corruption after restart',
      () async {
        await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        await store.close();
        final raw = await databaseFactoryFfi.openDatabase(databasePath);
        final row = (await raw.query('operation_outbox')).single;
        final mac = Uint8List.fromList(row['mac']! as Uint8List);
        mac[0] ^= 0x01;
        await raw.update('operation_outbox', <String, Object?>{'mac': mac});
        await raw.close();
        securityLockStore.writeFailuresRemaining = 1;

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        await expectLater(
          store.readForPrincipal(principalScopeId: _principal),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.locked,
            ),
          ),
        );
        expect(securityLockStore.code, isNull);
        await store.close();

        store = _store(
          databasePath: databasePath,
          keyStore: keyStore,
          securityLockStore: securityLockStore,
          clock: clock,
          ids: ids,
        );
        await expectLater(
          store.enqueueConfirmed(
            principalScopeId: _otherPrincipal,
            command: _command(commandId: _otherCommandId),
          ),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.corruptPayload,
            ),
          ),
        );
        expect(securityLockStore.code, OperationOutboxErrorCode.corruptPayload);
      },
    );

    test(
      'failed initialization can be retried without process restart',
      () async {
        keyStore.readFailuresRemaining = 1;

        await expectLater(
          store.enqueueConfirmed(
            principalScopeId: _principal,
            command: _command(),
          ),
          throwsA(
            isA<OperationOutboxException>().having(
              (error) => error.code,
              'code',
              OperationOutboxErrorCode.storageUnavailable,
            ),
          ),
        );

        final queued = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        expect(queued.record.state, OperationOutboxState.pending);
      },
    );

    test(
      'retention preserves pending Home convergence until acknowledged',
      () async {
        final queued = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        await store.claimNextDue(principalScopeId: _principal);
        await store.markSynced(
          localId: queued.record.localId,
          principalScopeId: _principal,
          commandId: _commandId,
          serverOperationId: _operationId,
        );

        clock.advance(const Duration(hours: 23));
        expect(await store.purgeExpiredSynced(), 0);
        clock.advance(const Duration(hours: 2));
        expect(await store.purgeExpiredSynced(), 0);
        final pending = (await store.readForPrincipal(
          principalScopeId: _principal,
        )).single;
        expect(pending.homeConvergencePending, isTrue);

        await store.markHomeConverged(
          localId: pending.localId,
          principalScopeId: _principal,
          commandId: _commandId,
        );
        expect(await store.purgeExpiredSynced(), 1);
        expect(
          await store.readForPrincipal(principalScopeId: _principal),
          isEmpty,
        );
      },
    );

    test('cap cleanup preserves pending Home convergence tombstones', () async {
      await store.close();
      store = _store(
        databasePath: databasePath,
        keyStore: keyStore,
        securityLockStore: securityLockStore,
        clock: clock,
        ids: ids,
        maxSyncedPerPrincipal: 1,
      );

      final pending = await _syncCommand(
        store,
        command: _command(),
        commandId: _commandId,
        operationId: _operationId,
      );
      final firstAcknowledged = await _syncCommand(
        store,
        command: _command(commandId: _otherCommandId),
        commandId: _otherCommandId,
        operationId: _otherOperationId,
      );
      await store.markHomeConverged(
        localId: firstAcknowledged.localId,
        principalScopeId: _principal,
        commandId: _otherCommandId,
      );
      final secondAcknowledged = await _syncCommand(
        store,
        command: _command(commandId: _thirdCommandId),
        commandId: _thirdCommandId,
        operationId: _thirdOperationId,
      );
      await store.markHomeConverged(
        localId: secondAcknowledged.localId,
        principalScopeId: _principal,
        commandId: _thirdCommandId,
      );

      expect(await store.purgeExpiredSynced(), 1);
      final retained = await store.readForPrincipal(
        principalScopeId: _principal,
      );
      expect(retained, hasLength(2));
      expect(
        retained
            .singleWhere((record) => record.localId == pending.localId)
            .homeConvergencePending,
        isTrue,
      );
      expect(
        retained.where((record) => !record.homeConvergencePending),
        hasLength(1),
      );
    });
  });

  group('SqliteOperationOutboxStore on an Android-strict database', () {
    late Directory directory;
    late _AndroidStrictDatabaseFactory databaseFactory;
    late SqliteOperationOutboxStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('mfa-outbox-android-');
      databaseFactory = _AndroidStrictDatabaseFactory(databaseFactoryFfi);
      store = SqliteOperationOutboxStore(
        keyStore: _MemoryKeyStore(),
        securityLockStore: _MemorySecurityLockStore(),
        databaseFactory: databaseFactory,
        databasePathProvider: () async =>
            '${directory.path}/operation_outbox.sqlite',
        clock: _MutableClock(DateTime.utc(2026, 7, 29, 10, 2)).call,
        jitterUnit: () => 0.5,
        localIdFactory: _IdSequence().call,
      );
    });

    tearDown(() async {
      await store.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'enqueues a confirmed command when execute() rejects result rows',
      () async {
        final queued = await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );

        expect(queued.wasExisting, isFalse);
        expect(queued.record.state, OperationOutboxState.pending);
        expect(
          await store.readForPrincipal(principalScopeId: _principal),
          hasLength(1),
        );
      },
    );

    test(
      'never configures the outbox with a row-returning execute()',
      () async {
        await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );

        expect(databaseFactory.rejectedStatements, isEmpty);
        expect(databaseFactory.executedStatements, isNotEmpty);
      },
    );

    test(
      'applies busy_timeout and secure_delete to the open database',
      () async {
        await store.enqueueConfirmed(
          principalScopeId: _principal,
          command: _command(),
        );
        final database = databaseFactory.openedDatabase!;

        expect(await _pragmaValue(database, 'busy_timeout'), 5000);
        expect(await _pragmaValue(database, 'secure_delete'), 1);
      },
    );
  });
}

Future<Object?> _pragmaValue(Database database, String pragma) async {
  final rows = await database.rawQuery('PRAGMA $pragma');
  return rows.single.values.single;
}

const _principal = '11111111-1111-4111-8111-111111111111';
const _otherPrincipal = '99999999-9999-4999-8999-999999999999';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _commandId = '44444444-4444-4444-8444-444444444444';
const _otherCommandId = '66666666-6666-4666-8666-666666666666';
const _thirdCommandId = '77777777-7777-4777-8777-777777777777';
const _operationId = '55555555-5555-4555-8555-555555555555';
const _otherOperationId = '88888888-8888-4888-8888-888888888888';
const _thirdOperationId = '99999999-9999-4999-8999-999999999998';

SqliteOperationOutboxStore _store({
  required String databasePath,
  required _MemoryKeyStore keyStore,
  required _MemorySecurityLockStore securityLockStore,
  required _MutableClock clock,
  required _IdSequence ids,
  int maxActivePerPrincipal = 100,
  int maxSyncedPerPrincipal = 100,
}) => SqliteOperationOutboxStore(
  keyStore: keyStore,
  securityLockStore: securityLockStore,
  databaseFactory: databaseFactoryFfi,
  databasePathProvider: () async => databasePath,
  clock: clock.call,
  jitterUnit: () => 0.5,
  localIdFactory: ids.call,
  maxActivePerPrincipal: maxActivePerPrincipal,
  maxSyncedPerPrincipal: maxSyncedPerPrincipal,
);

Future<OperationOutboxRecord> _syncCommand(
  SqliteOperationOutboxStore store, {
  required FinanceOperationCommitCommand command,
  required String commandId,
  required String operationId,
}) async {
  final queued = await store.enqueueConfirmed(
    principalScopeId: _principal,
    command: command,
  );
  final claimed = await store.claimNextDue(principalScopeId: _principal);
  expect(claimed?.localId, queued.record.localId);
  return store.markSynced(
    localId: claimed!.localId,
    principalScopeId: _principal,
    commandId: commandId,
    serverOperationId: operationId,
  );
}

FinanceOperationCommitCommand _command({String commandId = _commandId}) {
  final draft = FinanceOperationDraft.fromJson(<String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'type': 'expense',
    'amount': '731.42',
    'currency': 'EUR',
    'accountId': _accountId,
    'category': 'Synthetic Category Marker',
    'merchant': 'Synthetic Merchant Marker',
    'capturedAt': '2026-07-29T10:00:00Z',
    'capturedTimezone': 'Europe/Berlin',
    'sourceExpression': 'synthetic source expression marker',
    'dateResolverVersion': 'calendar-relative-v1',
    'occurredOn': '2026-07-28',
    'occurredAt': null,
    'source': 'manual_text',
  });
  return FinanceOperationCommitCommand.fromReview(
    review: FinanceOperationNeedsConfirmation(
      draft: draft,
      draftHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    confirmedAt: DateTime.utc(2026, 7, 29, 10, 1),
  );
}

final class _MemoryKeyStore implements OperationOutboxKeyStore {
  List<int>? key;
  int readFailuresRemaining = 0;

  @override
  Future<void> delete() async => key = null;

  @override
  Future<List<int>?> read() async {
    if (readFailuresRemaining > 0) {
      readFailuresRemaining -= 1;
      throw StateError('Synthetic key-store read failure.');
    }
    return key == null ? null : List<int>.from(key!);
  }

  @override
  Future<void> write(List<int> keyBytes) async {
    key = List<int>.from(keyBytes);
  }
}

final class _MemorySecurityLockStore
    implements OperationOutboxSecurityLockStore {
  OperationOutboxErrorCode? code;
  int readFailuresRemaining = 0;
  int writeFailuresRemaining = 0;

  @override
  Future<OperationOutboxErrorCode?> read() async {
    if (readFailuresRemaining > 0) {
      readFailuresRemaining -= 1;
      throw StateError('Synthetic security-lock read failure.');
    }
    return code;
  }

  @override
  Future<void> engage(OperationOutboxErrorCode value) async {
    if (writeFailuresRemaining > 0) {
      writeFailuresRemaining -= 1;
      throw StateError('Synthetic security-lock write failure.');
    }
    code = value;
  }
}

final class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

final class _IdSequence {
  var _next = 0;

  String call() {
    _next += 1;
    return '77777777-7777-4777-8777-${_next.toString().padLeft(12, '0')}';
  }
}

/// Reproduces the Android platform contract that `sqflite_common_ffi` does not
/// enforce: `SQLiteDatabase.execSQL` steps the statement and then rejects it
/// with `Queries can be performed using SQLiteDatabase query or rawQuery
/// methods only.` as soon as it produces a result row. `PRAGMA busy_timeout`
/// and `PRAGMA secure_delete` always return their new value, so a device
/// regression is invisible to a plain in-memory factory.
final class _AndroidStrictDatabaseFactory implements DatabaseFactory {
  _AndroidStrictDatabaseFactory(this._delegate);

  final DatabaseFactory _delegate;
  final List<String> executedStatements = <String>[];
  final List<String> rejectedStatements = <String>[];
  Database? openedDatabase;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final requested = options;
    final strict = requested == null
        ? null
        : OpenDatabaseOptions(
            version: requested.version,
            onConfigure: requested.onConfigure == null
                ? null
                : (database) => requested.onConfigure!(_wrap(database)),
            onCreate: requested.onCreate == null
                ? null
                : (database, version) =>
                      requested.onCreate!(_wrap(database), version),
            onUpgrade: requested.onUpgrade == null
                ? null
                : (database, from, to) =>
                      requested.onUpgrade!(_wrap(database), from, to),
            onDowngrade: requested.onDowngrade == null
                ? null
                : (database, from, to) =>
                      requested.onDowngrade!(_wrap(database), from, to),
            onOpen: requested.onOpen == null
                ? null
                : (database) => requested.onOpen!(_wrap(database)),
            readOnly: requested.readOnly,
            singleInstance: requested.singleInstance,
          );
    return openedDatabase = _wrap(
      await _delegate.openDatabase(path, options: strict),
    );
  }

  _AndroidStrictDatabase _wrap(Database database) =>
      _AndroidStrictDatabase(database, this);

  @override
  Future<String> getDatabasesPath() => _delegate.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) =>
      _delegate.setDatabasesPath(path);

  @override
  Future<void> deleteDatabase(String path) => _delegate.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => _delegate.databaseExists(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      _delegate.writeDatabaseBytes(path, bytes);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      _delegate.readDatabaseBytes(path);
}

final class _AndroidStrictDatabase implements Database {
  _AndroidStrictDatabase(this._delegate, this._factory);

  /// Statement prefixes that SQLite may answer with a result row. Anything else
  /// (DDL and DML) can never produce one, so it keeps the plain execute path.
  static final RegExp _mayReturnRows = RegExp(
    r'^\s*(SELECT|PRAGMA|EXPLAIN|WITH|VALUES)\b',
    caseSensitive: false,
  );

  final Database _delegate;
  final _AndroidStrictDatabaseFactory _factory;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    _factory.executedStatements.add(sql);
    if (!_mayReturnRows.hasMatch(sql)) {
      return _delegate.execute(sql, arguments);
    }
    // Android steps the statement first and only then rejects a produced row,
    // so the pragma side effect happens either way.
    final rows = await _delegate.rawQuery(sql, arguments);
    if (rows.isEmpty) return;
    _factory.rejectedStatements.add(sql);
    throw _AndroidExecSqlException(
      'Queries can be performed using SQLiteDatabase query or rawQuery '
      'methods only.',
    );
  }

  // The outbox never calls execute() inside a transaction, so the delegate
  // transaction object is forwarded unchanged.
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _delegate.transaction(action, exclusive: exclusive);

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _delegate.readTransaction(action);

  @override
  Database get database => this;

  @override
  String get path => _delegate.path;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Future<void> close() => _delegate.close();

  @override
  Batch batch() => _delegate.batch();

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _delegate.rawInsert(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _delegate.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _delegate.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _delegate.rawQuery(sql, arguments);

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _delegate.rawQueryCursor(sql, arguments, bufferSize: bufferSize);

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _delegate.queryCursor(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
    bufferSize: bufferSize,
  );

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _delegate.rawUpdate(sql, arguments);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _delegate.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _delegate.rawDelete(sql, arguments);

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _delegate.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      throw UnsupportedError('devInvokeMethod is not used by the outbox.');

  @override
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) => throw UnsupportedError('devInvokeSqlMethod is not used by the outbox.');
}

final class _AndroidExecSqlException extends DatabaseException {
  _AndroidExecSqlException(super.message);

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;
}

bool _containsSubsequence(List<int> bytes, List<int> marker) {
  if (marker.isEmpty || marker.length > bytes.length) return false;
  for (var start = 0; start <= bytes.length - marker.length; start += 1) {
    var matches = true;
    for (var index = 0; index < marker.length; index += 1) {
      if (bytes[start + index] != marker[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
