import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/auth/application/auth_controller.dart';
import 'package:mobile_finance_assistant/features/auth/data/auth_session_store.dart';
import 'package:mobile_finance_assistant/features/auth/domain/auth_session.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_dependencies.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/operation_sync_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/operation_outbox_store.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/operation_outbox.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

import '../../../support/home_contract_fixture.dart';

const _principalScopeId = '11111111-1111-4111-8111-111111111111';
const _otherPrincipalScopeId = '99999999-9999-4999-8999-999999999999';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _commandId = '33333333-3333-4333-8333-333333333333';
const _otherCommandId = '55555555-5555-4555-8555-555555555555';
const _operationId = '44444444-4444-4444-8444-444444444444';
const _revisionA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _revisionB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _draftHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
final _now = DateTime.utc(2026, 7, 30, 12);

void main() {
  group('OperationSyncController', () {
    test(
      'persists a confirmed command before the first network call',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) => _successCommit(command),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryAccepted>());
        expect(repository.commands, hasLength(1));
        expect(
          events.indexOf('store.enqueue'),
          lessThan(events.indexOf('network.commit')),
        );
      },
    );

    test(
      'reports durable acceptance before waiting for Home convergence',
      () async {
        final events = <String>[];
        final homeResult = Completer<HomeRepositoryResult>();
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) => _successCommit(command),
        );
        final home = _RecordingHomeRepository(
          events,
          onFetch: () => homeResult.future,
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          homeRepository: home,
          events: events,
        );
        addTearDown(harness.dispose);
        FinanceOperationCommit? acceptedCommit;
        var deliveryCompleted = false;

        final delivery = harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
          onAccepted: (commit) => acceptedCommit = commit,
        )..whenComplete(() => deliveryCompleted = true);
        for (
          var index = 0;
          index < 20 && (acceptedCommit == null || home.fetches == 0);
          index += 1
        ) {
          await Future<void>.delayed(Duration.zero);
          await harness.container.pump();
        }

        expect(store.single.state, OperationOutboxState.synced);
        expect(acceptedCommit?.operation.operationId, _operationId);
        expect(deliveryCompleted, isFalse);
        expect(
          events.indexOf('store.markSynced'),
          lessThan(events.indexOf('home.fetch')),
        );

        homeResult.complete(
          const HomeFailureResult(
            type: HomeFailureType.unknown,
            requestId: 'req_test_home_failure',
          ),
        );
        final result = await delivery;

        expect(result, isA<OperationDeliveryAccepted>());
        expect(
          (result as OperationDeliveryAccepted).homeStatus,
          AcceptedWriteHomeConvergenceResult.failed,
        );
        expect(store.single.homeConvergencePending, isTrue);
        expect(events, isNot(contains('store.markHomeConverged')));
      },
    );

    test(
      'automatically retries durable Home convergence without resending Finance',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) => _successCommit(command),
        );
        late final _RecordingHomeRepository home;
        home = _RecordingHomeRepository(
          events,
          onFetch: () async => home.fetches == 1
              ? const HomeFailureResult(
                  type: HomeFailureType.unknown,
                  requestId: 'req_home_retry_pending',
                )
              : HomeDataResult(loadHomeFixtureSnapshotSync('populated.json')),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          homeRepository: home,
          events: events,
          homeConvergenceRetryDelay: Duration.zero,
        );
        addTearDown(harness.dispose);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryAccepted>());
        expect(
          (result as OperationDeliveryAccepted).homeStatus,
          AcceptedWriteHomeConvergenceResult.failed,
        );
        expect(repository.commands, hasLength(1));
        expect(home.fetches, 1);
        expect(store.single.state, OperationOutboxState.synced);
        expect(store.single.homeConvergencePending, isTrue);

        for (
          var index = 0;
          index < 30 && store.single.homeConvergencePending;
          index += 1
        ) {
          await Future<void>.delayed(Duration.zero);
          await harness.container.pump();
        }

        expect(repository.commands, hasLength(1));
        expect(home.fetches, 2);
        expect(store.single.homeConvergencePending, isFalse);
        expect(
          events.where((event) => event == 'store.markHomeConverged'),
          hasLength(1),
        );
        expect(
          harness.container.read(operationSyncControllerProvider).phase,
          OperationSyncPhase.idle,
        );
      },
    );

    test(
      'a fresh controller converges durable Home state without resending Finance',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final firstRepository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) => _successCommit(command),
        );
        final firstHarness = await _Harness.create(
          store: store,
          repository: firstRepository,
          events: events,
        );

        final firstResult = await firstHarness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: firstHarness.command,
        );

        expect(firstResult, isA<OperationDeliveryAccepted>());
        expect(firstRepository.commands, hasLength(1));
        expect(store.single.state, OperationOutboxState.synced);
        expect(store.single.homeConvergencePending, isTrue);
        firstHarness.dispose();

        final secondRepository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Finance must not be resent.'),
        );
        final home = _RecordingHomeRepository(
          events,
          onFetch: () async =>
              HomeDataResult(loadHomeFixtureSnapshotSync('populated.json')),
        );
        final observedPhases = <OperationSyncPhase>[];
        final secondHarness = await _Harness.create(
          store: store,
          repository: secondRepository,
          homeRepository: home,
          events: events,
          observedPhases: observedPhases,
        );
        addTearDown(secondHarness.dispose);

        expect(secondRepository.commands, isEmpty);
        expect(home.fetches, 1);
        expect(store.single.state, OperationOutboxState.synced);
        expect(store.single.homeConvergencePending, isFalse);
        expect(events, contains('store.markHomeConverged'));
        expect(
          observedPhases,
          isNot(contains(OperationSyncPhase.synchronizing)),
          reason:
              'A server-accepted Home marker must never announce a pending '
              'Finance send after restart.',
        );
      },
    );

    test('an enqueue storage failure performs zero network requests', () async {
      final events = <String>[];
      final store = _FakeOperationOutboxStore(
        events: events,
        now: _now,
        enqueueFailure: OperationOutboxErrorCode.storageUnavailable,
      );
      final repository = _FakeFinanceEntryRepository(
        events: events,
        onCommit: (_, _) => throw StateError('Network must not be called.'),
      );
      final harness = await _Harness.create(
        store: store,
        repository: repository,
        events: events,
      );
      addTearDown(harness.dispose);

      final result = await harness.controller.enqueueAndSynchronize(
        expectedPrincipalScopeId: _principalScopeId,
        command: harness.command,
      );

      expect(result, isA<OperationDeliveryStorageFailure>());
      expect(repository.commands, isEmpty);
      expect(events.where((event) => event == 'network.commit'), isEmpty);
    });

    test(
      'an enqueue key lock returns permanent attention without HTTP',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(
          events: events,
          now: _now,
          enqueueFailure: OperationOutboxErrorCode.locked,
        );
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Network must not be called.'),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryPermanentFailure>());
        expect(
          (result as OperationDeliveryPermanentFailure).code,
          OperationOutboxErrorCode.locked,
        );
        expect(repository.commands, isEmpty);
        expect(
          harness.container.read(operationSyncControllerProvider).phase,
          OperationSyncPhase.locked,
        );
      },
    );

    test(
      'offline retry sends the exact command and converges Home only after sync',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, call) {
            if (call == 1) {
              return _failure(FinanceEntryFailureKind.offline);
            }
            return _successCommit(command, idempotentReplay: true);
          },
        );
        final home = _RecordingHomeRepository(events);
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          homeRepository: home,
          events: events,
        );
        addTearDown(harness.dispose);
        final originalWire = harness.command.toJson();

        final first = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(first, isA<OperationDeliveryQueued>());
        expect(
          (first as OperationDeliveryQueued).code,
          OperationOutboxErrorCode.offline,
        );
        expect(store.single.state, OperationOutboxState.retryableFailure);
        expect(home.invalidations, 0);
        expect(home.fetches, 0);

        await harness.controller.retryNow();

        expect(repository.commands, hasLength(2));
        expect(repository.commands[0], same(harness.command));
        expect(repository.commands[1], same(harness.command));
        expect(repository.commands[1].toJson(), originalWire);
        expect(store.single.state, OperationOutboxState.synced);
        expect(store.single.serverOperationId, _operationId);
        expect(home.invalidations, 1);
        expect(home.fetches, 1);
        expect(
          events.indexOf('store.markSynced'),
          lessThan(events.indexOf('home.invalidate')),
        );
        expect(
          events.indexOf('home.invalidate'),
          lessThan(events.indexOf('home.fetch')),
        );
      },
    );

    test(
      'a response completed while suspended converges Home only after resume',
      () async {
        final events = <String>[];
        final response =
            Completer<FinanceEntryResult<FinanceOperationCommit>>();
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => response.future,
        );
        final home = _RecordingHomeRepository(events);
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          homeRepository: home,
          events: events,
        );
        addTearDown(harness.dispose);

        final delivery = harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );
        for (
          var index = 0;
          index < 20 && repository.commands.isEmpty;
          index += 1
        ) {
          await Future<void>.delayed(Duration.zero);
          await harness.container.pump();
        }
        expect(repository.commands, hasLength(1));
        harness.controller.setForeground(false);
        response.complete(_successCommit(harness.command));

        final result = await delivery;

        expect(result, isA<OperationDeliveryAccepted>());
        expect(home.invalidations, 0);
        expect(home.fetches, 0);
        expect(store.single.state, OperationOutboxState.synced);

        harness.controller.setForeground(true);
        for (var index = 0; index < 20 && home.fetches == 0; index += 1) {
          await Future<void>.delayed(Duration.zero);
          await harness.container.pump();
        }

        expect(repository.commands, hasLength(1));
        expect(home.invalidations, 1);
        expect(home.fetches, 1);
      },
    );

    test(
      'background during projector delay stops polling until resume',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) => _successCommit(command),
        );
        late final _RecordingHomeRepository home;
        home = _RecordingHomeRepository(
          events,
          onFetch: () async => home.fetches == 1
              ? const HomeFailureResult(
                  type: HomeFailureType.serviceUnavailable,
                  requestId: 'req_projection_pending',
                )
              : HomeDataResult(loadHomeFixtureSnapshotSync('populated.json')),
        );
        late final _Harness harness;
        harness = await _Harness.create(
          store: store,
          repository: repository,
          homeRepository: home,
          events: events,
          acceptedWriteDelay: (_) async {
            harness.controller.setForeground(false);
          },
        );
        addTearDown(harness.dispose);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryAccepted>());
        expect(
          (result as OperationDeliveryAccepted).homeStatus,
          AcceptedWriteHomeConvergenceResult.failed,
        );
        expect(repository.commands, hasLength(1));
        expect(home.fetches, 1);
        expect(store.single.homeConvergencePending, isTrue);
        expect(
          harness.container.read(operationSyncControllerProvider).phase,
          OperationSyncPhase.homeConvergencePending,
        );
        expect(
          harness.container
              .read(operationSyncControllerProvider)
              .homeConvergenceCount,
          1,
        );

        harness.controller.setForeground(true);
        for (
          var index = 0;
          index < 30 && store.single.homeConvergencePending;
          index += 1
        ) {
          await Future<void>.delayed(Duration.zero);
          await harness.container.pump();
        }

        expect(repository.commands, hasLength(1));
        expect(home.fetches, 2);
        expect(store.single.homeConvergencePending, isFalse);
        expect(
          harness.container.read(operationSyncControllerProvider).phase,
          OperationSyncPhase.idle,
        );
      },
    );

    test(
      'background state persists a command without claiming or sending it',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) => _successCommit(command),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        harness.controller.setForeground(false);

        final queued = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );
        await harness.controller.synchronize();

        expect(queued, isA<OperationDeliveryQueued>());
        expect(store.single.state, OperationOutboxState.pending);
        expect(repository.commands, isEmpty);

        harness.controller.setForeground(true);
        for (
          var index = 0;
          index < 20 && repository.commands.isEmpty;
          index += 1
        ) {
          await Future<void>.delayed(Duration.zero);
          await harness.container.pump();
        }

        expect(repository.commands, hasLength(1));
        expect(store.single.state, OperationOutboxState.synced);
      },
    );

    test(
      'suspension after claim prevents the HTTP request from starting',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Network must not be called.'),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        store.afterClaim = () => harness.controller.setForeground(false);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryQueued>());
        expect(repository.commands, isEmpty);
        expect(store.single.state, OperationOutboxState.retryableFailure);
        expect(
          store.single.lastErrorCode,
          OperationOutboxErrorCode.interrupted,
        );
      },
    );

    test(
      'account epoch change after claim pauses before the HTTP request',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Network must not be called.'),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        store.afterClaim = () {
          harness.container.read(authAccountEpochProvider.notifier).advance();
          harness.container.read(operationSyncControllerProvider);
        };

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryQueued>());
        expect(repository.commands, isEmpty);
        expect(store.single.state, OperationOutboxState.retryableFailure);
        expect(
          store.single.lastErrorCode,
          OperationOutboxErrorCode.sessionChanged,
        );
      },
    );

    test(
      'suspension at the repository boundary prevents the HTTP request',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Network must not be called.'),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        repository.beforePreflight = () {
          harness.controller.setForeground(false);
        };

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryQueued>());
        expect(repository.commands, isEmpty);
        expect(store.single.state, OperationOutboxState.retryableFailure);
        expect(
          store.single.lastErrorCode,
          OperationOutboxErrorCode.interrupted,
        );
      },
    );

    test(
      'account epoch change at the repository boundary prevents the HTTP request',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Network must not be called.'),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        repository.beforePreflight = () {
          harness.container.read(authAccountEpochProvider.notifier).advance();
        };

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryQueued>());
        expect(repository.commands, isEmpty);
        expect(store.single.state, OperationOutboxState.retryableFailure);
        expect(
          store.single.lastErrorCode,
          OperationOutboxErrorCode.sessionChanged,
        );
      },
    );

    test(
      'a failed local transition is recovered by manual retry in one process',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(
          events: events,
          now: _now,
          markSyncedFailuresRemaining: 1,
        );
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, call) =>
              _successCommit(command, idempotentReplay: call > 1),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);

        final first = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(first, isA<OperationDeliveryQueued>());
        expect(store.single.state, OperationOutboxState.syncing);
        expect(repository.commands, hasLength(1));

        await harness.controller.retryNow();

        expect(repository.commands, hasLength(2));
        expect(repository.commands[0], same(repository.commands[1]));
        expect(store.single.state, OperationOutboxState.synced);
        expect(events, contains('store.recover.interrupted'));
      },
    );

    test(
      'a critical failure locks later commands across drain cycles',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => _failure(FinanceEntryFailureKind.securityFailure),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        await store.enqueueConfirmed(
          principalScopeId: _principalScopeId,
          command: harness.command,
        );
        await store.enqueueConfirmed(
          principalScopeId: _principalScopeId,
          command: _command(commandId: _otherCommandId),
        );

        await harness.controller.synchronize();
        await harness.controller.synchronize();

        expect(repository.commands, hasLength(1));
        expect(
          store.records.values.first.state,
          OperationOutboxState.permanentFailure,
        );
        expect(store.records.values.last.state, OperationOutboxState.pending);
        expect(
          harness.container.read(operationSyncControllerProvider).phase,
          OperationSyncPhase.locked,
        );
      },
    );

    test(
      'a lock found while delivering a new command returns permanent attention',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => _failure(FinanceEntryFailureKind.securityFailure),
        );
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
        );
        addTearDown(harness.dispose);
        await store.enqueueConfirmed(
          principalScopeId: _principalScopeId,
          command: _command(commandId: _otherCommandId),
        );

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryPermanentFailure>());
        expect(
          (result as OperationDeliveryPermanentFailure).code,
          OperationOutboxErrorCode.securityBlocked,
        );
        expect(repository.commands, hasLength(1));
        expect(
          harness.container.read(operationSyncControllerProvider).phase,
          OperationSyncPhase.locked,
        );
      },
    );

    test(
      'a response for another principal is permanent and never converges Home',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (command, _) =>
              _successCommit(command, responseUserId: _otherPrincipalScopeId),
        );
        final home = _RecordingHomeRepository(events);
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          homeRepository: home,
          events: events,
        );
        addTearDown(harness.dispose);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryPermanentFailure>());
        expect(
          (result as OperationDeliveryPermanentFailure).code,
          OperationOutboxErrorCode.responseScopeMismatch,
        );
        expect(store.single.state, OperationOutboxState.permanentFailure);
        expect(
          store.single.lastErrorCode,
          OperationOutboxErrorCode.responseScopeMismatch,
        );
        expect(home.invalidations, 0);
        expect(home.fetches, 0);
      },
    );

    test('a different authenticated account cannot enqueue or send', () async {
      final events = <String>[];
      final store = _FakeOperationOutboxStore(events: events, now: _now);
      final repository = _FakeFinanceEntryRepository(
        events: events,
        onCommit: (_, _) => throw StateError('Network must not be called.'),
      );
      final harness = await _Harness.create(
        store: store,
        repository: repository,
        events: events,
        session: _session(scope: _otherPrincipalScopeId),
      );
      addTearDown(harness.dispose);

      final result = await harness.controller.enqueueAndSynchronize(
        expectedPrincipalScopeId: _principalScopeId,
        command: harness.command,
      );

      expect(result, isA<OperationDeliveryAuthenticationRequired>());
      expect(store.records, isEmpty);
      expect(repository.commands, isEmpty);
    });

    test(
      'an account revision change after claim pauses before network',
      () async {
        final events = <String>[];
        final store = _FakeOperationOutboxStore(events: events, now: _now);
        final repository = _FakeFinanceEntryRepository(
          events: events,
          onCommit: (_, _) => throw StateError('Network must not be called.'),
        );
        final sessionStore = _FakeAuthSessionStore();
        final harness = await _Harness.create(
          store: store,
          repository: repository,
          events: events,
          sessionStore: sessionStore,
        );
        addTearDown(harness.dispose);
        sessionStore.scriptReads([
          _session(),
          _session(),
          _session(revision: _revisionB),
          _session(revision: _revisionB),
        ]);

        final result = await harness.controller.enqueueAndSynchronize(
          expectedPrincipalScopeId: _principalScopeId,
          command: harness.command,
        );

        expect(result, isA<OperationDeliveryQueued>());
        expect(
          (result as OperationDeliveryQueued).code,
          OperationOutboxErrorCode.sessionChanged,
        );
        expect(repository.commands, isEmpty);
        expect(store.single.state, OperationOutboxState.retryableFailure);
        expect(store.single.nextAttemptAtUtc, isNull);
        expect(
          store.single.lastErrorCode,
          OperationOutboxErrorCode.sessionChanged,
        );
      },
    );

    test('a lost response is retained as an ambiguous retry', () async {
      final events = <String>[];
      final store = _FakeOperationOutboxStore(events: events, now: _now);
      final repository = _FakeFinanceEntryRepository(
        events: events,
        onCommit: (_, _) => throw StateError('Response lost after send.'),
      );
      final home = _RecordingHomeRepository(events);
      final harness = await _Harness.create(
        store: store,
        repository: repository,
        homeRepository: home,
        events: events,
      );
      addTearDown(harness.dispose);

      final result = await harness.controller.enqueueAndSynchronize(
        expectedPrincipalScopeId: _principalScopeId,
        command: harness.command,
      );

      expect(result, isA<OperationDeliveryQueued>());
      expect(
        (result as OperationDeliveryQueued).code,
        OperationOutboxErrorCode.ambiguousResult,
      );
      expect(store.single.state, OperationOutboxState.retryableFailure);
      expect(
        store.single.lastErrorCode,
        OperationOutboxErrorCode.ambiguousResult,
      );
      expect(store.single.confirmedCommand, same(harness.command));
      expect(home.invalidations, 0);
      expect(home.fetches, 0);
    });
  });
}

