import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// The wallets that are not the balance card, one line each.
///
/// **Nothing is summed.** A wallet holds one currency and nothing is converted
/// (ADR 0029), so adding these together would need a rate the product
/// deliberately does not have. Each line states one wallet's own money and
/// stops there.
class WalletLines extends StatelessWidget {
  const WalletLines({required this.title, required this.items, super.key});

  final String title;
  final List<WalletLineItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('home-wallets'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            for (final item in items) ...[
              if (item != items.first) const SizedBox(height: AppSpacing.xs),
              _WalletRow(item: item),
            ],
          ],
        ),
      ),
    );
  }
}

@immutable
class WalletLineItem {
  const WalletLineItem({
    required this.accountId,
    required this.name,
    required this.balance,
  });

  final String accountId;
  final String name;

  /// Already formatted and already masked when privacy is on: this widget
  /// never sees an amount it could accidentally reveal.
  final String balance;
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.item});

  final WalletLineItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${item.name}: ${item.balance}',
      excludeSemantics: true,
      child: Row(
        key: Key('home-wallet-${item.accountId}'),
        children: [
          Expanded(
            child: Text(
              item.name,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            item.balance,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }
}
