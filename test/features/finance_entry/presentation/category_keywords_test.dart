import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings_controller.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/category_keywords_page.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _categoryId = '22222222-2222-4222-8222-222222222222';

/// Teaching a category the words that lead to it (ADR 0020 step 3).
void main() {
  testWidgets('the words a category already knows are listed', (tester) async {
    await _pump(tester, _FakeRepository(current: const ['авто', 'машин']));

    expect(find.byKey(const Key('category-keyword-авто')), findsOneWidget);
    expect(find.byKey(const Key('category-keyword-машин')), findsOneWidget);
    expect(find.byKey(const Key('category-keywords-empty')), findsNothing);
  });

  testWidgets('a category with no words says so plainly', (tester) async {
    await _pump(tester, _FakeRepository());

    expect(find.byKey(const Key('category-keywords-empty')), findsOneWidget);
  });

  testWidgets('adding a word sends the whole set, not just the new one', (
    tester,
  ) async {
    final repository = _FakeRepository(current: const ['авто']);
    await _pump(tester, repository);

    await tester.enterText(
      find.byKey(const Key('category-keyword-field')),
      'Заправ',
    );
    await tester.tap(find.byKey(const Key('category-keyword-add')));
    await tester.pumpAndSettle();

    // Replacing keeps the write idempotent by target state, and the word is
    // stored in one spelling so matching cannot depend on how it was typed.
    expect(repository.replaced, [
      ['авто', 'заправ'],
    ]);
    expect(find.byKey(const Key('category-keyword-заправ')), findsOneWidget);
  });

  testWidgets('removing a word sends the set without it', (tester) async {
    final repository = _FakeRepository(current: const ['авто', 'машин']);
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('category-keyword-remove-авто')));
    await tester.pumpAndSettle();

    expect(repository.replaced, [
      ['машин'],
    ]);
  });

  testWidgets('a word that leads elsewhere is refused, and nothing is lost', (
    tester,
  ) async {
    final repository = _FakeRepository(
      current: const ['авто'],
      failure: FinanceEntryFailure(
        kind: FinanceEntryFailureKind.conflict,
        requestId: 'req_synthetic',
        code: FinanceEntryErrorCode.categoryKeywordTaken,
      ),
    );
    await _pump(tester, repository);

    await tester.enterText(
      find.byKey(const Key('category-keyword-field')),
      'такси',
    );
    await tester.tap(find.byKey(const Key('category-keyword-add')));
    await tester.pumpAndSettle();

    expect(find.textContaining('уже ведёт в другую категорию'), findsOneWidget);
    // The vocabulary it already had must survive a refused addition.
    expect(find.byKey(const Key('category-keyword-авто')), findsOneWidget);
  });

  testWidgets('a malformed word never reaches the network', (tester) async {
    final repository = _FakeRepository(current: const ['авто']);
    await _pump(tester, repository);

    await tester.enterText(
      find.byKey(const Key('category-keyword-field')),
      'ав',
    );
    await tester.tap(find.byKey(const Key('category-keyword-add')));
    await tester.pumpAndSettle();

    expect(repository.replaced, isEmpty);
    expect(find.textContaining('от трёх букв'), findsOneWidget);
  });

  testWidgets('a failed read offers a retry', (tester) async {
    final repository = _FakeRepository(
      loadFailure: FinanceEntryFailureKind.timeout,
    );
    await _pump(tester, repository);

    expect(find.byKey(const Key('category-keywords-failure')), findsOneWidget);
    expect(find.byKey(const Key('category-keywords-retry')), findsOneWidget);
  });
  testWidgets('a pull re-reads the screen', (tester) async {
    final repository = _FakeRepository(current: const ['авто']);
    await _pump(tester, repository);
    await tester.fling(
      find.byKey(const Key('category-keywords-page')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
    // The words never leave the screen while they are being re-read.
    expect(find.text('авто'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, _FakeRepository repository) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialAppSettingsProvider.overrideWithValue(const AppSettings()),
        financeEntryRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(AppAccent.teal),
        home: CategoryKeywordsPage(
          categoryId: _categoryId,
          categoryName: 'Автомобиль',
          onSignInRequested: () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence(PlannedCostRecurrenceDraft draft) =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences() => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence(
    String recurrenceId,
    EndPlannedCostRecurrenceCommand command,
  ) => throw UnimplementedError();

  _FakeRepository({this.current = const [], this.failure, this.loadFailure});

  final List<String> current;
  final FinanceEntryFailure? failure;
  final FinanceEntryFailureKind? loadFailure;
  final List<List<String>> replaced = [];
  int listCalls = 0;

  @override
  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords(
    String categoryId,
  ) async {
    listCalls += 1;
    final kind = loadFailure;
    if (kind != null) {
      return FinanceEntryFailureResult<CategoryKeywords>(
        FinanceEntryFailure(kind: kind, requestId: 'req_synthetic'),
      );
    }
    return FinanceEntrySuccess<CategoryKeywords>(
      requestId: 'req_synthetic',
      value: CategoryKeywords(categoryId: categoryId, keywords: current),
    );
  }

  @override
  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords(
    String categoryId,
    List<String> keywords,
  ) async {
    final refusal = failure;
    if (refusal != null) {
      return FinanceEntryFailureResult<CategoryKeywords>(refusal);
    }
    replaced.add(List<String>.of(keywords));
    return FinanceEntrySuccess<CategoryKeywords>(
      requestId: 'req_synthetic',
      value: CategoryKeywords(categoryId: categoryId, keywords: keywords),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