final class _Harness {
  _Harness({
    required this.container,
    required this.controller,
    required this.command,
    this.phaseSubscription,
  });

  final ProviderContainer container;
  final OperationSyncController controller;
  final FinanceOperationCommitCommand command;
  final ProviderSubscription<OperationSyncState>? phaseSubscription;

  static Future<_Harness> create({
    required _FakeOperationOutboxStore store,
    required _FakeFinanceEntryRepository repository,
    required List<String> events,
    _FakeAuthSessionStore? sessionStore,
    AuthSession? session,
    _RecordingHomeRepository? homeRepository,
    AcceptedWriteHomeDelay? acceptedWriteDelay,
    Duration? homeConvergenceRetryDelay,
    List<OperationSyncPhase>? observedPhases,
  }) async {
    final authStore = sessionStore ?? _FakeAuthSessionStore();
    final home = homeRepository ?? _RecordingHomeRepository(events);
    final container = ProviderContainer(
      overrides: [
        operationOutboxStoreProvider.overrideWithValue(store),
        authSessionStoreProvider.overrideWithValue(authStore),
        financeEntryRepositoryDependencyProvider.overrideWithValue(repository),
        homeRepositoryProvider.overrideWithValue(home),
        operationSyncClockProvider.overrideWithValue(() => _now),
        operationSyncJitterProvider.overrideWithValue(() => 0.5),
        if (homeConvergenceRetryDelay != null)
          operationHomeConvergenceRetryDelayProvider.overrideWithValue(
            homeConvergenceRetryDelay,
          ),
        acceptedWriteHomeDelayProvider.overrideWithValue(
          acceptedWriteDelay ?? (_) async {},
        ),
      ],
    );
    final phaseSubscription = observedPhases == null
        ? null
        : container.listen(
            operationSyncControllerProvider,
            (_, next) => observedPhases.add(next.phase),
            fireImmediately: true,
          );
    final controller = container.read(operationSyncControllerProvider.notifier);

    // The production provider performs a safe startup recovery in a microtask.
    // It starts paused until the shell reports a resumed lifecycle. Keep it
    // unauthenticated during that bounded initialization so each test controls
    // the first account-scoped drain explicitly.
    for (
      var index = 0;
      index < 20 && !events.contains('store.purge');
      index += 1
    ) {
      await Future<void>.delayed(Duration.zero);
      await container.pump();
    }
    expect(events, contains('store.recover'));
    expect(events, contains('store.purge'));
    authStore.current = session ?? _session();
    controller.setForeground(true);
    await controller.synchronize(resumeAuthentication: true);
    expect(authStore.readCalls, greaterThan(0));

    return _Harness(
      container: container,
      controller: controller,
      command: _command(),
      phaseSubscription: phaseSubscription,
    );
  }

