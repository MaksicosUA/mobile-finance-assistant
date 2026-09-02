import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../auth/application/auth_controller.dart';
import '../data/home_api.dart';
import '../data/home_cache.dart';
import '../../../app/canonical_timezone.dart';
import '../data/home_repository.dart';
import '../data/home_repository_impl.dart';
import '../data/home_session_store.dart';
import '../data/mock_home_repository.dart';
import '../data/scenario_home_repository.dart';
import '../domain/home_snapshot.dart';
import 'home_session_recovery.dart';
import 'home_state.dart';

export 'home_state.dart';
export '../../auth/application/auth_controller.dart'
    show authSessionEpochProvider, homeSessionStoreProvider;
export '../data/home_cache.dart' show homeCacheProvider;

const _homeFixture = String.fromEnvironment(
  'HOME_FIXTURE',
  defaultValue: 'populated',
);
const _homeScenario = String.fromEnvironment(
  'HOME_SCENARIO',
  defaultValue: 'populated',
);
typedef AcceptedWriteHomeDelay = Future<void> Function(Duration duration);

enum AcceptedWriteHomeConvergenceResult {
  updated,
  projectionDelayed,
  authenticationRequired,
  sessionChanged,
  failed,
}

final acceptedWriteHomeDelayProvider = Provider<AcceptedWriteHomeDelay>(
  (_) =>
      (duration) => Future<void>.delayed(duration),
);

const _acceptedWriteRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

enum _HomeRequestOutcome {
  updated,
  firstUse,
  offline,
  serviceUnavailable,
  authenticationRequired,
  sessionChanged,
  interrupted,
  otherFailure,
  skipped,
}

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  // Watched unconditionally so the dependency is real rather than incidental:
  // correcting the zone (ADR 0028) must rebuild this client, or Home keeps
  // asking for months drawn where the user used to live.
  final timezone = ref.watch(canonicalTimezoneProvider);
  if (isNetworkBackendConfigured) {
    final dio = Dio();
    ref.onDispose(() => dio.close(force: true));
    return NetworkHomeRepository(
      api: HomeApi(
        dio: dio,
        baseUri: Uri.parse(configuredApiBaseUrl),
        timezone: timezone,
      ),
      cache: ref.watch(homeCacheProvider),
      sessionProvider: ref.watch(homeSessionStoreProvider).readSession,
    );
  }

  final fixtureRepository = MockHomeRepository(
    outcome: _homeFixture == 'empty'
        ? MockHomeOutcome.empty
        : MockHomeOutcome.populated,
  );
  return ScenarioHomeRepository(
    fixtureRepository: fixtureRepository,
    scenario: homeScenarioFromName(_homeScenario),
  );
});

final homeControllerProvider = NotifierProvider<HomeController, HomeState>(
  HomeController.new,
);

class HomeController extends Notifier<HomeState> {
  var _requestInFlight = false;
  Completer<void>? _requestCompletion;
  int? _activeRequestEpoch;
  var _reloadAfterInFlight = false;
  var _authRefreshAttempted = false;
  var _timezoneAdoptionAttempted = false;

  int get _sessionEpoch => ref.read(authSessionEpochProvider);

  @override
  HomeState build() {
    // Every credential/account epoch resets retained presentation state before
    // the next request, preventing a previous account snapshot from flashing
    // during login or account replacement.
    ref.watch(authSessionEpochProvider);
    _authRefreshAttempted = false;
    _timezoneAdoptionAttempted = false;
    return const HomeLoading();
  }

  void handleSessionChanging() {
    _authRefreshAttempted = false;
    state = const HomeLoading();
  }

  Future<void> load() async {
    final retained = state.retainedSnapshot;
    await _request(
      forceRefresh: false,
      retainedSnapshot: retained,
      showRetainedRefresh: retained != null,
      readCacheFirst: retained == null,
    );
  }

