import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_settings.dart';
import 'app_settings_controller.dart';

/// Appearance and general preferences, as they used to appear on their own
/// Settings screen.
///
/// They live inside Profile now: one door to everything about the account
/// rather than a gear on Home and a tab in the navigation bar.
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsControllerProvider);
    final controller = ref.read(appSettingsControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(l10n.appearanceSection),
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
        SettingsSectionLabel(l10n.generalSection),
        const SizedBox(height: AppSpacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SettingsValueRow(
                label: l10n.privacySetting,
                trailing: Switch(
                  key: const Key('settings-privacy-toggle'),
                  value: settings.privacyMode,
                  onChanged: controller.setPrivacyMode,
                ),
              ),
              Divider(height: 1, color: context.appColors.border),
              SettingsValueRow(
                label: l10n.languageSetting,
                value: l10n.russianLanguage,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.settingsNote, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
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

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.label, {super.key});

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

/// A read-only fact, or a preference with its own control.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
  });

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
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A row that opens something. [description] says what it does, and [value]
/// says what it currently is — an action named "Дата начала учёта" that does
/// not show the date makes the user open it just to read it.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
    this.value,
  });

  final IconData icon;
  final String label;
  final String description;

  /// Nullable so a row can be disabled while its action is in flight. A
  /// row that stays tappable during its own work invites a second tap
  /// that does nothing.
  final VoidCallback? onPressed;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticsLabel = value == null
        ? '$label. $description'
        : '$label. $value. $description';
    return Semantics(
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      label: semanticsLabel,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (value case final value?) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(description, style: theme.textTheme.bodySmall),
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
