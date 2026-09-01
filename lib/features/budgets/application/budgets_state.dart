import 'package:flutter/foundation.dart';

import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';

/// States of the screen that declares monthly ceilings (ADR 0027).
sealed class BudgetsState {
  const BudgetsState();
}

final class BudgetsLoading extends BudgetsState {
  const BudgetsLoading();
}

/// A ceiling belongs to an account, so there is nothing to declare without one.
final class BudgetsAccountRequired extends BudgetsState {
  const BudgetsAccountRequired();
}

final class BudgetsAuthenticationRequired extends BudgetsState {
  const BudgetsAuthenticationRequired();
}

@immutable
final class BudgetsFailure extends BudgetsState {
  const BudgetsFailure(this.failure);

  final FinanceEntryFailure failure;
}

@immutable
final class BudgetsReady extends BudgetsState {
  BudgetsReady({
    required this.account,
    required this.snapshot,
    required List<FinanceCategory> categories,
    this.isSubmitting = false,
    this.failure,
    this.busyBudgetId,
    List<PlannedCostIssue> issues = const [],
  }) : categories = List<FinanceCategory>.unmodifiable(categories),
       issues = List<PlannedCostIssue>.unmodifiable(issues);

  final FinanceAccount account;
  final BudgetsSnapshot snapshot;

  /// Expense categories only: budgeting income is not a thing anyone means.
  final List<FinanceCategory> categories;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<PlannedCostIssue> issues;

  /// The ceiling a removal is in flight for, so only that row shows progress.
  final String? busyBudgetId;

  /// Categories that have no ceiling yet, which is what a new one can name.
  List<FinanceCategory> get categoriesWithoutBudget {
    final taken = {for (final budget in snapshot.categories) budget.categoryId};
    return categories
        .where((category) => !taken.contains(category.categoryId))
        .toList(growable: false);
  }

  bool get hasOverallBudget => snapshot.overall != null;

  BudgetsReady copyWith({
    BudgetsSnapshot? snapshot,
    List<FinanceCategory>? categories,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    List<PlannedCostIssue>? issues,
    String? busyBudgetId,
    bool clearFailure = false,
    bool clearBusy = false,
  }) {
    return BudgetsReady(
      account: account,
      snapshot: snapshot ?? this.snapshot,
      categories: categories ?? this.categories,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      issues: issues ?? this.issues,
      busyBudgetId: clearBusy ? null : (busyBudgetId ?? this.busyBudgetId),
    );
  }
}