  Future<void> refresh() async {
    final retained = state.retainedSnapshot;
    if (retained == null) {
      await load();
      return;
    }
    await _request(
      forceRefresh: true,
      retainedSnapshot: retained,
      showRetainedRefresh: true,
      readCacheFirst: false,
    );
  }

  Future<void> retry() async {
    switch (state) {
      case HomeRefreshFailure(:final snapshot) ||
          HomeOffline(:final snapshot) ||
          HomePartial(:final snapshot):
        await _request(
          forceRefresh: true,
          retainedSnapshot: snapshot,
          showRetainedRefresh: true,
          readCacheFirst: false,
        );
      case HomeFailure() || HomeLoading() || HomeEmpty():
        await _request(
          forceRefresh: true,
          retainedSnapshot: null,
          showRetainedRefresh: false,
          readCacheFirst: false,
        );
      case HomeAuthRequired() || HomeReady() || HomeRefreshing():
        break;
    }
  }

  /// Converges Home after Finance Core has already accepted a financial write.
  ///
  /// A temporary service-unavailable response is expected while the standalone
  /// projector consumes its outbox event. The encrypted cache is invalidated
  /// once, and every poll is unconditional. Other failures are not retried here
  /// because the authoritative write has already succeeded and must never be
  /// presented as rejected merely because its read model is delayed.
  Future<AcceptedWriteHomeConvergenceResult> convergeAfterAcceptedWrite({
    HomeRequestPreflight? requestPreflight,
  }) async {
    if (!_requestAllowed(requestPreflight)) {
      return AcceptedWriteHomeConvergenceResult.failed;
    }
    final sessionEpoch = _sessionEpoch;
    final repository = ref.read(homeRepositoryProvider);
    var retained = state.retainedSnapshot;
    if (repository case final HomeCacheInvalidator invalidator) {
      try {
        await invalidator.invalidateHomeCache();
      } catch (_) {
        // The network refresh below remains authoritative. No cache or payload
        // details are exposed through logs or state.
      }
    }
    if (sessionEpoch != _sessionEpoch) {
      return AcceptedWriteHomeConvergenceResult.sessionChanged;
    }
    if (!_requestAllowed(requestPreflight)) {
      return AcceptedWriteHomeConvergenceResult.failed;
    }

    final delay = ref.read(acceptedWriteHomeDelayProvider);
    var retryIndex = 0;
    while (true) {
      if (!_requestAllowed(requestPreflight)) {
        return AcceptedWriteHomeConvergenceResult.failed;
      }
      await _waitForActiveRequest();
      if (sessionEpoch != _sessionEpoch) {
        return AcceptedWriteHomeConvergenceResult.sessionChanged;
      }
      if (!_requestAllowed(requestPreflight)) {
        return AcceptedWriteHomeConvergenceResult.failed;
      }

      retained = state.retainedSnapshot ?? retained;
      final outcome = await _request(
        forceRefresh: true,
        retainedSnapshot: retained,
        showRetainedRefresh: retained != null,
        readCacheFirst: false,
        requestPreflight: requestPreflight,
      );

      switch (outcome) {
        case _HomeRequestOutcome.updated:
          return AcceptedWriteHomeConvergenceResult.updated;
        case _HomeRequestOutcome.authenticationRequired:
          return AcceptedWriteHomeConvergenceResult.authenticationRequired;
        case _HomeRequestOutcome.sessionChanged:
          return AcceptedWriteHomeConvergenceResult.sessionChanged;
        case _HomeRequestOutcome.interrupted:
          return AcceptedWriteHomeConvergenceResult.failed;
        case _HomeRequestOutcome.serviceUnavailable:
          if (retryIndex >= _acceptedWriteRetryDelays.length) {
            return AcceptedWriteHomeConvergenceResult.projectionDelayed;
          }
          if (!_requestAllowed(requestPreflight)) {
            return AcceptedWriteHomeConvergenceResult.failed;
          }
          try {
            await delay(_acceptedWriteRetryDelays[retryIndex]);
          } catch (_) {
            return AcceptedWriteHomeConvergenceResult.failed;
          }
          retryIndex += 1;
          if (sessionEpoch != _sessionEpoch) {
            return AcceptedWriteHomeConvergenceResult.sessionChanged;
          }
          if (!_requestAllowed(requestPreflight)) {
            return AcceptedWriteHomeConvergenceResult.failed;
          }
          continue;
        case _HomeRequestOutcome.skipped:
          // A regular Home request won the race after the wait above. Wait for
          // it without consuming the bounded projector retry schedule, then
          // issue the required unconditional post-write request.
          continue;
        case _HomeRequestOutcome.firstUse ||
            _HomeRequestOutcome.offline ||
            _HomeRequestOutcome.otherFailure:
          return AcceptedWriteHomeConvergenceResult.failed;
      }
    }
  }

