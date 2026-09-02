import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/canonical_timezone.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/application/home_session_recovery.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';

import '../../../support/home_contract_fixture.dart';

void main() {
  group('HomeController', () {
    test('loads populated and first-use empty results', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final populated = _container(
        _QueueHomeRepository([HomeDataResult(snapshot)]),
      );
      addTearDown(populated.dispose);

      expect(populated.read(homeControllerProvider), isA<HomeLoading>());
      await populated.read(homeControllerProvider.notifier).load();

      final ready = populated.read(homeControllerProvider) as HomeReady;
      expect(ready.snapshot.balance.total.amount, '3240.50');
      expect(ready.snapshot.baseCurrency, 'EUR');

      final empty = _container(
        _QueueHomeRepository([
          HomeFirstUseResult(
            HomeFirstUseData(
              userName: 'Максим',
              availableActions: {HomeAction.voiceEntry},
            ),
          ),
        ]),
      );
      addTearDown(empty.dispose);
      await empty.read(homeControllerProvider.notifier).load();
      expect(empty.read(homeControllerProvider), isA<HomeEmpty>());
    });

    test('suppresses duplicate requests while one is in flight', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final pending = Completer<HomeRepositoryResult>();
      final repository = _QueueHomeRepository([pending.future]);
      final container = _container(repository);
      addTearDown(container.dispose);

      final first = container.read(homeControllerProvider.notifier).load();
      final duplicate = container.read(homeControllerProvider.notifier).load();
      expect(repository.calls, 1);

      pending.complete(HomeDataResult(snapshot));
      await Future.wait([first, duplicate]);
      expect(container.read(homeControllerProvider), isA<HomeReady>());
    });

    test('keeps prior data visible while refresh is pending', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final pending = Completer<HomeRepositoryResult>();
      final repository = _QueueHomeRepository([
        HomeDataResult(snapshot),
        pending.future,
      ]);
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();
      final refresh = container.read(homeControllerProvider.notifier).refresh();

      final refreshing =
          container.read(homeControllerProvider) as HomeRefreshing;
      expect(refreshing.snapshot, same(snapshot));
      expect(repository.forceRefreshValues, [false, true]);

      pending.complete(HomeDataResult(snapshot));
      await refresh;
      expect(container.read(homeControllerProvider), isA<HomeReady>());
    });

    test(
      'accepted write invalidates once and converges with bounded polling',
      () async {
        final snapshot = loadHomeFixtureSnapshotSync('populated.json');
        final repository = _QueueHomeRepository([
          HomeDataResult(snapshot),
          const HomeFailureResult(
            type: HomeFailureType.serviceUnavailable,
            requestId: 'req_projection_1',
          ),
          const HomeFailureResult(
            type: HomeFailureType.serviceUnavailable,
            requestId: 'req_projection_2',
          ),
          const HomeFailureResult(
            type: HomeFailureType.serviceUnavailable,
            requestId: 'req_projection_3',
          ),
          HomeDataResult(snapshot),
        ]);
        final delays = <Duration>[];
        late ProviderContainer container;
        container = _container(
          repository,
          acceptedWriteDelay: (duration) async {
            delays.add(duration);
            final failure =
                container.read(homeControllerProvider) as HomeRefreshFailure;
            expect(failure.snapshot, same(snapshot));
          },
        );
        addTearDown(container.dispose);

        await container.read(homeControllerProvider.notifier).load();
        final result = await container
            .read(homeControllerProvider.notifier)
            .invalidateAfterConfirmedOperation();

        expect(result, AcceptedWriteHomeConvergenceResult.updated);
        expect(repository.invalidations, 1);
        expect(delays, const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ]);
        expect(repository.forceRefreshValues, [false, true, true, true, true]);
        expect(container.read(homeControllerProvider), isA<HomeReady>());
      },
    );

    test(
      'accepted write reports delayed projection after bounded attempts',
      () async {
        final snapshot = loadHomeFixtureSnapshotSync('populated.json');
        const delayed = HomeFailureResult(
          type: HomeFailureType.serviceUnavailable,
          requestId: 'req_projection_delayed',
        );
        final repository = _QueueHomeRepository([
          HomeDataResult(snapshot),
          delayed,
          delayed,
          delayed,
          delayed,
        ]);
        final delays = <Duration>[];
        final container = _container(
          repository,
          acceptedWriteDelay: (duration) async => delays.add(duration),
        );
        addTearDown(container.dispose);

        await container.read(homeControllerProvider.notifier).load();
        final result = await container
            .read(homeControllerProvider.notifier)
            .invalidateAfterConfirmedOperation();

        expect(result, AcceptedWriteHomeConvergenceResult.projectionDelayed);
        expect(repository.invalidations, 1);
        expect(delays, const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ]);
        final state =
            container.read(homeControllerProvider) as HomeRefreshFailure;
        expect(state.snapshot, same(snapshot));
        expect(state.type, HomeFailureType.serviceUnavailable);
      },
    );

    test('accepted write stops on a nonretryable Home failure', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final repository = _QueueHomeRepository([
        HomeDataResult(snapshot),
        const HomeFailureResult(
          type: HomeFailureType.timeout,
          requestId: 'req_post_write_timeout',
        ),
      ]);
      final delays = <Duration>[];
      final container = _container(
        repository,
        acceptedWriteDelay: (duration) async => delays.add(duration),
      );
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();
      final result = await container
          .read(homeControllerProvider.notifier)
          .invalidateAfterConfirmedOperation();

      expect(result, AcceptedWriteHomeConvergenceResult.failed);
      expect(repository.invalidations, 1);
      expect(delays, isEmpty);
      expect(repository.calls, 2);
      final state =
          container.read(homeControllerProvider) as HomeRefreshFailure;
      expect(state.snapshot, same(snapshot));
      expect(state.type, HomeFailureType.timeout);
    });

    test('accepted write stops when authentication is required', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final repository = _QueueHomeRepository([
        HomeDataResult(snapshot),
        const HomeAuthExpiredResult(requestId: 'req_post_write_auth'),
      ]);
      final recovery = _FakeSessionRecovery(
        HomeSessionRecoveryResult.signOutRequired,
      );
      final delays = <Duration>[];
      final container = _container(
        repository,
        recovery: recovery,
        acceptedWriteDelay: (duration) async => delays.add(duration),
      );
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();
      final result = await container
          .read(homeControllerProvider.notifier)
          .invalidateAfterConfirmedOperation();

      expect(result, AcceptedWriteHomeConvergenceResult.authenticationRequired);
      expect(delays, isEmpty);
      expect(recovery.calls, 1);
      final state = container.read(homeControllerProvider) as HomeAuthRequired;
      expect(state.snapshot, same(snapshot));
    });

    test(
      'accepted write stops polling after the session epoch changes',
      () async {
        final snapshot = loadHomeFixtureSnapshotSync('populated.json');
        final repository = _QueueHomeRepository([
          HomeDataResult(snapshot),
          const HomeFailureResult(
            type: HomeFailureType.serviceUnavailable,
            requestId: 'req_projection_session_change',
          ),
        ]);
        final delays = <Duration>[];
        late ProviderContainer container;
        container = _container(
          repository,
          acceptedWriteDelay: (duration) async {
            delays.add(duration);
            container.read(authSessionEpochProvider.notifier).advance();
          },
        );
        addTearDown(container.dispose);

        await container.read(homeControllerProvider.notifier).load();
        final result = await container
            .read(homeControllerProvider.notifier)
            .invalidateAfterConfirmedOperation();

        expect(result, AcceptedWriteHomeConvergenceResult.sessionChanged);
        expect(delays, const [Duration(seconds: 1)]);
        expect(repository.invalidations, 1);
        expect(repository.calls, 2);
      },
    );

    test(
      'accepted write stops polling when request preflight changes during delay',
      () async {
        final snapshot = loadHomeFixtureSnapshotSync('populated.json');
        final repository = _QueueHomeRepository([
          HomeDataResult(snapshot),
          const HomeFailureResult(
            type: HomeFailureType.serviceUnavailable,
            requestId: 'req_projection_backgrounded',
          ),
          HomeDataResult(snapshot),
        ]);
        var requestAllowed = true;
        final delays = <Duration>[];
        final container = _container(
          repository,
          acceptedWriteDelay: (duration) async {
            delays.add(duration);
            requestAllowed = false;
          },
        );
        addTearDown(container.dispose);

        await container.read(homeControllerProvider.notifier).load();
        final result = await container
            .read(homeControllerProvider.notifier)
            .convergeAfterAcceptedWrite(requestPreflight: () => requestAllowed);

        expect(result, AcceptedWriteHomeConvergenceResult.failed);
        expect(delays, const [Duration(seconds: 1)]);
        expect(repository.invalidations, 1);
        expect(repository.calls, 2);
        expect(repository.forceRefreshValues, const [false, true]);
      },
    );

    test('isolates partial failures and exposes offline cached data', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final partialContainer = _container(
        _QueueHomeRepository([
          HomePartialResult(
            snapshot: snapshot,
            blockFailures: const {
              HomeBlock.primaryGoal: HomeBlockFailure(
                code: 'goal_unavailable',
                requestId: 'req_goal_fixture',
              ),
            },
          ),
        ]),
      );
      addTearDown(partialContainer.dispose);

      await partialContainer.read(homeControllerProvider.notifier).load();
      final partial =
          partialContainer.read(homeControllerProvider) as HomePartial;
      expect(partial.snapshot, same(snapshot));
      expect(partial.blockFailures.keys, [HomeBlock.primaryGoal]);

      final offlineContainer = _container(
        _QueueHomeRepository([HomeOfflineResult(snapshot)]),
      );
      addTearDown(offlineContainer.dispose);
      await offlineContainer.read(homeControllerProvider.notifier).load();
      expect(offlineContainer.read(homeControllerProvider), isA<HomeOffline>());
    });

    test('retains data after a refresh failure and retries safely', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final repository = _QueueHomeRepository([
        HomeDataResult(snapshot),
        const HomeFailureResult(
          type: HomeFailureType.timeout,
          requestId: 'req_refresh_fixture',
        ),
        HomeDataResult(snapshot),
      ]);
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();
      await container.read(homeControllerProvider.notifier).refresh();

      final failed =
          container.read(homeControllerProvider) as HomeRefreshFailure;
      expect(failed.snapshot, same(snapshot));
      expect(failed.requestId, 'req_refresh_fixture');

      await container.read(homeControllerProvider.notifier).retry();
      expect(container.read(homeControllerProvider), isA<HomeReady>());
    });

    test(
      'attempts auth recovery once and requests controlled sign-out',
      () async {
        final recoveredRepository = _QueueHomeRepository([
          const HomeAuthExpiredResult(requestId: 'req_auth_first'),
          HomeDataResult(loadHomeFixtureSnapshotSync('populated.json')),
        ]);
        final recoveredSession = _FakeSessionRecovery(
          HomeSessionRecoveryResult.recovered,
        );
        final recoveredContainer = _container(
          recoveredRepository,
          recovery: recoveredSession,
        );
        addTearDown(recoveredContainer.dispose);

        await recoveredContainer.read(homeControllerProvider.notifier).load();
        expect(
          recoveredContainer.read(homeControllerProvider),
          isA<HomeReady>(),
        );
        expect(recoveredSession.calls, 1);
        expect(recoveredRepository.calls, 2);

        final expiredRepository = _QueueHomeRepository([
          const HomeAuthExpiredResult(requestId: 'req_auth_expired'),
        ]);
        final expiredSession = _FakeSessionRecovery(
          HomeSessionRecoveryResult.signOutRequired,
        );
        final expiredContainer = _container(
          expiredRepository,
          recovery: expiredSession,
        );
        addTearDown(expiredContainer.dispose);

        await expiredContainer.read(homeControllerProvider.notifier).load();
        final required =
            expiredContainer.read(homeControllerProvider) as HomeAuthRequired;
        expect(required.requestId, 'req_auth_expired');
        expect(expiredSession.calls, 1);
      },
    );

    // The zone is correctable elsewhere (ADR 0028). A client left behind by a
    // correction must recover on its own, or Home shows an error until
    // something else happens to read the account back.
    test('adopts the zone the server names and reads again', () async {
      final repository = _QueueHomeRepository([
        const HomeTimezoneMismatchResult(
          canonicalTimezone: 'Europe/Kyiv',
          requestId: 'req_timezone_stale',
        ),
        HomeDataResult(loadHomeFixtureSnapshotSync('populated.json')),
      ]);
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();

      expect(container.read(homeControllerProvider), isA<HomeReady>());
      expect(container.read(canonicalTimezoneProvider), 'Europe/Kyiv');
      expect(repository.calls, 2);
      // The cached snapshot was drawn against the old month boundaries.
      expect(repository.invalidations, 1);
    });

    test('stops after one adoption instead of looping', () async {
      final repository = _QueueHomeRepository([
        const HomeTimezoneMismatchResult(
          canonicalTimezone: 'Europe/Kyiv',
          requestId: 'req_timezone_stale',
        ),
        const HomeTimezoneMismatchResult(
          canonicalTimezone: 'Europe/Lisbon',
          requestId: 'req_timezone_stale_again',
        ),
      ]);
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();

      expect(container.read(homeControllerProvider), isA<HomeFailure>());
      expect(repository.calls, 2);
    });

    test('a later refresh may adopt again', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final repository = _QueueHomeRepository([
        const HomeTimezoneMismatchResult(
          canonicalTimezone: 'Europe/Kyiv',
          requestId: 'req_timezone_stale',
        ),
        HomeDataResult(snapshot),
        const HomeTimezoneMismatchResult(
          canonicalTimezone: 'Europe/Lisbon',
          requestId: 'req_timezone_moved_again',
        ),
        HomeDataResult(snapshot),
      ]);
      final container = _container(repository);
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();
      await container.read(homeControllerProvider.notifier).refresh();

      expect(container.read(canonicalTimezoneProvider), 'Europe/Lisbon');
      expect(repository.calls, 4);
    });

    test('the Home client is rebuilt when the zone moves', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = container.read(homeRepositoryProvider);
      container
          .read(canonicalTimezoneProvider.notifier)
          .adopt('Pacific/Auckland');

      expect(container.read(homeRepositoryProvider), isNot(same(before)));
    });

    test('retains prior snapshot when auth expires during refresh', () async {
      final snapshot = loadHomeFixtureSnapshotSync('populated.json');
      final recovery = _FakeSessionRecovery(
        HomeSessionRecoveryResult.signOutRequired,
      );
      final container = _container(
        _QueueHomeRepository([
          HomeDataResult(snapshot),
          const HomeAuthExpiredResult(requestId: 'req_auth_refresh'),
        ]),
        recovery: recovery,
      );
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();
      await container.read(homeControllerProvider.notifier).refresh();

      final required =
          container.read(homeControllerProvider) as HomeAuthRequired;
      expect(required.snapshot, same(snapshot));
      expect(required.requestId, 'req_auth_refresh');
      expect(recovery.calls, 1);
    });

    test('maps unexpected exceptions to a redacted fatal failure', () async {
      final container = _container(
        _QueueHomeRepository([StateError('synthetic')]),
      );
      addTearDown(container.dispose);

      await container.read(homeControllerProvider.notifier).load();

      final failure = container.read(homeControllerProvider) as HomeFailure;
      expect(failure.type, HomeFailureType.unknown);
      expect(failure.requestId, 'req_local_unexpected');
    });
  });
}

