import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/features/home/presentation/money_formatter.dart';

void main() {
  group('MoneyFormatter', () {
    test('formats decimal strings for the Russian locale without double', () {
      final money = Money(amount: '1930.00', currency: 'EUR');

      expect(MoneyFormatter.format(money, locale: 'ru'), '1 930,00 €');
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
  });
}
