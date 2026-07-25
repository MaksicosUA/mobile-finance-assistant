import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.greeting,
    required this.dateLabel,
    required this.notificationsLabel,
    required this.settingsLabel,
    required this.avatarInitial,
    required this.onNotificationsPressed,
    required this.onOpenSettings,
  });

  final String greeting;
  final String dateLabel;
  final String notificationsLabel;
  final String settingsLabel;
  final String avatarInitial;
  final VoidCallback onNotificationsPressed;
  final VoidCallback onOpenSettings;

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
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
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
        const SizedBox(width: AppSpacing.xs),
        Semantics(
          button: true,
          label: settingsLabel,
          child: SizedBox.square(
            dimension: AppSizes.minTouchTarget,
            child: Material(
              color: colors.accentSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: InkWell(
                key: const Key('open-settings'),
                onTap: onOpenSettings,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Center(
                  child: Text(
                    avatarInitial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