  void dispose() {
    phaseSubscription?.close();
    container.dispose();
  }
}

final class _FakeOperationOutboxStore implements OperationOutboxStore {
  _FakeOperationOutboxStore({
    required this.events,
    required this.now,
    this.enqueueFailure,
    this.markSyncedFailuresRemaining = 0,
  });

  final List<String> events;
  final DateTime now;
  final OperationOutboxErrorCode? enqueueFailure;
  int markSyncedFailuresRemaining;
  void Function()? afterClaim;
  final LinkedHashMap<String, OperationOutboxRecord> records = LinkedHashMap();

  OperationOutboxRecord get single => records.values.single;

  String _key(String scope, String commandId) => '$scope::$commandId';

  @override
  Future<OperationOutboxEnqueueResult> enqueueConfirmed({
    required String principalScopeId,
    required FinanceOperationCommitCommand command,
  }) async {
    events.add('store.enqueue');
    final failure = enqueueFailure;
    if (failure != null) throw OperationOutboxException(failure);
    final key = _key(principalScopeId, command.review.draft.commandId);
    final existing = records[key];
    if (existing != null) {
      return OperationOutboxEnqueueResult(record: existing, wasExisting: true);
    }
    final record = OperationOutboxRecord(
      localId: 'local-${command.review.draft.commandId}',
      principalScopeId: principalScopeId,
      financeAccountId: command.review.draft.accountId!,
      commandId: command.review.draft.commandId,
      state: OperationOutboxState.pending,
      transitionSequence: 0,
      createdAtUtc: now,
      stateChangedAtUtc: now,
      attemptCount: 0,
      confirmedCommand: command,
    );
    records[key] = record;
    return OperationOutboxEnqueueResult(record: record, wasExisting: false);
  }

