import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

/// The greeting, the date, and notifications.
///
/// There is no profile/settings button here any more: Profile is a tab in the
/// navigation bar, and one door beats two (ADR 0021).
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.greeting,
    required this.dateLabel,
    required this.notificationsLabel,
    required this.hasUnseenNotifications,
    required this.onNotificationsPressed,
  });

  final String greeting;
  final String dateLabel;
  final String notificationsLabel;

  /// Whether anything is actually waiting. The dot used to be drawn
  /// unconditionally, so the app claimed there was news from the day it
  /// shipped — including to a screen reader.
  final bool hasUnseenNotifications;
  final VoidCallback onNotificationsPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Semantics(
          button: true,
          label: notificationsLabel,
          child: SizedBox.square(
            dimension: AppSizes.minTouchTarget,
            child: Material(
              color: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: colors.border),
              ),
              child: InkWell(
                key: const Key('open-notifications'),
                onTap: onNotificationsPressed,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      color: colors.textPrimary,
                    ),
                    if (hasUnseenNotifications)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          key: const Key('notifications-dot'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
