import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/domain/home_snapshot.dart';
import '../../home/presentation/money_formatter.dart';
import '../application/operation_history_controller.dart';
import '../domain/finance_entry_models.dart';

/// Every confirmed operation, newest first (ADR 0020, step 4).
///
/// Read-only. Correcting an operation is a Finance Core write with its own
/// audit, and this screen deliberately does not pretend to offer it.
class OperationHistoryPage extends ConsumerStatefulWidget {
  const OperationHistoryPage({required this.onSignInRequested, super.key});

  final Future<void> Function() onSignInRequested;

  @override
  ConsumerState<OperationHistoryPage> createState() =>
      _OperationHistoryPageState();
}

class _OperationHistoryPageState extends ConsumerState<OperationHistoryPage> {
  bool _signInRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(operationHistoryControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(operationHistoryControllerProvider);
    final privacy = ref.watch(appSettingsControllerProvider).privacyMode;

    if (state is OperationHistoryAuthenticationRequired && !_signInRequested) {
      _signInRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await widget.onSignInRequested();
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.operationHistoryTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: switch (state) {
            OperationHistoryLoading() => const Center(
              key: Key('history-loading'),
              child: CircularProgressIndicator.adaptive(),
            ),
            OperationHistoryAuthenticationRequired() => const Center(
              key: Key('history-authentication'),
              child: CircularProgressIndicator.adaptive(),
            ),
            OperationHistoryFailure() => Center(
              key: const Key('history-failure'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.operationHistoryLoadError,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref
                        .read(operationHistoryControllerProvider.notifier)
                        .load(),
                    child: Text(l10n.retryAction),
                  ),
                ],
              ),
            ),
            OperationHistoryReady() => _ready(context, l10n, state, privacy),
          },
        ),
      ),
    );
  }

  Widget _ready(
    BuildContext context,
    AppLocalizations l10n,
    OperationHistoryReady state,
    bool privacy,
  ) {
    if (state.isEmpty) {
      return Center(
        key: const Key('history-empty'),
        child: Text(l10n.operationHistoryEmpty, textAlign: TextAlign.center),
      );
    }

    final controller = ref.read(operationHistoryControllerProvider.notifier);
    return ListView.separated(
      key: const Key('history-list'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: state.operations.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == state.operations.length) {
          return _LoadMoreRow(
            isLoading: state.isLoadingMore,
            failed: state.loadMoreFailed,
            onPressed: controller.loadMore,
          );
        }
        final operation = state.operations[index];
        return _OperationRow(
          operation: operation,
          privacy: privacy,
          onTap: () => _openDetail(context, l10n, operation, privacy),
        );
      },
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    AppLocalizations l10n,
    OperationHistoryItem operation,
    bool privacy,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) =>
          _OperationDetail(operation: operation, privacy: privacy),
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({
    required this.operation,
    required this.privacy,
    required this.onTap,
  });

  final OperationHistoryItem operation;
  final bool privacy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isExpense = operation.type == FinanceOperationType.expense;
    return ListTile(
      key: Key('history-row-${operation.operationId}'),
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      isThreeLine: true,
      title: Text(operation.category ?? l10n.categoryPickerNone),
      // Date and direction share one line, and the amount is the only thing
      // trailing. Stacking two lines there overflows at 200% text scale, which
      // is a supported size rather than an edge case.
      subtitle: Text(
        '${_formatDate(operation.occurredOn, l10n)} · '
        // Never money by colour alone: the word says which direction it is.
        '${isExpense ? l10n.operationExpense : l10n.operationIncome}',
      ),
      trailing: Text(
        _formatAmount(context, operation, privacy),
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

class _OperationDetail extends StatelessWidget {
  const _OperationDetail({required this.operation, required this.privacy});

  final OperationHistoryItem operation;
  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SingleChildScrollView(
          key: const Key('history-detail'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatAmount(context, operation, privacy),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                operation.type == FinanceOperationType.expense
                    ? l10n.operationExpense
                    : l10n.operationIncome,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: l10n.operationDetailDate,
                value: _formatDate(operation.occurredOn, l10n),
              ),
              _DetailRow(
                label: l10n.operationDetailCategory,
                value: operation.category ?? l10n.categoryPickerNone,
              ),
              // Shown only when it disagrees with the category name, which is
              // exactly when it is informative: after a rename, or when the
              // link is wrong. Repeating an identical value would be noise.
              if (operation.textDiffersFromCategory)
                _DetailRow(
                  key: const Key('history-detail-original-text'),
                  label: l10n.operationDetailOriginalText,
                  value: operation.categoryText!,
                  hint: l10n.operationDetailOriginalTextHint,
                ),
              if (operation.merchant != null)
                _DetailRow(
                  label: l10n.operationDetailMerchant,
                  value: operation.merchant!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.hint,
    super.key,
  });

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
    required this.isLoading,
    required this.failed,
    required this.onPressed,
  });

  final bool isLoading;
  final bool failed;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isLoading) {
      return const Padding(
        key: Key('history-loading-more'),
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // A failed page keeps everything already read on screen: losing the
          // list because the next page failed would be worse than a retry.
          if (failed) ...[
            Text(
              l10n.operationHistoryLoadMoreError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            key: const Key('history-load-more'),
            onPressed: onPressed,
            child: Text(failed ? l10n.retryAction : l10n.operationHistoryMore),
          ),
        ],
      ),
    );
  }
}

String _formatAmount(
  BuildContext context,
  OperationHistoryItem operation,
  bool privacy,
) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  // The server sends an unsigned amount and a direction; the sign is a display
  // decision, so it is applied here rather than stored.
  final signed = operation.type == FinanceOperationType.expense
      ? '-${operation.amount}'
      : operation.amount;
  return MoneyFormatter.format(
    Money(amount: signed, currency: operation.currency),
    locale: locale,
    privacy: privacy,
    showPositiveSign: operation.type == FinanceOperationType.income,
  );
}

String _formatDate(String isoDate, AppLocalizations l10n) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return l10n.operationHistoryDate(parsed);
}
