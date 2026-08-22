import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';

final analyticsControllerProvider =
    NotifierProvider.autoDispose<AnalyticsController, AnalyticsState>(
      AnalyticsController.new,
    );

/// How many recent operations the analytics screen shows before the full list.
const int analyticsRecentOperations = 5;

sealed class AnalyticsState {
  const AnalyticsState();
}

final class AnalyticsLoading extends AnalyticsState {
  const AnalyticsLoading();
}

@immutable
final class AnalyticsReady extends AnalyticsState {
  AnalyticsReady({
    required this.window,
    required List<OperationHistoryItem> recent,
  }) : recent = List<OperationHistoryItem>.unmodifiable(recent);

  final AnalyticsWindow window;

  /// The newest operations, moved here from Home. Failing to read them must
  /// not hide the totals, so this is empty rather than fatal.
  final List<OperationHistoryItem> recent;
}

final class AnalyticsAuthenticationRequired extends AnalyticsState {
  const AnalyticsAuthenticationRequired();
}

@immutable
final class AnalyticsFailure extends AnalyticsState {
  const AnalyticsFailure(this.failure);

  final FinanceEntryFailure failure;
}

/// Reads one analysed month: totals, both breakdowns, the expense series, and
/// the newest operations.
///
/// Read-only. The figures are computed server-side from committed operations,
/// so nothing here recalculates money (AGENTS: clients format, never compute).
class AnalyticsController extends Notifier<AnalyticsState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;
  AnalyticsPeriodKind _period = AnalyticsPeriodKind.month;

  /// The window currently reported. Kept here rather than in the state so a
  /// failed load still knows which one to retry.
  AnalyticsPeriodKind get period => _period;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  AnalyticsState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const AnalyticsLoading();
  }

  /// Reports a different window. The screen shows its loading state again
  /// because every figure on it changes, not just the chart.
  Future<void> selectPeriod(AnalyticsPeriodKind period) async {
    if (period == _period) return;
    _period = period;
    await load();
  }

  Future<void> load() => _read(keepVisible: false);

  /// Re-reads the same window while the current one stays on screen.
  ///
  /// A pull that replaces usable figures with a spinner, or with an error page
  /// when the network blinks, is worse than no refresh at all. Returns `false`
  /// when the screen is still showing the older reading.
  Future<bool> refresh() => _read(keepVisible: true);

  Future<bool> _read({required bool keepVisible}) async {
    if (_requestInFlight) return true;
    final requestGeneration = _beginRequest();
    final retained = keepVisible && state is AnalyticsReady;
    if (!retained) state = const AnalyticsLoading();
    try {
      final result = await _repository.readAnalyticsWindow(period: _period);
      if (!_isCurrentRequest(requestGeneration)) return false;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = AnalyticsReady(window: value, recent: const []);
          await _loadRecent(requestGeneration);
          return true;
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const AnalyticsAuthenticationRequired();
          } else if (!retained) {
            state = AnalyticsFailure(failure);
          }
          return false;
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration) && !retained) {
        state = AnalyticsFailure(_unexpectedFailure());
      }
      return false;
    } finally {
      _endRequest(requestGeneration);
    }
  }

  /// Reads the newest operations as a secondary block.
  ///
  /// Deliberately swallows its own failure: the month's totals are the point
  /// of this screen, and losing them because a list failed would be worse.
  Future<void> _loadRecent(int requestGeneration) async {
    try {
      final result = await _repository.listOperations(
        limit: analyticsRecentOperations,
      );
      if (!_isCurrentRequest(requestGeneration)) return;
      final current = state;
      if (current is! AnalyticsReady) return;
      if (result case FinanceEntrySuccess(:final value)) {
        state = AnalyticsReady(
          window: current.window,
          recent: value.operations,
        );
      }
    } on Object {
      return;
    }
  }

  int _beginRequest() {
    _requestInFlight = true;
    _requestGeneration += 1;
    return _requestGeneration;
  }

  bool _isCurrentRequest(int requestGeneration) =>
      ref.mounted && requestGeneration == _requestGeneration;

  void _endRequest(int requestGeneration) {
    if (_isCurrentRequest(requestGeneration)) _requestInFlight = false;
  }
}

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_analytics_unknown',
);
