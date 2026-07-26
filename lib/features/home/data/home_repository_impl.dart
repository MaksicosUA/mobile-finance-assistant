import 'dart:async';
import 'dart:math';

import '../domain/home_snapshot.dart';
import 'home_api.dart';
import 'home_cache.dart';
import 'home_dto.dart';
import 'home_mapper.dart';
import 'home_repository.dart';
import 'home_session_store.dart';

typedef HomeSessionProvider = Future<HomeSessionSnapshot?> Function();
typedef HomeRepositoryClock = DateTime Function();
typedef HomeRetryDelay = Future<void> Function(Duration duration);
typedef HomeRetryJitter = double Function();

/// Cache-first, read-only implementation of the Home aggregate repository.
///
/// A cache scope must be a stable opaque identifier for the authenticated
/// account. Returning null disables persistence, which is safer than sharing a
/// snapshot when the authentication layer cannot prove the current scope.
final class NetworkHomeRepository
    implements HomeRepository, HomeCacheReader, HomeCacheInvalidator {
  NetworkHomeRepository({
    required HomeApiClient api,
    required HomeCache cache,
    required HomeSessionProvider sessionProvider,
    HomeRepositoryClock clock = _utcNow,
    HomeRetryDelay retryDelay = _delay,
    HomeRetryJitter retryJitter = _secureJitter,
    Duration cacheTtl = const Duration(minutes: 15),
    Duration maximumStaleAge = const Duration(days: 7),
    int maximumAttempts = 3,
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _api = api,
       // ignore: prefer_initializing_formals
       _cache = cache,
       // ignore: prefer_initializing_formals
       _sessionProvider = sessionProvider,
       // ignore: prefer_initializing_formals
       _clock = clock,
       // ignore: prefer_initializing_formals
       _retryDelay = retryDelay,
       // ignore: prefer_initializing_formals
       _retryJitter = retryJitter,
       _cacheTtl = cacheTtl,
       _maximumStaleAge = maximumStaleAge,
       _maximumAttempts = maximumAttempts {
    if (cacheTtl <= Duration.zero) {
      throw ArgumentError.value(cacheTtl, 'cacheTtl', 'Must be positive.');
    }
    if (maximumStaleAge < cacheTtl) {
      throw ArgumentError.value(
        maximumStaleAge,
        'maximumStaleAge',
        'Must be at least the cache TTL.',
      );
    }
    if (maximumAttempts < 1 || maximumAttempts > 3) {
      throw ArgumentError.value(
        maximumAttempts,
        'maximumAttempts',
        'Must be between one and three.',
      );
    }
  }

  static const Duration _baseRetryDelay = Duration(milliseconds: 250);
  static const Duration _maximumRetryDelay = Duration(seconds: 3);

  final HomeApiClient _api;
  final HomeCache _cache;
  final HomeSessionProvider _sessionProvider;
  final HomeRepositoryClock _clock;
  final HomeRetryDelay _retryDelay;
  final HomeRetryJitter _retryJitter;
  final Duration _cacheTtl;
  final Duration _maximumStaleAge;
  final int _maximumAttempts;

  @override
  Future<HomeCachedSnapshot?> readCachedHome() async {
    final session = await _readSession();
    if (session == null) return null;
    final scopeId = session.scopedCacheScopeId;

    final cached = await _readValidCache(scopeId);
    if (cached == null) return null;
    if (!session.isSameSession(await _readSession())) {
      await _clearBestEffort();
      return null;
    }
    final decoded = _decodePayload(cached.payload);
    if (decoded == null || decoded.dto.homeState != HomePayloadState.ready) {
      await _clearBestEffort();
      return null;
    }
    return HomeCachedSnapshot(
      snapshot: decoded.snapshot,
      isStale: cached.isStaleAt(_clock().toUtc()),
    );
  }

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    final session = await _readSession();
    final scopeId = session?.scopedCacheScopeId;
    var cached = scopeId == null ? null : await _readValidCache(scopeId);
    if (!await _sessionIsCurrent(session)) {
      await _clearBestEffort();
      return HomeFailureResult(
        type: HomeFailureType.unknown,
        requestId: 'req_local_session_changed',
      );
    }

    var apiResult = await _fetchWithRetry(
      // A user refresh or post-confirmation invalidation must be an
      // unconditional revalidation even when best-effort cache deletion
      // failed. Retain the old entry only as an offline fallback.
      etag: forceRefresh ? null : cached?.etag,
      expectedSession: session,
    );
    if (apiResult is HomeApiNotModified && (cached == null || forceRefresh)) {
      if (!await _sessionIsCurrent(session)) {
        await _clearBestEffort();
        return HomeFailureResult(
          type: HomeFailureType.unknown,
          requestId: apiResult.requestId,
        );
      }
      // A proxy or server may return an invalid 304 without a conditional
      // request. Recover with one unconditional request instead of rendering
      // an empty or known-stale screen.
      apiResult = await _fetchWithRetry(expectedSession: session);
    }

    // Do not return or persist a response if sign-in/account state changed
    // while the request was in flight. The next load will use the new session.
    if (!await _sessionIsCurrent(session)) {
      await _clearBestEffort();
      return HomeFailureResult(
        type: HomeFailureType.unknown,
        requestId: apiResult.requestId,
      );
    }

    switch (apiResult) {
      case HomeApiData(:final payload, :final etag, :final requestId):
        final decoded = _decodePayload(payload);
        if (decoded == null) {
          return HomeFailureResult(
            type: HomeFailureType.unknown,
            requestId: requestId,
          );
        }
        if (decoded.dto.homeState == HomePayloadState.firstUseEmpty) {
          // An empty account is authoritative. Do not retain or persist the
          // previous financial snapshot under the same account scope.
          await _clearBestEffort();
          if (!await _sessionIsCurrent(session)) {
            return HomeFailureResult(
              type: HomeFailureType.unknown,
              requestId: requestId,
            );
          }
          return HomeFirstUseResult(HomeMapper.toFirstUseData(decoded.dto));
        }
        if (scopeId != null) {
          final now = _clock().toUtc();
          await _writeBestEffort(
            HomeCacheEntry(
              payload: payload,
              etag: etag,
              storedAtUtc: now,
              expiresAtUtc: now.add(_cacheTtl),
              scopeId: scopeId,
            ),
          );
          if (!await _sessionIsCurrent(session)) {
            await _clearBestEffort();
            return HomeFailureResult(
              type: HomeFailureType.unknown,
              requestId: requestId,
            );
          }
        }
        return _resultFor(decoded, requestId: requestId);
      case HomeApiNotModified(:final etag, :final requestId):
        if (forceRefresh) {
          return HomeFailureResult(
            type: HomeFailureType.unknown,
            requestId: requestId,
          );
        }
        final current = cached;
        if (current == null) {
          return HomeFailureResult(
            type: HomeFailureType.unknown,
            requestId: requestId,
          );
        }
        final decoded = _decodePayload(current.payload);
        if (decoded == null) {
          await _clearBestEffort();
          return HomeFailureResult(
            type: HomeFailureType.unknown,
            requestId: requestId,
          );
        }
        if (decoded.dto.homeState == HomePayloadState.firstUseEmpty) {
          await _clearBestEffort();
          if (!await _sessionIsCurrent(session)) {
            return HomeFailureResult(
              type: HomeFailureType.unknown,
              requestId: requestId,
            );
          }
          return HomeFirstUseResult(HomeMapper.toFirstUseData(decoded.dto));
        }
        final now = _clock().toUtc();
        cached = HomeCacheEntry(
          payload: current.payload,
          etag: etag ?? current.etag,
          storedAtUtc: now,
          expiresAtUtc: now.add(_cacheTtl),
          scopeId: current.scopeId,
        );
        await _writeBestEffort(cached);
        if (!await _sessionIsCurrent(session)) {
          await _clearBestEffort();
          return HomeFailureResult(
            type: HomeFailureType.unknown,
            requestId: requestId,
          );
        }
        return _resultFor(decoded, requestId: requestId);
      case HomeApiOfflineFailure():
        final snapshot = cached == null ? null : _mapPayload(cached.payload);
        return snapshot == null
            ? HomeFailureResult(
                type: HomeFailureType.timeout,
                requestId: apiResult.requestId,
              )
            : HomeOfflineResult(snapshot);
      case HomeApiTimeoutFailure():
        return HomeFailureResult(
          type: HomeFailureType.timeout,
          requestId: apiResult.requestId,
        );
      case HomeApiUnauthorizedFailure():
        return HomeAuthExpiredResult(requestId: apiResult.requestId);
      case HomeApiThrottledFailure() || HomeApiServerFailure():
        return HomeFailureResult(
          type: HomeFailureType.serviceUnavailable,
          requestId: apiResult.requestId,
        );
      case HomeApiMalformedFailure() || HomeApiOtherFailure():
        return HomeFailureResult(
          type: HomeFailureType.unknown,
          requestId: apiResult.requestId,
        );
    }
  }

  @override
  Future<void> invalidateHomeCache() => _cache.clear();

  Future<HomeApiResult> _fetchWithRetry({
    String? etag,
    required HomeSessionSnapshot? expectedSession,
  }) async {
    late HomeApiResult result;
    for (var attempt = 1; attempt <= _maximumAttempts; attempt += 1) {
      // Do not start a later attempt with a credential captured before a
      // sign-out, account switch, or token refresh.
      if (attempt > 1 && !await _sessionIsCurrent(expectedSession)) {
        return result;
      }
      result = await _api.fetchHome(
        etag: etag,
        accessToken: expectedSession?.accessToken,
      );
      if (attempt == _maximumAttempts || !_isRetryable(result)) {
        return result;
      }

      final retryAfter = result is HomeApiThrottledFailure
          ? result.retryAfter
          : null;
      if (retryAfter != null && retryAfter > _maximumRetryDelay) {
        return result;
      }
      await _retryDelay(retryAfter ?? _backoffFor(attempt));
    }
    return result;
  }

  bool _isRetryable(HomeApiResult result) {
    return result is HomeApiTimeoutFailure ||
        result is HomeApiServerFailure ||
        result is HomeApiThrottledFailure;
  }

  Duration _backoffFor(int attempt) {
    final exponential = _baseRetryDelay.inMilliseconds * (1 << (attempt - 1));
    final bounded = min(exponential, _maximumRetryDelay.inMilliseconds);
    final jitter = 0.75 + (_retryJitter().clamp(0.0, 1.0) * 0.5);
    return Duration(milliseconds: (bounded * jitter).round());
  }

  Future<HomeSessionSnapshot?> _readSession() async {
    try {
      return await _sessionProvider();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _sessionIsCurrent(HomeSessionSnapshot? expected) async {
    final current = await _readSession();
    return expected == null ? current == null : expected.isSameSession(current);
  }

  Future<HomeCacheEntry?> _readValidCache(String scopeId) async {
    try {
      final entry = await _cache.read(scopeId: scopeId);
      if (entry == null) return null;

      final now = _clock().toUtc();
      final age = now.difference(entry.storedAtUtc);
      if (age.isNegative || age > _maximumStaleAge) {
        await _clearBestEffort();
        return null;
      }
      final decoded = _decodePayload(entry.payload);
      if (decoded == null ||
          decoded.dto.homeState == HomePayloadState.firstUseEmpty) {
        await _clearBestEffort();
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  HomeSnapshot? _mapPayload(Map<String, Object?> payload) {
    return _decodePayload(payload)?.snapshot;
  }

  _DecodedHomePayload? _decodePayload(Map<String, Object?> payload) {
    try {
      final dto = HomeDto.fromJson(payload);
      return _DecodedHomePayload(dto: dto, snapshot: HomeMapper.toDomain(dto));
    } catch (_) {
      return null;
    }
  }

  HomeRepositoryResult _resultFor(
    _DecodedHomePayload decoded, {
    required String requestId,
  }) {
    final blockFailures = <HomeBlock, HomeBlockFailure>{};
    for (final warning in decoded.dto.warnings) {
      final block = homeBlockFromContract(warning.block);
      if (block == null) continue;
      blockFailures.putIfAbsent(
        block,
        () => HomeBlockFailure(code: warning.code, requestId: requestId),
      );
    }
    if (blockFailures.isEmpty) {
      return HomeDataResult(decoded.snapshot);
    }
    return HomePartialResult(
      snapshot: decoded.snapshot,
      blockFailures: blockFailures,
    );
  }

  Future<void> _writeBestEffort(HomeCacheEntry entry) async {
    try {
      await _cache.write(entry);
    } catch (_) {
      // The network response remains usable; never downgrade to plaintext.
    }
  }

  Future<void> _clearBestEffort() async {
    try {
      await _cache.clear();
    } catch (_) {
      // A replaceable cache failure must not expose storage details.
    }
  }
}

final class _DecodedHomePayload {
  const _DecodedHomePayload({required this.dto, required this.snapshot});

  final HomeDto dto;
  final HomeSnapshot snapshot;
}

DateTime _utcNow() => DateTime.now().toUtc();

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);

double _secureJitter() => Random.secure().nextDouble();