  @override
  Future<OperationOutboxRecord?> claimNextDue({
    required String principalScopeId,
  }) async {
    events.add('store.claim');
    for (final record in records.values) {
      final code = record.lastErrorCode;
      if (record.state == OperationOutboxState.permanentFailure &&
          code != null &&
          operationOutboxSecurityLockCodes.contains(code)) {
        throw OperationOutboxException(code);
      }
    }
    for (final entry in records.entries) {
      final record = entry.value;
      final retryIsDue =
          record.state == OperationOutboxState.retryableFailure &&
          record.nextAttemptAtUtc != null &&
          !record.nextAttemptAtUtc!.isAfter(now);
      if (record.principalScopeId != principalScopeId ||
          (record.state != OperationOutboxState.pending && !retryIsDue)) {
        continue;
      }
      final claimed = OperationOutboxRecord(
        localId: record.localId,
        principalScopeId: record.principalScopeId,
        financeAccountId: record.financeAccountId,
        commandId: record.commandId,
        state: OperationOutboxState.syncing,
        transitionSequence: record.transitionSequence + 1,
        createdAtUtc: record.createdAtUtc,
        stateChangedAtUtc: now,
        lastAttemptAtUtc: now,
        syncStartedAtUtc: now,
        attemptCount: record.attemptCount + 1,
        confirmedCommand: record.confirmedCommand,
      );
      records[entry.key] = claimed;
      afterClaim?.call();
      return claimed;
    }
    return null;
  }

