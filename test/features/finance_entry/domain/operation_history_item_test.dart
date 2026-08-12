import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';

const _operationId = '11111111-1111-4111-8111-111111111111';
const _categoryId = '55555555-5555-4555-8555-555555555555';

Map<String, Object?> _json({
  String? category = 'Кофе и чай',
  String? categoryId = _categoryId,
  String? categoryText = 'Кофе',
  String type = 'expense',
  String status = 'confirmed',
}) => <String, Object?>{
  'operationId': _operationId,
  'type': type,
  'amount': '42.00',
  'currency': 'EUR',
  'accountId': null,
  'category': category,
  'categoryId': categoryId,
  'categoryText': categoryText,
  'merchant': null,
  'occurredOn': '2026-08-12',
  'occurredAt': null,
  'source': 'manual_text',
  'status': status,
  'createdAt': '2026-08-12T12:00:00Z',
};

void main() {
  group('parsing', () {
    test('the current name and the written text are both kept', () {
      final item = OperationHistoryItem.fromJson(_json());
      expect(item.category, 'Кофе и чай');
      expect(item.categoryText, 'Кофе');
      expect(item.categoryId, _categoryId);
      // The pair the detail card exists to show side by side.
      expect(item.textDiffersFromCategory, isTrue);
    });

    test('an unchanged name is not worth repeating', () {
      final item = OperationHistoryItem.fromJson(
        _json(category: 'Продукты', categoryText: 'Продукты'),
      );
      expect(item.textDiffersFromCategory, isFalse);
    });

    test('an operation with no link keeps only what was written', () {
      // With no link the server echoes the written text into both fields,
      // because the text is the only thing there is to resolve.
      final item = OperationHistoryItem.fromJson(
        _json(
          category: 'Наличными',
          categoryId: null,
          categoryText: 'Наличными',
        ),
      );
      expect(item.categoryId, isNull);
      expect(item.category, 'Наличными');
      // Nothing to compare against, so there is nothing extra to show.
      expect(item.textDiffersFromCategory, isFalse);
    });

    test('a fully uncategorized operation is representable', () {
      final item = OperationHistoryItem.fromJson(
        _json(category: null, categoryId: null, categoryText: null),
      );
      expect(item.category, isNull);
      expect(item.categoryText, isNull);
      expect(item.textDiffersFromCategory, isFalse);
    });

    test('an unknown field is refused rather than ignored', () {
      expect(
        () =>
            OperationHistoryItem.fromJson({..._json(), 'userId': _operationId}),
        throwsFormatException,
      );
    });

    test('a missing field is refused', () {
      final incomplete = _json()..remove('currency');
      expect(
        () => OperationHistoryItem.fromJson(incomplete),
        throwsFormatException,
      );
    });

    test('only confirmed operations are readable', () {
      // Nothing else reaches this endpoint today, and quietly rendering some
      // other status as if it were settled money would be worse than failing.
      expect(
        () => OperationHistoryItem.fromJson(_json(status: 'pending')),
        throwsFormatException,
      );
    });

    test('an unknown direction is refused', () {
      expect(
        () => OperationHistoryItem.fromJson(_json(type: 'transfer')),
        throwsFormatException,
      );
    });
  });

  group('cursor', () {
    test('a cursor is opaque, bounded, and URL-safe', () {
      expect(validatedOperationCursor('MjAyNi0wOC0xMg'), 'MjAyNi0wOC0xMg');
      for (final rejected in ['', 'has space', 'has/slash', 'a' * 257]) {
        expect(
          () => validatedOperationCursor(rejected),
          throwsFormatException,
          reason: 'must reject "$rejected"',
        );
      }
    });
  });
}
