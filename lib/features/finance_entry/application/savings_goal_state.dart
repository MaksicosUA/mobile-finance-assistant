import 'package:flutter/foundation.dart';

import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

/// States of the savings-goal screen (ADR 0019).
///
/// Like a planned cost and unlike an operation there is no review step: a goal
/// and its ledger earmark balance that is already in the account, so nothing
/// here moves money and an explicit confirmation would protect nothing.
sealed class SavingsGoalScreenState {
  const SavingsGoalScreenState();
}

final class SavingsGoalLoading extends SavingsGoalScreenState {
  const SavingsGoalLoading();
}

enum SavingsGoalUnavailableReason { accountRequired }

@immutable
final class SavingsGoalUnavailable extends SavingsGoalScreenState {
  const SavingsGoalUnavailable(this.reason);

  final SavingsGoalUnavailableReason reason;
}

@immutable
final class SavingsGoalReady extends SavingsGoalScreenState {
  SavingsGoalReady({
    required this.account,
    required this.selectedDate,
    required this.earliestDate,
    required this.latestDate,
    this.title = '',
    this.targetAmount = '',
    this.monthlyContribution = '',
    this.contributionAmount = '',
    this.isSubmitting = false,
    this.isCreating = false,
    this.failure,
    this.busyGoalId,
    List<SavingsGoalIssue> issues = const [],
    List<SavingsGoal> goals = const [],
  }) : issues = List<SavingsGoalIssue>.unmodifiable(issues),
       goals = List<SavingsGoal>.unmodifiable(goals);

  final FinanceAccount account;
  final String title;
  final String targetAmount;

  /// The user's declared monthly intent. Blank means "no declared plan", which
  /// is sent as an omitted field rather than as zero.
  final String monthlyContribution;

  /// The amount typed into the deposit/withdraw sheet of the open goal.
  final String contributionAmount;
  final DateTime selectedDate;

  /// A target before the account baseline describes a deadline the account did
  /// not exist for.
  final DateTime earliestDate;

  /// A usability bound on the picker, not a contract rule.
  final DateTime latestDate;
  final bool isSubmitting;

  /// Whether the create form is expanded. Goals are usually few, so the list
  /// leads and the form stays out of the way until asked for.
  final bool isCreating;
  final FinanceEntryFailure? failure;
  final List<SavingsGoalIssue> issues;

  /// Active goals only. A cancelled goal keeps its ledger server-side but is
  /// no longer something the user is pursuing.
  final List<SavingsGoal> goals;

  /// The goal a contribution or cancellation is in flight for, so only that
  /// card shows progress instead of the whole screen.
  final String? busyGoalId;

  SavingsGoalReady copyWith({
    String? title,
    String? targetAmount,
    String? monthlyContribution,
    String? contributionAmount,
    DateTime? selectedDate,
    bool? isSubmitting,
    bool? isCreating,
    FinanceEntryFailure? failure,
    List<SavingsGoalIssue>? issues,
    List<SavingsGoal>? goals,
    String? busyGoalId,
    bool clearFailure = false,
    bool clearBusyGoalId = false,
  }) {
    return SavingsGoalReady(
      account: account,
      title: title ?? this.title,
      targetAmount: targetAmount ?? this.targetAmount,
      monthlyContribution: monthlyContribution ?? this.monthlyContribution,
      contributionAmount: contributionAmount ?? this.contributionAmount,
      selectedDate: selectedDate ?? this.selectedDate,
      earliestDate: earliestDate,
      latestDate: latestDate,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isCreating: isCreating ?? this.isCreating,
      failure: clearFailure ? null : (failure ?? this.failure),
      issues: issues ?? this.issues,
      goals: goals ?? this.goals,
      busyGoalId: clearBusyGoalId ? null : (busyGoalId ?? this.busyGoalId),
    );
  }
}

final class SavingsGoalAuthenticationRequired extends SavingsGoalScreenState {
  const SavingsGoalAuthenticationRequired();
}

@immutable
final class SavingsGoalFailure extends SavingsGoalScreenState {
  const SavingsGoalFailure(this.failure);

  final FinanceEntryFailure failure;
}
