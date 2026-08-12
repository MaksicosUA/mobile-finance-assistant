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
  malformedGoalCommand,
  goalRejected,
  goalNotFound,
  goalPersistenceUnavailable,
  malformedCategoryCommand,
  categoryNotFound,
  categoryNameTaken,
  categoryArchived,
  categoryPersistenceUnavailable,
  analyticsUnavailable,
  malformedAnalyticsQuery,
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
  }) : issues = List.unmodifiable(issues),
       baselineIssues = List.unmodifiable(baselineIssues),
       plannedCostIssues = List.unmodifiable(plannedCostIssues),
       goalIssues = List.unmodifiable(goalIssues);

  final FinanceEntryFailureKind kind;
  final String requestId;
  final FinanceEntryErrorCode? code;
  final List<FinanceIssue> issues;
  final List<FinanceBaselineIssue> baselineIssues;
  final List<PlannedCostIssue> plannedCostIssues;
  final List<SavingsGoalIssue> goalIssues;
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
