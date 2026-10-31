import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/core/money/entered_amount.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';

void main() {
  test('a separator before exactly three digits groups thousands', () {
    expect(enteredAmountText('1,250'), '1250');
    expect(enteredAmountText('1.250'), '1250');
    expect(enteredAmountText('1,250,000'), '1250000');
    expect(enteredAmountText('1.250.000'), '1250000');
  });

  test('a separator before one or two digits is the decimal point', () {
    expect(enteredAmountText('12,50'), '12.50');
    expect(enteredAmountText('12.50'), '12.50');
    expect(enteredAmountText('12,5'), '12.5');
  });

  test('with two separators the last one is the decimal point', () {
    expect(enteredAmountText('1,250.50'), '1250.50');
    expect(enteredAmountText('1.250,50'), '1250.50');
  });

  test('spaces of every kind are grouping', () {
    expect(enteredAmountText(' 1 250,50 '), '1250.50');
    expect(enteredAmountText('1 250'), '1250');
    expect(enteredAmountText('1 250'), '1250');
  });

  test('a bare zero is not a group of thousands', () {
    expect(enteredAmountText('0,125'), '0.125');
    expect(enteredAmountText('0.125'), '0.125');
  });

  test('a sign survives', () {
    expect(enteredAmountText('-1,250'), '-1250');
  });

  test('what makes no sense stays something the form refuses', () {
    expect(() => normalizeMoneyInput('1,25,50'), throwsFormatException);
    expect(() => normalizeMoneyInput('1.250.50'), throwsFormatException);
    expect(() => normalizeMoneyInput('abc'), throwsFormatException);
  });

  test('the entry form reads an English thousand as a thousand', () {
    expect(normalizeMoneyInput('1,250'), '1250');
    expect(normalizeMoneyInput('12,50'), '12.50');
  });
}
