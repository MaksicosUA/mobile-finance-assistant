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
    this.settlingId,
    this.repeats = false,
    this.lastDayOfMonth = false,
    this.endingRecurrenceId,
    List<PlannedCostIssue> issues = const [],
    List<PlannedCost> plans = const [],
    List<PlannedCostRecurrenceListItem> recurrences = const [],
    List<FinanceAccount>? wallets,
  }) : issues = List<PlannedCostIssue>.unmodifiable(issues),
       plans = List<PlannedCost>.unmodifiable(plans),
       recurrences = List<PlannedCostRecurrenceListItem>.unmodifiable(
         recurrences,
       ),
       wallets = List<FinanceAccount>.unmodifiable(wallets ?? [account]);

  /// The wallet this plan will be paid from.
  final FinanceAccount account;

  /// Every wallet the profile holds (ADR 0029). A profile with one wallet has
  /// one entry and the screen offers no choice.
  final List<FinanceAccount> wallets;
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

  /// Outstanding plans only. A settled plan is no longer an obligation and
  /// disappears from the list rather than lingering as history.
  final List<PlannedCost> plans;

  /// The plan a cancellation is currently in flight for, so only that row
  /// shows progress instead of the whole screen.
  final String? settlingId;

  /// Whether the form records a repeating payment rather than a single one
  /// (ADR 0025). The chosen date then becomes the day the series starts.
  final bool repeats;

  /// Anchors the series to the end of every month. Clamping makes «the 31st»
  /// and «the last day» the same schedule, so this stores 31 rather than a
  /// second concept.
  final bool lastDayOfMonth;

  /// The rules the user already has, each with the outstanding instances it
  /// owns — which is how an instance of a series is told from a one-off plan.
  final List<PlannedCostRecurrenceListItem> recurrences;

  /// The rule an ending is currently in flight for.
  final String? endingRecurrenceId;

  /// The day of the month the series would be anchored to, unclamped.
  int get dayOfMonth => lastDayOfMonth ? 31 : selectedDate.day;

  /// Instances that belong to a series, so the screen can offer to skip one.
  /// Skipping a one-off plan would mean exactly what cancelling means.
  Set<String> get seriesInstanceIds => <String>{
    for (final item in recurrences)
      for (final instance in item.upcoming) instance.plannedCostId,
  };

  PlannedCostEditing copyWith({
    String? title,
    String? amount,
    DateTime? selectedDate,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    List<PlannedCostIssue>? issues,
    List<PlannedCost>? plans,
    List<PlannedCostRecurrenceListItem>? recurrences,
    String? settlingId,
    bool? repeats,
    bool? lastDayOfMonth,
    String? endingRecurrenceId,
    bool clearFailure = false,
    bool clearSettlingId = false,
    bool clearEndingRecurrenceId = false,
  }) {
    return PlannedCostEditing(
      account: account,
      wallets: wallets,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      selectedDate: selectedDate ?? this.selectedDate,
      earliestDate: earliestDate,
      latestDate: latestDate,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      issues: issues ?? this.issues,
      plans: plans ?? this.plans,
      recurrences: recurrences ?? this.recurrences,
      settlingId: clearSettlingId ? null : (settlingId ?? this.settlingId),
      repeats: repeats ?? this.repeats,
      lastDayOfMonth: lastDayOfMonth ?? this.lastDayOfMonth,
      endingRecurrenceId: clearEndingRecurrenceId
          ? null
          : (endingRecurrenceId ?? this.endingRecurrenceId),
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

/// A repeating plan was accepted, with the dates it has just materialised.
///
/// Shown as its own state rather than folded into [PlannedCostAccepted]: the
/// point of the screen is the list of dates, because that is where a user sees
/// what «the 31st» does to February before it happens.
@immutable
final class PlannedCostRecurrenceAccepted extends PlannedCostState {
  PlannedCostRecurrenceAccepted({
    required this.recurrence,
    required this.homeStatus,
    required List<String> occurrences,
  }) : occurrences = List<String>.unmodifiable(occurrences);

  final PlannedCostRecurrence recurrence;
  final List<String> occurrences;
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