  Future<AcceptedWriteHomeConvergenceResult>
  invalidateAfterConfirmedOperation() => convergeAfterAcceptedWrite();

  /// Clears credentials and encrypted Home data before leaving the session.
  Future<bool> clearSessionForSignOut() async {
    final expectedEpoch = _sessionEpoch + 1;
    _authRefreshAttempted = false;
    state = const HomeLoading();
    try {
      await ref.read(homeSessionStoreProvider).clearSession();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (_sessionEpoch == expectedEpoch) {
        state = const HomeLoading();
      }
    }
  }

  Future<_HomeRequestOutcome> _request({
    required bool forceRefresh,
    required HomeSnapshot? retainedSnapshot,
    required bool showRetainedRefresh,
    required bool readCacheFirst,
    HomeRequestPreflight? requestPreflight,
  }) async {
    if (!_requestAllowed(requestPreflight)) {
      return _HomeRequestOutcome.interrupted;
    }
    if (_requestInFlight) {
      if (_activeRequestEpoch != _sessionEpoch) {
        _reloadAfterInFlight = true;
      }
      return _HomeRequestOutcome.skipped;
    }
    _requestInFlight = true;
    // Once per request: a later refresh may adopt again if the zone moves
    // again, but one read never loops over a server that keeps disagreeing.
    _timezoneAdoptionAttempted = false;
    final requestCompletion = Completer<void>();
    _requestCompletion = requestCompletion;
    final sessionEpoch = _sessionEpoch;
    _activeRequestEpoch = sessionEpoch;
    var effectiveSnapshot = retainedSnapshot;
    var effectiveUserName = retainedSnapshot?.userName ?? state.knownUserName;

    try {
      final repository = ref.read(homeRepositoryProvider);

      if (readCacheFirst) {
        if (repository case final HomeCacheReader cacheReader) {
          try {
            final cached = await cacheReader.readCachedHome();
            effectiveSnapshot = cached?.snapshot;
            effectiveUserName =
                effectiveSnapshot?.userName ?? effectiveUserName;
          } catch (_) {
            effectiveSnapshot = null;
          }
        }
      }
      if (sessionEpoch != _sessionEpoch) {
        return _HomeRequestOutcome.sessionChanged;
      }
      if (!_requestAllowed(requestPreflight)) {
        return _HomeRequestOutcome.interrupted;
      }

      if (effectiveSnapshot != null &&
          (showRetainedRefresh || readCacheFirst)) {
        state = HomeRefreshing(effectiveSnapshot);
      } else {
        state = HomeLoading(userName: effectiveUserName);
      }

      final result = await _fetchHome(
        repository,
        forceRefresh: forceRefresh,
        requestPreflight: requestPreflight,
      );
      if (sessionEpoch != _sessionEpoch) {
        return _HomeRequestOutcome.sessionChanged;
      }
      if (!_requestAllowed(requestPreflight)) {
        return _HomeRequestOutcome.interrupted;
      }
      return await _applyResult(
        result,
        retainedSnapshot: effectiveSnapshot,
        retainedUserName: effectiveUserName,
        forceRefresh: forceRefresh,
        sessionEpoch: sessionEpoch,
        requestPreflight: requestPreflight,
      );
    } catch (_) {
      if (sessionEpoch != _sessionEpoch) {
        return _HomeRequestOutcome.sessionChanged;
      }
      if (!_requestAllowed(requestPreflight)) {
        return _HomeRequestOutcome.interrupted;
      }
      _showFailure(
        type: HomeFailureType.unknown,
        requestId: 'req_local_unexpected',
        retainedSnapshot: effectiveSnapshot,
        retainedUserName: effectiveUserName,
      );
      return _HomeRequestOutcome.otherFailure;
    } finally {
      _requestInFlight = false;
      _activeRequestEpoch = null;
      if (identical(_requestCompletion, requestCompletion)) {
        _requestCompletion = null;
      }
      if (!requestCompletion.isCompleted) requestCompletion.complete();
      if (_reloadAfterInFlight) {
        _reloadAfterInFlight = false;
        unawaited(load());
      }
    }
  }

