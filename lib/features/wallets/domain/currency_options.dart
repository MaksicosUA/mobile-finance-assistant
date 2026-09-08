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
  const CurrencyOption(this.code, this.name, {this.symbol});

  /// The ISO 4217 code, which is what the wallet stores.
  final String code;

  /// What it is called, because "ALL" is not a word and "лек" is.
  final String name;

  /// Shown beside the code when there is a well-known one.
  final String? symbol;

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return code.toLowerCase().contains(needle) ||
        name.toLowerCase().contains(needle);
  }
}

const currencyOptions = <CurrencyOption>[
  CurrencyOption('EUR', 'Евро', symbol: '€'),
  CurrencyOption('USD', 'Доллар США', symbol: r'$'),
  CurrencyOption('UAH', 'Гривна', symbol: '₴'),
  CurrencyOption('GBP', 'Фунт стерлингов', symbol: '£'),
  CurrencyOption('PLN', 'Злотый'),
  CurrencyOption('CHF', 'Швейцарский франк'),
  CurrencyOption('CZK', 'Чешская крона'),
  CurrencyOption('SEK', 'Шведская крона'),
  CurrencyOption('NOK', 'Норвежская крона'),
  CurrencyOption('DKK', 'Датская крона'),
  CurrencyOption('HUF', 'Форинт'),
  CurrencyOption('RON', 'Румынский лей'),
  CurrencyOption('BGN', 'Болгарский лев'),
  CurrencyOption('RSD', 'Сербский динар'),
  CurrencyOption('ALL', 'Албанский лек'),
  CurrencyOption('MKD', 'Македонский денар'),
  CurrencyOption('BAM', 'Конвертируемая марка'),
  CurrencyOption('TRY', 'Турецкая лира', symbol: '₺'),
  CurrencyOption('MDL', 'Молдавский лей'),
  CurrencyOption('RUB', 'Российский рубль', symbol: '₽'),
  CurrencyOption('BYN', 'Белорусский рубль'),
  CurrencyOption('GEL', 'Лари', symbol: '₾'),
  CurrencyOption('AMD', 'Армянский драм', symbol: '֏'),
  CurrencyOption('AZN', 'Азербайджанский манат', symbol: '₼'),
  CurrencyOption('KZT', 'Тенге', symbol: '₸'),
  CurrencyOption('UZS', 'Узбекский сум'),
  CurrencyOption('KGS', 'Киргизский сом'),
  CurrencyOption('ILS', 'Шекель', symbol: '₪'),
  CurrencyOption('AED', 'Дирхам ОАЭ'),
  CurrencyOption('EGP', 'Египетский фунт'),
  CurrencyOption('INR', 'Индийская рупия', symbol: '₹'),
  CurrencyOption('CNY', 'Юань', symbol: '¥'),
  CurrencyOption('JPY', 'Иена', symbol: '¥'),
  CurrencyOption('KRW', 'Вона', symbol: '₩'),
  CurrencyOption('THB', 'Бат', symbol: '฿'),
  CurrencyOption('VND', 'Донг', symbol: '₫'),
  CurrencyOption('IDR', 'Индонезийская рупия'),
  CurrencyOption('SGD', 'Сингапурский доллар'),
  CurrencyOption('HKD', 'Гонконгский доллар'),
  CurrencyOption('AUD', 'Австралийский доллар'),
  CurrencyOption('NZD', 'Новозеландский доллар'),
  CurrencyOption('CAD', 'Канадский доллар'),
  CurrencyOption('MXN', 'Мексиканское песо'),
  CurrencyOption('BRL', 'Бразильский реал', symbol: r'R$'),
  CurrencyOption('ARS', 'Аргентинское песо'),
  CurrencyOption('CLP', 'Чилийское песо'),
  CurrencyOption('ZAR', 'Южноафриканский рэнд'),
  CurrencyOption('MAD', 'Марокканский дирхам'),
  CurrencyOption('TND', 'Тунисский динар'),
  CurrencyOption('ISK', 'Исландская крона'),
];
