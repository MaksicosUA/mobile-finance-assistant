import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../home/domain/home_snapshot.dart';
import '../../home/presentation/money_formatter.dart';
import '../application/transfer_controller.dart';
import '../domain/implied_rate.dart';

/// Move money between two wallets (ADR 0029).
///
/// Two amounts, because those are the two numbers the user witnessed: what
/// left one wallet and what arrived in the other. The rate between them is
/// **shown** as they type and never sent or stored — it follows from the pair,
/// and seeing it is how a zero typed one too many times gets noticed.
class TransferPage extends ConsumerStatefulWidget {
  const TransferPage({super.key});

  @override
  ConsumerState<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends ConsumerState<TransferPage> {
  final _fromAmount = TextEditingController();
  final _toAmount = TextEditingController();
  FinanceAccount? _from;
  FinanceAccount? _to;
  DateTime _occurredOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(transferControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _fromAmount.dispose();
    _toAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(transferControllerProvider);

    ref.listen<TransferState>(transferControllerProvider, (previous, next) {
      if (next is! TransferReady) return;
      final message = _failureMessage(next, l10n);
      if (message == null) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.transferTitle)),
      body: SafeArea(child: _body(state, l10n)),
    );
  }

  Widget _body(TransferState state, AppLocalizations l10n) {
    switch (state) {
      case TransferLoading():
        return const Center(child: CircularProgressIndicator());
      case TransferSecondWalletRequired():
        return _Message(
          key: const Key('transfer-second-wallet-required'),
          text: l10n.transferSecondWalletRequired,
        );
      case TransferLoadFailure():
        return _Message(
          key: const Key('transfer-load-error'),
          text: l10n.transferLoadError,
        );
      case TransferAccepted(:final transfer):
        return _Accepted(transfer: transfer, l10n: l10n);
      case TransferReady():
        return _form(state, l10n);
    }
  }

