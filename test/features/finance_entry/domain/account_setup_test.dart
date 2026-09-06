import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';

/// The timezone revision counts how many times the zone has been settled, and
/// correcting it raises the number (ADR 0028). A client that reads it as a
/// flag stops loading the account the first time someone moves.
const _hryvnia = '55555555-5555-4555-8555-555555555555';

void main() {
  FinanceAccount account({
    String timezone = 'Europe/Lisbon',
    String id = '11111111-1111-4111-8111-111111111111',
    String currency = 'EUR',
    bool isDefault = true,
  }) => FinanceAccount(
    accountId: id,
    userId: '22222222-2222-4222-8222-222222222222',
    commandId: '33333333-3333-4333-8333-333333333333',
    name: 'Основной',
    currency: currency,
    openingBalance: '0',
    openingBalanceOn: '2024-01-01',
    openingTimezone: timezone,
    isDefault: isDefault,
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

  // Several wallets, one currency each (ADR 0029).
  test('a second wallet loads, and the default is the one that is flagged', () {
    final setup = FinanceAccountSetup(
      canonicalTimezone: 'Europe/Lisbon',
      timezoneRevision: 2,
      accounts: [
        account(id: _hryvnia, currency: 'UAH', isDefault: false),
        account(),
      ],
    );

    expect(setup.accounts, hasLength(2));
    // Not the first row: the wire promises no order.
    expect(setup.account?.currency, 'EUR');
  });

  test('exactly one wallet is the default', () {
    expect(
      () => FinanceAccountSetup(
        canonicalTimezone: 'Europe/Lisbon',
        timezoneRevision: 1,
        accounts: [
          account(),
          account(id: _hryvnia, currency: 'UAH'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => FinanceAccountSetup(
        canonicalTimezone: 'Europe/Lisbon',
        timezoneRevision: 1,
        accounts: [account(isDefault: false)],
      ),
      throwsFormatException,
    );
  });

  test('every wallet draws its months in the same zone', () {
    expect(
      () => FinanceAccountSetup(
        canonicalTimezone: 'Europe/Lisbon',
        timezoneRevision: 1,
        accounts: [
          account(),
          account(
            id: _hryvnia,
            currency: 'UAH',
            isDefault: false,
            timezone: 'Europe/Kyiv',
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('a wallet that is not the default is a real account on the wire', () {
    final parsed = FinanceAccount.fromJson(const {
      'accountId': _hryvnia,
      'userId': '22222222-2222-4222-8222-222222222222',
      'commandId': '33333333-3333-4333-8333-333333333333',
      'name': 'Гривна',
      'currency': 'UAH',
      'openingBalance': '0',
      'openingBalanceOn': '2024-01-01',
      'openingTimezone': 'Europe/Lisbon',
      'status': 'active',
      'isDefault': false,
      'confirmedAt': '2026-09-01T12:00:00Z',
      'createdAt': '2026-09-01T12:00:00Z',
    });

    expect(parsed.isDefault, isFalse);
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
