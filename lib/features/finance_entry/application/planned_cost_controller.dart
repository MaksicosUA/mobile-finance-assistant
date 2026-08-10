import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';
import 'planned_cost_state.dart';

export 'planned_cost_state.dart';

final plannedCostControllerProvider =
    NotifierProvider.autoDispose<PlannedCostController, PlannedCostState>(
      PlannedCostController.new,
    );

/// Records one intended future payment.
///
/// A plan never moves the authoritative balance, so this controller has no
/// review step and no delivery outbox: a lost request simply means no plan was
/// recorded, which the user can see and repeat.
class PlannedCostController extends Notifier<PlannedCostState> {
  /// Reused across retries so a repeated submit is an idempotent replay rather
  /// than a second plan.
  String? _commandId;
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  DateTime get _now => ref.read(financeEntryClockProvider)();

  String get _newCommandId => ref.read(financeCommandIdFactoryProvider)();

  @override
  PlannedCostState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    _commandId = null;
    return const PlannedCostLoading();
  }

  Future<void> load() => _load();

  void setTitle(String value) {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    _commandId = null;
    state = current.copyWith(
      title: value,
      clearFailure: true,
      issues: const [],
    );
  }

  void setAmount(String value) {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    _commandId = null;
    state = current.copyWith(
      amount: value,
      clearFailure: true,
      issues: const [],
    );
  }

  void selectDate(DateTime value) {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    final selected = _dateOnly(value);
    if (selected.isBefore(current.earliestDate) ||
        selected.isAfter(current.latestDate)) {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }
    _commandId = null;
    state = current.copyWith(
      selectedDate: selected,
      clearFailure: true,
      issues: const [],
    );
  }

  Future<void> submit() async {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;

    late final PlannedCostDraft draft;
    try {
      if (current.selectedDate.isBefore(current.earliestDate) ||
          current.selectedDate.isAfter(current.latestDate)) {
        throw const FormatException('Planned date is outside local bounds.');
      }
      final commandId = _commandId ??= _newCommandId;
      draft = PlannedCostDraft(
        commandId: commandId,
        accountId: current.account.accountId,
        amount: _normalizedAmount(current.amount),
        currency: current.account.currency,
        title: current.title.trim(),
        plannedOn: plannedCostWireDate(current.selectedDate),
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validatePlannedCostDraft(draft);
    } on Object {
      _commandId = null;
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    final requestGeneration = _beginRequest();
    state = current.copyWith(
      isSubmitting: true,
      clearFailure: true,
      issues: const [],
    );
    try {
      final result = await _repository.createPlannedCost(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          _commandId = null;
          state = PlannedCostAccepted(
            plannedCost: value.plannedCost,
            homeStatus: PlannedCostHomeStatus.pending,
          );
          unawaited(
            _convergeHomeAfterAcceptedPlan(
              value.plannedCost,
              requestGeneration,
            ),
          );
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const PlannedCostAuthenticationRequired();
            return;
          }
          state = current.copyWith(
            isSubmitting: false,
            failure: failure,
            issues: failure.plannedCostIssues,
          );
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = current.copyWith(
          isSubmitting: false,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> _load() async {
    if (_requestInFlight) return;
    final requestGeneration = _beginRequest();
    _commandId = null;
    state = const PlannedCostLoading();
    try {
      final result = await _repository.listAccounts();
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          if (!value.isInitialized) {
            state = const PlannedCostUnavailable(
              PlannedCostUnavailableReason.accountRequired,
            );
            return;
          }
          state = _editingState(value.account!);
          await _loadPlans(requestGeneration);
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const PlannedCostAuthenticationRequired();
          } else {
            state = PlannedCostFailure(failure);
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = PlannedCostFailure(_unexpectedFailure());
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  /// Cancels one outstanding plan.
  ///
  /// Cancel, not skip: with no recurrence yet the two would look identical to
  /// a user, and cancel is what "this plan was wrong" means. Skip becomes
  /// meaningful only once a rule generates instances.
  Future<void> cancelPlan(String plannedCostId) async {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    if (current.settlingId != null) return;

    late final PlannedCostTransitionCommand command;
    try {
      command = PlannedCostTransitionCommand(
        commandId: _newCommandId,
        transition: PlannedCostTransition.cancel,
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validatePlannedCostTransition(command);
      validatePlannedCostId(plannedCostId);
    } on Object {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    final requestGeneration = _beginRequest();
    state = current.copyWith(
      settlingId: plannedCostId,
      clearFailure: true,
      issues: const [],
    );
    try {
      final result = await _repository.transitionPlannedCost(
        plannedCostId,
        command,
      );
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess():
          final latest = state;
          if (latest is! PlannedCostEditing) return;
          // A settled plan stops being an obligation, so it leaves the list.
          state = latest.copyWith(
            plans: latest.plans
                .where((plan) => plan.plannedCostId != plannedCostId)
                .toList(growable: false),
            clearSettlingId: true,
          );
          unawaited(_convergeHomeAfterSettledPlan());
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const PlannedCostAuthenticationRequired();
            return;
          }
          final latest = state;
          if (latest is! PlannedCostEditing) return;
          state = latest.copyWith(failure: failure, clearSettlingId: true);
      }
    } on Object {
      final latest = state;
      if (_isCurrentRequest(requestGeneration) &&
          latest is PlannedCostEditing) {
        state = latest.copyWith(
          failure: _unexpectedFailure(),
          clearSettlingId: true,
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> _loadPlans(int requestGeneration) async {
    try {
      final result = await _repository.listPlannedCosts();
      if (!_isCurrentRequest(requestGeneration)) return;
      final current = state;
      if (current is! PlannedCostEditing) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = current.copyWith(
            plans: value.plans
                .where((plan) => plan.status == 'planned')
                .toList(growable: false),
          );
        case FinanceEntryFailureResult():
          // The list is secondary: failing to read it must not block planning.
          return;
      }
    } on Object {
      return;
    }
  }

  Future<void> _convergeHomeAfterSettledPlan() async {
    try {
      await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite();
    } on Object {
      // Home convergence is best-effort here: the plan is already settled
      // server-side, and Home refreshes on its own schedule.
      return;
    }
  }

  PlannedCostEditing _editingState(FinanceAccount account) {
    final today = _dateOnly(_now.toUtc());
    final baseline = _parsedDate(account.openingBalanceOn) ?? today;
    // A plan before the baseline could never be confirmed into an operation.
    final earliest = baseline;
    // A usability bound on the picker, not a contract rule: the wire range
    // reaches 2100 and the server accepts anything inside it.
    final latest = DateTime.utc(today.year + 10, today.month, today.day);
    final selected = today.isBefore(earliest) ? earliest : today;
    return PlannedCostEditing(
      account: account,
      selectedDate: selected,
      earliestDate: earliest,
      latestDate: latest,
    );
  }

  Future<void> _convergeHomeAfterAcceptedPlan(
    PlannedCost plannedCost,
    int requestGeneration,
  ) async {
    PlannedCostHomeStatus homeStatus;
    try {
      final result = await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite();
      homeStatus = _homeStatus(result);
    } on Object {
      homeStatus = PlannedCostHomeStatus.failed;
    }
    if (!_isCurrentRequest(requestGeneration)) return;
    final current = state;
    if (current is PlannedCostAccepted &&
        identical(current.plannedCost, plannedCost)) {
      state = PlannedCostAccepted(
        plannedCost: plannedCost,
        homeStatus: homeStatus,
      );
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

/// Accepts the comma decimal separator Russian keyboards produce.
String _normalizedAmount(String value) => value.trim().replaceAll(',', '.');

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

DateTime? _parsedDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : _dateOnly(parsed);
}

FinanceEntryFailure _invalidInputFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.invalidInput,
  requestId: 'req_local_planned_cost_input',
);

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_planned_cost_unknown',
);

PlannedCostHomeStatus _homeStatus(AcceptedWriteHomeConvergenceResult result) =>
    switch (result) {
      AcceptedWriteHomeConvergenceResult.updated =>
        PlannedCostHomeStatus.updated,
      AcceptedWriteHomeConvergenceResult.projectionDelayed =>
        PlannedCostHomeStatus.projectionDelayed,
      AcceptedWriteHomeConvergenceResult.authenticationRequired =>
        PlannedCostHomeStatus.authenticationRequired,
      AcceptedWriteHomeConvergenceResult.sessionChanged =>
        PlannedCostHomeStatus.authenticationRequired,
      AcceptedWriteHomeConvergenceResult.failed => PlannedCostHomeStatus.failed,
    };
