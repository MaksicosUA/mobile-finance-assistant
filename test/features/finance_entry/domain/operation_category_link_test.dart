import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';

const _commandId = '44444444-4444-4444-8444-444444444444';
const _accountId = '22222222-2222-4222-8222-222222222222';
const _categoryId = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> _draftJson({bool withLink = true}) {
  final json = <String, Object?>{
    'schemaVersion': '1',
    'commandId': _commandId,
    'type': 'expense',
    'amount': '25.00',
    'currency': 'EUR',
    'accountId': _accountId,
    'category': 'Продукты',
    'categoryId': _categoryId,
    'merchant': null,
    'capturedAt': '2026-08-11T12:00:00.000Z',
    'capturedTimezone': 'Europe/Berlin',
    'sourceExpression': null,
    'dateResolverVersion': 'calendar-relative-v1',
    'occurredOn': '2026-08-11',
    'occurredAt': null,
    'source': 'manual_text',
  };
  if (!withLink) json.remove('categoryId');
  return json;
}

void main() {
  group('operation category link', () {
    test('a draft carries the link beside the text the user wrote', () {
      final draft = FinanceOperationDraft.fromJson(_draftJson());
      expect(draft.categoryId, _categoryId);
      // The text is evidence of intent and is never replaced by the link.
      expect(draft.category, 'Продукты');
    });

    test('a command stored before the link existed still loads', () {
      // The encrypted outbox persists a command before its first send, so an
      // app update must not make an older stored command unreadable — that
      // would trip the fail-closed delivery lock over a field it never needed.
      final draft = FinanceOperationDraft.fromJson(_draftJson(withLink: false));
      expect(draft.categoryId, isNull);
      expect(draft.category, 'Продукты');
    });

    test('an older stored command is replayed byte-for-byte', () {
      // Canonical bytes must survive the round trip, or the draft hash the
      // server already issued would no longer match on delivery.
      final stored = _draftJson(withLink: false);
      final replayed = FinanceOperationDraft.fromJson(stored).toJson();
      expect(replayed, stored);
      expect(replayed.containsKey('categoryId'), isFalse);
    });

    test('an unknown field is still refused', () {
      expect(
        () => FinanceOperationDraft.fromJson({
          ..._draftJson(),
          'categoryName': 'Продукты',
        }),
        throwsFormatException,
      );
    });

    test('a malformed link is refused rather than dropped', () {
      expect(
        () => FinanceOperationDraft.fromJson({
          ..._draftJson(),
          'categoryId': 'not-a-uuid',
        }),
        throwsFormatException,
      );
    });

    test('a locally built draft sends the link explicitly', () {
      final draft = FinanceOperationDraft(
        commandId: _commandId,
        type: FinanceOperationType.expense,
        amount: '25.00',
        currency: 'EUR',
        accountId: _accountId,
        category: 'Продукты',
        categoryId: _categoryId,
        merchant: null,
        capturedAt: '2026-08-11T12:00:00.000Z',
        capturedTimezone: 'Europe/Berlin',
        sourceExpression: null,
        occurredOn: '2026-08-11',
        occurredAt: null,
        source: FinanceOperationSource.manualText,
      );
      expect(draft.toJson()['categoryId'], _categoryId);
      // Absence is expressed as an explicit null, never by omitting the key.
      final unlinked = FinanceOperationDraft(
        commandId: _commandId,
        type: FinanceOperationType.expense,
        amount: '25.00',
        currency: 'EUR',
        accountId: _accountId,
        category: null,
        merchant: null,
        capturedAt: '2026-08-11T12:00:00.000Z',
        capturedTimezone: 'Europe/Berlin',
        sourceExpression: null,
        occurredOn: '2026-08-11',
        occurredAt: null,
        source: FinanceOperationSource.manualText,
      );
      expect(unlinked.toJson().containsKey('categoryId'), isTrue);
      expect(unlinked.toJson()['categoryId'], isNull);
    });

    test('a committed operation without a link still parses', () {
      final json = <String, Object?>{
        'operationId': '66666666-6666-4666-8666-666666666666',
        'userId': '11111111-1111-4111-8111-111111111111',
        'commandId': _commandId,
        'type': 'expense',
        'amount': '25.00',
        'currency': 'EUR',
        'accountId': _accountId,
        'category': 'Продукты',
        'merchant': null,
        'capturedAt': '2026-08-11T12:00:00.000Z',
        'capturedTimezone': 'Europe/Berlin',
        'sourceExpression': null,
        'dateResolverVersion': 'calendar-relative-v1',
        'occurredOn': '2026-08-11',
        'occurredAt': null,
        'source': 'manual_text',
        'status': 'confirmed',
        'confirmedAt': '2026-08-11T12:00:01.000Z',
        'createdAt': '2026-08-11T12:00:01.000Z',
      };
      expect(CommittedFinanceOperation.fromJson(json).categoryId, isNull);
      expect(
        CommittedFinanceOperation.fromJson({
          ...json,
          'categoryId': _categoryId,
        }).categoryId,
        _categoryId,
      );
    });
  });
}
