import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/entered_amount.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/data/finance_entry_repository.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';
import 'budgets_state.dart';

export 'budgets_state.dart';

final budgetsControllerProvider =
    NotifierProvider.autoDispose<BudgetsController, BudgetsState>(
      BudgetsController.new,
    );

/// Declares monthly ceilings and reports how the month stands (ADR 0027).
///
/// Nothing here computes a total. The limit is the only thing this screen
/// sends; spent, remaining and overspent arrive already derived, so it cannot
/// disagree with Analytics about the same month.
class BudgetsController extends Notifier<BudgetsState> {
  bool _busy = false;
  int _generation = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  DateTime get _now => ref.read(financeEntryClockProvider)();

  String get _newCommandId => ref.read(financeCommandIdFactoryProvider)();

  @override
  BudgetsState build() {
    ref.watch(authAccountEpochProvider);
    _generation += 1;
    _busy = false;
    return const BudgetsLoading();
  }

  Future<void> load() => _load(showLoading: true);

  /// Re-reads without blanking the screen, so a pull keeps what is readable.
  Future<void> refresh() => _load(showLoading: false);

  Future<void> _load({required bool showLoading}) async {
    if (_busy) return;
    _busy = true;
    final generation = _beginRequest();
    if (showLoading) state = const BudgetsLoading();
    try {
      final accounts = await _repository.listAccounts();
      if (!_isCurrent(generation)) return;
      switch (accounts) {
        case FinanceEntrySuccess(:final value):
          if (!value.isInitialized) {
            state = const BudgetsAccountRequired();
            return;
          }
          final snapshot = await _repository.readBudgets();
          if (!_isCurrent(generation)) return;
          switch (snapshot) {
            case FinanceEntrySuccess(value: final budgets):
              state = BudgetsReady(
                account: value.account!,
                snapshot: budgets,
                categories: await _expenseCategories(),
              );
            case FinanceEntryFailureResult(:final failure):
              _reportLoadFailure(failure);
          }
        case FinanceEntryFailureResult(:final failure):
          _reportLoadFailure(failure);
      }
    } on Object {
      if (_isCurrent(generation)) {
        state = BudgetsFailure(_unexpected());
      }
    } finally {
      _busy = false;
    }
  }

  /// Declares or changes one ceiling. A null category is the overall one.
  Future<void> setBudget({
    required String? categoryId,
    required String limit,
  }) async {
    final current = state;
    if (_busy || current is! BudgetsReady) return;

    late final SetBudgetCommand command;
    try {
      command = SetBudgetCommand(
        commandId: _newCommandId,
        accountId: current.account.accountId,
        categoryId: categoryId,
        limit: _normalizedLimit(limit),
        currency: current.account.currency,
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validateSetBudget(command);
    } on Object {
      state = current.copyWith(failure: _invalidInput());
      return;
    }

    await _write(
      current,
      () => _repository.setBudget(command),
      markSubmitting: true,
    );
  }

  Future<void> removeBudget(String budgetId) async {
    final current = state;
    if (_busy || current is! BudgetsReady) return;

    late final RemoveBudgetCommand command;
    try {
      command = RemoveBudgetCommand(
        commandId: _newCommandId,
        requestedAt: plannedCostWireTimestamp(_now),
      );
      validateRemoveBudget(command);
      validateBudgetId(budgetId);
    } on Object {
      state = current.copyWith(failure: _invalidInput());
      return;
    }

    await _write(
      current,
      () => _repository.removeBudget(budgetId, command),
      busyBudgetId: budgetId,
    );
  }

  Future<void> _write(
    BudgetsReady current,
    Future<FinanceEntryResult<BudgetWritten>> Function() send, {
    bool markSubmitting = false,
    String? busyBudgetId,
  }) async {
    _busy = true;
    final generation = _beginRequest();
    state = current.copyWith(
      isSubmitting: markSubmitting,
      busyBudgetId: busyBudgetId,
      clearFailure: true,
      issues: const [],
    );
    try {
      final result = await send();
      if (!_isCurrent(generation)) return;
      switch (result) {
        case FinanceEntrySuccess():
          // Re-read rather than patch: spent and remaining are the server's
          // arithmetic, and guessing at them here is how two screens start
          // disagreeing.
          final snapshot = await _repository.readBudgets();
          if (!_isCurrent(generation)) return;
          final latest = state;
          if (latest is! BudgetsReady) return;
          if (snapshot case FinanceEntrySuccess(:final value)) {
            state = latest.copyWith(
              snapshot: value,
              isSubmitting: false,
              clearBusy: true,
            );
          } else {
            state = latest.copyWith(isSubmitting: false, clearBusy: true);
          }
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const BudgetsAuthenticationRequired();
            return;
          }
          final latest = state;
          if (latest is! BudgetsReady) return;
          state = latest.copyWith(
            isSubmitting: false,
            failure: failure,
            issues: failure.plannedCostIssues,
            clearBusy: true,
          );
      }
    } on Object {
      final latest = state;
      if (_isCurrent(generation) && latest is BudgetsReady) {
        state = latest.copyWith(
          isSubmitting: false,
          failure: _unexpected(),
          clearBusy: true,
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<List<FinanceCategory>> _expenseCategories() async {
    try {
      final result = await _repository.listCategories();
      if (result case FinanceEntrySuccess(:final value)) {
        return value.categories
            .where(
              (category) => category.direction == FinanceOperationType.expense,
            )
            .toList(growable: false);
      }
    } on Object {
      return const [];
    }
    // Secondary: without the catalogue a ceiling cannot be added, but the ones
    // already declared still read correctly.
    return const [];
  }

  void _reportLoadFailure(FinanceEntryFailure failure) {
    state = _requiresAuthentication(failure)
        ? const BudgetsAuthenticationRequired()
        : BudgetsFailure(failure);
  }

  int _beginRequest() {
    _generation += 1;
    return _generation;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  static String _normalizedLimit(String value) {
    final trimmed = enteredAmountText(value);
    if (trimmed.isEmpty) throw const FormatException('Empty limit.');
    return trimmed;
  }

  FinanceEntryFailure _invalidInput() => FinanceEntryFailure(
    kind: FinanceEntryFailureKind.invalidInput,
    requestId: 'local',
  );

  FinanceEntryFailure _unexpected() => FinanceEntryFailure(
    kind: FinanceEntryFailureKind.unknown,
    requestId: 'local',
  );
}

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;
