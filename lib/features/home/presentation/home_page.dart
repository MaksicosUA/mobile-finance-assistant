import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/home_controller.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';
import 'money_formatter.dart';
import 'widgets/app_header.dart';
import 'widgets/balance_card.dart';
import 'widgets/goal_card.dart';
import 'widgets/home_empty_view.dart';
import 'widgets/home_failure_view.dart';
import 'widgets/home_loading_view.dart';
import 'widgets/home_status_banner.dart';
import 'widgets/monthly_summary.dart';
import 'widgets/recent_transactions_list.dart';
import 'widgets/spending_chart.dart';
import 'widgets/upcoming_payments_list.dart';
import 'widgets/voice_cta.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    required this.onOpenSettings,
    required this.onNotificationsPressed,
    required this.onVoicePressed,
    required this.onAnalyticsPressed,
    required this.onGoalPressed,
    required this.onSignOutRequested,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onVoicePressed;
  final VoidCallback onAnalyticsPressed;
  final VoidCallback onGoalPressed;
  final VoidCallback onSignOutRequested;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final homeState = ref.watch(homeControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final userName =
        homeState.retainedSnapshot?.userName ?? l10n.defaultUserName;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.screenMaxWidth),
          child: RefreshIndicator(
            onRefresh: ref.read(homeControllerProvider.notifier).refresh,
            child: ListView(
              key: const Key('home-page'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                20,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              children: [
                AppHeader(
                  greeting: l10n.greeting(userName),
                  dateLabel: l10n.homeDate,
                  notificationsLabel: l10n.notificationsLabel,
                  settingsLabel: l10n.openSettingsLabel,
                  avatarInitial: userName.characters.first.toUpperCase(),
                  onNotificationsPressed: widget.onNotificationsPressed,
                  onOpenSettings: widget.onOpenSettings,
                ),
                const SizedBox(height: AppSpacing.lg),
                _HomeStateBody(
                  state: homeState,
                  privacyEnabled: settings.privacyMode,
                  onTogglePrivacy: ref
                      .read(appSettingsControllerProvider.notifier)
                      .togglePrivacyMode,
                  onVoicePressed: widget.onVoicePressed,
                  onAnalyticsPressed: widget.onAnalyticsPressed,
                  onGoalPressed: widget.onGoalPressed,
                  onRetry: ref.read(homeControllerProvider.notifier).retry,
                  onSignOutRequested: widget.onSignOutRequested,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeStateBody extends StatelessWidget {
  const _HomeStateBody({
    required this.state,
    required this.privacyEnabled,
    required this.onTogglePrivacy,
    required this.onVoicePressed,
    required this.onAnalyticsPressed,
    required this.onGoalPressed,
    required this.onRetry,
    required this.onSignOutRequested,
  });

  final HomeState state;
  final bool privacyEnabled;
  final VoidCallback onTogglePrivacy;
  final VoidCallback onVoicePressed;
  final VoidCallback onAnalyticsPressed;
  final VoidCallback onGoalPressed;
  final Future<void> Function() onRetry;
  final VoidCallback onSignOutRequested;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (state is HomeLoading) {
      return HomeLoadingView(label: l10n.loadingLabel);
    }
    if (state is HomeEmpty) {
      return HomeEmptyView(
        title: l10n.emptyTitle,
        description: l10n.emptyDescription,
        voiceLabel: l10n.addByVoice,
        voiceSemanticsLabel: l10n.voiceEntryLabel,
        onVoicePressed: onVoicePressed,
      );
    }
    if (state case HomeFailure(:final requestId)) {
      return HomeFailureView(
        title: l10n.fatalErrorTitle,
        description: l10n.fatalErrorDescription,
        requestIdLabel: l10n.requestIdLabel(requestId),
        retryLabel: l10n.retryAction,
        onRetry: () {
          onRetry();
        },
      );
    }
    if (state case HomeAuthRequired(snapshot: null, :final requestId)) {
      return HomeAuthRequiredView(
        title: l10n.authExpiredTitle,
        description: l10n.authExpiredDescription,
        requestIdLabel: l10n.requestIdLabel(requestId),
        actionLabel: l10n.signInAgainAction,
        onAction: onSignOutRequested,
      );
    }

    final snapshot = state.retainedSnapshot;
    assert(snapshot != null, 'Every remaining state must retain a snapshot.');
    final failedBlocks = <HomeBlock>{
      ...snapshot!.warnings
          .map((warning) => homeBlockFromContract(warning.block))
          .nonNulls,
      if (state case HomePartial(:final blockFailures)) ...blockFailures.keys,
    };
    final banner = _buildBanner(context, snapshot);

    return Column(
      key: const Key('home-state-with-snapshot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null) ...[banner, const SizedBox(height: AppSpacing.md)],
        _PopulatedHome(
          snapshot: snapshot,
          failedBlocks: failedBlocks,
          privacyEnabled: privacyEnabled,
          onTogglePrivacy: onTogglePrivacy,
          onVoicePressed: onVoicePressed,
          onAnalyticsPressed: onAnalyticsPressed,
          onGoalPressed: onGoalPressed,
        ),
      ],
    );
  }

  Widget? _buildBanner(BuildContext context, HomeSnapshot snapshot) {
    final l10n = AppLocalizations.of(context);
    if (state is HomeRefreshing) {
      return HomeStatusBanner(
        key: const Key('refreshing-banner'),
        title: l10n.refreshingTitle,
        description: l10n.refreshingDescription,
        tone: HomeBannerTone.neutral,
      );
    }
    if (state is HomePartial) {
      return HomeStatusBanner(
        key: const Key('partial-banner'),
        title: l10n.partialDataTitle,
        description: l10n.partialDataDescription,
        tone: HomeBannerTone.warning,
      );
    }
    if (state is HomeOffline) {
      final value = snapshot.dataAsOf.toUtc();
      final materialL10n = MaterialLocalizations.of(context);
      final date = materialL10n.formatMediumDate(value);
      final time = materialL10n.formatTimeOfDay(
        TimeOfDay(hour: value.hour, minute: value.minute),
        alwaysUse24HourFormat: true,
      );
      return HomeStatusBanner(
        key: const Key('offline-banner'),
        title: l10n.offlineTitle,
        description: l10n.offlineDataAsOf(date, time),
        tone: HomeBannerTone.warning,
      );
    }
    if (state is HomeRefreshFailure) {
      return HomeStatusBanner(
        key: const Key('refresh-failure-banner'),
        title: l10n.refreshFailedTitle,
        description: l10n.refreshFailedDescription,
        tone: HomeBannerTone.error,
        actionLabel: l10n.retryAction,
        onAction: () {
          onRetry();
        },
      );
    }
    if (state is HomeAuthRequired) {
      return HomeStatusBanner(
        key: const Key('auth-required-banner'),
        title: l10n.authExpiredTitle,
        description: l10n.authExpiredDescription,
        tone: HomeBannerTone.error,
        actionLabel: l10n.signInAgainAction,
        onAction: onSignOutRequested,
      );
    }
    return null;
  }
}

class _PopulatedHome extends StatelessWidget {
  const _PopulatedHome({
    required this.snapshot,
    required this.privacyEnabled,
    required this.onTogglePrivacy,
    required this.onVoicePressed,
    required this.onAnalyticsPressed,
    required this.onGoalPressed,
    this.failedBlocks = const <HomeBlock>{},
  });

  final HomeSnapshot snapshot;
  final bool privacyEnabled;
  final VoidCallback onTogglePrivacy;
  final VoidCallback onVoicePressed;
  final VoidCallback onAnalyticsPressed;
  final VoidCallback onGoalPressed;
  final Set<HomeBlock> failedBlocks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final balance = snapshot.balance;
    final month = snapshot.monthSummary;
    final trend = snapshot.trend;
    final materialL10n = MaterialLocalizations.of(context);
    final analyticsAvailable = snapshot.availableActions.contains(
      HomeAction.analytics,
    );
    final goalsAvailable = snapshot.availableActions.contains(HomeAction.goals);
    final voiceAvailable = snapshot.availableActions.contains(
      HomeAction.voiceEntry,
    );
    bool blockFailed(HomeBlock block) => failedBlocks.contains(block);

    final trendTitle = switch (trend.metric) {
      TrendMetric.expense => l10n.trendExpensesTitle,
      TrendMetric.balance => l10n.trendBalanceTitle,
      TrendMetric.unknown => l10n.trendUnknownTitle,
    };
    final trendPeriodDescription = switch (trend.period) {
      TrendPeriod.days7 => l10n.trendLast7Days,
      TrendPeriod.days30 => l10n.trendLast30Days,
      TrendPeriod.unknown => l10n.trendPeriodUnknown,
    };
    final trendPeriodLabel = switch (trend.period) {
      TrendPeriod.days7 => l10n.trend7DaysChip,
      TrendPeriod.days30 => l10n.trend30DaysChip,
      TrendPeriod.unknown => l10n.trendPeriodUnknown,
    };
    final trendTotal = MoneyFormatter.format(
      trend.total,
      locale: locale,
      privacy: privacyEnabled,
    );

    final paymentItems = snapshot.upcomingPayments
        .map((payment) {
          final date = materialL10n.formatMediumDate(payment.dueAt);
          final dueLabel = switch (payment.status) {
            PaymentStatus.scheduled => l10n.paymentDueDate(date),
            PaymentStatus.overdue => l10n.paymentOverdueDate(date),
            PaymentStatus.unknown => l10n.paymentDateUnknown(date),
          };
          final amount = MoneyFormatter.format(
            payment.amount,
            locale: locale,
            privacy: privacyEnabled,
          );
          return PaymentListItem(
            keyValue: payment.id,
            title: payment.title,
            dueLabel: dueLabel,
            amount: amount,
            semanticsLabel: l10n.paymentSemantics(
              payment.title,
              dueLabel,
              amount,
            ),
            isOverdue: payment.status == PaymentStatus.overdue,
          );
        })
        .toList(growable: false);

    final transactionItems = snapshot.recentTransactions
        .map((transaction) {
          final date = materialL10n.formatMediumDate(transaction.occurredAt);
          final kind = switch (transaction.direction) {
            TransactionDirection.income => l10n.transactionIncome,
            TransactionDirection.expense => l10n.transactionExpense,
            TransactionDirection.transfer => l10n.transactionTransfer,
            TransactionDirection.unknown => l10n.transactionUnknown,
          };
          final metadata = l10n.transactionMetadata(transaction.category, date);
          final amount = MoneyFormatter.format(
            transaction.amount,
            locale: locale,
            privacy: privacyEnabled,
            showPositiveSign:
                transaction.direction == TransactionDirection.income,
          );
          return TransactionListItem(
            keyValue: transaction.id,
            title: transaction.title,
            metadata: metadata,
            amount: amount,
            kindLabel: kind,
            semanticsLabel: l10n.transactionSemantics(
              transaction.title,
              transaction.category,
              date,
              amount,
              kind,
            ),
            direction: transaction.direction,
          );
        })
        .toList(growable: false);

    return Column(
      key: const Key('home-populated'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blockFailed(HomeBlock.balance))
          HomeBlockUnavailableCard(
            key: const Key('balance-unavailable'),
            label: l10n.balanceUnavailable,
          )
        else
          BalanceCard(
            title: l10n.totalBalance,
            balance: MoneyFormatter.format(
              balance.total,
              locale: locale,
              privacy: privacyEnabled,
            ),
            delta: MoneyFormatter.format(
              balance.deltaAmount,
              locale: locale,
              privacy: privacyEnabled,
              showPositiveSign: true,
            ),
            deltaPercent: MoneyFormatter.formatPercent(
              balance.deltaPercent,
              locale: locale,
              privacy: privacyEnabled,
              showPositiveSign: true,
            ),
            monthDeltaLabel: l10n.monthDelta,
            accountsLabel: l10n.activeAccounts,
            privacyLabel: privacyEnabled ? l10n.showAmounts : l10n.hideAmounts,
            privacyEnabled: privacyEnabled,
            onTogglePrivacy: onTogglePrivacy,
          ),
        const SizedBox(height: AppSpacing.lg),
        VoiceCta(
          label: l10n.addByVoice,
          semanticsLabel: l10n.voiceEntryLabel,
          onPressed: voiceAvailable ? onVoicePressed : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (blockFailed(HomeBlock.monthSummary))
          HomeBlockUnavailableCard(
            key: const Key('month-summary-unavailable'),
            label: l10n.monthSummaryUnavailable,
          )
        else
          MonthlySummary(
            title: l10n.monthSummaryTitle,
            incomeLabel: l10n.income,
            incomeValue: MoneyFormatter.format(
              month.income,
              locale: locale,
              privacy: privacyEnabled,
            ),
            incomeCaption: l10n.incomeCaption,
            expenseLabel: l10n.expenses,
            expenseValue: MoneyFormatter.format(
              month.expense,
              locale: locale,
              privacy: privacyEnabled,
            ),
            expenseCaption: l10n.expensesCaption,
            netLabel: l10n.netFlow,
            netValue: MoneyFormatter.format(
              month.netFlow,
              locale: locale,
              privacy: privacyEnabled,
              showPositiveSign: true,
            ),
            netCaption: l10n.netPositiveCaption,
          ),
        const SizedBox(height: AppSpacing.lg),
        if (blockFailed(HomeBlock.trend))
          HomeBlockUnavailableCard(
            key: const Key('trend-unavailable'),
            label: l10n.trendUnavailable,
          )
        else
          SpendingChart(
            trend: trend,
            title: trendTitle,
            periodDescription: trendPeriodDescription,
            periodLabel: trendPeriodLabel,
            detailsLabel: l10n.detailsAction,
            emptyLabel: l10n.trendEmpty,
            semanticsLabel: l10n.trendSemantics(
              trendTitle,
              privacyEnabled ? l10n.amountsHidden : trendTotal,
            ),
            amountsHiddenLabel: l10n.amountsHidden,
            privacyEnabled: privacyEnabled,
            onOpenDetails: analyticsAvailable ? onAnalyticsPressed : null,
          ),
        const SizedBox(height: AppSpacing.lg),
        if (blockFailed(HomeBlock.primaryGoal))
          GoalUnavailableCard(label: l10n.goalUnavailable)
        else if (snapshot.primaryGoal case final goal?)
          GoalCard(
            title: goal.title,
            dueLabel: l10n.goalDueDate(
              materialL10n.formatMediumDate(goal.dueDate),
            ),
            currentValue: MoneyFormatter.format(
              goal.current,
              locale: locale,
              privacy: privacyEnabled,
            ),
            targetAndProgressLabel: l10n.goalProgressSummary(
              MoneyFormatter.format(
                goal.target,
                locale: locale,
                privacy: privacyEnabled,
              ),
              MoneyFormatter.formatDecimal(
                goal.progressPercent,
                locale: locale,
              ),
            ),
            monthlyContributionLabel: l10n.goalMonthlyContribution(
              MoneyFormatter.format(
                goal.monthlyContribution,
                locale: locale,
                privacy: privacyEnabled,
              ),
            ),
            progressPercent: goal.progressPercent,
            semanticsLabel: l10n.goalSemantics(
              goal.title,
              MoneyFormatter.format(
                goal.current,
                locale: locale,
                privacy: privacyEnabled,
              ),
              MoneyFormatter.format(
                goal.target,
                locale: locale,
                privacy: privacyEnabled,
              ),
              MoneyFormatter.formatDecimal(
                goal.progressPercent,
                locale: locale,
              ),
            ),
            onPressed: goalsAvailable ? onGoalPressed : null,
          )
        else
          GoalUnavailableCard(label: l10n.goalNotSelected),
        const SizedBox(height: AppSpacing.lg),
        if (blockFailed(HomeBlock.upcomingPayments))
          HomeBlockUnavailableCard(
            key: const Key('upcoming-payments-unavailable'),
            label: l10n.paymentsUnavailable,
          )
        else
          UpcomingPaymentsList(
            title: l10n.upcomingPaymentsTitle,
            allPaymentsLabel: l10n.allPaymentsAction,
            emptyLabel: l10n.noUpcomingPayments,
            items: paymentItems,
            onOpenAll: analyticsAvailable ? onAnalyticsPressed : null,
          ),
        const SizedBox(height: AppSpacing.lg),
        if (blockFailed(HomeBlock.recentTransactions))
          HomeBlockUnavailableCard(
            key: const Key('recent-transactions-unavailable'),
            label: l10n.transactionsUnavailable,
          )
        else
          RecentTransactionsList(
            title: l10n.recentTransactionsTitle,
            emptyLabel: l10n.noRecentTransactions,
            items: transactionItems,
          ),
      ],
    );
  }
}
