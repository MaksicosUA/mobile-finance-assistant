import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/widgets/category_picker.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _groceriesId = '11111111-1111-4111-8111-111111111111';
const _transportId = '22222222-2222-4222-8222-222222222222';
const _salaryId = '33333333-3333-4333-8333-333333333333';
const _renamedId = '44444444-4444-4444-8444-444444444444';

FinanceCategory _category({
  required String id,
  required String name,
  required FinanceOperationType direction,
  String? systemKey,
}) => FinanceCategory(
  categoryId: id,
  name: name,
  direction: direction,
  systemKey: systemKey,
);

final _catalogue = FinanceCategoryList(
  categories: [
    _category(
      id: _groceriesId,
      name: 'Продукты',
      direction: FinanceOperationType.expense,
      systemKey: 'groceries',
    ),
    _category(
      id: _transportId,
      name: 'Транспорт',
      direction: FinanceOperationType.expense,
      systemKey: 'transport',
    ),
    _category(
      id: _salaryId,
      name: 'Зарплата',
      direction: FinanceOperationType.income,
      systemKey: 'salary',
    ),
  ],
);

void main() {
  group('catalogue filtering', () {
    test('a direction is offered only its own categories', () {
      // A purchase must never be offered a salary category: the server would
      // reject it, and the user would not know why.
      final expense = _catalogue.forDirection(FinanceOperationType.expense);
      expect(expense.map((item) => item.categoryId), [
        _groceriesId,
        _transportId,
      ]);
      expect(
        _catalogue.forDirection(FinanceOperationType.income).single.categoryId,
        _salaryId,
      );
    });
  });

  group('labels', () {
    testWidgets('a seeded category follows the app language', (tester) async {
      late AppLocalizations l10n;
      await _pump(tester, onBuilt: (value) => l10n = value);

      expect(
        categoryLabel(
          l10n,
          _category(
            id: _groceriesId,
            name: 'ignored-stored-name',
            direction: FinanceOperationType.expense,
            systemKey: 'groceries',
          ),
        ),
        'Продукты',
      );
    });

    testWidgets('a renamed category shows the name the user chose', (
      tester,
    ) async {
      late AppLocalizations l10n;
      await _pump(tester, onBuilt: (value) => l10n = value);

      // No key means the user renamed it, so translating would contradict them.
      expect(
        categoryLabel(
          l10n,
          _category(
            id: _renamedId,
            name: 'Кофе по утрам',
            direction: FinanceOperationType.expense,
          ),
        ),
        'Кофе по утрам',
      );
    });

    testWidgets('an unknown key falls back to the stored name', (tester) async {
      late AppLocalizations l10n;
      await _pump(tester, onBuilt: (value) => l10n = value);

      // The server seeded something this build predates; the raw key must
      // never reach the screen.
      expect(
        categoryLabel(
          l10n,
          _category(
            id: _renamedId,
            name: 'Подписки',
            direction: FinanceOperationType.expense,
            systemKey: 'subscriptions',
          ),
        ),
        'Подписки',
      );
    });
  });

  group('picker', () {
    testWidgets('choosing a category reports it upward', (tester) async {
      CategoryChoice? reported;
      await _pumpPicker(tester, onChanged: (choice) => reported = choice);

      await tester.tap(find.byKey(const Key('operation-category-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Транспорт').last);
      await tester.pumpAndSettle();

      expect(reported, isA<CategoryFromCatalogue>());
      expect(
        (reported! as CategoryFromCatalogue).category.categoryId,
        _transportId,
      );
    });

    testWidgets('free text stays reachable so entry is never blocked', (
      tester,
    ) async {
      CategoryChoice choice = const CategoryUnset();
      await _pumpPicker(
        tester,
        choiceOf: () => choice,
        onChanged: (value) => choice = value,
      );

      // No text field until the user asks for one: two inputs for one concept
      // would be confusing.
      expect(find.byKey(const Key('operation-category')), findsNothing);

      await tester.tap(find.byKey(const Key('operation-category-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Другое (ввести текстом)').last);
      await tester.pumpAndSettle();

      expect(choice, isA<CategoryFreeText>());
      expect(find.byKey(const Key('operation-category')), findsOneWidget);
    });

    testWidgets('an unreadable catalogue degrades to plain text', (
      tester,
    ) async {
      // Losing the picker must not stop a user from recording money.
      await _pumpPicker(tester, catalogueUnavailable: true);

      expect(find.byKey(const Key('operation-category')), findsOneWidget);
      expect(find.byKey(const Key('operation-category-picker')), findsNothing);
      expect(
        find.text('Список категорий недоступен — впишите название вручную.'),
        findsOneWidget,
      );
    });

    testWidgets('a disabled picker cannot be changed while submitting', (
      tester,
    ) async {
      CategoryChoice? reported;
      await _pumpPicker(
        tester,
        enabled: false,
        onChanged: (choice) => reported = choice,
      );

      await tester.tap(find.byKey(const Key('operation-category-picker')));
      await tester.pumpAndSettle();

      expect(reported, isNull);
    });

    testWidgets('the picker fits 360 dp at 200 percent text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpPicker(tester, textScale: 2);

      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ValueChanged<AppLocalizations> onBuilt,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          onBuilt(AppLocalizations.of(context));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  CategoryChoice Function()? choiceOf,
  ValueChanged<CategoryChoice>? onChanged,
  bool catalogueUnavailable = false,
  bool enabled = true,
  double textScale = 1,
}) async {
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  var choice = const CategoryUnset() as CategoryChoice;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: CategoryPicker(
              categories: _catalogue.forDirection(FinanceOperationType.expense),
              choice: choiceOf?.call() ?? choice,
              freeTextController: controller,
              enabled: enabled,
              catalogueUnavailable: catalogueUnavailable,
              onChanged: (value) {
                onChanged?.call(value);
                setState(() => choice = value);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
