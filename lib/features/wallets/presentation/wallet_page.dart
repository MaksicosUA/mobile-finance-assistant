import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/wallet_controller.dart';
import '../domain/currency_options.dart';

/// Open a wallet in another currency (ADR 0029).
///
/// The screen says plainly that nothing is converted: a wallet holds one
/// currency, and moving money between two of them is a transfer written as two
/// amounts. Someone would otherwise reasonably expect the app to convert.
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  final _name = TextEditingController();
  final _openingBalance = TextEditingController(text: '0');
  String? _currency;
  DateTime _openingOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(walletControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(walletControllerProvider);

    ref.listen<WalletState>(walletControllerProvider, (previous, next) {
      if (next is! WalletReady ||
          (next.failure == null && next.issues.isEmpty)) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(l10n.walletWriteError)));
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.walletTitle)),
      body: SafeArea(child: _body(state, l10n)),
    );
  }

  Widget _body(WalletState state, AppLocalizations l10n) {
    switch (state) {
      case WalletLoading():
        return const Center(child: CircularProgressIndicator());
      case WalletAccountRequired():
        return _Message(
          key: const Key('wallet-account-required'),
          text: l10n.walletAccountRequired,
        );
      case WalletLoadFailure():
        return _Message(
          key: const Key('wallet-load-error'),
          text: l10n.walletLoadError,
        );
      case WalletOpened(:final account):
        return _Message(
          key: const Key('wallet-opened'),
          text:
              '${l10n.walletOpenedTitle}: ${account.name} · '
              '${account.currency}',
        );
      case WalletReady():
        return _form(state, l10n);
    }
  }

  Widget _form(WalletReady state, AppLocalizations l10n) {
    final materialL10n = MaterialLocalizations.of(context);
    final currency = _currency;
    return ListView(
      key: const Key('wallet-form'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          l10n.walletExplanation,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const Key('wallet-name'),
          controller: _name,
          enabled: !state.isSubmitting,
          maxLength: 100,
          decoration: InputDecoration(labelText: l10n.walletNameField),
          onChanged: (_) =>
              ref.read(walletControllerProvider.notifier).discardReview(),
        ),
        ListTile(
          key: const Key('wallet-currency'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.walletCurrencyField),
          subtitle: Text(currency ?? '—'),
          trailing: const Icon(Icons.expand_more_rounded),
          enabled: !state.isSubmitting,
          onTap: state.isSubmitting
              ? null
              : () async {
                  final picked = await _pickCurrency(state, l10n);
                  if (picked == null || !mounted) return;
                  setState(() => _currency = picked);
                  ref.read(walletControllerProvider.notifier).discardReview();
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('wallet-opening-balance'),
          controller: _openingBalance,
          enabled: !state.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: l10n.walletOpeningBalanceField,
            suffixText: currency,
          ),
          onChanged: (_) =>
              ref.read(walletControllerProvider.notifier).discardReview(),
        ),
        const SizedBox(height: AppSpacing.md),
        ListTile(
          key: const Key('wallet-opening-date'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.walletOpeningDateField),
          subtitle: Text(materialL10n.formatMediumDate(_openingOn)),
          trailing: const Icon(Icons.calendar_today_outlined),
          enabled: !state.isSubmitting,
          onTap: state.isSubmitting
              ? null
              : () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _openingOn,
                    firstDate: DateTime(now.year - 20),
                    // A balance cannot start tomorrow.
                    lastDate: now,
                  );
                  if (picked == null || !mounted) return;
                  setState(() => _openingOn = picked);
                  ref.read(walletControllerProvider.notifier).discardReview();
                },
        ),
        const SizedBox(height: AppSpacing.lg),
        if (state.isSubmitting) const LinearProgressIndicator(),
        if (state.review == null)
          FilledButton(
            key: const Key('wallet-review'),
            onPressed:
                state.isSubmitting ||
                    currency == null ||
                    _name.text.trim().isEmpty
                ? null
                : () => ref
                      .read(walletControllerProvider.notifier)
                      .evaluate(
                        name: _name.text,
                        currency: currency,
                        openingBalance: _openingBalance.text,
                        openingBalanceOn: _openingOn,
                      ),
            child: Text(l10n.walletReviewAction),
          )
        else
          FilledButton(
            key: const Key('wallet-confirm'),
            onPressed: state.isSubmitting
                ? null
                : () => ref.read(walletControllerProvider.notifier).confirm(),
            child: Text(l10n.walletConfirmAction),
          ),
      ],
    );
  }

  Future<String?> _pickCurrency(WalletReady state, AppLocalizations l10n) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CurrencySheet(
        held: state.heldCurrencies,
        searchLabel: l10n.walletCurrencySearch,
        heldLabel: l10n.walletCurrencyHeld,
      ),
    );
  }
}

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({
    required this.held,
    required this.searchLabel,
    required this.heldLabel,
  });

  final Set<String> held;
  final String searchLabel;
  final String heldLabel;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final matches = currencyOptions
        .where((option) => option.matches(_query))
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                key: const Key('wallet-currency-search'),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.searchLabel,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: ListView.builder(
                key: const Key('wallet-currency-list'),
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final option = matches[index];
                  final held = widget.held.contains(option.code);
                  return ListTile(
                    key: Key('wallet-currency-${option.code}'),
                    title: Text(option.name),
                    subtitle: Text(
                      option.symbol == null
                          ? option.code
                          : '${option.code} · ${option.symbol}',
                    ),
                    // Still selectable: a bank account and cash are both euro
                    // and both real (ADR 0029).
                    trailing: held ? Text(widget.heldLabel) : null,
                    onTap: () => Navigator.of(context).pop(option.code),
                  );
                },
              ),
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