  @override
  Future<OperationOutboxRecord> markRetryableFailure({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
    DateTime? nextAttemptAtUtc,
  }) async {
    events.add('store.markRetryable');
    final record = _required(principalScopeId, commandId, localId);
    final updated = OperationOutboxRecord(
      localId: record.localId,
      principalScopeId: record.principalScopeId,
      financeAccountId: record.financeAccountId,
      commandId: record.commandId,
      state: OperationOutboxState.retryableFailure,
      transitionSequence: record.transitionSequence + 1,
      createdAtUtc: record.createdAtUtc,
      stateChangedAtUtc: now,
      lastAttemptAtUtc: record.lastAttemptAtUtc,
      nextAttemptAtUtc: nextAttemptAtUtc,
      attemptCount: record.attemptCount,
      lastErrorCode: errorCode,
      confirmedCommand: record.confirmedCommand,
    );
    records[_key(principalScopeId, commandId)] = updated;
    return updated;
  }

  @override
  Future<OperationOutboxRecord> markAuthenticationPaused({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
  }) async {
    events.add('store.markAuthenticationPaused');
    return markRetryableFailure(
      localId: localId,
      principalScopeId: principalScopeId,
      commandId: commandId,
      errorCode: errorCode,
    );
  }

  @override
  Future<OperationOutboxRecord> markPermanentFailure({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required OperationOutboxErrorCode errorCode,
  }) async {
    events.add('store.markPermanent');
    final record = _required(principalScopeId, commandId, localId);
    final updated = OperationOutboxRecord(
      localId: record.localId,
      principalScopeId: record.principalScopeId,
      financeAccountId: record.financeAccountId,
      commandId: record.commandId,
      state: OperationOutboxState.permanentFailure,
      transitionSequence: record.transitionSequence + 1,
      createdAtUtc: record.createdAtUtc,
      stateChangedAtUtc: now,
      lastAttemptAtUtc: record.lastAttemptAtUtc,
      attemptCount: record.attemptCount,
      lastErrorCode: errorCode,
      confirmedCommand: record.confirmedCommand,
    );
    records[_key(principalScopeId, commandId)] = updated;
    return updated;
  }

