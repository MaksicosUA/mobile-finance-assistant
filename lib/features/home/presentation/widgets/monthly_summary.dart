import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

class MonthlySummary extends StatelessWidget {
  const MonthlySummary({
    super.key,
    required this.title,
    required this.incomeLabel,
    required this.incomeValue,
    required this.incomeCaption,
    required this.expenseLabel,
    required this.expenseValue,
    required this.expenseCaption,
    required this.netLabel,
    required this.netValue,
    required this.netCaption,
  });

  final String title;
  final String incomeLabel;
  final String incomeValue;
  final String incomeCaption;
  final String expenseLabel;
  final String expenseValue;
  final String expenseCaption;
  final String netLabel;
  final String netValue;
  final String netCaption;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final vertical = scale > 1.35 || constraints.maxWidth < 328;
            final items = [
              _SummaryItem(
                icon: Icons.arrow_upward_rounded,
                iconColor: Theme.of(context).colorScheme.primary,
                label: incomeLabel,
                value: incomeValue,
                caption: incomeCaption,
              ),
              _SummaryItem(
                icon: Icons.arrow_downward_rounded,
                iconColor: context.appColors.accentSecondary,
                label: expenseLabel,
                value: expenseValue,
                caption: expenseCaption,
              ),
              _SummaryItem(
                icon: Icons.drag_handle_rounded,
                iconColor: context.appColors.textSecondary,
                label: netLabel,
                value: netValue,
                caption: netCaption,
              ),
            ];

            if (vertical) {
              return Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    items[index],
                    if (index < items.length - 1)
                      const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  Expanded(child: items[index]),
                  if (index < items.length - 1)
                    const SizedBox(width: AppSpacing.xs),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall,
                    softWrap: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
