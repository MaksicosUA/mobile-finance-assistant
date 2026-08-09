import 'package:flutter/foundation.dart';

import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

sealed class AccountBaselineState {
  const AccountBaselineState();
}

final class AccountBaselineLoading extends AccountBaselineState {
  const AccountBaselineLoading();
}

enum AccountBaselineUnavailableReason { accountRequired, minimumDate }

@immutable
final class AccountBaselineUnavailable extends AccountBaselineState {
  const AccountBaselineUnavailable(this.reason);

  final AccountBaselineUnavailableReason reason;
}

@immutable
final class AccountBaselineEditing extends AccountBaselineState {
  AccountBaselineEditing({
    required this.account,
    required this.selectedDate,
    required this.earliestDate,
    required this.latestDate,
    this.isSubmitting = false,
    this.failure,
    List<FinanceBaselineIssue> issues = const [],
  }) : issues = List<FinanceBaselineIssue>.unmodifiable(issues);

  final FinanceAccount account;
  final DateTime selectedDate;
  final DateTime earliestDate;
  final DateTime latestDate;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<FinanceBaselineIssue> issues;
}

@immutable
final class AccountBaselineReviewing extends AccountBaselineState {
  const AccountBaselineReviewing({
    required this.account,
    required this.review,
    required this.earliestDate,
    required this.latestDate,
    this.isSubmitting = false,
    this.failure,
  });

  final FinanceAccount account;
  final FinanceBaselineNeedsConfirmation review;
  final DateTime earliestDate;
  final DateTime latestDate;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
}

enum AccountBaselineHomeStatus {
  pending,
  updated,
  projectionDelayed,
  authenticationRequired,
  sessionChanged,
  failed,
}

@immutable
final class AccountBaselineAccepted extends AccountBaselineState {
  const AccountBaselineAccepted({
    required this.commit,
    required this.homeStatus,
  });

  final FinanceBaselineCommit commit;
  final AccountBaselineHomeStatus homeStatus;
}

final class AccountBaselineAuthenticationRequired extends AccountBaselineState {
  const AccountBaselineAuthenticationRequired();
}

@immutable
final class AccountBaselineFailure extends AccountBaselineState {
  const AccountBaselineFailure(this.failure);

  final FinanceEntryFailure failure;
}
