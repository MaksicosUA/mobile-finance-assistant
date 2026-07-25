import 'home_repository.dart';

enum HomeScenario {
  populated,
  partialGoal,
  offline,
  authExpired,
  fatal,
  refreshFailure,
}

class ScenarioHomeRepository implements HomeRepository {
  ScenarioHomeRepository({
    required this.fixtureRepository,
    this.scenario = HomeScenario.populated,
  });

  final HomeRepository fixtureRepository;
  final HomeScenario scenario;

  var _requestCount = 0;

  int get requestCount => _requestCount;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    _requestCount += 1;

    switch (scenario) {
      case HomeScenario.authExpired:
        return const HomeAuthExpiredResult(requestId: 'req_fixture_auth');
      case HomeScenario.fatal:
        return const HomeFailureResult(
          type: HomeFailureType.serviceUnavailable,
          requestId: 'req_fixture_fatal',
        );
      case HomeScenario.refreshFailure when _requestCount > 1:
        return const HomeFailureResult(
          type: HomeFailureType.timeout,
          requestId: 'req_fixture_refresh',
        );
      case HomeScenario.populated:
      case HomeScenario.partialGoal:
      case HomeScenario.offline:
      case HomeScenario.refreshFailure:
        break;
    }

    final fixtureResult = await fixtureRepository.fetchHome(
      forceRefresh: forceRefresh,
    );
    if (fixtureResult is! HomeDataResult || fixtureResult.snapshot == null) {
      return fixtureResult;
    }
    final snapshot = fixtureResult.snapshot!;

    return switch (scenario) {
      HomeScenario.partialGoal => HomePartialResult(
        snapshot: snapshot,
        blockFailures: const {
          HomeBlock.primaryGoal: HomeBlockFailure(
            code: 'goal_unavailable',
            requestId: 'req_fixture_goal',
          ),
        },
      ),
      HomeScenario.offline => HomeOfflineResult(snapshot),
      HomeScenario.populated || HomeScenario.refreshFailure => fixtureResult,
      HomeScenario.authExpired || HomeScenario.fatal => fixtureResult,
    };
  }
}

HomeScenario homeScenarioFromName(String value) {
  return switch (value) {
    'partial' => HomeScenario.partialGoal,
    'offline' => HomeScenario.offline,
    'auth' => HomeScenario.authExpired,
    'fatal' => HomeScenario.fatal,
    'refresh_failure' => HomeScenario.refreshFailure,
    _ => HomeScenario.populated,
  };
}