  @override
  Future<OperationOutboxRecord> markSynced({
    required String localId,
    required String principalScopeId,
    required String commandId,
    required String serverOperationId,
  }) async {
    events.add('store.markSynced');
    final record = _required(principalScopeId, commandId, localId);
    if (markSyncedFailuresRemaining > 0) {
      markSyncedFailuresRemaining -= 1;
      throw const OperationOutboxException(
        OperationOutboxErrorCode.storageUnavailable,
      );
    }
    final updated = OperationOutboxRecord(
      localId: record.localId,
      principalScopeId: record.principalScopeId,
      financeAccountId: record.financeAccountId,
      commandId: record.commandId,
      state: OperationOutboxState.synced,
      transitionSequence: record.transitionSequence + 1,
      createdAtUtc: record.createdAtUtc,
      stateChangedAtUtc: now,
      lastAttemptAtUtc: record.lastAttemptAtUtc,
      syncedAtUtc: now,
      attemptCount: record.attemptCount,
      confirmedCommand: null,
      serverOperationId: serverOperationId,
      homeConvergencePending: true,
    );
    records[_key(principalScopeId, commandId)] = updated;
    return updated;
  }

  @override
  Future<OperationOutboxRecord> markHomeConverged({
    required String localId,
    required String principalScopeId,
    required String commandId,
  }) async {
    events.add('store.markHomeConverged');
    final record = _required(principalScopeId, commandId, localId);
    final updated = OperationOutboxRecord(
      localId: record.localId,
      principalScopeId: record.principalScopeId,
      financeAccountId: record.financeAccountId,
      commandId: record.commandId,
      state: OperationOutboxState.synced,
      transitionSequence: record.transitionSequence + 1,
      createdAtUtc: record.createdAtUtc,
      stateChangedAtUtc: now,
      lastAttemptAtUtc: record.lastAttemptAtUtc,
      syncedAtUtc: record.syncedAtUtc,
      attemptCount: record.attemptCount,
      confirmedCommand: null,
      serverOperationId: record.serverOperationId,
      homeConvergencePending: false,
    );
    records[_key(principalScopeId, commandId)] = updated;
    return updated;
  }

