import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_widgets.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../account_data/presentation/account_data_section.dart';
import '../../app_update/presentation/app_update_section.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../application/profile_controller.dart';

/// Everything about the account behind one door: who is signed in, the durable
/// facts of the account, the actions that used to hide in Settings, appearance,
/// and which build is installed.
///
/// Deliberately reports no money. A balance belongs on Home, and a second
/// surface reporting it is a second thing that can disagree with the
/// authoritative projection.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({
    required this.onSignInRequested,
    required this.onCorrectOpeningDate,
    required this.onCorrectTimezone,
    required this.onTransfer,
    required this.onOpenWallet,
    required this.onPlanCost,
    required this.onManageCategories,
    required this.onOperationHistory,
    required this.onBudgets,
    required this.onSignOut,
    super.key,
  });

  final Future<void> Function() onSignInRequested;
  final VoidCallback onCorrectOpeningDate;
  final VoidCallback onCorrectTimezone;
  final VoidCallback onTransfer;
  final VoidCallback onOpenWallet;
  final VoidCallback onPlanCost;
  final VoidCallback onManageCategories;
  final VoidCallback onOperationHistory;
  final VoidCallback onBudgets;
  final Future<void> Function() onSignOut;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(profileControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(profileControllerProvider);

    if (state is ProfileAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    final profile = state is ProfileReady ? state.profile : null;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.screenMaxWidth),
          child: RefreshIndicator(
            onRefresh: () => _refresh(l10n),
            child: ListView(
              key: const Key('profile-page'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                20,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  l10n.profileTab,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                // The identity and the account facts are one block and fail
                // together. Everything below keeps working without them.
                _IdentityBlock(state: state, l10n: l10n),
                const SizedBox(height: AppSpacing.lg),
                SettingsSectionLabel(l10n.accountSection),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-opening-date'),
                    icon: Icons.calendar_month_outlined,
                    label: l10n.baselineSettingsAction,
                    // Shown beside the action, so reading the date no longer
                    // means opening the screen that changes it.
                    value: _openingDateLabel(profile, l10n),
                    description: l10n.baselineSettingsDescription,
                    onPressed: widget.onCorrectOpeningDate,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-timezone'),
                    icon: Icons.public_outlined,
                    label: l10n.profileTimezoneSetting,
                    // Beside the action for the same reason the opening date
                    // is: reading it should not mean opening the screen that
                    // changes it.
                    value: profile?.account?.canonicalTimezone,
                    description: l10n.timezoneSettingsDescription,
                    onPressed: widget.onCorrectTimezone,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-open-wallet'),
                    icon: Icons.account_balance_wallet_outlined,
                    label: l10n.walletSettingsAction,
                    description: l10n.walletSettingsDescription,
                    onPressed: widget.onOpenWallet,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-transfer'),
                    icon: Icons.swap_horiz_rounded,
                    label: l10n.transferSettingsAction,
                    description: l10n.transferSettingsDescription,
                    onPressed: widget.onTransfer,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-plan-cost'),
                    icon: Icons.event_repeat_outlined,
                    label: l10n.plannedCostSettingsAction,
                    description: l10n.plannedCostSettingsDescription,
                    onPressed: widget.onPlanCost,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-categories'),
                    icon: Icons.sell_outlined,
                    label: l10n.categoriesSettingsAction,
                    description: l10n.categoriesSettingsDescription,
                    onPressed: widget.onManageCategories,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-budgets'),
                    icon: Icons.pie_chart_outline_rounded,
                    label: l10n.budgetsSettingsAction,
                    description: l10n.budgetsSettingsDescription,
                    onPressed: widget.onBudgets,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SettingsActionRow(
                    key: const Key('profile-operation-history'),
                    icon: Icons.receipt_long_outlined,
                    label: l10n.operationHistorySettingsAction,
                    description: l10n.operationHistorySettingsDescription,
                    onPressed: widget.onOperationHistory,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const AccountDataSection(),
                const SizedBox(height: AppSpacing.lg),
                const AppearanceSettingsSection(),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  button: true,
                  child: OutlinedButton.icon(
                    key: const Key('profile-sign-out'),
                    onPressed: () => _confirmSignOut(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(l10n.signOutAction),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppUpdateSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A failed refresh keeps the profile that is already on screen, so the
  /// only way the user learns it failed is to be told.
  Future<void> _refresh(AppLocalizations l10n) async {
    final refreshed = await ref
        .read(profileControllerProvider.notifier)
        .refresh();
    if (refreshed || !mounted) return;
    if (ref.read(profileControllerProvider) is! ProfileReady) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.profileLoadError)));
  }

  String? _openingDateLabel(UserProfile? profile, AppLocalizations l10n) {
    final account = profile?.account;
    if (account == null) return null;
    final parsed = DateTime.tryParse(account.openingBalanceOn);
    if (parsed == null) return null;
    return l10n.profileOpeningDateValue(parsed);
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.signOutDialogTitle),
        content: Text(l10n.signOutDialogDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            key: const Key('confirm-sign-out'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.signOutAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.onSignOut();
  }
}

class _IdentityBlock extends ConsumerWidget {
  const _IdentityBlock({required this.state, required this.l10n});

  final ProfileState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      ProfileLoading() || ProfileAuthenticationRequired() => const Padding(
        key: Key('profile-loading'),
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator.adaptive()),
      ),
      ProfileFailure() => Card(
        key: const Key('profile-failure'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.profileLoadError),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                key: const Key('profile-retry'),
                onPressed: () =>
                    ref.read(profileControllerProvider.notifier).load(),
                child: Text(l10n.retryAction),
              ),
            ],
          ),
        ),
      ),
      ProfileReady(:final profile) => _Identity(profile: profile, l10n: l10n),
    };
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.profile, required this.l10n});

  final UserProfile profile;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = profile.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  key: const Key('profile-name'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Semantics(
                  label: '${l10n.profileEmailLabel}: ${profile.email}',
                  excludeSemantics: true,
                  child: Text(
                    profile.email,
                    key: const Key('profile-email'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SettingsSectionLabel(l10n.profileAccountSection),
        const SizedBox(height: AppSpacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: account == null
              ? SettingsValueRow(
                  key: const Key('profile-no-account'),
                  label: l10n.profileNoAccount,
                )
              : Column(
                  children: [
                    SettingsValueRow(
                      key: const Key('profile-currency'),
                      label: l10n.baseCurrencySetting,
                      value: account.currency,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
