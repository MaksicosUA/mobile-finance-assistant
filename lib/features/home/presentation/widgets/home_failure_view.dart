import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

class HomeFailureView extends StatelessWidget {
  const HomeFailureView({
    super.key,
    required this.title,
    required this.description,
    required this.requestIdLabel,
    required this.retryLabel,
    required this.onRetry,
  });

  final String title;
  final String description;
  final String requestIdLabel;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredStateCard(
      stateKey: const Key('home-fatal-error'),
      icon: Icons.cloud_off_outlined,
      title: title,
      description: description,
      requestIdLabel: requestIdLabel,
      actionLabel: retryLabel,
      onAction: onRetry,
    );
  }
}

class HomeAuthRequiredView extends StatelessWidget {
  const HomeAuthRequiredView({
    super.key,
    required this.title,
    required this.description,
    required this.requestIdLabel,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String description;
  final String requestIdLabel;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return _CenteredStateCard(
      stateKey: const Key('home-auth-required'),
      icon: Icons.lock_clock_outlined,
      title: title,
      description: description,
      requestIdLabel: requestIdLabel,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _CenteredStateCard extends StatelessWidget {
  const _CenteredStateCard({
    required this.stateKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.requestIdLabel,
    required this.actionLabel,
    required this.onAction,
  });

  final Key stateKey;
  final IconData icon;
  final String title;
  final String description;
  final String requestIdLabel;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: stateKey,
      container: true,
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.appColors.surfaceSecondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                requestIdLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
