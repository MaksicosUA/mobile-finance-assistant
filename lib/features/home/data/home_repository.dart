import 'package:flutter/foundation.dart';

import '../domain/home_snapshot.dart';

enum HomeBlock {
  balance,
  monthSummary,
  trend,
  primaryGoal,
  upcomingPayments,
  recentTransactions,
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

  /// Null represents a first-use account without financial operations.
  final HomeSnapshot? snapshot;
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

  /// A synthetic cached snapshot in Slice 2; no persistence is implemented.
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

abstract interface class HomeRepository {
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false});
}
