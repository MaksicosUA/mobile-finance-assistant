import '../domain/home_snapshot.dart';
import 'home_dto.dart';

abstract final class HomeMapper {
  static HomeFirstUseData toFirstUseData(HomeDto dto) {
    return HomeFirstUseData(
      userName: dto.user.displayName,
      availableActions: dto.availableActions.map(_homeAction).toSet(),
    );
  }

  static HomeSnapshot toDomain(HomeDto dto) {
    final baseCurrency = dto.baseCurrency;
    return HomeSnapshot(
      generatedAt: DateTime.parse(dto.generatedAt),
      dataAsOf: DateTime.parse(dto.dataAsOf),
      baseCurrency: baseCurrency,
      userName: dto.user.displayName,
      balance: BalanceSummary(
        total: Money(amount: dto.balance.amount, currency: baseCurrency),
        deltaAmount: Money(
          amount: dto.balance.deltaAmount,
          currency: baseCurrency,
        ),
        deltaPercent: dto.balance.deltaPercent,
      ),
      monthSummary: MonthSummary(
        from: _date(dto.monthSummary.from),
        to: _date(dto.monthSummary.to),
        income: Money(amount: dto.monthSummary.income, currency: baseCurrency),
        expense: Money(
          amount: dto.monthSummary.expense,
          currency: baseCurrency,
        ),
        netFlow: Money(
          amount: dto.monthSummary.netFlow,
          currency: baseCurrency,
        ),
      ),
      trend: TrendSummary(
        metric: _trendMetric(dto.trend.metric),
        period: _trendPeriod(dto.trend.period),
        total: Money(amount: dto.trend.total, currency: baseCurrency),
        points: dto.trend.points
            .take(30)
            .map((point) {
              return TrendPoint(
                date: _date(point.date),
                amount: Money(amount: point.amount, currency: baseCurrency),
              );
            })
            .toList(growable: false),
      ),
      wallets: dto.wallets
          .map(
            (wallet) => Wallet(
              accountId: wallet.accountId,
              name: wallet.name,
              // Its own currency, never the profile's: that is the whole
              // point of a wallet (ADR 0029).
              balance: Money(amount: wallet.balance, currency: wallet.currency),
              isDefault: wallet.isDefault,
            ),
          )
          .toList(growable: false),
      primaryGoal: dto.primaryGoal == null ? null : _goal(dto.primaryGoal!),
      upcomingPayments: dto.upcomingPayments
          .take(3)
          .map((payment) {
            return UpcomingPayment(
              id: payment.id,
              title: payment.title,
              dueOn: _date(payment.dueOn),
              dueAt: payment.dueAt == null
                  ? null
                  : DateTime.parse(payment.dueAt!),
              amount: Money(amount: payment.amount, currency: payment.currency),
              status: _paymentStatus(payment.status),
            );
          })
          .toList(growable: false),
      recentTransactions: dto.recentTransactions
          .where(
            (transaction) =>
                _transactionStatus(transaction.status) ==
                TransactionStatus.confirmed,
          )
          .take(3)
          .map((transaction) {
            return RecentTransaction(
              id: transaction.id,
              title: transaction.title,
              category: transaction.category,
              occurredOn: _date(transaction.occurredOn),
              occurredAt: transaction.occurredAt == null
                  ? null
                  : DateTime.parse(transaction.occurredAt!),
              amount: Money(
                amount: transaction.amount,
                currency: transaction.currency,
              ),
              direction: _transactionDirection(transaction.direction),
              status: TransactionStatus.confirmed,
            );
          })
          .toList(growable: false),
      availableActions: dto.availableActions.map(_homeAction).toSet(),
      warnings: dto.warnings
          .map((warning) {
            return HomeWarning(code: warning.code, block: warning.block);
          })
          .toList(growable: false),
    );
  }

  static GoalSummary _goal(HomeGoalDto goal) {
    return GoalSummary(
      id: goal.id,
      title: goal.title,
      current: Money(amount: goal.current, currency: goal.currency),
      target: Money(amount: goal.target, currency: goal.currency),
      dueDate: _date(goal.dueDate),
      progressPercent: goal.progressPercent,
      monthlyContribution: Money(
        amount: goal.monthlyContribution,
        currency: goal.currency,
      ),
    );
  }

  static DateTime _date(String value) {
    final parts = value.split('-').map(int.parse).toList(growable: false);
    return DateTime.utc(parts[0], parts[1], parts[2]);
  }

  static TrendMetric _trendMetric(String value) {
    return switch (value) {
      'expense' => TrendMetric.expense,
      'balance' => TrendMetric.balance,
      _ => TrendMetric.unknown,
    };
  }

  static TrendPeriod _trendPeriod(String value) {
    return switch (value) {
      '7d' => TrendPeriod.days7,
      '30d' => TrendPeriod.days30,
      _ => TrendPeriod.unknown,
    };
  }

  static PaymentStatus _paymentStatus(String value) {
    return switch (value) {
      'scheduled' => PaymentStatus.scheduled,
      'overdue' => PaymentStatus.overdue,
      _ => PaymentStatus.unknown,
    };
  }

  static TransactionStatus _transactionStatus(String value) {
    return switch (value) {
      'confirmed' => TransactionStatus.confirmed,
      'pending' => TransactionStatus.pending,
      _ => TransactionStatus.unknown,
    };
  }

  static TransactionDirection _transactionDirection(String value) {
    return switch (value) {
      'income' => TransactionDirection.income,
      'expense' => TransactionDirection.expense,
      'transfer' => TransactionDirection.transfer,
      _ => TransactionDirection.unknown,
    };
  }

  static HomeAction _homeAction(String value) {
    return switch (value) {
      'voice_entry' => HomeAction.voiceEntry,
      'analytics' => HomeAction.analytics,
      'goals' => HomeAction.goals,
      'telegram' => HomeAction.telegram,
      _ => HomeAction.unknown,
    };
  }
}
