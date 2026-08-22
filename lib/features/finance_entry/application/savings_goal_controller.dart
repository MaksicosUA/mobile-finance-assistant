import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';
import 'savings_goal_state.dart';

export 'savings_goal_state.dart';

final savingsGoalControllerProvider =
    NotifierProvider.autoDispose<SavingsGoalController, SavingsGoalScreenState>(
      SavingsGoalController.new,
    );

/// Records savings goals and the contributions that fill them.
///
/// A contribution earmarks balance that is already in the account (ADR 0019),
/// so this controller has no review step and no delivery outbox: a lost
/// request simply means nothing was recorded, which the user can see and
/// repeat. The server returns the goal with the entry already applied, so the
/// derived total is never recomputed here.
class SavingsGoalController extends Notifier<SavingsGoalScreenState> {
  /// Reused across retries so a repeated submit is an idempotent replay rather
  /// than a second goal.
  String? _createCommandId;

  /// Per goal, for the same reason: retrying a deposit must not deposit twice.
  final Map<String, String> _contributionCommandIds = <String, String>{};
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  DateTime get _now => ref.read(financeEntryClockProvider)();

  String get _newCommandId => ref.read(financeCommandIdFactoryProvider)();

  @override
  SavingsGoalScreenState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    _createCommandId = null;
    _contributionCommandIds.clear();
    return const SavingsGoalLoading();
  }

  Future<void> load() => _load();

  /// Re-reads the goals without resetting the screen.
  ///
  /// A full load rebuilds the ready state from scratch, which would discard a
  /// goal the user is halfway through describing. A pull asks for the list, so
  /// only the list is re-read. Returns `false` when the screen still shows the
  /// older reading.
  Future<bool> refresh() async {
    final current = state;
    if (current is! SavingsGoalReady) {
      await _load();
      return state is SavingsGoalReady;
    }
    if (_requestInFlight) return true;
    final requestGeneration = _beginRequest();
    try {
      return await _loadGoals(requestGeneration);
    } finally {
      _endRequest(requestGeneration);
    }
  }

  void startCreating() {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    state = current.copyWith(
      isCreating: true,
      clearFailure: true,
      issues: const [],
    );
  }

  void cancelCreating() {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    _createCommandId = null;
    state = current.copyWith(
      isCreating: false,
      title: '',
      targetAmount: '',
      monthlyContribution: '',
      clearFailure: true,
      issues: const [],
    );
  }

  void setTitle(String value) =>
      _editDraft((current) => current.copyWith(title: value));

  void setTargetAmount(String value) =>
      _editDraft((current) => current.copyWith(targetAmount: value));

  void setMonthlyContribution(String value) =>
      _editDraft((current) => current.copyWith(monthlyContribution: value));

  void setContributionAmount(String value) {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    state = current.copyWith(
      contributionAmount: value,
      clearFailure: true,
      issues: const [],
    );
  }

  void selectTargetDate(DateTime value) {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    final selected = _dateOnly(value);
    if (selected.isBefore(current.earliestDate) ||
        selected.isAfter(current.latestDate)) {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }
    _createCommandId = null;
    state = current.copyWith(
      selectedDate: selected,
      clearFailure: true,
      issues: const [],
    );
  }

  Future<void> submit() async {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;

    late final SavingsGoalDraft draft;
    try {
      if (current.selectedDate.isBefore(current.earliestDate) ||
          current.selectedDate.isAfter(current.latestDate)) {
        throw const FormatException('Target date is outside local bounds.');
      }
      final monthly = _normalizedAmount(current.monthlyContribution);
      final commandId = _createCommandId ??= _newCommandId;
      draft = SavingsGoalDraft(
        commandId: commandId,
        accountId: current.account.accountId,
        title: current.title.trim(),
        targetAmount: _normalizedAmount(current.targetAmount),
        currency: current.account.currency,
        targetOn: plannedCostWireDate(current.selectedDate),
        // Blank means "no declared monthly plan", sent as an omitted field so
        // absence has exactly one representation on the wire.
        monthlyContribution: monthly.isEmpty ? null : monthly,
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validateSavingsGoalDraft(draft);
    } on Object {
      _createCommandId = null;
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
      final result = await _repository.createGoal(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          _createCommandId = null;
          final latest = state;
          if (latest is! SavingsGoalReady) return;
          state = latest.copyWith(
            isSubmitting: false,
            isCreating: false,
            title: '',
            targetAmount: '',
            monthlyContribution: '',
            goals: _withGoal(latest.goals, value.goal),
            clearFailure: true,
            issues: const [],
          );
          unawaited(_convergeHome());
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const SavingsGoalAuthenticationRequired();
            return;
          }
          state = current.copyWith(
            isSubmitting: false,
            failure: failure,
            issues: failure.goalIssues,
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

  /// Appends one ledger entry to a goal.
  ///
  /// The command id is kept per goal until the entry is accepted, so a retry
  /// after a lost response replays the same entry instead of recording a
  /// second one. Sending different content under it is a visible conflict,
  /// which is the safer of the two failures.
  Future<void> recordContribution(
    SavingsGoal goal,
    GoalContributionDirection direction,
  ) async {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    if (current.busyGoalId != null) return;

    late final GoalContributionCommand command;
    try {
      final commandId = _contributionCommandIds[goal.goalId] ??= _newCommandId;
      command = GoalContributionCommand(
        commandId: commandId,
        direction: direction,
        amount: _normalizedAmount(current.contributionAmount),
        // Omitted on purpose: only the server knows today's date in the
        // account's canonical timezone (ADR 0007).
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validateGoalContributionCommand(command);
      validateGoalId(goal.goalId);
    } on Object {
      _contributionCommandIds.remove(goal.goalId);
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    final requestGeneration = _beginRequest();
    state = current.copyWith(
      busyGoalId: goal.goalId,
      clearFailure: true,
      issues: const [],
    );
    try {
      final result = await _repository.recordGoalContribution(
        goal.goalId,
        command,
      );
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          _contributionCommandIds.remove(goal.goalId);
          final latest = state;
          if (latest is! SavingsGoalReady) return;
          state = latest.copyWith(
            // The server already applied the entry, so the card shows an
            // authoritative total rather than a locally recomputed one.
            goals: _withGoal(latest.goals, value.goal),
            contributionAmount: '',
            clearBusyGoalId: true,
            clearFailure: true,
          );
          unawaited(_convergeHome());
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const SavingsGoalAuthenticationRequired();
            return;
          }
          final latest = state;
          if (latest is! SavingsGoalReady) return;
          state = latest.copyWith(
            failure: failure,
            issues: failure.goalIssues,
            clearBusyGoalId: true,
          );
      }
    } on Object {
      final latest = state;
      if (_isCurrentRequest(requestGeneration) && latest is SavingsGoalReady) {
        state = latest.copyWith(
          failure: _unexpectedFailure(),
          clearBusyGoalId: true,
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  /// Stops pursuing a goal without erasing what was set aside for it.
  Future<void> cancelGoal(String goalId) async {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    if (current.busyGoalId != null) return;

    late final FinanceGoalCancelCommand command;
    try {
      command = FinanceGoalCancelCommand(
        commandId: _newCommandId,
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validateGoalId(goalId);
    } on Object {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    final requestGeneration = _beginRequest();
    state = current.copyWith(
      busyGoalId: goalId,
      clearFailure: true,
      issues: const [],
    );
    try {
      final result = await _repository.cancelGoal(goalId, command);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess():
          _contributionCommandIds.remove(goalId);
          final latest = state;
          if (latest is! SavingsGoalReady) return;
          // A cancelled goal is no longer pursued, so it leaves the list. Its
          // ledger stays on the server as the record of what happened.
          state = latest.copyWith(
            goals: latest.goals
                .where((goal) => goal.goalId != goalId)
                .toList(growable: false),
            clearBusyGoalId: true,
          );
          unawaited(_convergeHome());
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const SavingsGoalAuthenticationRequired();
            return;
          }
          final latest = state;
          if (latest is! SavingsGoalReady) return;
          state = latest.copyWith(
            failure: failure,
            issues: failure.goalIssues,
            clearBusyGoalId: true,
          );
      }
    } on Object {
      final latest = state;
      if (_isCurrentRequest(requestGeneration) && latest is SavingsGoalReady) {
        state = latest.copyWith(
          failure: _unexpectedFailure(),
          clearBusyGoalId: true,
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  void _editDraft(SavingsGoalReady Function(SavingsGoalReady) edit) {
    final current = state;
    if (_requestInFlight || current is! SavingsGoalReady) return;
    _createCommandId = null;
    state = edit(current).copyWith(clearFailure: true, issues: const []);
  }

  Future<void> _load() async {
    if (_requestInFlight) return;
    final requestGeneration = _beginRequest();
    _createCommandId = null;
    state = const SavingsGoalLoading();
    try {
      final result = await _repository.listAccounts();
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          if (!value.isInitialized) {
            state = const SavingsGoalUnavailable(
              SavingsGoalUnavailableReason.accountRequired,
            );
            return;
          }
          state = _readyState(value.account!);
          await _loadGoals(requestGeneration);
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const SavingsGoalAuthenticationRequired();
          } else {
            state = SavingsGoalFailure(failure);
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = SavingsGoalFailure(_unexpectedFailure());
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<bool> _loadGoals(int requestGeneration) async {
    try {
      final result = await _repository.listGoals();
      if (!_isCurrentRequest(requestGeneration)) return false;
      final current = state;
      if (current is! SavingsGoalReady) return false;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = current.copyWith(
            goals: value.goals
                .where((goal) => goal.isActive)
                .toList(growable: false),
          );
          return true;
        case FinanceEntryFailureResult():
          // The list is secondary: failing to read it must not block creating
          // a goal.
          return false;
      }
    } on Object {
      return false;
    }
  }

  Future<void> _convergeHome() async {
    try {
      await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite();
    } on Object {
      // Best-effort: the goal is already stored server-side, and Home refreshes
      // on its own schedule.
      return;
    }
  }

  SavingsGoalReady _readyState(FinanceAccount account) {
    final today = _dateOnly(_now.toUtc());
    final baseline = _parsedDate(account.openingBalanceOn) ?? today;
    final latest = DateTime.utc(today.year + 10, today.month, today.day);
    // A goal deadline is normally in the future; default a year out so the
    // common case needs no picking.
    final defaultTarget = DateTime.utc(today.year + 1, today.month, today.day);
    final selected = defaultTarget.isBefore(baseline)
        ? baseline
        : defaultTarget;
    return SavingsGoalReady(
      account: account,
      selectedDate: selected,
      earliestDate: baseline,
      latestDate: latest,
    );
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

/// Replaces a goal in place, or appends it, keeping the nearest deadline first
/// so the list matches the order Home derives its primary goal from.
List<SavingsGoal> _withGoal(List<SavingsGoal> goals, SavingsGoal updated) {
  final merged =
      <SavingsGoal>[
        for (final goal in goals)
          if (goal.goalId != updated.goalId) goal,
        if (updated.isActive) updated,
      ]..sort((left, right) {
        final byDate = left.targetOn.compareTo(right.targetOn);
        return byDate != 0 ? byDate : left.goalId.compareTo(right.goalId);
      });
  return List<SavingsGoal>.unmodifiable(merged);
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
  requestId: 'req_local_savings_goal_input',
);

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_savings_goal_unknown',
);