  Future<_HomeRequestOutcome> _applyResult(
    HomeRepositoryResult result, {
    required HomeSnapshot? retainedSnapshot,
    required String? retainedUserName,
    required bool forceRefresh,
    required int sessionEpoch,
    HomeRequestPreflight? requestPreflight,
  }) async {
    if (sessionEpoch != _sessionEpoch) {
      return _HomeRequestOutcome.sessionChanged;
    }
    switch (result) {
      case HomeDataResult(:final snapshot):
        _authRefreshAttempted = false;
        state = HomeReady(snapshot);
        return _HomeRequestOutcome.updated;
      case HomeFirstUseResult(:final data):
        _authRefreshAttempted = false;
        state = HomeEmpty(data);
        return _HomeRequestOutcome.firstUse;
      case HomePartialResult(:final snapshot, :final blockFailures):
        _authRefreshAttempted = false;
        state = HomePartial(snapshot: snapshot, blockFailures: blockFailures);
        return _HomeRequestOutcome.updated;
      case HomeOfflineResult(:final snapshot):
        _authRefreshAttempted = false;
        state = HomeOffline(snapshot);
        return _HomeRequestOutcome.offline;
      case HomeFailureResult(:final type, :final requestId):
        _showFailure(
          type: type,
          requestId: requestId,
          retainedSnapshot: retainedSnapshot,
          retainedUserName: retainedUserName,
        );
        return type == HomeFailureType.serviceUnavailable
            ? _HomeRequestOutcome.serviceUnavailable
            : _HomeRequestOutcome.otherFailure;
      case HomeAuthExpiredResult(:final requestId):
        return _recoverAuthentication(
          requestId: requestId,
          retainedSnapshot: retainedSnapshot,
          retainedUserName: retainedUserName,
          forceRefresh: forceRefresh,
          sessionEpoch: sessionEpoch,
          requestPreflight: requestPreflight,
        );
      case HomeTimezoneMismatchResult(:final canonicalTimezone):
        return await _adoptCanonicalTimezone(
          canonicalTimezone,
          retainedSnapshot: retainedSnapshot,
          retainedUserName: retainedUserName,
          forceRefresh: forceRefresh,
          sessionEpoch: sessionEpoch,
          requestPreflight: requestPreflight,
        );
      case HomeRequestInterruptedResult():
        return _HomeRequestOutcome.interrupted;
    }
  }

