import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../auth/application/auth_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/finance_command_id.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';
import 'operation_sync_controller.dart';
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

  /// Every wallet the profile holds (ADR 0029), kept off the form state so a
  /// refusal or a written plan cannot take the choice away.
  List<FinanceAccount> _wallets = const [];

  Future<void> load() => _load();

  /// Plans the next cost against another wallet.
  ///
  /// The wallet denominates the plan and carries its own opening baseline, so
  /// the date bounds are recomputed and the chosen date is clamped into them.
  /// What is typed is kept: switching wallets is choosing where the bill will
  /// be paid from, not starting again.
  void selectAccount(FinanceAccount account) {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    if (!_wallets.any((wallet) => wallet.accountId == account.accountId)) {
      return;
    }
    final rebuilt = _editingState(account);
    final selected = current.selectedDate.isBefore(rebuilt.earliestDate)
        ? rebuilt.earliestDate
        : current.selectedDate;
    state = PlannedCostEditing(
      account: account,
      wallets: _wallets,
      selectedDate: selected,
      earliestDate: rebuilt.earliestDate,
      latestDate: rebuilt.latestDate,
      title: current.title,
      amount: current.amount,
      repeats: current.repeats,
      lastDayOfMonth: current.lastDayOfMonth,
      plans: current.plans,
      recurrences: current.recurrences,
    );
  }

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

  /// Turns the form from a single payment into a repeating one (ADR 0025).
  void setRepeats(bool value) {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    _commandId = null;
    state = current.copyWith(
      repeats: value,
      clearFailure: true,
      issues: const [],
    );
  }

  /// Anchors the series to the end of every month.
  ///
  /// Under clamping this is the same schedule as «the 31st», which is why it
  /// stores 31 rather than introducing a second concept.
  void setLastDayOfMonth(bool value) {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    _commandId = null;
    state = current.copyWith(
      lastDayOfMonth: value,
      clearFailure: true,
      issues: const [],
    );
  }

  Future<void> submit() async {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    if (current.repeats) return _submitRecurrence(current);

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

  Future<void> _submitRecurrence(PlannedCostEditing current) async {
    late final PlannedCostRecurrenceDraft draft;
    try {
      if (current.selectedDate.isBefore(current.earliestDate) ||
          current.selectedDate.isAfter(current.latestDate)) {
        throw const FormatException('Start date is outside local bounds.');
      }
      final commandId = _commandId ??= _newCommandId;
      draft = PlannedCostRecurrenceDraft(
        commandId: commandId,
        accountId: current.account.accountId,
        amount: _normalizedAmount(current.amount),
        currency: current.account.currency,
        title: current.title.trim(),
        dayOfMonth: current.dayOfMonth,
        startsOn: plannedCostWireDate(current.selectedDate),
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validatePlannedCostRecurrenceDraft(draft);
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
      final result = await _repository.createPlannedCostRecurrence(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          _commandId = null;
          state = PlannedCostRecurrenceAccepted(
            recurrence: value.recurrence,
            occurrences: value.occurrences,
            homeStatus: PlannedCostHomeStatus.pending,
          );
          unawaited(_convergeHomeAfterAcceptedRecurrence(requestGeneration));
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

  /// Skips one instance of a series.
  ///
  /// Different from cancelling: the rule keeps generating, and this month
  /// simply will not happen. Offered only on an instance a rule produced,
  /// because on a one-off plan it would mean exactly what cancel means.
  Future<void> skipPlan(String plannedCostId) =>
      _settlePlan(plannedCostId, PlannedCostTransition.skip);

  /// Cancels one outstanding plan.
  Future<void> cancelPlan(String plannedCostId) =>
      _settlePlan(plannedCostId, PlannedCostTransition.cancel);

  /// Ends a series: no further instances, and the untouched future ones are
  /// withdrawn with it. Instances already due survive to be settled or skipped.
  Future<void> endRecurrence(String recurrenceId) async {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    if (current.endingRecurrenceId != null) return;

    late final EndPlannedCostRecurrenceCommand command;
    try {
      command = EndPlannedCostRecurrenceCommand(
        commandId: _newCommandId,
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validateEndPlannedCostRecurrence(command);
      validateRecurrenceId(recurrenceId);
    } on Object {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    final requestGeneration = _beginRequest();
    state = current.copyWith(
      endingRecurrenceId: recurrenceId,
      clearFailure: true,
      issues: const [],
    );
    try {
      final result = await _repository.endPlannedCostRecurrence(
        recurrenceId,
        command,
      );
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess():
          final latest = state;
          if (latest is! PlannedCostEditing) return;
          final withdrawn = <String>{
            for (final item in latest.recurrences)
              if (item.recurrence.recurrenceId == recurrenceId)
                for (final instance in item.upcoming) instance.plannedCostId,
          };
          state = latest.copyWith(
            recurrences: latest.recurrences
                .where((item) => item.recurrence.recurrenceId != recurrenceId)
                .toList(growable: false),
            clearEndingRecurrenceId: true,
          );
          // Re-read rather than guess which instances survived: an instance
          // already due is left outstanding on purpose, and only the server
          // knows which side of today each one fell on.
          await _loadPlans(requestGeneration, keepOnFailure: withdrawn);
          unawaited(_convergeHomeAfterSettledPlan());
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const PlannedCostAuthenticationRequired();
            return;
          }
          final latest = state;
          if (latest is! PlannedCostEditing) return;
          state = latest.copyWith(
            failure: failure,
            issues: failure.plannedCostIssues,
            clearEndingRecurrenceId: true,
          );
      }
    } on Object {
      final latest = state;
      if (_isCurrentRequest(requestGeneration) &&
          latest is PlannedCostEditing) {
        state = latest.copyWith(
          failure: _unexpectedFailure(),
          clearEndingRecurrenceId: true,
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> _convergeHomeAfterAcceptedRecurrence(
    int requestGeneration,
  ) async {
    final status = await _homeStatusAfterWrite();
    if (!_isCurrentRequest(requestGeneration)) return;
    final current = state;
    if (current is! PlannedCostRecurrenceAccepted) return;
    state = PlannedCostRecurrenceAccepted(
      recurrence: current.recurrence,
      occurrences: current.occurrences,
      homeStatus: status,
    );
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
          _wallets = value.accounts;
          state = _editingState(value.account!);
          await _loadPlans(requestGeneration);
          await _loadRecurrences(requestGeneration);
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

  /// Moves one outstanding plan to a terminal status.
  ///
  /// Cancel means the plan itself was wrong; skip means this one instance will
  /// not happen and the rule continues. Until recurrence existed the two were
  /// indistinguishable, which is why skip is only offered on an instance a rule
  /// produced (ADR 0018, 0025).
  Future<void> _settlePlan(
    String plannedCostId,
    PlannedCostTransition transition,
  ) async {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    if (current.settlingId != null) return;

    late final PlannedCostTransitionCommand command;
    try {
      command = PlannedCostTransitionCommand(
        commandId: _newCommandId,
        transition: transition,
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
          // A settled plan stops being an obligation, so it leaves the
          // list — and the rule that owns it stops offering to skip it.
          state = latest.copyWith(
            plans: latest.plans
                .where((plan) => plan.plannedCostId != plannedCostId)
                .toList(growable: false),
            recurrences: _withoutInstance(latest.recurrences, plannedCostId),
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

  /// Confirms one plan by recording the real operation it stood for.
  ///
  /// Order is asymmetric on purpose (ADR 0018): the operation is committed
  /// first through the normal path and its encrypted delivery outbox, and only
  /// an accepted operation transitions the plan. A lost transition therefore
  /// leaves a visible outstanding plan; the reverse order could mark a plan
  /// paid with no operation behind it and quietly lose the payment.
  Future<void> confirmPlan(PlannedCost plan, {DateTime? occurredOn}) async {
    final current = state;
    if (_requestInFlight || current is! PlannedCostEditing) return;
    if (current.settlingId != null) return;

    final plannedOn = _parsedDate(plan.plannedOn);
    if (plannedOn == null) {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }
    final today = _dateOnly(_now.toUtc());
    // A future-dated plan cannot be recorded on its planned day: an operation
    // may never be in the future. Default to the planned day when it has
    // already arrived, otherwise to today.
    final effectiveDate = occurredOn == null
        ? (plannedOn.isAfter(today) ? today : plannedOn)
        : _dateOnly(occurredOn);
    if (effectiveDate.isAfter(today) ||
        effectiveDate.isBefore(current.earliestDate)) {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    final requestGeneration = _beginRequest();
    state = current.copyWith(
      settlingId: plan.plannedCostId,
      clearFailure: true,
      issues: const [],
    );
    try {
      final timeContext = await ref
          .read(financeCaptureContextSourceProvider)
          .capture(canonicalTimezone: ref.read(canonicalTimezoneProvider));
      if (!_isCurrentRequest(requestGeneration)) return;
      final operationCommandId = plannedCostOperationCommandId(
        plan.plannedCostId,
      );
      final draft = FinanceOperationDraft(
        commandId: operationCommandId,
        type: FinanceOperationType.expense,
        amount: plan.amount,
        currency: plan.currency,
        accountId: plan.accountId,
        category: plan.category,
        merchant: null,
        capturedAt: timeContext.capturedAtUtc.toIso8601String(),
        capturedTimezone: timeContext.capturedTimezone,
        sourceExpression: null,
        occurredOn: plannedCostWireDate(effectiveDate),
        occurredAt: null,
        source: FinanceOperationSource.manualText,
      );
      validateOperationDraft(draft);

      final evaluation = await _repository.evaluateOperation(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      final review = switch (evaluation) {
        FinanceEntrySuccess(:final value)
            when value is FinanceOperationNeedsConfirmation =>
          value,
        _ => null,
      };
      if (review == null) {
        _failSettling(evaluation);
        return;
      }

      final delivery = await ref
          .read(operationDeliveryCoordinatorProvider)
          .enqueueAndSynchronize(
            expectedPrincipalScopeId: current.account.userId,
            command: FinanceOperationCommitCommand.fromReview(
              review: review,
              confirmedAt: _now,
            ),
            onAccepted: (_) {},
          );
      if (!_isCurrentRequest(requestGeneration)) return;

      switch (delivery) {
        case OperationDeliveryAccepted():
        case OperationDeliveryAlreadySynced():
          // The money is recorded; only now may the plan stop being an
          // obligation.
          await _transitionConfirmed(
            plan: plan,
            operationCommandId: operationCommandId,
            requestGeneration: requestGeneration,
          );
        case OperationDeliveryAuthenticationRequired():
          state = const PlannedCostAuthenticationRequired();
        case OperationDeliveryQueued():
        case OperationDeliveryPermanentFailure():
        case OperationDeliveryStorageFailure():
          // The operation did not reach the server, so the plan stays
          // outstanding and the user can retry; the derived command id makes
          // that retry a replay rather than a second operation.
          final latest = state;
          if (latest is PlannedCostEditing) {
            state = latest.copyWith(
              failure: _confirmDeliveryFailure(),
              clearSettlingId: true,
            );
          }
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

  Future<void> _transitionConfirmed({
    required PlannedCost plan,
    required String operationCommandId,
    required int requestGeneration,
  }) async {
    final command = PlannedCostTransitionCommand(
      commandId: _newCommandId,
      transition: PlannedCostTransition.confirm,
      operationCommandId: operationCommandId,
      requestedAt: plannedCostWireTimestamp(_now),
    );
    final result = await _repository.transitionPlannedCost(
      plan.plannedCostId,
      command,
    );
    if (!_isCurrentRequest(requestGeneration)) return;
    final latest = state;
    if (latest is! PlannedCostEditing) return;
    switch (result) {
      case FinanceEntrySuccess():
        state = latest.copyWith(
          plans: latest.plans
              .where((item) => item.plannedCostId != plan.plannedCostId)
              .toList(growable: false),
          clearSettlingId: true,
        );
        unawaited(_convergeHomeAfterSettledPlan());
      case FinanceEntryFailureResult(:final failure):
        // The operation is already recorded, so this is not a lost payment:
        // the plan simply still shows as outstanding until a retry succeeds.
        state = latest.copyWith(
          failure: failure,
          issues: failure.plannedCostIssues,
          clearSettlingId: true,
        );
    }
  }

  void _failSettling(FinanceEntryResult<FinanceOperationEvaluation> result) {
    if (result is FinanceEntryFailureResult<FinanceOperationEvaluation> &&
        _requiresAuthentication(result.failure)) {
      state = const PlannedCostAuthenticationRequired();
      return;
    }
    final latest = state;
    if (latest is! PlannedCostEditing) return;
    state = latest.copyWith(
      failure: result is FinanceEntryFailureResult<FinanceOperationEvaluation>
          ? result.failure
          : _confirmDeliveryFailure(),
      clearSettlingId: true,
    );
  }

  Future<void> _loadPlans(
    int requestGeneration, {
    Set<String> keepOnFailure = const <String>{},
  }) async {
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
          // What it must not do either is leave instances on screen that the
          // server has just withdrawn, so those are dropped locally.
          if (keepOnFailure.isEmpty) return;
          state = current.copyWith(
            plans: current.plans
                .where((plan) => !keepOnFailure.contains(plan.plannedCostId))
                .toList(growable: false),
          );
      }
    } on Object {
      return;
    }
  }

  /// Reads the user's rules with the instances each one owns.
  ///
  /// Secondary like the plan list: failing to read the rules must not stop
  /// someone recording a plan, it only means no series is marked as such.
  Future<void> _loadRecurrences(int requestGeneration) async {
    try {
      final result = await _repository.listPlannedCostRecurrences();
      if (!_isCurrentRequest(requestGeneration)) return;
      final current = state;
      if (current is! PlannedCostEditing) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = current.copyWith(
            recurrences: value.recurrences
                .where(
                  (item) =>
                      item.recurrence.status ==
                      PlannedCostRecurrenceStatus.active,
                )
                .toList(growable: false),
          );
        case FinanceEntryFailureResult():
          return;
      }
    } on Object {
      return;
    }
  }

  static List<PlannedCostRecurrenceListItem> _withoutInstance(
    List<PlannedCostRecurrenceListItem> recurrences,
    String plannedCostId,
  ) {
    return recurrences
        .map(
          (item) => PlannedCostRecurrenceListItem(
            recurrence: item.recurrence,
            upcoming: item.upcoming
                .where((instance) => instance.plannedCostId != plannedCostId)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
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
      wallets: _wallets.isEmpty ? [account] : _wallets,
      selectedDate: selected,
      earliestDate: earliest,
      latestDate: latest,
    );
  }

  Future<PlannedCostHomeStatus> _homeStatusAfterWrite() async {
    try {
      return _homeStatus(
        await ref
            .read(homeControllerProvider.notifier)
            .convergeAfterAcceptedWrite(),
      );
    } on Object {
      return PlannedCostHomeStatus.failed;
    }
  }

  Future<void> _convergeHomeAfterAcceptedPlan(
    PlannedCost plannedCost,
    int requestGeneration,
  ) async {
    final homeStatus = await _homeStatusAfterWrite();
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

FinanceEntryFailure _confirmDeliveryFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.serviceUnavailable,
  requestId: 'req_local_planned_cost_confirm',
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
