import 'package:flutter/foundation.dart';

import 'finance_entry_models.dart';

enum FinanceEntryFailureKind {
  invalidInput,
  unauthenticated,
  sessionChanged,
  interrupted,
  unauthorized,
  conflict,
  rejected,
  offline,
  timeout,
  serviceUnavailable,
  securityFailure,
  localStorage,
  malformedResponse,
  unknown,
}

enum FinanceEntryErrorCode {
  malformedAccount,
  malformedOperation,
  confirmationMismatch,
  commandConflict,
  accountAlreadyInitialized,
  accountRejected,
  accountUnavailable,
  baselineRejected,
  operationRejected,
  malformedPlannedCost,
  plannedCostRejected,
  plannedCostNotFound,
  plannedCostPersistenceUnavailable,
  // A repeating plan is its own contract (ADR 0025): the rule is refused or
  // missing, not the instance it would have generated.
  malformedRecurrence,
  recurrenceRejected,
  recurrenceNotFound,
  recurrencePersistenceUnavailable,
  // Redrawing where an account's months fall (ADR 0028).
  timezoneRejected,
  malformedGoalCommand,
  goalRejected,
  goalNotFound,
  goalPersistenceUnavailable,
  malformedCategoryCommand,
  categoryNotFound,
  categoryNameTaken,
  categoryArchived,
  categoryKeywordTaken,
  categoryPersistenceUnavailable,
  // Correcting or removing a confirmed operation (ADR 0023). "Not found"
  // also covers another user's operation, so the API never confirms one
  // exists outside the caller's own ledger.
  operationNotFound,
  operationAlreadyReversed,
  analyticsUnavailable,
  malformedAnalyticsQuery,
  profileUnavailable,
  textEntryUnavailable,
  // Asking about an installable update (ADR 0026).
  appReleaseUnavailable,
  appReleaseNotFound,
  // Monthly ceilings (ADR 0027).
  malformedBudget,
  budgetRejected,
  budgetNotFound,
  budgetPersistenceUnavailable,
  authenticationUnavailable,
  financePersistenceUnavailable,
}

@immutable
final class FinanceEntryFailure {
  FinanceEntryFailure({
    required this.kind,
    required this.requestId,
    this.code,
    List<FinanceIssue> issues = const [],
    List<FinanceBaselineIssue> baselineIssues = const [],
    List<PlannedCostIssue> plannedCostIssues = const [],
    List<SavingsGoalIssue> goalIssues = const [],
    List<FinanceTimezoneIssue> timezoneIssues = const [],
  }) : issues = List.unmodifiable(issues),
       baselineIssues = List.unmodifiable(baselineIssues),
       plannedCostIssues = List.unmodifiable(plannedCostIssues),
       goalIssues = List.unmodifiable(goalIssues),
       timezoneIssues = List.unmodifiable(timezoneIssues);

  final FinanceEntryFailureKind kind;
  final String requestId;
  final FinanceEntryErrorCode? code;
  final List<FinanceIssue> issues;
  final List<FinanceBaselineIssue> baselineIssues;
  final List<PlannedCostIssue> plannedCostIssues;
  final List<SavingsGoalIssue> goalIssues;
  final List<FinanceTimezoneIssue> timezoneIssues;
}

sealed class FinanceEntryResult<T> {
  const FinanceEntryResult({required this.requestId});

  final String requestId;
}

@immutable
final class FinanceEntrySuccess<T> extends FinanceEntryResult<T> {
  const FinanceEntrySuccess({required super.requestId, required this.value});

  final T value;
}

@immutable
final class FinanceEntryFailureResult<T> extends FinanceEntryResult<T> {
  FinanceEntryFailureResult(this.failure) : super(requestId: failure.requestId);

  final FinanceEntryFailure failure;
}
