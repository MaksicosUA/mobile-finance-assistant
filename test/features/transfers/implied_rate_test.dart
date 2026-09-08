import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/transfers/domain/implied_rate.dart';

/// The rate is never stored and never sent (ADR 0029). It is worked out from
/// the two amounts at the moment of drawing, so it has to be exact.
void main() {
  test('the rate is what the two amounts say, both ways round', () {
    final rate = impliedRate(from: '100.00', to: '4800.00');

    expect(rate?.value, '48.0000');
    expect(rate?.inverse, '0.0208');
  });

  test('it is exact, not floating point', () {
    final rate = impliedRate(from: '0.30', to: '0.10');

    expect(rate?.value, '0.3333');
  });

  test('a very large amount does not overflow', () {
    final rate = impliedRate(from: '1', to: '99999999999999999999');

    expect(rate?.value, '99999999999999999999.0000');
  });

  test('scales that differ are still exact', () {
    expect(impliedRate(from: '2', to: '1.5')?.value, '0.7500');
    expect(impliedRate(from: '1.5', to: '3')?.value, '2.0000');
  });

  test('there is no rate to state when there is no amount', () {
    for (final pair in const [
      ('', '100'),
      ('100', ''),
      ('0', '100'),
      ('100', '0'),
      ('0.00', '100'),
      ('abc', '100'),
      ('1.2.3', '100'),
      ('-100', '100'),
      ('100.', '100'),
    ]) {
      expect(
        impliedRate(from: pair.$1, to: pair.$2),
        isNull,
        reason: '${pair.$1} -> ${pair.$2}',
      );
    }
  });
}
