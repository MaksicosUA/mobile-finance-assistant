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
    final window = state.window;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final currency = window.baseCurrency;

    String money(String amount) => MoneyFormatter.format(
      Money(amount: amount, currency: currency),
      locale: locale,
      privacy: privacy,
    );

    return ListView(
      key: const Key('analytics-page'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _PeriodSelector(
          selected: window.kind,
          onSelected: (period) => ref
              .read(analyticsControllerProvider.notifier)
              .selectPeriod(period),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.analyticsWindowRange(
            _day(context, window.periodStart),
            _day(context, window.periodEnd),
          ),
          key: const Key('analytics-window-range'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        MonthlySummary(
          title: l10n.analyticsWindowRange(
            _day(context, window.periodStart),
            _day(context, window.periodEnd),
          ),
          incomeLabel: l10n.income,
          incomeValue: money(window.income),
          incomeCaption: l10n.analyticsPreviousAmount(
            money(window.previousIncome),
          ),
          expenseLabel: l10n.expenses,
          expenseValue: money(window.expense),
          expenseCaption: l10n.analyticsPreviousAmount(
            money(window.previousExpense),
          ),
          netLabel: l10n.netFlow,
          netValue: money(window.netFlow),
          netCaption: l10n.analyticsPreviousAmount(
            money(window.previousNetFlow),
          ),
        ),
        const SizedBox(height: 24),
        _BalanceCard(
          window: window,
          money: money,
          privacy: privacy,
          l10n: l10n,
        ),
        const SizedBox(height: 24),
        _ChangeTable(
          key: const Key('analytics-expense-changes'),
          title: l10n.analyticsExpenseByCategory,
          emptyLabel: l10n.analyticsBreakdownEmpty,
          rows: window.expenseChanges,
          money: money,
        ),
        const SizedBox(height: 24),
        _ChangeTable(
          key: const Key('analytics-income-changes'),
          title: l10n.analyticsIncomeByCategory,
          emptyLabel: l10n.analyticsBreakdownEmpty,
          rows: window.incomeChanges,
          money: money,
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

  String _day(BuildContext context, String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    return MaterialLocalizations.of(context).formatShortDate(parsed);
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

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelected});

  final AnalyticsPeriodKind selected;
  final ValueChanged<AnalyticsPeriodKind> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const offered = [
      AnalyticsPeriodKind.last7Days,
      AnalyticsPeriodKind.month,
      AnalyticsPeriodKind.quarter,
      AnalyticsPeriodKind.year,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in offered) ...[
            ChoiceChip(
              key: Key('analytics-period-${period.wire}'),
              label: Text(_label(l10n, period)),
              selected: period == selected,
              onSelected: (_) => onSelected(period),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  String _label(AppLocalizations l10n, AnalyticsPeriodKind period) {
    return switch (period) {
      AnalyticsPeriodKind.last7Days => l10n.analyticsPeriod7Days,
      AnalyticsPeriodKind.month => l10n.analyticsPeriodMonth,
      AnalyticsPeriodKind.quarter => l10n.analyticsPeriodQuarter,
      AnalyticsPeriodKind.year => l10n.analyticsPeriodYear,
      AnalyticsPeriodKind.custom => l10n.analyticsPeriodLabel,
    };
  }
}

/// The balance from the control point it started at to the one it ended at.
///
/// The question a chart should answer is whether this got better; where the
/// money went is the table's job, and the table below says it.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.window,
    required this.money,
    required this.privacy,
    required this.l10n,
  });

  final AnalyticsWindow window;
  final String Function(String) money;
  final bool privacy;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final balance = window.balance;
    return Column(
      key: const Key('analytics-balance'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpendingChart(
          trend: TrendSummary(
            metric: TrendMetric.balance,
            period: TrendPeriod.days7,
            total: Money(
              amount: balance.closing,
              currency: window.baseCurrency,
            ),
            points: [
              for (final point in balance.points)
                TrendPoint(
                  date: DateTime.parse(point.date),
                  amount: Money(
                    amount: point.amount,
                    currency: window.baseCurrency,
                  ),
                ),
            ],
          ),
          title: l10n.analyticsBalanceTitle,
          periodDescription: l10n.analyticsBalanceFromTo(
            money(balance.opening),
            money(balance.closing),
          ),
          periodLabel: privacy
              ? l10n.amountsHidden
              : l10n.analyticsBalanceChange(_signed(balance.change)),
          detailsLabel: l10n.detailsAction,
          emptyLabel: l10n.trendEmpty,
          semanticsLabel: l10n.trendSemantics(
            l10n.analyticsBalanceTitle,
            privacy ? l10n.amountsHidden : money(balance.closing),
          ),
          amountsHiddenLabel: l10n.amountsHidden,
          privacyEnabled: privacy,
        ),
        if (window.expense == '0') ...[
          const SizedBox(height: 8),
          Text(
            // Seven zero points are not an empty list, so without this the
            // card reads as a broken chart rather than a quiet period.
            l10n.analyticsNoSpending,
            key: const Key('analytics-no-spending'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _signed(String change) =>
      change.startsWith('-') ? money(change) : '+${money(change)}';
}

/// Categories side by side with the window before them.
class _ChangeTable extends StatelessWidget {
  const _ChangeTable({
    required this.title,
    required this.emptyLabel,
    required this.rows,
    required this.money,
    super.key,
  });

  final String title;
  final String emptyLabel;
  final List<AnalyticsCategoryChange> rows;
  final String Function(String) money;

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
        if (rows.isEmpty)
          Text(emptyLabel, style: theme.textTheme.bodyMedium)
        else
          for (final row in rows)
            Padding(
              key: Key('analytics-change-${row.categoryId ?? 'none'}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stacked) ...[
                    Text(
                      row.name ?? l10n.categoryPickerNone,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(money(row.amount), style: theme.textTheme.bodyLarge),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            row.name ?? l10n.categoryPickerNone,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            money(row.amount),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  Text(
                    l10n.analyticsPreviousAmount(money(row.previousAmount)),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
