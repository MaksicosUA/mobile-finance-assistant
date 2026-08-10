import 'package:flutter/foundation.dart';

final RegExp _decimalPattern = RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');

@immutable
class Money {
  Money({required this.amount, required this.currency}) {
    if (!_decimalPattern.hasMatch(amount)) {
      throw const FormatException('Money amount must be a decimal string.');
    }
    if (!_currencyPattern.hasMatch(currency)) {
      throw const FormatException('Money currency must be ISO 4217.');
    }
  }

  /// Authoritative decimal-string value. It must never be converted to double.
  final String amount;
  final String currency;

  @override
  bool operator ==(Object other) {
    return other is Money &&
        other.amount == amount &&
        other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(amount, currency);
}

@immutable
class BalanceSummary {
  BalanceSummary({
    required this.total,
    required this.deltaAmount,
    required this.deltaPercent,
  }) {
    if (deltaPercent != null && !_decimalPattern.hasMatch(deltaPercent!)) {
      throw const FormatException(
        'Balance delta percent must be a decimal string.',
      );
    }
  }

  final Money total;
  final Money deltaAmount;

  /// Null when a meaningful percentage cannot be calculated, for example
  /// when the comparison balance is zero.
  final String? deltaPercent;
}

@immutable
class MonthSummary {
  const MonthSummary({
    required this.from,
    required this.to,
    required this.income,
    required this.expense,
    required this.netFlow,
  });

  final DateTime from;
  final DateTime to;
  final Money income;
  final Money expense;
  final Money netFlow;
}

enum TrendMetric { expense, balance, unknown }

enum TrendPeriod { days7, days30, unknown }

@immutable
class TrendPoint {
  const TrendPoint({required this.date, required this.amount});

  final DateTime date;
  final Money amount;
}

@immutable
class TrendSummary {
  TrendSummary({
    required this.metric,
    required this.period,
    required this.total,
    required List<TrendPoint> points,
  }) : points = List<TrendPoint>.unmodifiable(points);

  final TrendMetric metric;
  final TrendPeriod period;
  final Money total;
  final List<TrendPoint> points;
}

@immutable
class GoalSummary {
  GoalSummary({
    required this.id,
    required this.title,
    required this.current,
    required this.target,
    required this.dueDate,
    required this.progressPercent,
    required this.monthlyContribution,
  }) {
    if (!_decimalPattern.hasMatch(progressPercent)) {
      throw const FormatException(
        'Goal progress percent must be a decimal string.',
      );
    }
  }

  final String id;
  final String title;
  final Money current;
  final Money target;
  final DateTime dueDate;
  final String progressPercent;
  final Money monthlyContribution;
}

enum PaymentStatus { scheduled, overdue, unknown }

@immutable
class UpcomingPayment {
  const UpcomingPayment({
    required this.id,
    required this.title,
    required this.dueOn,
    required this.dueAt,
    required this.amount,
    required this.status,
  });

  final String id;
  final String title;

  /// Authoritative local due date. A planned cost has a calendar date and no
  /// time of day, so this is what the UI must present and compare.
  final DateTime dueOn;

  /// Exact instant, only when one is genuinely known. Never synthesized.
  final DateTime? dueAt;
  final Money amount;
  final PaymentStatus status;
}

enum TransactionDirection { income, expense, transfer, unknown }

enum TransactionStatus { confirmed, pending, unknown }

@immutable
class RecentTransaction {
  const RecentTransaction({
    required this.id,
    required this.title,
    required this.category,
    required this.occurredOn,
    required this.occurredAt,
    required this.amount,
    required this.direction,
    required this.status,
  });

  final String id;
  final String? title;
  final String? category;

  /// Canonical calendar date represented at UTC midnight for display only.
  /// It is not an exact occurrence instant.
  final DateTime occurredOn;

  /// Exact authoritative UTC instant when one was captured; never synthesized.
  final DateTime? occurredAt;
  final Money amount;
  final TransactionDirection direction;
  final TransactionStatus status;
}

enum HomeAction { voiceEntry, analytics, goals, telegram, unknown }

/// Non-financial metadata retained for a first-use account.
///
/// This data is kept in memory only. An authoritative empty response must not
/// be persisted as a financial Home snapshot.
@immutable
class HomeFirstUseData {
  HomeFirstUseData({
    required this.userName,
    required Set<HomeAction> availableActions,
  }) : availableActions = Set<HomeAction>.unmodifiable(availableActions);

  final String userName;
  final Set<HomeAction> availableActions;
}

@immutable
class HomeWarning {
  const HomeWarning({required this.code, required this.block});

  final String code;
  final String block;
}

@immutable
class HomeSnapshot {
  HomeSnapshot({
    required this.generatedAt,
    required this.dataAsOf,
    required this.baseCurrency,
    required this.userName,
    required this.balance,
    required this.monthSummary,
    required this.trend,
    required this.primaryGoal,
    required List<UpcomingPayment> upcomingPayments,
    required List<RecentTransaction> recentTransactions,
    required Set<HomeAction> availableActions,
    required List<HomeWarning> warnings,
  }) : upcomingPayments = List<UpcomingPayment>.unmodifiable(upcomingPayments),
       recentTransactions = List<RecentTransaction>.unmodifiable(
         recentTransactions,
       ),
       availableActions = Set<HomeAction>.unmodifiable(availableActions),
       warnings = List<HomeWarning>.unmodifiable(warnings) {
    if (!_currencyPattern.hasMatch(baseCurrency)) {
      throw const FormatException('Base currency must be ISO 4217.');
    }
    if (!generatedAt.isUtc || !dataAsOf.isUtc) {
      throw const FormatException('Home timestamps must be UTC.');
    }
    if (monthSummary.to.isBefore(monthSummary.from)) {
      throw const FormatException('Month boundaries are invalid.');
    }
  }

  final DateTime generatedAt;
  final DateTime dataAsOf;
  final String baseCurrency;
  final String userName;
  final BalanceSummary balance;
  final MonthSummary monthSummary;
  final TrendSummary trend;
  final GoalSummary? primaryGoal;
  final List<UpcomingPayment> upcomingPayments;
  final List<RecentTransaction> recentTransactions;
  final Set<HomeAction> availableActions;
  final List<HomeWarning> warnings;
}