  /// Read Home again in the zone the server says this account now uses.
  ///
  /// The zone is correctable elsewhere (ADR 0028), and a client that missed the
  /// correction would otherwise show an error until something happened to read
  /// the account back. Adopting rebuilds the Home client, so the cached
  /// snapshot — drawn against the old month boundaries — is dropped first.
  ///
  /// Once per request: if the retry disagrees again, something other than a
  /// correction is wrong and the failure is shown rather than looped over.
  Future<_HomeRequestOutcome> _adoptCanonicalTimezone(
    String canonicalTimezone, {
    required HomeSnapshot? retainedSnapshot,
    required String? retainedUserName,
    required bool forceRefresh,
    required int sessionEpoch,
    HomeRequestPreflight? requestPreflight,
  }) async {
    if (_timezoneAdoptionAttempted ||
        canonicalTimezone == ref.read(canonicalTimezoneProvider)) {
      _showFailure(
        type: HomeFailureType.unknown,
        requestId: 'req_local_timezone_mismatch',
        retainedSnapshot: retainedSnapshot,
        retainedUserName: retainedUserName,
      );
      return _HomeRequestOutcome.otherFailure;
    }
    _timezoneAdoptionAttempted = true;
    await _invalidateCacheSafely();
    if (sessionEpoch != _sessionEpoch) {
      return _HomeRequestOutcome.sessionChanged;
    }
    ref.read(canonicalTimezoneProvider.notifier).adopt(canonicalTimezone);
    if (!_requestAllowed(requestPreflight)) {
      return _HomeRequestOutcome.interrupted;
    }
    final retryResult = await _fetchHome(
      ref.read(homeRepositoryProvider),
      forceRefresh: true,
      requestPreflight: requestPreflight,
    );
    if (sessionEpoch != _sessionEpoch) {
      return _HomeRequestOutcome.sessionChanged;
    }
    if (!_requestAllowed(requestPreflight)) {
      return _HomeRequestOutcome.interrupted;
    }
    return await _applyResult(
      retryResult,
      retainedSnapshot: retainedSnapshot,
      retainedUserName: retainedUserName,
      forceRefresh: forceRefresh,
      sessionEpoch: sessionEpoch,
      requestPreflight: requestPreflight,
    );
  }

  Future<void> _invalidateCacheSafely() async {
    final repository = ref.read(homeRepositoryProvider);
    if (repository case final HomeCacheInvalidator invalidator) {
      try {
        await invalidator.invalidateHomeCache();
      } catch (_) {
        // A replaceable cache that cannot be dropped is not worth failing a
        // read over; the fresh response replaces it anyway.
      }
    }
  }

