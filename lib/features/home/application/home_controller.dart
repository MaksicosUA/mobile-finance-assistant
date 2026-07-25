import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_repository.dart';
import '../data/mock_home_repository.dart';
import '../data/scenario_home_repository.dart';
import '../domain/home_snapshot.dart';
import 'home_session_recovery.dart';
import 'home_state.dart';

export 'home_state.dart';

const _homeFixture = String.fromEnvironment(
  'HOME_FIXTURE',
  defaultValue: 'populated',
);
const _homeScenario = String.fromEnvironment(
  'HOME_SCENARIO',
  defaultValue: 'populated',
);

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
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
  var _authRefreshAttempted = false;

  @override
  HomeState build() => const HomeLoading();

  Future<void> load() async {
    final retained = state.retainedSnapshot;
    await _request(
      forceRefresh: false,
      retainedSnapshot: retained,
      showRetainedRefresh: retained != null,
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
        );
      case HomeFailure() || HomeLoading() || HomeEmpty():
        await _request(
          forceRefresh: true,
          retainedSnapshot: null,
          showRetainedRefresh: false,
        );
      case HomeAuthRequired() || HomeReady() || HomeRefreshing():
        break;
    }
  }

  Future<void> _request({
    required bool forceRefresh,
    required HomeSnapshot? retainedSnapshot,
    required bool showRetainedRefresh,
  }) async {
    if (_requestInFlight) return;
    _requestInFlight = true;

    if (showRetainedRefresh && retainedSnapshot != null) {
      state = HomeRefreshing(retainedSnapshot);
    } else {
      state = const HomeLoading();
    }

    try {
      final result = await ref
          .read(homeRepositoryProvider)
          .fetchHome(forceRefresh: forceRefresh);
      await _applyResult(
        result,
        retainedSnapshot: retainedSnapshot,
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      _showFailure(
        type: HomeFailureType.unknown,
        requestId: 'req_local_unexpected',
        retainedSnapshot: retainedSnapshot,
      );
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _applyResult(
    HomeRepositoryResult result, {
    required HomeSnapshot? retainedSnapshot,
    required bool forceRefresh,
  }) async {
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
        );
    }
  }

  Future<void> _recoverAuthentication({
    required String requestId,
    required HomeSnapshot? retainedSnapshot,
    required bool forceRefresh,
  }) async {
    if (!_authRefreshAttempted) {
      _authRefreshAttempted = true;
      HomeSessionRecoveryResult recoveryResult;
      try {
        recoveryResult = await ref
            .read(homeSessionRecoveryProvider)
            .refreshSession();
      } catch (_) {
        recoveryResult = HomeSessionRecoveryResult.signOutRequired;
      }

      if (recoveryResult == HomeSessionRecoveryResult.recovered) {
        final retryResult = await ref
            .read(homeRepositoryProvider)
            .fetchHome(forceRefresh: forceRefresh);
        if (retryResult is! HomeAuthExpiredResult) {
          await _applyResult(
            retryResult,
            retainedSnapshot: retainedSnapshot,
            forceRefresh: forceRefresh,
          );
          return;
        }
      }
    }

    state = HomeAuthRequired(requestId: requestId, snapshot: retainedSnapshot);
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
