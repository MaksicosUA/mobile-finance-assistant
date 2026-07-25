import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../domain/home_snapshot.dart';

@immutable
class TransactionListItem {
  const TransactionListItem({
    required this.keyValue,
    required this.title,
    required this.metadata,
    required this.amount,
    required this.kindLabel,
    required this.semanticsLabel,
    required this.direction,
  });

  final String keyValue;
  final String title;
  final String metadata;
  final String amount;
  final String kindLabel;
  final String semanticsLabel;
  final TransactionDirection direction;
}

class RecentTransactionsList extends StatelessWidget {
  const RecentTransactionsList({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.items,
  });

  final String title;
  final String emptyLabel;
  final List<TransactionListItem> items;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('recent-transactions'),
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
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
                        _TransactionRow(item: items[index]),
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

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item});

  final TransactionListItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final amountAndKind = Column(
      crossAxisAlignment: textScale > 1.35
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          item.amount,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Text(item.kindLabel, style: theme.textTheme.bodySmall),
      ],
    );

    return Semantics(
      key: Key('transaction-${item.keyValue}'),
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
                child: Icon(_icon, size: 19, color: _iconColor(context)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(item.metadata, style: theme.textTheme.bodySmall),
                    if (textScale > 1.35) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      amountAndKind,
                    ],
                  ],
                ),
              ),
              if (textScale <= 1.35) ...[
                const SizedBox(width: AppSpacing.xs),
                amountAndKind,
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon {
    return switch (item.direction) {
      TransactionDirection.income => Icons.arrow_downward_rounded,
      TransactionDirection.expense => Icons.arrow_upward_rounded,
      TransactionDirection.transfer => Icons.swap_horiz_rounded,
      TransactionDirection.unknown => Icons.receipt_long_outlined,
    };
  }

  Color _iconColor(BuildContext context) {
    return switch (item.direction) {
      TransactionDirection.income => Theme.of(context).colorScheme.primary,
      TransactionDirection.expense => context.appColors.accentSecondary,
      TransactionDirection.transfer ||
      TransactionDirection.unknown => context.appColors.textSecondary,
    };
  }
}
