import 'package:flutter/foundation.dart';

import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

/// States of the flow that records one intended future payment (ADR 0018).
///
/// There is deliberately no review step: a plan is a forecast, and nothing it
/// can do moves the authoritative balance, so the explicit confirmation an
/// operation requires would add a round trip without protecting anything.
sealed class PlannedCostState {
  const PlannedCostState();
}

final class PlannedCostLoading extends PlannedCostState {
  const PlannedCostLoading();
}

enum PlannedCostUnavailableReason { accountRequired }

@immutable
final class PlannedCostUnavailable extends PlannedCostState {
  const PlannedCostUnavailable(this.reason);

  final PlannedCostUnavailableReason reason;
}

@immutable
final class PlannedCostEditing extends PlannedCostState {
  PlannedCostEditing({
    required this.account,
    required this.selectedDate,
    required this.earliestDate,
    required this.latestDate,
    this.title = '',
    this.amount = '',
    this.isSubmitting = false,
    this.failure,
    List<PlannedCostIssue> issues = const [],
  }) : issues = List<PlannedCostIssue>.unmodifiable(issues);

  final FinanceAccount account;
  final String title;
  final String amount;
  final DateTime selectedDate;

  /// A plan may not precede the account baseline: it could never be confirmed
  /// into a legal operation.
  final DateTime earliestDate;

  /// A forecast is allowed far into the future; this is only the contract
  /// range bound, not a product rule.
  final DateTime latestDate;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<PlannedCostIssue> issues;

  PlannedCostEditing copyWith({
    String? title,
    String? amount,
    DateTime? selectedDate,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    List<PlannedCostIssue>? issues,
    bool clearFailure = false,
  }) {
    return PlannedCostEditing(
      account: account,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      selectedDate: selectedDate ?? this.selectedDate,
      earliestDate: earliestDate,
      latestDate: latestDate,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      issues: issues ?? this.issues,
    );
  }
}

/// Whether Home has caught up with the accepted plan.
///
/// Acceptance and Home convergence are separate durable facts: the plan is
/// already stored server-side even when the projection has not been rebuilt.
enum PlannedCostHomeStatus {
  pending,
  updated,
  projectionDelayed,
  authenticationRequired,
  failed,
}

@immutable
final class PlannedCostAccepted extends PlannedCostState {
  const PlannedCostAccepted({
    required this.plannedCost,
    required this.homeStatus,
  });

  final PlannedCost plannedCost;
  final PlannedCostHomeStatus homeStatus;
}

final class PlannedCostAuthenticationRequired extends PlannedCostState {
  const PlannedCostAuthenticationRequired();
}

@immutable
final class PlannedCostFailure extends PlannedCostState {
  const PlannedCostFailure(this.failure);

  final FinanceEntryFailure failure;
}
