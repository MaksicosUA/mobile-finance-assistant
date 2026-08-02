import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/data/home_api.dart';
import 'package:mobile_finance_assistant/features/home/data/home_cache.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository_impl.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

void main() {
  test(
    'guarded fetch stops before a second API request after backgrounding',
    () async {
      final api = _FailingHomeApi();
      final cache = _EmptyHomeCache();
      final session = HomeSessionSnapshot(
        accessToken: 'synthetic-access-token',
        cacheScopeId: 'synthetic-account',
        revision: '0123456789abcdef0123456789abcdef',
      );
      var requestAllowed = true;
      final delays = <Duration>[];
      final repository = NetworkHomeRepository(
        api: api,
        cache: cache,
        sessionProvider: () async => session,
        retryDelay: (duration) async {
          delays.add(duration);
          requestAllowed = false;
        },
        retryJitter: () => 0.5,
      );

      final result = await repository.fetchHomeGuarded(
        forceRefresh: true,
        preflight: () => requestAllowed,
      );

      expect(result, isA<HomeRequestInterruptedResult>());
      expect(api.calls, 1);
      expect(delays, const [Duration(milliseconds: 250)]);
      expect(cache.reads, 1);
      expect(cache.writes, 0);
    },
  );
}

final class _FailingHomeApi implements HomeApiClient {
  var calls = 0;

  @override
  Future<HomeApiResult> fetchHome({String? etag, String? accessToken}) async {
    calls += 1;
    if (calls > 1) {
      throw StateError('A second API request must not start.');
    }
    return const HomeApiServerFailure(
      requestId: 'req_retryable_server_failure',
      statusCode: 503,
    );
  }
}

final class _EmptyHomeCache implements HomeCache {
  var reads = 0;
  var writes = 0;

  @override
  Future<HomeCacheEntry?> read({required String scopeId}) async {
    reads += 1;
    return null;
  }

  @override
  Future<void> write(HomeCacheEntry entry) async {
    writes += 1;
  }

  @override
  Future<void> clear() async {}
}
