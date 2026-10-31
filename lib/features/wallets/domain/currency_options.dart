import 'package:flutter/foundation.dart';

/// One currency someone can open a wallet in.
///
/// A curated list rather than all of ISO 4217: a picker of a hundred and eighty
/// codes is worse than fifty currencies someone might actually hold. The server
/// accepts any ISO-shaped code (ADR 0029), so nothing here limits what a wallet
/// may be — a currency an account already holds is shown even when this list
/// does not know it.
@immutable
final class CurrencyOption {
  const CurrencyOption(this.code, {this.symbol});

  /// The ISO 4217 code, which is what the wallet stores.
  final String code;

  /// Shown beside the code when there is a well-known one.
  final String? symbol;

  /// Whether [query] matches the code or [name], what it is called in the
  /// language the screen is in.
  bool matches(String query, {required String name}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return code.toLowerCase().contains(needle) ||
        name.toLowerCase().contains(needle);
  }
}

const currencyOptions = <CurrencyOption>[
  CurrencyOption('EUR', symbol: '€'),
  CurrencyOption('USD', symbol: r'$'),
  CurrencyOption('UAH', symbol: '₴'),
  CurrencyOption('GBP', symbol: '£'),
  CurrencyOption('PLN'),
  CurrencyOption('CHF'),
  CurrencyOption('CZK'),
  CurrencyOption('SEK'),
  CurrencyOption('NOK'),
  CurrencyOption('DKK'),
  CurrencyOption('HUF'),
  CurrencyOption('RON'),
  CurrencyOption('BGN'),
  CurrencyOption('RSD'),
  CurrencyOption('ALL'),
  CurrencyOption('MKD'),
  CurrencyOption('BAM'),
  CurrencyOption('TRY', symbol: '₺'),
  CurrencyOption('MDL'),
  CurrencyOption('RUB', symbol: '₽'),
  CurrencyOption('BYN'),
  CurrencyOption('GEL', symbol: '₾'),
  CurrencyOption('AMD', symbol: '֏'),
  CurrencyOption('AZN', symbol: '₼'),
  CurrencyOption('KZT', symbol: '₸'),
  CurrencyOption('UZS'),
  CurrencyOption('KGS'),
  CurrencyOption('ILS', symbol: '₪'),
  CurrencyOption('AED'),
  CurrencyOption('EGP'),
  CurrencyOption('INR', symbol: '₹'),
  CurrencyOption('CNY', symbol: '¥'),
  CurrencyOption('JPY', symbol: '¥'),
  CurrencyOption('KRW', symbol: '₩'),
  CurrencyOption('THB', symbol: '฿'),
  CurrencyOption('VND', symbol: '₫'),
  CurrencyOption('IDR'),
  CurrencyOption('SGD'),
  CurrencyOption('HKD'),
  CurrencyOption('AUD'),
  CurrencyOption('NZD'),
  CurrencyOption('CAD'),
  CurrencyOption('MXN'),
  CurrencyOption('BRL', symbol: r'R$'),
  CurrencyOption('ARS'),
  CurrencyOption('CLP'),
  CurrencyOption('ZAR'),
  CurrencyOption('MAD'),
  CurrencyOption('TND'),
  CurrencyOption('ISK'),
];
