import 'package:flutter/foundation.dart';

import '../domain/home_snapshot.dart';

enum HomeBlock {
  balance,
  balanceDelta,
  monthSummary,
  trend,
  primaryGoal,
  upcomingPayments,
  recentTransactions,
}

/// Maps the open contract enum to blocks understood by this client version.
///
/// Unknown future values are ignored so additive backend changes cannot hide
/// otherwise usable v2 data.
HomeBlock? homeBlockFromContract(String value) {
  return switch (value) {
    'balance' => HomeBlock.balance,
    'balanceDelta' => HomeBlock.balanceDelta,
    'monthSummary' => HomeBlock.monthSummary,
    'trend' => HomeBlock.trend,
    'primaryGoal' => HomeBlock.primaryGoal,
    'upcomingPayments' => HomeBlock.upcomingPayments,
    'recentTransactions' => HomeBlock.recentTransactions,
    _ => null,
  };
}

enum HomeFailureType { timeout, serviceUnavailable, unknown }

@immutable
class HomeBlockFailure {
  const HomeBlockFailure({required this.code, required this.requestId});

  final String code;
  final String requestId;
}

sealed class HomeRepositoryResult {
  const HomeRepositoryResult();
}

final class HomeDataResult extends HomeRepositoryResult {
  const HomeDataResult(this.snapshot);

  final HomeSnapshot snapshot;
}

final class HomeFirstUseResult extends HomeRepositoryResult {
  const HomeFirstUseResult(this.data);

  final HomeFirstUseData data;
}

final class HomePartialResult extends HomeRepositoryResult {
  HomePartialResult({
    required this.snapshot,
    required Map<HomeBlock, HomeBlockFailure> blockFailures,
  }) : blockFailures = Map<HomeBlock, HomeBlockFailure>.unmodifiable(
         blockFailures,
       );

  final HomeSnapshot snapshot;
  final Map<HomeBlock, HomeBlockFailure> blockFailures;
}

final class HomeOfflineResult extends HomeRepositoryResult {
  const HomeOfflineResult(this.snapshot);

  /// The most recent valid cached snapshot retained while the network is down.
  final HomeSnapshot snapshot;
}

final class HomeAuthExpiredResult extends HomeRepositoryResult {
  const HomeAuthExpiredResult({required this.requestId});

  final String requestId;
}

final class HomeFailureResult extends HomeRepositoryResult {
  const HomeFailureResult({required this.type, required this.requestId});

  final HomeFailureType type;
  final String requestId;
}

@immutable
final class HomeCachedSnapshot {
  const HomeCachedSnapshot({required this.snapshot, required this.isStale});

  final HomeSnapshot snapshot;
  final bool isStale;
}

abstract interface class HomeRepository {
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false});
}

/// Optional cache-first capability implemented by the network repository.
abstract interface class HomeCacheReader {
  Future<HomeCachedSnapshot?> readCachedHome();
}

/// Invalidates a replaceable snapshot after a confirmed financial operation.
abstract interface class HomeCacheInvalidator {
  Future<void> invalidateHomeCache();
}