ProviderContainer _container(
  HomeRepository repository, {
  HomeSessionRecovery? recovery,
  AcceptedWriteHomeDelay? acceptedWriteDelay,
}) {
  return ProviderContainer(
    overrides: [
      homeRepositoryProvider.overrideWithValue(repository),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      if (recovery != null)
        homeSessionRecoveryProvider.overrideWithValue(recovery),
      if (acceptedWriteDelay != null)
        acceptedWriteHomeDelayProvider.overrideWithValue(acceptedWriteDelay),
    ],
  );
}

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}

class _QueueHomeRepository implements HomeRepository, HomeCacheInvalidator {
  _QueueHomeRepository(this._results);

  final List<Object> _results;
  var calls = 0;
  var invalidations = 0;
  final forceRefreshValues = <bool>[];

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    forceRefreshValues.add(forceRefresh);
    final result = _results[calls++];
    if (result is Future<HomeRepositoryResult>) return result;
    if (result is HomeRepositoryResult) return result;
    throw result;
  }

  @override
  Future<void> invalidateHomeCache() async {
    invalidations += 1;
  }
}

class _FakeSessionRecovery implements HomeSessionRecovery {
  _FakeSessionRecovery(this.result);

  final HomeSessionRecoveryResult result;
  var calls = 0;

  @override
  Future<HomeSessionRecoveryResult> refreshSession() async {
    calls += 1;
    return result;
  }
}
