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
    // Zero claims no direction: «+0,00 €» announces a gain that did not
    // happen, and a month that only moved money between wallets ends there.
    final isZero = _isZero(unsigned);
    final sign = isZero
        ? ''
        : isNegative
        ? '−'
        : (showPositiveSign ? '+' : '');
    final decimalSeparator = locale.startsWith('ru') ? ',' : '.';
    return '$sign$whole$decimalSeparator${fraction.substring(0, 2)} $symbol';
  }

  /// The most decimals a percent is shown with.
  ///
  /// A percent beside a balance is read at a glance; it is not a figure anyone
  /// reconciles. The server once sent one carrying its column's padding, and
  /// «−0,0700000000000000%» is what the phone printed.
  static const percentFractionDigits = 3;

  static String formatPercent(
    String decimalString, {
    required String locale,
    bool privacy = false,
    bool showPositiveSign = false,
  }) {
    if (privacy) return '$_privacyMask%';

    final isNegative = decimalString.startsWith('-');
    final unsigned = _roundedHalfUp(
      isNegative ? decimalString.substring(1) : decimalString,
      fractionDigits: percentFractionDigits,
    );
    final separator = locale.startsWith('ru') ? ',' : '.';
    final localized = unsigned.replaceFirst('.', separator);
    // Rounded to zero, a percent has no direction to claim either way.
    final sign = _isZero(unsigned)
        ? ''
        : isNegative
        ? '−'
        : (showPositiveSign ? '+' : '');
    return '$sign$localized%';
  }

  /// [unsigned] rounded half up to at most [fractionDigits] decimals, with the
  /// trailing zeros dropped.
  ///
  /// Worked on the digits rather than through a double, so «0.9996» becomes
  /// «1» exactly and nothing picks up a binary rounding artefact on the way.
  static String _roundedHalfUp(String unsigned, {required int fractionDigits}) {
    final parts = unsigned.split('.');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final fraction = parts.length > 1 ? parts[1] : '';
    final kept = fraction
        .padRight(fractionDigits, '0')
        .substring(0, fractionDigits);
    var scaled = BigInt.parse('$whole$kept');
    if (fraction.length > fractionDigits &&
        fraction.codeUnitAt(fractionDigits) >= 0x35) {
      scaled += BigInt.one;
    }
    final digits = scaled.toString().padLeft(fractionDigits + 1, '0');
    final wholePart = digits.substring(0, digits.length - fractionDigits);
    final fractionPart = digits
        .substring(digits.length - fractionDigits)
        .replaceFirst(RegExp(r'0+$'), '');
    return fractionPart.isEmpty ? wholePart : '$wholePart.$fractionPart';
  }

  static bool _isZero(String unsigned) =>
      unsigned.replaceAll('.', '').split('').every((digit) => digit == '0');

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
