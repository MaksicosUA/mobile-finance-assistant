import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/application/home_controller.dart';
import '../features/home/presentation/home_page.dart';
import '../features/app_update/application/app_update_controller.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/budgets/presentation/budgets_page.dart';
import '../features/finance_entry/application/operation_sync_controller.dart';
import '../features/finance_entry/domain/operation_outbox.dart';
import '../features/finance_entry/presentation/account_baseline_page.dart';
import '../features/finance_entry/presentation/analytics_page.dart';
import '../features/finance_entry/presentation/category_management_page.dart';
import '../features/finance_entry/presentation/operation_history_page.dart';
import '../features/finance_entry/presentation/planned_cost_page.dart';
import '../features/finance_entry/presentation/savings_goal_page.dart';
import '../features/finance_entry/presentation/finance_entry_page.dart';
import '../features/home/presentation/widgets/home_status_banner.dart';
import '../features/notifications/presentation/notifications_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/timezone/presentation/timezone_page.dart';
import '../features/transfers/presentation/transfer_page.dart';
import '../features/voice_entry/application/voice_entry_controller.dart';
import '../features/wallets/presentation/wallet_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../core/network/api_config.dart';
import 'theme/app_colors.dart';
import 'theme/app_tokens.dart';

enum AppSection { home, chat, analytics, goals, profile }

