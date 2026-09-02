import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';

/// The timezone revision counts how many times the zone has been settled, and
/// correcting it raises the number (ADR 0028). A client that reads it as a
/// flag stops loading the account the first time someone moves.
void main() {
  FinanceAccount account({String timezone = 'Europe/Lisbon'}) => FinanceAccount(
    accountId: '11111111-1111-4111-8111-111111111111',
    userId: '22222222-2222-4222-8222-222222222222',
    commandId: '33333333-3333-4333-8333-333333333333',
    name: 'Основной',
    currency: 'EUR',
    openingBalance: '0',
    openingBalanceOn: '2024-01-01',
    openingTimezone: timezone,
    confirmedAt: '2026-09-01T12:00:00Z',
    createdAt: '2026-09-01T12:00:00Z',
  );

  test('a corrected timezone still reads as a settled account', () {
    for (final revision in const [1, 2, 7]) {
      final setup = FinanceAccountSetup(
        canonicalTimezone: 'Europe/Lisbon',
        timezoneRevision: revision,
        accounts: [account()],
      );

      expect(setup.isInitialized, isTrue);
      expect(setup.canonicalTimezone, 'Europe/Lisbon');
    }
  });

  test('an unsettled timezone is still refused', () {
    expect(
      () => FinanceAccountSetup(
        canonicalTimezone: 'Europe/Lisbon',
        timezoneRevision: 0,
        accounts: [account()],
      ),
      throwsFormatException,
    );
    expect(
      () => FinanceAccountSetup(
        canonicalTimezone: null,
        timezoneRevision: 2,
        accounts: [account()],
      ),
      throwsFormatException,
    );
  });

  test('the two copies of the timezone must still agree', () {
    expect(
      () => FinanceAccountSetup(
        canonicalTimezone: 'Europe/Lisbon',
        timezoneRevision: 2,
        accounts: [account(timezone: 'Europe/Kyiv')],
      ),
      throwsFormatException,
    );
  });
}