  Widget _form(TransferReady state, AppLocalizations l10n) {
    final from = _from ??= state.wallets.firstWhere(
      (wallet) => wallet.isDefault,
      orElse: () => state.wallets.first,
    );
    final to = _to ??= state.wallets.firstWhere(
      (wallet) => wallet.accountId != from.accountId,
      orElse: () => state.wallets.last,
    );
    final review = state.review;
    final rate = impliedRate(from: _fromAmount.text, to: _toAmount.text);

    return ListView(
      key: const Key('transfer-form'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _WalletPicker(
          fieldKey: const Key('transfer-from'),
          label: l10n.transferFromField,
          wallets: state.wallets,
          value: from,
          enabled: !state.isSubmitting,
          onChanged: (wallet) => setState(() {
            _from = wallet;
            if (_to?.accountId == wallet.accountId) _to = null;
            ref.read(transferControllerProvider.notifier).discardReview();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('transfer-from-amount'),
          controller: _fromAmount,
          enabled: !state.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.transferFromAmountField,
            suffixText: from.currency,
          ),
          onChanged: (_) => setState(
            () => ref.read(transferControllerProvider.notifier).discardReview(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _WalletPicker(
          fieldKey: const Key('transfer-to'),
          label: l10n.transferToField,
          wallets: state.wallets
              .where((wallet) => wallet.accountId != from.accountId)
              .toList(growable: false),
          value: to.accountId == from.accountId ? null : to,
          enabled: !state.isSubmitting,
          onChanged: (wallet) => setState(() {
            _to = wallet;
            ref.read(transferControllerProvider.notifier).discardReview();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('transfer-to-amount'),
          controller: _toAmount,
          enabled: !state.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.transferToAmountField,
            suffixText: to.currency,
          ),
          onChanged: (_) => setState(
            () => ref.read(transferControllerProvider.notifier).discardReview(),
          ),
        ),
        // Derived while typing, never stored and never sent: it follows from
        // the two amounts, and a stored copy could disagree with them.
        if (rate != null && from.currency != to.currency) ...[
          const SizedBox(height: AppSpacing.sm),
          _RateLine(
            key: const Key('transfer-rate'),
            text: l10n.transferRateLabel(
              from.currency,
              rate.value,
              to.currency,
            ),
            hint: l10n.transferRateHint,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _DateRow(
          label: l10n.transferDateField,
          value: _occurredOn,
          enabled: !state.isSubmitting,
          onChanged: (value) => setState(() {
            _occurredOn = value;
            ref.read(transferControllerProvider.notifier).discardReview();
          }),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (state.isSubmitting) const LinearProgressIndicator(),
        if (review == null)
          FilledButton(
            key: const Key('transfer-review'),
            onPressed: state.isSubmitting
                ? null
                : () => ref
                      .read(transferControllerProvider.notifier)
                      .evaluate(
                        from: from,
                        to: to,
                        fromAmount: _fromAmount.text,
                        toAmount: _toAmount.text,
                        occurredOn: _occurredOn,
                      ),
            child: Text(l10n.transferReviewAction),
          )
        else
          FilledButton(
            key: const Key('transfer-confirm'),
            onPressed: state.isSubmitting
                ? null
                : () => ref.read(transferControllerProvider.notifier).confirm(),
            child: Text(l10n.transferConfirmAction),
          ),
      ],
    );
  }

  String? _failureMessage(TransferReady state, AppLocalizations l10n) {
    for (final issue in state.issues) {
      return switch (issue.code) {
        FinanceTransferIssueCode.walletUnavailable =>
          l10n.transferIssueWalletUnavailable,
        FinanceTransferIssueCode.walletCurrencyMismatch =>
          l10n.transferIssueCurrencyMismatch,
        FinanceTransferIssueCode.transferBeforeWalletBaseline =>
          l10n.transferIssueBeforeBaseline,
        FinanceTransferIssueCode.futureOccurredDate =>
          l10n.transferIssueFutureDate,
        FinanceTransferIssueCode.confirmationBeforeCapture =>
          l10n.transferIssueConfirmationBeforeCapture,
      };
    }
    return state.failure == null ? null : l10n.transferWriteError;
  }
}

class _RateLine extends StatelessWidget {
  const _RateLine({required this.text, required this.hint, super.key});

  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(hint, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _WalletPicker extends StatelessWidget {
  const _WalletPicker({
    required this.fieldKey,
    required this.label,
    required this.wallets,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final List<FinanceAccount> wallets;
  final FinanceAccount? value;
  final bool enabled;
  final ValueChanged<FinanceAccount> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: fieldKey,
      initialValue: value?.accountId,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final wallet in wallets)
          DropdownMenuItem(
            value: wallet.accountId,
            child: Text('${wallet.name} · ${wallet.currency}'),
          ),
      ],
      onChanged: enabled
          ? (selected) {
              if (selected == null) return;
              onChanged(
                wallets.firstWhere((item) => item.accountId == selected),
              );
            }
          : null,
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    return ListTile(
      key: const Key('transfer-date'),
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(materialL10n.formatMediumDate(value)),
      trailing: const Icon(Icons.calendar_today_outlined),
      enabled: enabled,
      onTap: enabled
          ? () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(now.year - 5),
                // Never the future: money cannot have moved tomorrow.
                lastDate: now,
              );
              if (picked != null) onChanged(picked);
            }
          : null,
    );
  }
}

class _Accepted extends ConsumerWidget {
  const _Accepted({required this.transfer, required this.l10n});

  final FinanceTransferCommitted transfer;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(appSettingsControllerProvider).privacyMode;
    final locale = Localizations.localeOf(context).toString();
    String money(String amount, String currency) => MoneyFormatter.format(
      Money(amount: amount, currency: currency),
      locale: locale,
      privacy: privacy,
    );

    return Center(
      key: const Key('transfer-accepted'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.transferAcceptedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.transferAcceptedBody(
                money(transfer.fromAmount, transfer.fromCurrency),
                money(transfer.toAmount, transfer.toCurrency),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
