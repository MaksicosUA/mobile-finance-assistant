import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';

const _groceriesId = '55555555-5555-4555-8555-555555555555';
const _hiddenId = '66666666-6666-4666-8666-666666666666';

Map<String, Object?> _json({
  String id = _groceriesId,
  String name = 'Продукты',
  String? systemKey = 'groceries',
  String? archivedAt,
}) => <String, Object?>{
  'categoryId': id,
  'name': name,
  'direction': 'expense',
  'systemKey': systemKey,
  'createdAt': '2026-08-11T12:00:00Z',
  'archivedAt': ?archivedAt,
};

void main() {
  group('parsing', () {
    test('a hidden category reports when it was hidden', () {
      final hidden = ManagedFinanceCategory.fromJson(
        _json(
          id: _hiddenId,
          name: 'Аренда',
          systemKey: null,
          archivedAt: '2026-08-12T12:00:00Z',
        ),
      );
      expect(hidden.isArchived, isTrue);
      expect(hidden.archivedAt, '2026-08-12T12:00:00Z');
    });

    test('an absent archive date means the category is offered', () {
      // Optional rather than required, so a payload written before the field
      // existed still loads.
      expect(ManagedFinanceCategory.fromJson(_json()).isArchived, isFalse);
      expect(
        ManagedFinanceCategory.fromJson(_json(archivedAt: null)).archivedAt,
        isNull,
      );
    });

    test('an unknown field is refused rather than ignored', () {
      expect(
        () => ManagedFinanceCategory.fromJson({
          ..._json(),
          'userId': _groceriesId,
        }),
        throwsFormatException,
      );
    });

    test('a missing required field is refused', () {
      final incomplete = _json()..remove('direction');
      expect(
        () => ManagedFinanceCategory.fromJson(incomplete),
        throwsFormatException,
      );
    });
  });

  group('grouping', () {
    test('hidden categories never appear among the offered ones', () {
      final catalogue = ManagedCategoryList(
        categories: [
          ManagedFinanceCategory.fromJson(_json()),
          ManagedFinanceCategory.fromJson(
            _json(
              id: _hiddenId,
              name: 'Аренда',
              systemKey: null,
              archivedAt: '2026-08-12T12:00:00Z',
            ),
          ),
        ],
      );

      expect(
        catalogue.offered(FinanceOperationType.expense).map((c) => c.name),
        ['Продукты'],
      );
      expect(
        catalogue.hidden(FinanceOperationType.expense).map((c) => c.name),
        ['Аренда'],
      );
      // An expense catalogue holds no income categories, so a purchase can
      // never be offered a salary category.
      expect(catalogue.offered(FinanceOperationType.income), isEmpty);
    });
  });

  group('name validation', () {
    test('a name is trimmed and bounded exactly as the server bounds it', () {
      expect(validatedCategoryName('  Кофе  '), 'Кофе');
      expect(validatedCategoryName('П' * 100), 'П' * 100);
      // The control character is an escape on purpose: a literal one is
      // invisible in review and survives copy-paste unnoticed.
      for (final rejected in ['', '   ', 'П' * 101, 'Ко\u0007фе']) {
        expect(
          () => validatedCategoryName(rejected),
          throwsFormatException,
          reason: 'must reject ${rejected.length} characters',
        );
      }
    });

    test('a create command carries only what the server accepts', () {
      const command = CreateCategoryCommand(
        name: 'Кофе',
        direction: FinanceOperationType.expense,
      );
      expect(command.toJson(), {
        'schemaVersion': '1',
        'name': 'Кофе',
        'direction': 'expense',
      });
      expect(const RenameCategoryCommand(name: 'Еда').toJson(), {
        'schemaVersion': '1',
        'name': 'Еда',
      });
    });
  });
}
