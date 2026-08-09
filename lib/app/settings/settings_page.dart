import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_settings.dart';
import 'app_settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.onCorrectOpeningDate, this.onSignOut});

  final VoidCallback? onCorrectOpeningDate;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsControllerProvider);
    final controller = ref.read(appSettingsControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.screenMaxWidth,
            ),
            child: ListView(
              key: const Key('settings-page'),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    IconButton.outlined(
                      key: const Key('settings-back'),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: l10n.backLabel,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.settingsTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionLabel(l10n.appearanceSection),
                const SizedBox(height: AppSpacing.sm),
                _ThemeSelector(
                  selected: settings.themeMode,
                  lightLabel: l10n.lightTheme,
                  darkLabel: l10n.darkTheme,
                  onSelected: controller.setThemeMode,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.accentColor,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final accent in AppAccent.values)
                      _AccentSwatch(
                        accent: accent,
                        selected: settings.accent == accent,
                        label: _accentLabel(l10n, accent),
                        onSelected: () => controller.setAccent(accent),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SectionLabel(l10n.generalSection),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _SettingsRow(
                        label: l10n.privacySetting,
                        trailing: Switch(
                          key: const Key('settings-privacy-toggle'),
                          value: settings.privacyMode,
                          onChanged: controller.setPrivacyMode,
                        ),
                      ),
                      Divider(height: 1, color: context.appColors.border),
                      _SettingsRow(
                        label: l10n.languageSetting,
                        value: l10n.russianLanguage,
                      ),
                      Divider(height: 1, color: context.appColors.border),
                      _SettingsRow(
                        label: l10n.baseCurrencySetting,
                        value: 'EUR',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.settingsNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (onCorrectOpeningDate != null || onSignOut != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _SectionLabel(l10n.accountSection),
                  const SizedBox(height: AppSpacing.sm),
                  if (onCorrectOpeningDate != null) ...[
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: _SettingsActionRow(
                        key: const Key('settings-opening-date'),
                        icon: Icons.calendar_month_outlined,
                        label: l10n.baselineSettingsAction,
                        description: l10n.baselineSettingsDescription,
                        onPressed: onCorrectOpeningDate!,
                      ),
                    ),
                    if (onSignOut != null)
                      const SizedBox(height: AppSpacing.sm),
                  ],
                  if (onSignOut != null)
                    Semantics(
                      button: true,
                      child: OutlinedButton.icon(
                        key: const Key('settings-sign-out'),
                        onPressed: () => _confirmSignOut(context),
                        icon: const Icon(Icons.logout_rounded),
                        label: Text(l10n.signOutAction),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).pop();
    await onSignOut?.call();
  }

  String _accentLabel(AppLocalizations l10n, AppAccent accent) {
    return switch (accent) {
      AppAccent.teal => l10n.tealAccent,
      AppAccent.blue => l10n.blueAccent,
      AppAccent.purple => l10n.purpleAccent,
      AppAccent.terracotta => l10n.terracottaAccent,
    };
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.selected,
    required this.lightLabel,
    required this.darkLabel,
    required this.onSelected,
  });

  final ThemeMode selected;
  final String lightLabel;
  final String darkLabel;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final cards = [
      _ThemeCard(
        key: const Key('theme-light'),
        label: lightLabel,
        mode: ThemeMode.light,
        selected: selected == ThemeMode.light,
        onTap: () => onSelected(ThemeMode.light),
      ),
      _ThemeCard(
        key: const Key('theme-dark'),
        label: darkLabel,
        mode: ThemeMode.dark,
        selected: selected == ThemeMode.dark,
        onTap: () => onSelected(ThemeMode.dark),
      ),
    ];

    if (scale > 1.5) {
      return Column(
        children: [
          cards.first,
          const SizedBox(height: AppSpacing.sm),
          cards.last,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: cards.first),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: cards.last),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    super.key,
    required this.label,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previewDark = mode == ThemeMode.dark;
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? accent : context.appColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 80,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: previewDark
                      ? const Color(0xFF0D1621)
                      : const Color(0xFFF6F8FB),
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(color: const Color(0xFFD8E1E8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 86,
                      height: 10,
                      decoration: BoxDecoration(
                        color: previewDark
                            ? const Color(0xFFA8B5C2)
                            : const Color(0xFF16324F),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: double.infinity,
                      height: 26,
                      decoration: BoxDecoration(
                        color: previewDark
                            ? const Color(0xFF152332)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD8E1E8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? accent : context.appColors.border,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final AppAccent accent;
  final bool selected;
  final String label;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: Key('accent-${accent.name}'),
        onTap: onSelected,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppSizes.minTouchTarget,
          height: AppSizes.minTouchTarget,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.appColors.surface,
            border: Border.all(
              color: selected ? accent.color : context.appColors.border,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.color,
              shape: BoxShape.circle,
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    color: AppTheme.contrastForeground(accent.color),
                    size: 20,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (value case final value?)
              Text(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      excludeSemantics: true,
      label: '$label. $description',
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const ExcludeSemantics(
                  child: Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
