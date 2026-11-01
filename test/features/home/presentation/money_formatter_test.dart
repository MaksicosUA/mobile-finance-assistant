import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/features/home/presentation/money_formatter.dart';

void main() {
  group('MoneyFormatter', () {
    test('formats decimal strings for the Russian locale without double', () {
      final money = Money(amount: '1930.00', currency: 'EUR');

      expect(MoneyFormatter.format(money, locale: 'ru'), '1 930,00 €');
    });

    test('each language writes a number its own way', () {
      final money = Money(amount: '1930.50', currency: 'EUR');

      expect(MoneyFormatter.format(money, locale: 'uk'), '1 930,50 €');
      expect(MoneyFormatter.format(money, locale: 'de'), '1.930,50 €');
      expect(MoneyFormatter.format(money, locale: 'en'), '€1,930.50');
      expect(MoneyFormatter.format(money, locale: 'en-GB'), '€1,930.50');
    });

    test('English puts the sign before the currency', () {
      final money = Money(amount: '-1930.50', currency: 'EUR');

      expect(MoneyFormatter.format(money, locale: 'en'), '−€1,930.50');
    });

    test('a currency with no symbol keeps its space in every language', () {
      final money = Money(amount: '1930.50', currency: 'CHF');

      expect(MoneyFormatter.format(money, locale: 'en'), 'CHF 1,930.50');
      expect(MoneyFormatter.format(money, locale: 'de'), '1.930,50 CHF');
    });

    test('privacy masks the amount in every language', () {
      final money = Money(amount: '1930.50', currency: 'EUR');

      expect(
        MoneyFormatter.format(money, locale: 'en', privacy: true),
        '€••••••',
      );
      expect(
        MoneyFormatter.format(money, locale: 'de', privacy: true),
        '•••••• €',
      );
    });

    test('a decimal follows the language too', () {
      expect(MoneyFormatter.formatDecimal('12.50', locale: 'de'), '12,50');
      expect(MoneyFormatter.formatDecimal('12.50', locale: 'uk'), '12,50');
      expect(MoneyFormatter.formatDecimal('12.50', locale: 'en'), '12.50');
      expect(MoneyFormatter.formatPercent('5.96', locale: 'de'), '5,96%');
    });

    test('preserves sign semantics and masks the full amount', () {
      final money = Money(amount: '1082.80', currency: 'EUR');

      expect(
        MoneyFormatter.format(money, locale: 'ru', showPositiveSign: true),
        '+1 082,80 €',
      );
      expect(
        MoneyFormatter.format(money, locale: 'ru', privacy: true),
        '•••••• €',
      );
    });

    test('a zero amount claims no direction', () {
      // After a month with only a transfer the delta is zero, and «+0,00 €»
      // would announce a gain that did not happen.
      final zero = Money(amount: '0.00', currency: 'EUR');

      expect(
        MoneyFormatter.format(zero, locale: 'ru', showPositiveSign: true),
        '0,00 €',
      );
      expect(
        MoneyFormatter.format(
          Money(amount: '-0.00', currency: 'EUR'),
          locale: 'ru',
          showPositiveSign: true,
        ),
        '0,00 €',
      );
    });

    test('masks a percentage in privacy mode', () {
      expect(
        MoneyFormatter.formatPercent(
          '5.96',
          locale: 'ru',
          privacy: true,
          showPositiveSign: true,
        ),
        '••••••%',
      );
    });

    test('a percent shows at most three decimals, never the padding', () {
      // The server's percent column is NUMERIC(38, 18), and «−0,07%» once
      // reached the screen as «−0,0700000000000000%».
      expect(
        MoneyFormatter.formatPercent(
          '-0.070000000000000000',
          locale: 'ru',
          showPositiveSign: true,
        ),
        '−0,07%',
      );
      expect(MoneyFormatter.formatPercent('12.3456', locale: 'ru'), '12,346%');
      expect(MoneyFormatter.formatPercent('5', locale: 'ru'), '5%');
      expect(MoneyFormatter.formatPercent('5.96', locale: 'en'), '5.96%');
    });

    test('rounding a percent carries into the whole part', () {
      expect(MoneyFormatter.formatPercent('0.9996', locale: 'ru'), '1%');
      expect(MoneyFormatter.formatPercent('-9.9999', locale: 'ru'), '−10%');
    });

    test('a percent that rounds to zero has no sign at all', () {
      // «−0%» or «+0%» would each claim a direction the number does not have.
      expect(
        MoneyFormatter.formatPercent(
          '-0.0004',
          locale: 'ru',
          showPositiveSign: true,
        ),
        '0%',
      );
      expect(
        MoneyFormatter.formatPercent(
          '0.00',
          locale: 'ru',
          showPositiveSign: true,
        ),
        '0%',
      );
    });

    test('a positive percent keeps its plus when asked for one', () {
      expect(
        MoneyFormatter.formatPercent(
          '2.5',
          locale: 'ru',
          showPositiveSign: true,
        ),
        '+2,5%',
      );
    });
  });

  group('an exact amount on a confirmation card', () {
    final dollars = Money(amount: '1250.5', currency: 'USD');

    test('is written the way the language writes a number', () {
      expect(MoneyFormatter.formatExact(dollars, locale: 'en'), r'$1,250.5');
      expect(MoneyFormatter.formatExact(dollars, locale: 'de'), r'1.250,5 $');
      expect(MoneyFormatter.formatExact(dollars, locale: 'ru'), r'1 250,5 $');
    });

    test('keeps every digit that was entered', () {
      expect(
        MoneyFormatter.formatExact(
          Money(amount: '0.125', currency: 'EUR'),
          locale: 'ru',
        ),
        '0,125 €',
      );
    });

    test('adds no decimals nobody entered', () {
      expect(
        MoneyFormatter.formatExact(
          Money(amount: '100', currency: 'UAH'),
          locale: 'ru',
        ),
        '100 UAH',
      );
    });

    test('carries a sign only when there is something to sign', () {
      expect(
        MoneyFormatter.formatExact(
          Money(amount: '-3.50', currency: 'EUR'),
          locale: 'ru',
        ),
        '−3,50 €',
      );
      expect(
        MoneyFormatter.formatExact(
          Money(amount: '-0', currency: 'EUR'),
          locale: 'ru',
        ),
        '0 €',
      );
    });

    test('hides the amount in privacy mode', () {
      expect(
        MoneyFormatter.formatExact(dollars, locale: 'en', privacy: true),
        r'$••••••',
      );
    });
  });
}