  @override
  Future<void> resumeAuthentication({required String principalScopeId}) async {
    events.add('store.resumeAuthentication');
    for (final entry in records.entries.toList(growable: false)) {
      final record = entry.value;
      if (record.principalScopeId != principalScopeId ||
          record.state != OperationOutboxState.retryableFailure ||
          record.nextAttemptAtUtc != null ||
          !const {
            OperationOutboxErrorCode.authenticationRequired,
            OperationOutboxErrorCode.sessionChanged,
            OperationOutboxErrorCode.unauthorized,
          }.contains(record.lastErrorCode)) {
        continue;
      }
      records[entry.key] = _pending(record);
    }
  }

  @override
  Future<void> retryNow({required String principalScopeId}) async {
    events.add('store.retryNow');
    for (final entry in records.entries.toList(growable: false)) {
      final record = entry.value;
      if (record.principalScopeId == principalScopeId &&
          record.state == OperationOutboxState.retryableFailure &&
          record.nextAttemptAtUtc != null) {
        records[entry.key] = _pending(record);
      }
    }
  }

  OperationOutboxRecord _pending(OperationOutboxRecord record) {
    return OperationOutboxRecord(
      localId: record.localId,
      principalScopeId: record.principalScopeId,
      financeAccountId: record.financeAccountId,
      commandId: record.commandId,
      state: OperationOutboxState.pending,
      transitionSequence: record.transitionSequence + 1,
      createdAtUtc: record.createdAtUtc,
      stateChangedAtUtc: now,
      lastAttemptAtUtc: record.lastAttemptAtUtc,
      attemptCount: record.attemptCount,
      confirmedCommand: record.confirmedCommand,
    );
  }

  OperationOutboxRecord _required(
    String principalScopeId,
    String commandId,
    String localId,
  ) {
    final record = records[_key(principalScopeId, commandId)];
    if (record == null || record.localId != localId) {
      throw StateError('Unknown outbox record.');
    }
    return record;
  }

  @override
  Future<List<OperationOutboxRecord>> readForPrincipal({
    required String principalScopeId,
  }) async {
    events.add('store.read');
    return records.values
        .where((record) => record.principalScopeId == principalScopeId)
        .toList(growable: false);
  }

  @override
  Future<int> recoverInterrupted() async {
    events.add('store.recover');
    var recovered = 0;
    for (final entry in records.entries.toList(growable: false)) {
      final record = entry.value;
      if (record.state != OperationOutboxState.syncing) continue;
      recovered += 1;
      events.add('store.recover.interrupted');
      records[entry.key] = OperationOutboxRecord(
        localId: record.localId,
        principalScopeId: record.principalScopeId,
        financeAccountId: record.financeAccountId,
        commandId: record.commandId,
        state: OperationOutboxState.retryableFailure,
        transitionSequence: record.transitionSequence + 1,
        createdAtUtc: record.createdAtUtc,
        stateChangedAtUtc: now,
        lastAttemptAtUtc: record.lastAttemptAtUtc,
        nextAttemptAtUtc: now,
        attemptCount: record.attemptCount,
        lastErrorCode: OperationOutboxErrorCode.interrupted,
        confirmedCommand: record.confirmedCommand,
      );
    }
    return recovered;
  }

  @override
  Future<int> purgeExpiredSynced() async {
    events.add('store.purge');
    return 0;
  }

  @override
  Future<void> close() async {}
}

