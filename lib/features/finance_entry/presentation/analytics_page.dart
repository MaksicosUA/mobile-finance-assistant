import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/domain/home_snapshot.dart';
import '../../home/presentation/money_formatter.dart';
import '../../home/presentation/widgets/monthly_summary.dart';
import '../../home/presentation/widgets/recent_transactions_list.dart';
import '../../home/presentation/widgets/spending_chart.dart';
import '../application/analytics_controller.dart';
import '../domain/finance_entry_models.dart';

/// The analysed month: totals, both breakdowns, the expense series, and the
/// newest operations.
///
/// The chart, the monthly totals, and the recent list are the same widgets
/// Home used to render. They moved here rather than being rewritten, so the
/// screens stay visually one product.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({
    required this.onSignInRequested,
    required this.onOpenAllOperations,
    super.key,
  });

  final Future<void> Function() onSignInRequested;
  final VoidCallback onOpenAllOperations;

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(analyticsControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(analyticsControllerProvider);
    final privacy = ref.watch(appSettingsControllerProvider).privacyMode;

    if (state is AnalyticsAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: switch (state) {
        AnalyticsLoading() => const Center(
          key: Key('analytics-loading'),
          child: CircularProgressIndicator.adaptive(),
        ),
        AnalyticsAuthenticationRequired() => const Center(
          key: Key('analytics-authentication'),
          child: CircularProgressIndicator.adaptive(),
        ),
        AnalyticsFailure() => Center(
          key: const Key('analytics-failure'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.analyticsLoadError, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.read(analyticsControllerProvider.notifier).load(),
                child: Text(l10n.retryAction),
              ),
            ],
          ),
        ),
        AnalyticsReady() => _ready(context, l10n, state, privacy),
      },
    );
  }

  Widget _ready(
    BuildContext context,
    AppLocalizations l10n,
    AnalyticsReady state,
    bool privacy,
  ) {
    final summary = state.summary;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final currency = summary.baseCurrency;

    String money(String amount) => MoneyFormatter.format(
      Money(amount: amount, currency: currency),
      locale: locale,
      privacy: privacy,
    );

    return ListView(
      key: const Key('analytics-page'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        MonthlySummary(
          title: l10n.monthSummaryTitle(_monthLabel(summary.periodStart, l10n)),
          incomeLabel: l10n.income,
          incomeValue: money(summary.income),
          incomeCaption: l10n.incomeCaption,
          expenseLabel: l10n.expenses,
          expenseValue: money(summary.expense),
          expenseCaption: l10n.expensesCaption,
          netLabel: l10n.netFlow,
          netValue: money(summary.netFlow),
          netCaption: summary.netFlow.startsWith('-')
              ? l10n.expensesCaption
              : l10n.netPositiveCaption,
        ),
        const SizedBox(height: 24),
        SpendingChart(
          trend: _trend(summary),
          title: l10n.trendExpensesTitle,
          periodDescription: l10n.trendLast7Days,
          periodLabel: l10n.trend7DaysChip,
          detailsLabel: l10n.detailsAction,
          emptyLabel: l10n.trendEmpty,
          semanticsLabel: l10n.trendSemantics(
            l10n.trendExpensesTitle,
            privacy ? l10n.amountsHidden : money(summary.trendTotal),
          ),
          amountsHiddenLabel: l10n.amountsHidden,
          privacyEnabled: privacy,
        ),
        const SizedBox(height: 24),
        _Breakdown(
          key: const Key('analytics-expense-breakdown'),
          title: l10n.analyticsExpenseByCategory,
          emptyLabel: l10n.analyticsBreakdownEmpty,
          items: summary.expenseByCategory,
          money: money,
          privacy: privacy,
        ),
        const SizedBox(height: 24),
        _Breakdown(
          key: const Key('analytics-income-breakdown'),
          title: l10n.analyticsIncomeByCategory,
          emptyLabel: l10n.analyticsBreakdownEmpty,
          items: summary.incomeByCategory,
          money: money,
          privacy: privacy,
        ),
        const SizedBox(height: 24),
        RecentTransactionsList(
          title: l10n.recentTransactionsTitle,
          emptyLabel: l10n.analyticsBreakdownEmpty,
          items: [
            for (final operation in state.recent)
              _transactionItem(operation, l10n, money),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('analytics-all-operations'),
          onPressed: widget.onOpenAllOperations,
          child: Text(l10n.operationHistorySettingsAction),
        ),
      ],
    );
  }

  TransactionListItem _transactionItem(
    OperationHistoryItem operation,
    AppLocalizations l10n,
    String Function(String) money,
  ) {
    final isExpense = operation.type == FinanceOperationType.expense;
    final label = operation.category ?? l10n.categoryPickerNone;
    final amount = money(isExpense ? '-${operation.amount}' : operation.amount);
    final kind = isExpense ? l10n.operationExpense : l10n.operationIncome;
    return TransactionListItem(
      keyValue: operation.operationId,
      title: label,
      metadata: operation.occurredOn,
      amount: amount,
      kindLabel: kind,
      // The direction is spoken as well as coloured: never money by colour
      // alone.
      semanticsLabel: '$label, $kind, $amount',
      direction: isExpense
          ? TransactionDirection.expense
          : TransactionDirection.income,
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.money,
    required this.privacy,
    super.key,
  });

  final String title;
  final String emptyLabel;
  final List<AnalyticsCategoryTotal> items;
  final String Function(String) money;
  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(emptyLabel, style: theme.textTheme.bodyMedium)
        else
          for (final item in items)
            Padding(
              key: Key('analytics-row-${item.categoryId ?? 'none'}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stacked once the text is large, the same rule the monthly
                  // totals already use: at 200% an amount like "1 500,00 €"
                  // cannot share a line with a category name, and a supported
                  // text size must never overflow.
                  if (stacked) ...[
                    Text(
                      item.name ?? l10n.categoryPickerNone,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(money(item.amount), style: theme.textTheme.bodyLarge),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name ?? l10n.categoryPickerNone,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            money(item.amount),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            // Decoration only: the share is also written out,
                            // so the bar carries no meaning on its own.
                            value: _fraction(item.sharePercent),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          privacy
                              ? l10n.amountsHidden
                              : l10n.analyticsShare(item.sharePercent),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }

  double _fraction(String sharePercent) {
    final parsed = double.tryParse(sharePercent);
    if (parsed == null) return 0;
    return (parsed / 100).clamp(0, 1);
  }
}

TrendSummary _trend(AnalyticsSummary summary) => TrendSummary(
  metric: TrendMetric.expense,
  period: TrendPeriod.days7,
  total: Money(amount: summary.trendTotal, currency: summary.baseCurrency),
  points: [
    for (final point in summary.trendPoints)
      TrendPoint(
        date: DateTime.parse(point.date),
        amount: Money(amount: point.amount, currency: summary.baseCurrency),
      ),
  ],
);

/// The month a period belongs to, as `2026-08-01` carries it.
String _monthLabel(String periodStart, AppLocalizations l10n) {
  final parsed = DateTime.tryParse(periodStart);
  if (parsed == null) return periodStart;
  return l10n.analyticsMonth(parsed);
}
