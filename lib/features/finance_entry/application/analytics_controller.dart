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
    List<FinanceAccount> wallets = const [],
    this.accountId,
  }) : recent = List<OperationHistoryItem>.unmodifiable(recent),
       wallets = List<FinanceAccount>.unmodifiable(wallets);

  final AnalyticsWindow window;

  /// Every wallet, so one can be chosen. Empty when they could not be read:
  /// a report of the default wallet is still worth showing (ADR 0029).
  final List<FinanceAccount> wallets;

  /// The wallet being reported. Null is the default one.
  final String? accountId;

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

  /// Which wallet is being reported. Null is the default one.
  String? _accountId;
  List<FinanceAccount> _wallets = const [];
  DateTime? _customFrom;
  DateTime? _customTo;

  /// The window currently reported. Kept here rather than in the state so a
  /// failed load still knows which one to retry.
  AnalyticsPeriodKind get period => _period;

  /// The chosen window when [period] is custom, so the screen can show which
  /// dates it is reporting rather than re-deriving them from the response.
  ({DateTime from, DateTime to})? get customWindow {
    final from = _customFrom;
    final to = _customTo;
    if (from == null || to == null) return null;
    return (from: from, to: to);
  }

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
    if (period == AnalyticsPeriodKind.custom) {
      // A custom window without both bounds is not a window. The screen asks
      // for the dates first and comes back through [selectCustomWindow].
      return;
    }
    _period = period;
    _customFrom = null;
    _customTo = null;
    await load();
  }

  /// Reports an arbitrary window the user picked.
  ///
  /// The bounds are ordered here rather than trusted from the picker, because
  /// a reversed window is refused by the server as a bad request and there is
  /// nothing to learn from that round trip.
  Future<void> selectCustomWindow(DateTime from, DateTime to) async {
    final ordered = from.isAfter(to) ? (to, from) : (from, to);
    _period = AnalyticsPeriodKind.custom;
    _customFrom = _dateOnly(ordered.$1);
    _customTo = _dateOnly(ordered.$2);
    await load();
  }

  Future<void> load() => _read(keepVisible: false);

  /// Re-reads the same window while the current one stays on screen.
  ///
  /// A pull that replaces usable figures with a spinner, or with an error page
  /// when the network blinks, is worse than no refresh at all. Returns `false`
  /// when the screen is still showing the older reading.
  Future<bool> refresh() => _read(keepVisible: true);

  /// Report another wallet.
  ///
  /// Null means the default one, which is what the balance card shows.
  /// Figures are never added across wallets: that would need a rate, and
  /// there is none (ADR 0029).
  Future<void> selectAccount(String? accountId) async {
    if (_accountId == accountId) return;
    _accountId = accountId;
    await _read(keepVisible: false);
  }

  Future<bool> _read({required bool keepVisible}) async {
    if (_requestInFlight) return true;
    final requestGeneration = _beginRequest();
    final retained = keepVisible && state is AnalyticsReady;
    if (!retained) state = const AnalyticsLoading();
    try {
      final result = await _repository.readAnalyticsWindow(
        period: _period,
        from: _customFrom == null ? null : _dateWire(_customFrom!),
        to: _customTo == null ? null : _dateWire(_customTo!),
        accountId: _accountId,
      );
      if (!_isCurrentRequest(requestGeneration)) return false;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = AnalyticsReady(
            window: value,
            recent: const [],
            wallets: _wallets,
            accountId: _accountId,
          );
          await _loadRecent(requestGeneration);
          await _loadWallets(requestGeneration);
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
  /// Reads the wallet list beside the report.
  ///
  /// A failure leaves the chooser out rather than the report: not knowing
  /// which other wallets exist is not a reason to hide this one's figures.
  Future<void> _loadWallets(int requestGeneration) async {
    if (_wallets.isNotEmpty) return;
    try {
      final result = await _repository.listAccounts();
      if (!_isCurrentRequest(requestGeneration)) return;
      if (result case FinanceEntrySuccess(:final value)) {
        _wallets = value.accounts;
        final current = state;
        if (current is AnalyticsReady) {
          state = AnalyticsReady(
            window: current.window,
            recent: current.recent,
            wallets: _wallets,
            accountId: _accountId,
          );
        }
      }
    } on Object {
      // Left out, deliberately.
    }
  }

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

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _dateWire(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_analytics_unknown',
);
