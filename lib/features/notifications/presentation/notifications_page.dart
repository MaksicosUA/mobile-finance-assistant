import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/presentation/money_formatter.dart';
import '../application/notifications_controller.dart';

/// Everything worth attention, in one place.
///
/// Opening this screen *is* the acknowledgement: the moment it is shown is
/// recorded, and the dot on the bell goes quiet until something newer happens.
/// Nothing has to be dismissed one by one, and ignoring an item is a decision
/// the app respects rather than a prompt it repeats.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({
    required this.onOpenProfile,
    required this.onOpenPlannedCosts,
    super.key,
  });

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenPlannedCosts;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(notificationsSeenProvider.notifier).markOpened());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifications = ref.watch(appNotificationsProvider);
    final privacy = ref.watch(appSettingsControllerProvider).privacyMode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: SafeArea(
        child: notifications.isEmpty
            ? _Empty(key: const Key('notifications-empty'), l10n: l10n)
            : ListView.separated(
                key: const Key('notifications-list'),
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: notifications.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) => _NotificationCard(
                  notification: notifications[index],
                  privacy: privacy,
                  onOpenProfile: widget.onOpenProfile,
                  onOpenPlannedCosts: widget.onOpenPlannedCosts,
                ),
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n, super.key});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.notificationsEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.notificationsEmptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.privacy,
    required this.onOpenProfile,
    required this.onOpenPlannedCosts,
  });

  final AppNotification notification;
  final bool privacy;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenPlannedCosts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();

    final (
      icon,
      title,
      body,
      actionLabel,
      onAction,
      urgent,
    ) = switch (notification) {
      UpdateAvailableNotification(:final release) => (
        Icons.system_update_outlined,
        l10n.notificationUpdateTitle(release.versionName),
        release.notes ?? l10n.notificationUpdateBody,
        l10n.notificationUpdateAction,
        onOpenProfile,
        false,
      ),
      PaymentOverdueNotification(:final payment) => (
        Icons.event_busy_outlined,
        l10n.notificationPaymentOverdueTitle(payment.title),
        l10n.notificationPaymentBody(
          materialL10n.formatMediumDate(payment.dueOn),
          // Masked like every other amount: a notification is not an
          // exception to privacy mode.
          MoneyFormatter.format(
            payment.amount,
            locale: locale,
            privacy: privacy,
          ),
        ),
        l10n.notificationPaymentAction,
        onOpenPlannedCosts,
        true,
      ),
      PaymentDueSoonNotification(:final payment) => (
        Icons.event_outlined,
        l10n.notificationPaymentDueSoonTitle(payment.title),
        l10n.notificationPaymentBody(
          materialL10n.formatMediumDate(payment.dueOn),
          MoneyFormatter.format(
            payment.amount,
            locale: locale,
            privacy: privacy,
          ),
        ),
        l10n.notificationPaymentAction,
        onOpenPlannedCosts,
        false,
      ),
    };

    return Card(
      key: Key('notification-${notification.runtimeType}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Urgency is carried by the icon and the words as well as the
                // colour: never colour alone.
                Icon(icon, color: urgent ? scheme.error : scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(body, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(actionLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
