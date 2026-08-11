import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_command_id.dart';

const _planA = '55555555-5555-4555-8555-555555555555';
const _planB = '66666666-6666-4666-8666-666666666666';

void main() {
  group('plannedCostOperationCommandId', () {
    test('is stable for the same plan across app restarts', () {
      // This is the whole point: a retry after a lost transition must replay
      // the same operation instead of committing a second one.
      expect(
        plannedCostOperationCommandId(_planA),
        plannedCostOperationCommandId(_planA),
      );
    });

    test('differs between plans', () {
      expect(
        plannedCostOperationCommandId(_planA),
        isNot(plannedCostOperationCommandId(_planB)),
      );
    });

    test('never returns the plan id itself', () {
      // Reusing the plan id would collide with the plan's own command space.
      expect(plannedCostOperationCommandId(_planA), isNot(_planA));
    });

    test('produces a contract-shaped v4 identifier', () {
      final id = plannedCostOperationCommandId(_planA);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'server contracts validate a UUID shape',
      );
    });

    test('accepts an upper-case plan id and rejects a malformed one', () {
      expect(
        plannedCostOperationCommandId(_planA.toUpperCase()),
        plannedCostOperationCommandId(_planA),
      );
      expect(
        () => plannedCostOperationCommandId('not-a-uuid'),
        throwsFormatException,
      );
    });
  });
}
