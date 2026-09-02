import 'package:flutter/foundation.dart';

import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';

sealed class TimezoneState {
  const TimezoneState();
}

final class TimezoneLoading extends TimezoneState {
  const TimezoneLoading();
}

/// A registered user without an account has no months to redraw yet.
final class TimezoneAccountRequired extends TimezoneState {
  const TimezoneAccountRequired();
}

@immutable
final class TimezoneLoadFailure extends TimezoneState {
  const TimezoneLoadFailure(this.failure);

  final FinanceEntryFailure failure;
}

@immutable
final class TimezoneReady extends TimezoneState {
  TimezoneReady({
    required this.accountId,
    required this.canonicalTimezone,
    this.deviceTimezone,
    this.isSubmitting = false,
    this.failure,
    List<FinanceTimezoneIssue> issues = const [],
  }) : issues = List<FinanceTimezoneIssue>.unmodifiable(issues);

  final String accountId;

  /// Where the account draws its months right now, as the server reports it.
  final String canonicalTimezone;

  /// What the phone itself is set to, when it could be read and differs.
  /// Offered first, because moving is the reason anyone opens this screen.
  final String? deviceTimezone;

  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<FinanceTimezoneIssue> issues;

  TimezoneReady copyWith({
    String? canonicalTimezone,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    List<FinanceTimezoneIssue>? issues,
  }) {
    return TimezoneReady(
      accountId: accountId,
      canonicalTimezone: canonicalTimezone ?? this.canonicalTimezone,
      deviceTimezone: deviceTimezone,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      issues: issues ?? const [],
    );
  }
}
