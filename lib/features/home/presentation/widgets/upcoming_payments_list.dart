import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

@immutable
class PaymentListItem {
  const PaymentListItem({
    required this.keyValue,
    required this.title,
    required this.dueLabel,
    required this.amount,
    required this.semanticsLabel,
    required this.isOverdue,
  });

  final String keyValue;
  final String title;
  final String dueLabel;
  final String amount;
  final String semanticsLabel;
  final bool isOverdue;
}

class UpcomingPaymentsList extends StatelessWidget {
  const UpcomingPaymentsList({
    super.key,
    required this.title,
    required this.allPaymentsLabel,
    required this.emptyLabel,
    required this.items,
    this.onOpenAll,
  });

  final String title;
  final String allPaymentsLabel;
  final String emptyLabel;
  final List<PaymentListItem> items;
  final VoidCallback? onOpenAll;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('upcoming-payments'),
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onOpenAll != null)
                  // Bounded so a long label wraps inside the button: a German
                  // one at 200% is wider than the whole row (ADR 0034).
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.6,
                    ),
                    child: TextButton(
                      key: const Key('open-all-payments'),
                      onPressed: onOpenAll,
                      child: Text(allPaymentsLabel),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Card(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      emptyLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < items.length; index++) ...[
                        _PaymentRow(item: items[index]),
                        if (index < items.length - 1)
                          Divider(height: 1, color: context.appColors.border),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.item});

  final PaymentListItem item;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final theme = Theme.of(context);
    final colors = context.appColors;
    final amountWidget = Text(
      item.amount,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    return Semantics(
      key: Key('payment-${item.keyValue}'),
      container: true,
      label: item.semanticsLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Icon(
                  item.isOverdue
                      ? Icons.event_busy_outlined
                      : Icons.calendar_today_outlined,
                  size: 18,
                  color: item.isOverdue
                      ? theme.colorScheme.error
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      item.dueLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: item.isOverdue
                            ? theme.colorScheme.error
                            : colors.textSecondary,
                      ),
                    ),
                    if (textScale > 1.35) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      amountWidget,
                    ],
                  ],
                ),
              ),
              if (textScale <= 1.35) ...[
                const SizedBox(width: AppSpacing.xs),
                amountWidget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
