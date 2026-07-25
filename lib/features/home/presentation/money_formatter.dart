import '../domain/home_snapshot.dart';

abstract final class MoneyFormatter {
  static const _privacyMask = '••••••';

  static String format(
    Money money, {
    required String locale,
    bool privacy = false,
    bool showPositiveSign = false,
  }) {
    final symbol = _currencySymbol(money.currency);
    if (privacy) return '$_privacyMask $symbol';

    final isNegative = money.amount.startsWith('-');
    final unsigned = isNegative ? money.amount.substring(1) : money.amount;
    final parts = unsigned.split('.');
    final whole = _groupThousands(parts.first);
    final fraction = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
    final sign = isNegative ? '−' : (showPositiveSign ? '+' : '');
    final decimalSeparator = locale.startsWith('ru') ? ',' : '.';
    return '$sign$whole$decimalSeparator${fraction.substring(0, 2)} $symbol';
  }

  static String formatPercent(
    String decimalString, {
    required String locale,
    bool privacy = false,
    bool showPositiveSign = false,
  }) {
    if (privacy) return '$_privacyMask%';

    final localized = formatDecimal(decimalString, locale: locale);
    final sign = showPositiveSign && !localized.startsWith('-') ? '+' : '';
    return '$sign$localized%';
  }

  static String formatDecimal(String decimalString, {required String locale}) {
    return locale.startsWith('ru')
        ? decimalString.replaceFirst('.', ',')
        : decimalString;
  }

  static String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      final remaining = digits.length - index;
      buffer.write(digits[index]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(' ');
    }
    return buffer.toString();
  }

  static String _currencySymbol(String currency) {
    return switch (currency) {
      'EUR' => '€',
      'USD' => r'$',
      _ => currency,
    };
  }
}
