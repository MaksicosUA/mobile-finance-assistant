import 'package:flutter/material.dart';

import '../features/home/presentation/home_page.dart';
import '../l10n/generated/app_localizations.dart';
import 'settings/settings_page.dart';
import 'theme/app_colors.dart';
import 'theme/app_tokens.dart';

enum AppSection { home, chat, analytics, goals, profile }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.home;
  bool _voiceEntryRequested = false;

  void _selectSection(AppSection section) {
    setState(() {
      _section = section;
      _voiceEntryRequested = false;
    });
  }

  void _openVoiceEntry() {
    setState(() {
      _section = AppSection.chat;
      _voiceEntryRequested = true;
    });
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  void _openNotifications() {
    final l10n = AppLocalizations.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          body: StubPage(
            title: l10n.notificationsTitle,
            description: l10n.notificationsStubDescription,
            actionLabel: l10n.backLabel,
            onBackHome: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }

  void _openSessionExpired() {
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
    return Scaffold(
      body: IndexedStack(
        index: _section.index,
        children: [
          HomePage(
            onOpenSettings: _openSettings,
            onNotificationsPressed: _openNotifications,
            onVoicePressed: _openVoiceEntry,
            onAnalyticsPressed: () => _selectSection(AppSection.analytics),
            onGoalPressed: () => _selectSection(AppSection.goals),
            onSignOutRequested: _openSessionExpired,
          ),
          StubPage(
            title: _voiceEntryRequested ? l10n.voiceStubTitle : l10n.chatTab,
            description: _voiceEntryRequested
                ? l10n.voiceStubDescription
                : l10n.stubDescription,
            onBackHome: () => _selectSection(AppSection.home),
          ),
          StubPage(
            title: l10n.analyticsTab,
            description: l10n.stubDescription,
            onBackHome: () => _selectSection(AppSection.home),
          ),
          StubPage(
            title: l10n.goalsTab,
            description: l10n.stubDescription,
            onBackHome: () => _selectSection(AppSection.home),
          ),
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
