import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

/// Which way the month's result went.
enum BalanceTrend {
  up('↗'),
  down('↘'),
  flat('→');

  const BalanceTrend(this.arrow);

  final String arrow;

  /// Read from the authoritative decimal string, never from a formatted one.
  static BalanceTrend of(String amount) {
    final isNegative = amount.startsWith('-');
    final digits = amount.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.split('').every((digit) => digit == '0')) return flat;
    return isNegative ? down : up;
  }
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.title,
    required this.balance,
    required this.delta,
    required this.deltaTrend,
    required this.deltaPercent,
    required this.monthDeltaLabel,
    required this.deltaUnavailableLabel,
    required this.privacyLabel,
    required this.privacyEnabled,
    required this.onTogglePrivacy,
  });

  final String title;
  final String balance;
  final String? delta;

  /// Null hides the arrow. Privacy mode passes null: the direction a month went
  /// is itself something about the money, and an arrow beside a masked amount
  /// would still tell an onlooker which way it went.
  final BalanceTrend? deltaTrend;
  final String? deltaPercent;
  final String monthDeltaLabel;
  final String deltaUnavailableLabel;
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
                          // The arrow used to be a constant «↗», so a month
                          // that lost money pointed up beside its own minus.
                          [
                            ?deltaTrend?.arrow,
                            deltaPercent == null
                                ? delta!
                                : '$delta  ·  $deltaPercent',
                          ].join(' '),
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
            ],
          ),
        ),
      ),
    );
  }
}