@visibleForTesting
Future<void> popToRootBeforeSignIn({
  required BuildContext context,
  required Future<void> Function() requireSignIn,
}) async {
  Navigator.of(context).popUntil((route) => route.isFirst);
  await requireSignIn();
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  AppSection _section = AppSection.home;

  /// A one-shot request from Home to land in the sentence field.
  bool _quickEntryRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // At most once a week, and only while signed in. It says nothing unless it
    // finds something, and then only by marking the bell (ADR 0026 amendment).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(appUpdateControllerProvider.notifier).checkIfDue());
    });
    if (isNetworkBackendConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(operationSyncControllerProvider.notifier)
              .setForeground(
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed,
              );
        }
      });
    }
  }

  @override
  void dispose() {
    if (isNetworkBackendConfigured) {
      ref.read(operationSyncControllerProvider.notifier).setForeground(false);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isNetworkBackendConfigured) return;
    ref
        .read(operationSyncControllerProvider.notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  void _selectSection(AppSection section) {
    // A sentence heard but never taken must not surface on some later visit
    // to the entry screen, filling a form the person did not ask to fill.
    ref.read(spokenSentenceProvider.notifier).discard();
    setState(() {
      _section = section;
      _quickEntryRequested = false;
    });
  }

  /// Home's microphone: the phone's recogniser listens, and what it heard
  /// lands in the sentence field already read (ADR 0031). Nothing is recorded
  /// until the person confirms the card, exactly as when typing.
  Future<void> _openVoiceEntry() async {
    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(voiceEntryControllerProvider.notifier)
        .listen(prompt: l10n.voicePrompt);
    if (!mounted || outcome == null) return;
    final message = switch (outcome) {
      VoiceEntryOutcome.heard || VoiceEntryOutcome.cancelled => null,
      VoiceEntryOutcome.nothingHeard => l10n.voiceNothingHeard,
      VoiceEntryOutcome.needsNetwork => l10n.voiceNeedsNetwork,
      VoiceEntryOutcome.unavailable => l10n.voiceUnavailable,
      VoiceEntryOutcome.failed => l10n.voiceFailed,
    };
    if (outcome == VoiceEntryOutcome.heard) {
      setState(() {
        _section = AppSection.chat;
        _quickEntryRequested = false;
      });
      return;
    }
    if (message == null) return;
    // Writing the sentence always works, so it is offered whenever speaking
    // did not.
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const Key('voice-entry-message'),
        content: Text(message),
        action: SnackBarAction(
          label: l10n.voiceTypeInsteadAction,
          onPressed: _openQuickEntry,
        ),
      ),
    );
  }

  /// Home's written entry: the same screen, with the sentence field ready.
  /// Voice lands in the very same field (see [_openVoiceEntry]).
  void _openQuickEntry() {
    ref.read(spokenSentenceProvider.notifier).discard();
    setState(() {
      _section = AppSection.chat;
      _quickEntryRequested = true;
    });
  }

  void _openManualEntry() {
    ref.read(spokenSentenceProvider.notifier).discard();
    setState(() {
      _section = AppSection.chat;
      _quickEntryRequested = false;
    });
  }

  void _openBudgets() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BudgetsPage(onSignInRequested: _openSessionExpired),
      ),
    );
  }

  void _openWallet() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const WalletPage()));
  }

  void _openTransfer() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const TransferPage()));
  }

  void _openTimezone() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const TimezonePage()));
  }

  void _openPlannedCost() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlannedCostPage(onSignInRequested: _openSessionExpired),
      ),
    );
  }

  void _openCategories() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            CategoryManagementPage(onSignInRequested: _openSessionExpired),
      ),
    );
  }

  void _openOperationHistory() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            OperationHistoryPage(onSignInRequested: _openSessionExpired),
      ),
    );
  }

  void _openAccountBaseline() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            AccountBaselinePage(onSignInRequested: _openSessionExpired),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => NotificationsPage(
          onOpenProfile: () {
            Navigator.of(routeContext).pop();
            setState(() => _section = AppSection.profile);
          },
          onOpenPlannedCosts: () {
            Navigator.of(routeContext).pop();
            _openPlannedCost();
          },
        ),
      ),
    );
  }

  Future<void> _openSessionExpired() async {
    if (isNetworkBackendConfigured) {
      await popToRootBeforeSignIn(
        context: context,
        requireSignIn: ref.read(authControllerProvider.notifier).requireSignIn,
      );
      return;
    }
    await ref.read(homeControllerProvider.notifier).clearSessionForSignOut();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          body: StubPage(
            title: l10n.sessionExpiredStubTitle,
            description: l10n.sessionExpiredStubDescription,
            actionLabel: l10n.backLabel,
            onBackHome: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final operationSyncState = isNetworkBackendConfigured
        ? ref.watch(operationSyncControllerProvider)
        : null;
    return Scaffold(
      body: IndexedStack(
        index: _section.index,
        children: [
          HomePage(
            onNotificationsPressed: _openNotifications,
            onEntryPressed: _openQuickEntry,
            // The fixture build has no entry screen for a sentence to land on.
            onVoicePressed: isNetworkBackendConfigured
                ? () => unawaited(_openVoiceEntry())
                : null,
            onManualEntryPressed: isNetworkBackendConfigured
                ? _openManualEntry
                : null,
            onAnalyticsPressed: () => _selectSection(AppSection.analytics),
            onGoalPressed: () => _selectSection(AppSection.goals),
            onSignOutRequested: _openSessionExpired,
            operationDeliveryStatus:
                operationSyncState == null ||
                    (operationSyncState.phase == OperationSyncPhase.idle &&
                        !operationSyncState.hasLocalOperations)
                ? null
                : OperationSyncStatusBanner(
                    state: operationSyncState,
                    onRetry: ref
                        .read(operationSyncControllerProvider.notifier)
                        .retryNow,
                    onSignIn: _openSessionExpired,
                  ),
          ),
          if (isNetworkBackendConfigured && _section == AppSection.chat)
            FinanceEntryPage(
              onBackHome: () => _selectSection(AppSection.home),
              onSignInRequested: _openSessionExpired,
              focusSentence: _quickEntryRequested,
              deliveryLocked:
                  operationSyncState?.phase == OperationSyncPhase.locked,
            )
          else
            StubPage(
              title: l10n.chatTab,
              description: l10n.stubDescription,
              onBackHome: () => _selectSection(AppSection.home),
            ),
          // Analytics needs the authenticated backend: it groups committed
          // operations, and the fixture build has none behind it.
          if (isNetworkBackendConfigured)
            AnalyticsPage(
              onSignInRequested: _openSessionExpired,
              onOpenAllOperations: _openOperationHistory,
            )
          else
            StubPage(
              title: l10n.analyticsTab,
              description: l10n.stubDescription,
              onBackHome: () => _selectSection(AppSection.home),
            ),
          // Goals need the authenticated backend: a goal and its ledger are
          // server facts, and the fixture build has no account behind them.
          if (isNetworkBackendConfigured)
            SavingsGoalPage(onSignInRequested: _openSessionExpired)
          else
            StubPage(
              title: l10n.goalsTab,
              description: l10n.stubDescription,
              onBackHome: () => _selectSection(AppSection.home),
            ),
          // Profile needs the authenticated backend: the identity and the
          // account facts are server truth, and the fixture build has neither.
          if (isNetworkBackendConfigured)
            ProfilePage(
              onSignInRequested: _openSessionExpired,
              onCorrectOpeningDate: _openAccountBaseline,
              onPlanCost: _openPlannedCost,
              onManageCategories: _openCategories,
              onOperationHistory: _openOperationHistory,
              onBudgets: _openBudgets,
              onCorrectTimezone: _openTimezone,
              onTransfer: _openTransfer,
              onOpenWallet: _openWallet,
              onSignOut: ref.read(authControllerProvider.notifier).signOut,
            )
          else
            StubPage(
              title: l10n.profileTab,
              description: l10n.stubDescription,
              onBackHome: () => _selectSection(AppSection.home),
            ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        selected: _section,
        onSelected: _selectSection,
      ),
    );
  }
}

class OperationSyncStatusBanner extends StatelessWidget {
  const OperationSyncStatusBanner({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onSignIn,
  });

  final OperationSyncState state;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (state.phase) {
      OperationSyncPhase.idle when !state.hasLocalOperations =>
        const SizedBox.shrink(),
      OperationSyncPhase.synchronizing => HomeStatusBanner(
        key: const Key('operation-syncing-banner'),
        title: l10n.operationSyncingBannerTitle,
        description: l10n.operationSyncingBannerDescription,
        tone: HomeBannerTone.neutral,
      ),
      OperationSyncPhase.homeConvergencePending => HomeStatusBanner(
        key: const Key('operation-home-convergence-banner'),
        title: l10n.operationHomeUpdatingBannerTitle,
        description: l10n.operationHomeUpdatingBannerDescription,
        tone: HomeBannerTone.neutral,
        actionLabel: l10n.operationHomeUpdatingAction,
        onAction: onRetry,
      ),
      OperationSyncPhase.pending ||
      OperationSyncPhase.retryableFailure => HomeStatusBanner(
        key: const Key('operation-pending-banner'),
        title: l10n.operationPendingBannerTitle,
        description: l10n.operationPendingBannerDescription,
        tone: HomeBannerTone.warning,
        actionLabel: l10n.operationRetryNowAction,
        onAction: onRetry,
      ),
      OperationSyncPhase.authenticationRequired => HomeStatusBanner(
        key: const Key('operation-auth-banner'),
        title: l10n.operationAuthBannerTitle,
        description: l10n.operationAuthBannerDescription,
        tone: HomeBannerTone.warning,
        actionLabel: l10n.signInAgainAction,
        onAction: onSignIn,
      ),
      OperationSyncPhase.attentionRequired => HomeStatusBanner(
        key: const Key('operation-attention-banner'),
        title: l10n.operationAttentionBannerTitle,
        description: l10n.operationAttentionBannerDescription,
        tone: HomeBannerTone.error,
        actionLabel:
            state.lastSafeError == OperationOutboxErrorCode.storageUnavailable
            ? l10n.operationRetryNowAction
            : null,
        onAction:
            state.lastSafeError == OperationOutboxErrorCode.storageUnavailable
            ? onRetry
            : null,
      ),
      OperationSyncPhase.locked => HomeStatusBanner(
        key: const Key('operation-locked-banner'),
        title: l10n.operationAttentionBannerTitle,
        description: l10n.operationLockedBannerDescription,
        tone: HomeBannerTone.error,
      ),
      OperationSyncPhase.idle => const SizedBox.shrink(),
    };
  }
}

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AppSection selected;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final destinations = [
      (AppSection.home, Icons.home_outlined, l10n.homeTab),
      (AppSection.chat, Icons.chat_bubble_outline_rounded, l10n.chatTab),
      (AppSection.analytics, Icons.bar_chart_rounded, l10n.analyticsTab),
      (AppSection.goals, Icons.track_changes_rounded, l10n.goalsTab),
      (AppSection.profile, Icons.person_outline_rounded, l10n.profileTab),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final destination in destinations)
                Expanded(
                  child: _NavigationItem(
                    section: destination.$1,
                    icon: destination.$2,
                    label: destination.$3,
                    selected: destination.$1 == selected,
                    onTap: () => onSelected(destination.$1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.section,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppSection section;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : context.appColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: Key('nav-${section.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StubPage extends StatelessWidget {
  const StubPage({
    super.key,
    required this.title,
    required this.description,
    required this.onBackHome,
    this.actionLabel,
  });

  final String title;
  final String description;
  final VoidCallback onBackHome;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      bottom: false,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: onBackHome,
                      child: Text(actionLabel ?? l10n.backHome),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
