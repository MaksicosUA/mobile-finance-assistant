import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/currency_options.dart';

/// Asks for a currency, searchable by code or by its name in the language the
/// screen is in. Answers null when the sheet is dismissed.
///
/// [held] marks the currencies the person already has a wallet in.
Future<String?> showCurrencySheet(
  BuildContext context, {
  Set<String> held = const {},
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CurrencySheet(held: held),
  );
}

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.held});

  final Set<String> held;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final matches = currencyOptions
        .where(
          (option) =>
              option.matches(_query, name: l10n.currencyName(option.code)),
        )
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
                  labelText: l10n.walletCurrencySearch,
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
                    title: Text(l10n.currencyName(option.code)),
                    subtitle: Text(
                      option.symbol == null
                          ? option.code
                          : '${option.code} · ${option.symbol}',
                    ),
                    // Still selectable: a bank account and cash are both euro
                    // and both real (ADR 0029).
                    trailing: held ? Text(l10n.walletCurrencyHeld) : null,
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
