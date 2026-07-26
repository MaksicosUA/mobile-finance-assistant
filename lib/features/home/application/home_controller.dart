import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../auth/application/auth_controller.dart';
import '../data/home_api.dart';
import '../data/home_cache.dart';
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
const _homeApiTimezone = String.fromEnvironment(
  'HOME_API_TIMEZONE',
  defaultValue: 'Europe/Berlin',
);

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  if (isNetworkBackendConfigured) {
    final dio = Dio();
    ref.onDispose(() => dio.close(force: true));
    return NetworkHomeRepository(
      api: HomeApi(
        dio: dio,
        baseUri: Uri.parse(configuredApiBaseUrl),
        timezone: _homeApiTimezone,
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
  int? _activeRequestEpoch;
  var _reloadAfterInFlight = false;
  var _authRefreshAttempted = false;

  int get _sessionEpoch => ref.read(authSessionEpochProvider);

  @override
  HomeState build() {
    // Every credential/account epoch resets retained presentation state before
    // the next request, preventing a previous account snapshot from flashing
    // during login or account replacement.
    ref.watch(authSessionEpochProvider);
    _authRefreshAttempted = false;
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

  /// Called by the confirmation flow once Finance Core accepts an operation.
  Future<void> invalidateAfterConfirmedOperation() async {
    final sessionEpoch = _sessionEpoch;
    final repository = ref.read(homeRepositoryProvider);
    if (repository case final HomeCacheInvalidator invalidator) {
      try {
        await invalidator.invalidateHomeCache();
      } catch (_) {
        // The network refresh below remains authoritative. No cache or payload
        // details are exposed through logs or state.
      }
    }
    if (sessionEpoch != _sessionEpoch) return;

    final retained = state.retainedSnapshot;
    await _request(
      forceRefresh: true,
      retainedSnapshot: retained,
      showRetainedRefresh: retained != null,
      readCacheFirst: false,
    );
  }

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

  Future<void> _request({
    required bool forceRefresh,
    required HomeSnapshot? retainedSnapshot,
    required bool showRetainedRefresh,
    required bool readCacheFirst,
  }) async {
    if (_requestInFlight) {
      if (_activeRequestEpoch != _sessionEpoch) {
        _reloadAfterInFlight = true;
      }
      return;
    }
    _requestInFlight = true;
    final sessionEpoch = _sessionEpoch;
    _activeRequestEpoch = sessionEpoch;
    var effectiveSnapshot = retainedSnapshot;

    try {
      final repository = ref.read(homeRepositoryProvider);

      if (readCacheFirst) {
        if (repository case final HomeCacheReader cacheReader) {
          try {
            final cached = await cacheReader.readCachedHome();
            effectiveSnapshot = cached?.snapshot;
          } catch (_) {
            effectiveSnapshot = null;
          }
        }
      }
      if (sessionEpoch != _sessionEpoch) return;

      if (effectiveSnapshot != null &&
          (showRetainedRefresh || readCacheFirst)) {
        state = HomeRefreshing(effectiveSnapshot);
      } else {
        state = const HomeLoading();
      }

      final result = await repository.fetchHome(forceRefresh: forceRefresh);
      if (sessionEpoch != _sessionEpoch) return;
      await _applyResult(
        result,
        retainedSnapshot: effectiveSnapshot,
        forceRefresh: forceRefresh,
        sessionEpoch: sessionEpoch,
      );
    } catch (_) {
      if (sessionEpoch != _sessionEpoch) return;
      _showFailure(
        type: HomeFailureType.unknown,
        requestId: 'req_local_unexpected',
        retainedSnapshot: effectiveSnapshot,
      );
    } finally {
      _requestInFlight = false;
      _activeRequestEpoch = null;
      if (_reloadAfterInFlight) {
        _reloadAfterInFlight = false;
        unawaited(load());
      }
    }
  }

  Future<void> _applyResult(
    HomeRepositoryResult result, {
    required HomeSnapshot? retainedSnapshot,
    required bool forceRefresh,
    required int sessionEpoch,
  }) async {
    if (sessionEpoch != _sessionEpoch) return;
    switch (result) {
      case HomeDataResult(:final snapshot):
        _authRefreshAttempted = false;
        state = snapshot == null ? const HomeEmpty() : HomeReady(snapshot);
      case HomePartialResult(:final snapshot, :final blockFailures):
        _authRefreshAttempted = false;
        state = HomePartial(snapshot: snapshot, blockFailures: blockFailures);
      case HomeOfflineResult(:final snapshot):
        _authRefreshAttempted = false;
        state = HomeOffline(snapshot);
      case HomeFailureResult(:final type, :final requestId):
        _showFailure(
          type: type,
          requestId: requestId,
          retainedSnapshot: retainedSnapshot,
        );
      case HomeAuthExpiredResult(:final requestId):
        await _recoverAuthentication(
          requestId: requestId,
          retainedSnapshot: retainedSnapshot,
          forceRefresh: forceRefresh,
          sessionEpoch: sessionEpoch,
        );
    }
  }

  Future<void> _recoverAuthentication({
    required String requestId,
    required HomeSnapshot? retainedSnapshot,
    required bool forceRefresh,
    required int sessionEpoch,
  }) async {
    if (sessionEpoch != _sessionEpoch) return;
    var authRequestId = requestId;
    if (!_authRefreshAttempted) {
      _authRefreshAttempted = true;
      final sessionBeforeRecovery = await _readSessionSafely();
      if (sessionEpoch != _sessionEpoch) return;
      HomeSessionRecoveryResult recoveryResult;
      try {
        recoveryResult = await ref
            .read(homeSessionRecoveryProvider)
            .refreshSession();
      } catch (_) {
        recoveryResult = HomeSessionRecoveryResult.signOutRequired;
      }
      final sessionAfterRecovery = await _readSessionSafely();

      if (recoveryResult == HomeSessionRecoveryResult.recovered) {
        if (!_isSameAccount(sessionBeforeRecovery, sessionAfterRecovery)) {
          return;
        }
        final retryEpoch = _sessionEpoch;
        final retryResult = await ref
            .read(homeRepositoryProvider)
            .fetchHome(forceRefresh: forceRefresh);
        if (retryEpoch != _sessionEpoch) return;
        if (retryResult is! HomeAuthExpiredResult) {
          await _applyResult(
            retryResult,
            retainedSnapshot: retainedSnapshot,
            forceRefresh: forceRefresh,
            sessionEpoch: retryEpoch,
          );
          return;
        }
        authRequestId = retryResult.requestId;
        if (retryEpoch != _sessionEpoch) return;
      } else if (recoveryResult == HomeSessionRecoveryResult.signOutRequired) {
        if (!_isSameSession(sessionBeforeRecovery, sessionAfterRecovery)) {
          return;
        }
      } else {
        _authRefreshAttempted = false;
        _showFailure(
          type: HomeFailureType.serviceUnavailable,
          requestId: authRequestId,
          retainedSnapshot: retainedSnapshot,
        );
        return;
      }
    }

    state = HomeAuthRequired(
      requestId: authRequestId,
      snapshot: retainedSnapshot,
    );
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
  }) {
    state = retainedSnapshot == null
        ? HomeFailure(type: type, requestId: requestId)
        : HomeRefreshFailure(
            snapshot: retainedSnapshot,
            type: type,
            requestId: requestId,
          );
  }
}
