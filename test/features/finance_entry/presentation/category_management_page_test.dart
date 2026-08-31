import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/finance_entry/presentation/category_management_page.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

const _groceriesId = '11111111-1111-4111-8111-111111111111';
const _hiddenId = '44444444-4444-4444-8444-444444444444';
const _archivedAt = '2026-08-12T12:00:00Z';

void main() {
  testWidgets('offered categories are listed and hidden ones stay collapsed', (
    tester,
  ) async {
    await _pumpPage(tester, repository: _FakeRepository());

    // A seeded category renders its localized label, not the raw key.
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.byKey(const Key('category-row-$_groceriesId')), findsOneWidget);
    // Hidden rows are a recovery list, so they are behind one tap.
    expect(find.text('Аренда'), findsNothing);
    expect(find.byKey(const Key('categories-hidden-toggle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('categories-hidden-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Аренда'), findsOneWidget);
    expect(
      find.byKey(const Key('category-restore-$_hiddenId')),
      findsOneWidget,
    );
  });

  testWidgets('hiding asks first and says the old operations stay', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.tap(find.byKey(const Key('category-hide-$_groceriesId')));
    await tester.pumpAndSettle();

    // The dialog states the consequence, because "delete" and "hide" look the
    // same from the outside and only one of them keeps history.
    expect(find.text('Скрыть категорию?'), findsOneWidget);
    expect(
      find.textContaining('Прошлые операции останутся в ней'),
      findsOneWidget,
    );
    expect(repository.archived, isEmpty);

    await tester.tap(find.byKey(const Key('category-hide-confirm')));
    await tester.pumpAndSettle();

    expect(repository.archived, [_groceriesId]);
    // It left the offered list without leaving the catalogue.
    expect(find.byKey(const Key('category-row-$_groceriesId')), findsNothing);
    expect(find.byKey(const Key('categories-hidden-toggle')), findsOneWidget);
  });

  testWidgets('cancelling the dialog hides nothing', (tester) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.tap(find.byKey(const Key('category-hide-$_groceriesId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(repository.archived, isEmpty);
    expect(find.byKey(const Key('category-row-$_groceriesId')), findsOneWidget);
  });

  testWidgets('renaming opens a field holding the stored name', (tester) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);

    await tester.tap(find.byKey(const Key('category-rename-$_groceriesId')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('category-rename-field-$_groceriesId')),
    );
    expect(field.controller?.text, 'Продукты');

    await tester.enterText(
      find.byKey(const Key('category-rename-field-$_groceriesId')),
      'Еда',
    );
    await tester.tap(
      find.byKey(const Key('category-rename-submit-$_groceriesId')),
    );
    await tester.pumpAndSettle();

    expect(repository.renamed[_groceriesId], 'Еда');
    expect(find.text('Еда'), findsOneWidget);
  });

  testWidgets('a taken name is shown next to the form, not swallowed', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        writeFailure: FinanceEntryErrorCode.categoryNameTaken,
      ),
    );

    await tester.tap(find.byKey(const Key('categories-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('categories-new-name')),
      'Транспорт',
    );
    await tester.tap(find.byKey(const Key('categories-create-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('categories-failure-note')), findsOneWidget);
    expect(find.text('Такое название уже есть'), findsOneWidget);
    // Never colour alone.
    expect(
      find.descendant(
        of: find.byKey(const Key('categories-failure-note')),
        matching: find.byIcon(Icons.error_outline_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable catalogue offers a retry', (tester) async {
    await _pumpPage(
      tester,
      repository: _FakeRepository(
        listFailure: FinanceEntryFailureKind.serviceUnavailable,
      ),
    );

    expect(find.byKey(const Key('categories-failure')), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
  });

  testWidgets('the screen fits 360 dp at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpPage(tester, repository: _FakeRepository(), textScale: 2);

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('categories-hidden-toggle')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('a pull re-reads the screen', (tester) async {
    final repository = _FakeRepository();
    await _pumpPage(tester, repository: repository);
    await tester.fling(
      find.byKey(const Key('categories-page')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeRepository repository,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financeEntryRepositoryProvider.overrideWithValue(repository),
        homeRepositoryProvider.overrideWithValue(const _FirstUseHome()),
        homeSessionStoreProvider.overrideWithValue(
          const _NullHomeSessionStore(),
        ),
        acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
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
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
        home: CategoryManagementPage(onSignInRequested: () async {}),
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

  _FakeRepository({this.listFailure, this.writeFailure});

  final FinanceEntryFailureKind? listFailure;
  final FinanceEntryErrorCode? writeFailure;
  final List<String> archived = [];
  int listCalls = 0;
  final Map<String, String> renamed = {};

  late final List<ManagedFinanceCategory> _categories = [
    _category(_groceriesId, 'Продукты', systemKey: 'groceries'),
    _category('22222222-2222-4222-8222-222222222222', 'Транспорт'),
    _category(_hiddenId, 'Аренда', archivedAt: _archivedAt),
  ];

  @override
  Future<FinanceEntryResult<ManagedCategoryList>>
  listManagedCategories() async {
    listCalls += 1;
    if (listFailure != null) {
      return FinanceEntryFailureResult<ManagedCategoryList>(
        FinanceEntryFailure(kind: listFailure!, requestId: _requestId),
      );
    }
    return FinanceEntrySuccess<ManagedCategoryList>(
      requestId: _requestId,
      value: ManagedCategoryList(categories: _categories),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory(
    CreateCategoryCommand command,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    final created = _category('created', command.name);
    _categories.add(created);
    return _accepted(created);
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory(
    String categoryId,
    RenameCategoryCommand command,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    renamed[categoryId] = command.name;
    return _accepted(_replace(categoryId, name: command.name));
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory(
    String categoryId,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    archived.add(categoryId);
    return _accepted(_replace(categoryId, archivedAt: _archivedAt));
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory(
    String categoryId,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    return _accepted(_replace(categoryId, clearArchived: true));
  }

  FinanceEntryFailureResult<ManagedFinanceCategory>? _refusal() {
    if (writeFailure == null) return null;
    return FinanceEntryFailureResult<ManagedFinanceCategory>(
      FinanceEntryFailure(
        kind: FinanceEntryFailureKind.conflict,
        requestId: _requestId,
        code: writeFailure,
      ),
    );
  }

  FinanceEntrySuccess<ManagedFinanceCategory> _accepted(
    ManagedFinanceCategory category,
  ) => FinanceEntrySuccess<ManagedFinanceCategory>(
    requestId: _requestId,
    value: category,
  );

  ManagedFinanceCategory _replace(
    String categoryId, {
    String? name,
    String? archivedAt,
    bool clearArchived = false,
  }) {
    final index = _categories.indexWhere(
      (item) => item.categoryId == categoryId,
    );
    final current = _categories[index];
    final updated = ManagedFinanceCategory(
      categoryId: current.categoryId,
      name: name ?? current.name,
      direction: current.direction,
      systemKey: name == null ? current.systemKey : null,
      archivedAt: clearArchived ? null : (archivedAt ?? current.archivedAt),
    );
    _categories[index] = updated;
    return updated;
  }

  static const String _requestId = 'req_synthetic_category';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ManagedFinanceCategory _category(
  String id,
  String name, {
  String? systemKey,
  String? archivedAt,
}) => ManagedFinanceCategory(
  categoryId: id,
  name: name,
  direction: FinanceOperationType.expense,
  systemKey: systemKey,
  archivedAt: archivedAt,
);

/// A rename converges Home, so the screen reaches the real Home controller.
/// Without a stand-in it would start a live fetch the test never finishes.
class _FirstUseHome implements HomeRepository, HomeCacheInvalidator {
  const _FirstUseHome();

  @override
  Future<void> invalidateHomeCache() async {}

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    return HomeFirstUseResult(
      HomeFirstUseData(userName: 'Тест', availableActions: const {}),
    );
  }
}

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
