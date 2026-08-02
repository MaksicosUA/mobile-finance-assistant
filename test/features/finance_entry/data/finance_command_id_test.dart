import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_command_id.dart';

void main() {
  test('secure command ID factory emits distinct RFC 4122 UUIDv4 values', () {
    final values = List.generate(128, (_) => newFinanceCommandId());
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(values.toSet(), hasLength(values.length));
    expect(values, everyElement(matches(pattern)));
  });
}
