import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/wallets/domain/currency_options.dart';

void main() {
  test('a region offers the currency people there hold', () {
    expect(currencyOfRegion('US'), 'USD');
    expect(currencyOfRegion('UA'), 'UAH');
    expect(currencyOfRegion('GB'), 'GBP');
    expect(currencyOfRegion('DE'), 'EUR');
  });

  test('a region it does not know offers nothing rather than a guess', () {
    expect(currencyOfRegion('ZZ'), isNull);
    expect(currencyOfRegion(null), isNull);
  });

  test('a suggestion is always something the picker can show', () {
    final offered = currencyOptions.map((option) => option.code).toSet();
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    for (final first in letters.split('')) {
      for (final second in letters.split('')) {
        final currency = currencyOfRegion('$first$second');
        if (currency != null) {
          expect(offered, contains(currency), reason: '$first$second');
        }
      }
    }
  });
}