typedef _CommitHandler =
    FutureOr<FinanceEntryResult<FinanceOperationCommit>> Function(
      FinanceOperationCommitCommand command,
      int call,
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
  _FakeFinanceEntryRepository({required this.events, required this.onCommit});

  final List<String> events;
  final _CommitHandler onCommit;
  final List<FinanceOperationCommitCommand> commands = [];
  void Function()? beforePreflight;

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation(
    FinanceOperationCommitCommand command, {
    required String expectedPrincipalScopeId,
    required String expectedSessionRevision,
    required FinanceCommitPreflight preflight,
  }) async {
    beforePreflight?.call();
    final blocked = preflight();
    if (blocked != null) return _failure(blocked);
    events.add('network.commit');
    commands.add(command);
    return await onCommit(command, commands.length);
  }

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
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts() {
    throw StateError('Unexpected account list.');
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount(
    FinanceAccountDraft draft,
  ) {
    throw StateError('Unexpected account evaluation.');
  }

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount(
    FinanceAccountCommitCommand command,
  ) {
    throw StateError('Unexpected account commit.');
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline(
    FinanceBaselineDraft draft,
  ) {
    throw StateError('Unexpected baseline evaluation.');
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline(
    FinanceBaselineCommitCommand command,
  ) {
    throw StateError('Unexpected baseline commit.');
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation(
    FinanceOperationDraft draft,
  ) {
    throw StateError('Unexpected operation evaluation.');
  }
}

final class _FakeAuthSessionStore implements AuthSessionStore {
  AuthSession? current;
  final Queue<AuthSession?> _scriptedReads = Queue<AuthSession?>();
  var readCalls = 0;

  void scriptReads(Iterable<AuthSession?> values) {
    _scriptedReads.addAll(values);
  }

  @override
  Future<AuthSession?> readAuthSession() async {
    readCalls += 1;
    return _scriptedReads.isEmpty ? current : _scriptedReads.removeFirst();
  }

  @override
  Future<HomeSessionSnapshot?> readSession() async {
    final session = await readAuthSession();
    if (session == null) return null;
    return HomeSessionSnapshot(
      accessToken: session.accessToken,
      cacheScopeId: session.cacheScopeId,
      revision: session.revision,
    );
  }

  @override
  Future<AuthSession> saveAuthenticatedSession(AuthTokenBundle tokens) async {
    final saved = AuthSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAtUtc: tokens.accessExpiresAtUtc,
      refreshExpiresAtUtc: tokens.refreshExpiresAtUtc,
      cacheScopeId: tokens.cacheScopeId,
      revision: _revisionA,
    );
    current = saved;
    return saved;
  }

  @override
  Future<AuthSession> rotateAuthenticatedSession({
    required AuthTokenBundle tokens,
    required AuthSession expectedSession,
  }) async {
    final rotated = AuthSession(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAtUtc: tokens.accessExpiresAtUtc,
      refreshExpiresAtUtc: tokens.refreshExpiresAtUtc,
      cacheScopeId: expectedSession.cacheScopeId,
      revision: expectedSession.revision,
    );
    current = rotated;
    return rotated;
  }

  @override
  Future<bool> clearSessionIfCurrent(AuthSession expectedSession) async {
    if (!expectedSession.isSameSession(current)) return false;
    current = null;
    return true;
  }

  @override
  Future<bool> clearSessionForAccountScope(String expectedCacheScopeId) async {
    if (current?.cacheScopeId != expectedCacheScopeId) return false;
    current = null;
    return true;
  }

  @override
  Future<void> clearSession() async {
    current = null;
  }
}

final class _RecordingHomeRepository
    implements HomeRepository, HomeCacheInvalidator {
  _RecordingHomeRepository(this.events, {this.onFetch});

  final List<String> events;
  final Future<HomeRepositoryResult> Function()? onFetch;
  var invalidations = 0;
  var fetches = 0;

  @override
  Future<void> invalidateHomeCache() async {
    invalidations += 1;
    events.add('home.invalidate');
  }

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    fetches += 1;
    events.add('home.fetch');
    expect(forceRefresh, isTrue);
    final fetch = onFetch;
    if (fetch != null) return fetch();
    return const HomeFailureResult(
      type: HomeFailureType.unknown,
      requestId: 'req_test_home_failure',
    );
  }
}

AuthSession _session({
  String scope = _principalScopeId,
  String revision = _revisionA,
}) {
  return AuthSession(
    accessToken: 'access-$scope-$revision',
    refreshToken: 'refresh-$scope-$revision',
    accessExpiresAtUtc: _now.add(const Duration(minutes: 10)),
    refreshExpiresAtUtc: _now.add(const Duration(days: 7)),
    cacheScopeId: scope,
    revision: revision,
  );
}

FinanceOperationCommitCommand _command({String commandId = _commandId}) {
  final draft = FinanceOperationDraft.fromJson(<String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'type': 'expense',
    'amount': '35.00',
    'currency': 'EUR',
    'accountId': _accountId,
    'category': 'groceries',
    'merchant': 'Synthetic shop',
    'capturedAt': '2026-07-30T10:00:00.000Z',
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
      draftHash: _draftHash,
    ),
    confirmedAt: _now,
  );
}

FinanceEntrySuccess<FinanceOperationCommit> _successCommit(
  FinanceOperationCommitCommand command, {
  bool idempotentReplay = false,
  String responseUserId = _principalScopeId,
}) {
  final draft = command.review.draft;
  return FinanceEntrySuccess<FinanceOperationCommit>(
    requestId: 'req_test_commit',
    value: FinanceOperationCommit(
      idempotentReplay: idempotentReplay,
      operation: CommittedFinanceOperation(
        operationId: _operationId,
        userId: responseUserId,
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
        createdAt: '2026-07-30T12:00:01.000Z',
      ),
    ),
  );
}

FinanceEntryFailureResult<FinanceOperationCommit> _failure(
  FinanceEntryFailureKind kind,
) {
  return FinanceEntryFailureResult<FinanceOperationCommit>(
    FinanceEntryFailure(kind: kind, requestId: 'req_test_failure'),
  );
}
