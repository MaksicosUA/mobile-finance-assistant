import 'package:flutter/foundation.dart';

import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';

sealed class HomeState {
  const HomeState();

  HomeSnapshot? get retainedSnapshot => switch (this) {
    HomeReady(:final snapshot) ||
    HomeRefreshing(:final snapshot) ||
    HomePartial(:final snapshot) ||
    HomeOffline(:final snapshot) ||
    HomeRefreshFailure(:final snapshot) => snapshot,
    HomeAuthRequired(:final snapshot) => snapshot,
    HomeLoading() || HomeEmpty() || HomeFailure() => null,
  };
}

final class HomeLoading extends HomeState {
  const HomeLoading();
}

final class HomeEmpty extends HomeState {
  const HomeEmpty();
}

final class HomeReady extends HomeState {
  const HomeReady(this.snapshot);

  final HomeSnapshot snapshot;
}

final class HomeRefreshing extends HomeState {
  const HomeRefreshing(this.snapshot);

  final HomeSnapshot snapshot;
}

@immutable
final class HomePartial extends HomeState {
  HomePartial({
    required this.snapshot,
    required Map<HomeBlock, HomeBlockFailure> blockFailures,
  }) : blockFailures = Map<HomeBlock, HomeBlockFailure>.unmodifiable(
         blockFailures,
       );

  final HomeSnapshot snapshot;
  final Map<HomeBlock, HomeBlockFailure> blockFailures;
}

final class HomeOffline extends HomeState {
  const HomeOffline(this.snapshot);

  final HomeSnapshot snapshot;
}

final class HomeRefreshFailure extends HomeState {
  const HomeRefreshFailure({
    required this.snapshot,
    required this.type,
    required this.requestId,
  });

  final HomeSnapshot snapshot;
  final HomeFailureType type;
  final String requestId;
}

final class HomeAuthRequired extends HomeState {
  const HomeAuthRequired({required this.requestId, this.snapshot});

  final String requestId;
  final HomeSnapshot? snapshot;
}

final class HomeFailure extends HomeState {
  const HomeFailure({required this.type, required this.requestId});

  final HomeFailureType type;
  final String requestId;
}