  Future<_HomeRequestOutcome> _recoverAuthentication({
    required String requestId,
    required HomeSnapshot? retainedSnapshot,
    required String? retainedUserName,
    required bool forceRefresh,
    required int sessionEpoch,
    HomeRequestPreflight? requestPreflight,
  }) async {
    if (sessionEpoch != _sessionEpoch) {
      return _HomeRequestOutcome.sessionChanged;
    }
    if (!_requestAllowed(requestPreflight)) {
      _authRefreshAttempted = false;
      return _HomeRequestOutcome.interrupted;
    }
    var authRequestId = requestId;
    if (!_authRefreshAttempted) {
      _authRefreshAttempted = true;
      final sessionBeforeRecovery = await _readSessionSafely();
      if (sessionEpoch != _sessionEpoch) {
        return _HomeRequestOutcome.sessionChanged;
      }
      if (!_requestAllowed(requestPreflight)) {
        _authRefreshAttempted = false;
        return _HomeRequestOutcome.interrupted;
      }
      HomeSessionRecoveryResult recoveryResult;
      try {
        recoveryResult = await ref
            .read(homeSessionRecoveryProvider)
            .refreshSession();
      } catch (_) {
        recoveryResult = HomeSessionRecoveryResult.signOutRequired;
      }
      final sessionAfterRecovery = await _readSessionSafely();
      if (!_requestAllowed(requestPreflight)) {
        _authRefreshAttempted = false;
        return _HomeRequestOutcome.interrupted;
      }

      if (recoveryResult == HomeSessionRecoveryResult.recovered) {
        if (!_isSameAccount(sessionBeforeRecovery, sessionAfterRecovery)) {
          return _HomeRequestOutcome.sessionChanged;
        }
        final retryEpoch = _sessionEpoch;
        final retryResult = await _fetchHome(
          ref.read(homeRepositoryProvider),
          forceRefresh: forceRefresh,
          requestPreflight: requestPreflight,
        );
        if (retryEpoch != _sessionEpoch) {
          return _HomeRequestOutcome.sessionChanged;
        }
        if (!_requestAllowed(requestPreflight)) {
          _authRefreshAttempted = false;
          return _HomeRequestOutcome.interrupted;
        }
        if (retryResult is! HomeAuthExpiredResult) {
          return await _applyResult(
            retryResult,
            retainedSnapshot: retainedSnapshot,
            retainedUserName: retainedUserName,
            forceRefresh: forceRefresh,
            sessionEpoch: retryEpoch,
            requestPreflight: requestPreflight,
          );
        }
        authRequestId = retryResult.requestId;
        if (retryEpoch != _sessionEpoch) {
          return _HomeRequestOutcome.sessionChanged;
        }
      } else if (recoveryResult == HomeSessionRecoveryResult.signOutRequired) {
        if (!_isSameSession(sessionBeforeRecovery, sessionAfterRecovery)) {
          return _HomeRequestOutcome.sessionChanged;
        }
      } else {
        _authRefreshAttempted = false;
        _showFailure(
          type: HomeFailureType.serviceUnavailable,
          requestId: authRequestId,
          retainedSnapshot: retainedSnapshot,
          retainedUserName: retainedUserName,
        );
        return _HomeRequestOutcome.otherFailure;
      }
    }

    state = HomeAuthRequired(
      requestId: authRequestId,
      snapshot: retainedSnapshot,
      userName: retainedUserName,
    );
    return _HomeRequestOutcome.authenticationRequired;
  }

  Future<void> _waitForActiveRequest() async {
    while (_requestInFlight) {
      final completion = _requestCompletion;
      if (completion == null) return;
      await completion.future;
    }
  }

  Future<HomeRepositoryResult> _fetchHome(
    HomeRepository repository, {
    required bool forceRefresh,
    HomeRequestPreflight? requestPreflight,
  }) {
    if (!_requestAllowed(requestPreflight)) {
      return Future<HomeRepositoryResult>.value(
        const HomeRequestInterruptedResult(),
      );
    }
    if (requestPreflight != null) {
      if (repository case final HomeRequestGuardedRepository guarded) {
        return guarded.fetchHomeGuarded(
          forceRefresh: forceRefresh,
          preflight: requestPreflight,
        );
      }
    }
    return repository.fetchHome(forceRefresh: forceRefresh);
  }

  bool _requestAllowed(HomeRequestPreflight? preflight) {
    if (preflight == null) return true;
    try {
      return preflight();
    } on Object {
      return false;
    }
  }

  Future<HomeSessionSnapshot?> _readSessionSafely() async {
    try {
      return await ref.read(homeSessionStoreProvider).readSession();
    } catch (_) {
      return null;
    }
  }

  bool _isSameAccount(HomeSessionSnapshot? before, HomeSessionSnapshot? after) {
    if (before == null || after == null) {
      return before == null && after == null;
    }
    return before.cacheScopeId == after.cacheScopeId;
  }

  bool _isSameSession(HomeSessionSnapshot? before, HomeSessionSnapshot? after) {
    if (before == null || after == null) {
      return before == null && after == null;
    }
    return before.isSameSession(after);
  }

  void _showFailure({
    required HomeFailureType type,
    required String requestId,
    required HomeSnapshot? retainedSnapshot,
    required String? retainedUserName,
  }) {
    state = retainedSnapshot == null
        ? HomeFailure(
            type: type,
            requestId: requestId,
            userName: retainedUserName,
          )
        : HomeRefreshFailure(
            snapshot: retainedSnapshot,
            type: type,
            requestId: requestId,
          );
  }
}
