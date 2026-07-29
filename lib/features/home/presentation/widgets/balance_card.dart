import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.title,
    required this.balance,
    required this.delta,
    required this.deltaPercent,
    required this.monthDeltaLabel,
    required this.deltaUnavailableLabel,
    required this.accountsLabel,
    required this.privacyLabel,
    required this.privacyEnabled,
    required this.onTogglePrivacy,
  });

  final String title;
  final String balance;
  final String? delta;
  final String? deltaPercent;
  final String monthDeltaLabel;
  final String deltaUnavailableLabel;
  final String accountsLabel;
  final String privacyLabel;
  final bool privacyEnabled;
  final VoidCallback onTogglePrivacy;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title, $balance',
      child: Card(
        key: const Key('balance-card'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('privacy-toggle'),
                    onPressed: onTogglePrivacy,
                    tooltip: privacyLabel,
                    icon: Icon(
                      privacyEnabled
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                balance,
                key: const Key('balance-value'),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (delta == null)
                Text(
                  deltaUnavailableLabel,
                  key: const Key('balance-delta-unavailable'),
                  style: theme.textTheme.bodySmall,
                )
              else
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          deltaPercent == null
                              ? '↗ $delta'
                              : '↗ $delta  ·  $deltaPercent',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Text(monthDeltaLabel, style: theme.textTheme.bodySmall),
                  ],
                ),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.border),
              const SizedBox(height: 10),
              Text(accountsLabel, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
