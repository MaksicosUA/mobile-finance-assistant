import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/home_controller.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';
import 'home_header_time.dart';
import 'money_formatter.dart';
import 'widgets/app_header.dart';
import 'widgets/balance_card.dart';
import 'widgets/home_empty_view.dart';
import 'widgets/home_failure_view.dart';
import 'widgets/home_loading_view.dart';
import 'widgets/home_status_banner.dart';
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
    this.onManualEntryPressed,
    this.operationDeliveryStatus,
    this.localClock,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onVoicePressed;
  final VoidCallback onAnalyticsPressed;
  final VoidCallback onGoalPressed;
  final VoidCallback onSignOutRequested;
  final VoidCallback? onManualEntryPressed;
  final Widget? operationDeliveryStatus;
  final DateTime Function()? localClock;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  Timer? _clockTimer;
  late DateTime _localNow;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localNow = _readLocalNow();
    _scheduleClockUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(homeControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateClock();
    }
  }

  DateTime _readLocalNow() => widget.localClock?.call() ?? DateTime.now();

  void _scheduleClockUpdate() {
    _clockTimer?.cancel();
    final nextMinute = DateTime(
      _localNow.year,
      _localNow.month,
      _localNow.day,
      _localNow.hour,
      _localNow.minute + 1,
    );
    final delay = nextMinute.difference(_localNow);
    _clockTimer = Timer(delay, _updateClock);
  }

  void _updateClock() {
    if (!mounted) return;
    setState(() {
      _localNow = _readLocalNow();
    });
    _scheduleClockUpdate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(authSessionEpochProvider, (previous, next) {
      if (previous == null || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(homeControllerProvider.notifier).load();
      });
    });
    final l10n = AppLocalizations.of(context);
    final homeState = ref.watch(homeControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final userName = homeState.knownUserName;
    final materialL10n = MaterialLocalizations.of(context);
    final dateLabel = sentenceCase(materialL10n.formatFullDate(_localNow));

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
                  greeting: localizedHomeGreeting(
                    l10n,
                    userName: userName,
                    localNow: _localNow,
                  ),
                  dateLabel: dateLabel,
                  notificationsLabel: l10n.notificationsLabel,
                  settingsLabel: l10n.openSettingsLabel,
                  avatarInitial: userName?.characters.first.toUpperCase(),
                  onNotificationsPressed: widget.onNotificationsPressed,
                  onOpenSettings: widget.onOpenSettings,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (widget.operationDeliveryStatus case final status?) ...[
                  status,
                  const SizedBox(height: AppSpacing.sm),
                ],
                _HomeStateBody(
                  state: homeState,
                  privacyEnabled: settings.privacyMode,
                  onTogglePrivacy: ref
                      .read(appSettingsControllerProvider.notifier)
                      .togglePrivacyMode,
                  onVoicePressed: widget.onVoicePressed,
                  onManualEntryPressed: widget.onManualEntryPressed,
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
    required this.onManualEntryPressed,
    required this.onAnalyticsPressed,
    required this.onGoalPressed,
    required this.onRetry,
    required this.onSignOutRequested,
  });

  final HomeState state;
  final bool privacyEnabled;
  final VoidCallback onTogglePrivacy;
  final VoidCallback onVoicePressed;
  final VoidCallback? onManualEntryPressed;
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
    if (state case HomeEmpty(:final data)) {
      return HomeEmptyView(
        title: l10n.emptyTitle,
        description: l10n.emptyDescription,
        voiceLabel: l10n.addByVoice,
        voiceSemanticsLabel: l10n.voiceEntryLabel,
        manualLabel: l10n.setupAccountAction,
        onManualPressed: onManualEntryPressed,
        onVoicePressed: data.availableActions.contains(HomeAction.voiceEntry)
            ? onVoicePressed
            : null,
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
    final materialL10n = MaterialLocalizations.of(context);
    final analyticsAvailable = snapshot.availableActions.contains(
      HomeAction.analytics,
    );
    final voiceAvailable = snapshot.availableActions.contains(
      HomeAction.voiceEntry,
    );
    bool blockFailed(HomeBlock block) => failedBlocks.contains(block);

    final paymentItems = snapshot.upcomingPayments
        .map((payment) {
          // The authoritative fact is the local due date. Formatting an exact
          // instant here would shift the shown day for a device in another
          // timezone, which is why the contract carries dueOn separately.
          final date = materialL10n.formatMediumDate(payment.dueOn);
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
            delta: blockFailed(HomeBlock.balanceDelta)
                ? null
                : MoneyFormatter.format(
                    balance.deltaAmount,
                    locale: locale,
                    privacy: privacyEnabled,
                    showPositiveSign: true,
                  ),
            deltaPercent:
                blockFailed(HomeBlock.balanceDelta) ||
                    balance.deltaPercent == null
                ? null
                : MoneyFormatter.formatPercent(
                    balance.deltaPercent!,
                    locale: locale,
                    privacy: privacyEnabled,
                    showPositiveSign: true,
                  ),
            monthDeltaLabel: l10n.monthDelta,
            deltaUnavailableLabel: l10n.balanceDeltaUnavailable,
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
      ],
    );
  }
}
