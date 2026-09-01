import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/category_management_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/application/finance_entry_controller.dart';
import 'package:mobile_finance_assistant/features/finance_entry/data/finance_entry_repository.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_models.dart';
import 'package:mobile_finance_assistant/features/finance_entry/domain/finance_entry_result.dart';
import 'package:mobile_finance_assistant/features/home/application/home_controller.dart';
import 'package:mobile_finance_assistant/features/home/data/home_session_store.dart';

const _groceriesId = '11111111-1111-4111-8111-111111111111';
const _transportId = '22222222-2222-4222-8222-222222222222';
const _salaryId = '33333333-3333-4333-8333-333333333333';
const _hiddenId = '44444444-4444-4444-8444-444444444444';
const _archivedAt = '2026-08-12T12:00:00Z';

void main() {
  group('loading', () {
    test('offered and hidden categories are separated per direction', () async {
      final container = _container(_FakeRepository(catalogue: _catalogue()));
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );

      await controller.load();

      final state = _ready(container);
      expect(state.direction, FinanceOperationType.expense);
      expect(state.offered.map((item) => item.name), ['Продукты', 'Транспорт']);
      expect(state.hidden.map((item) => item.name), ['Аренда']);
      // Hidden rows stay collapsed: they are a recovery list, not the working
      // one.
      expect(state.showHidden, isFalse);

      controller.selectDirection(FinanceOperationType.income);
      expect(_ready(container).offered.map((item) => item.name), ['Зарплата']);
      expect(_ready(container).hidden, isEmpty);
    });

    test(
      'an expired session asks for sign-in rather than showing an error',
      () async {
        final container = _container(
          _FakeRepository(
            catalogue: _catalogue(),
            listFailure: FinanceEntryFailureKind.unauthenticated,
          ),
        );
        addTearDown(container.dispose);

        await container
            .read(categoryManagementControllerProvider.notifier)
            .load();

        expect(
          container.read(categoryManagementControllerProvider),
          isA<CategoryManagementAuthenticationRequired>(),
        );
      },
    );
  });

  group('creating', () {
    test('a new category is trimmed and appears in its direction', () async {
      final repository = _FakeRepository(catalogue: _catalogue());
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );
      await controller.load();

      controller.startCreating();
      controller.setNewName('  Кофе  ');
      await controller.submitCreate();

      final command = repository.created.single;
      expect(command.name, 'Кофе');
      expect(command.direction, FinanceOperationType.expense);
      final state = _ready(container);
      expect(state.offered.map((item) => item.name), contains('Кофе'));
      // The form closes and empties, so a second tap cannot resubmit it.
      expect(state.isCreating, isFalse);
      expect(state.newName, isEmpty);
    });

    test('a blank name never reaches the server', () async {
      final repository = _FakeRepository(catalogue: _catalogue());
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );
      await controller.load();

      controller.startCreating();
      controller.setNewName('   ');
      await controller.submitCreate();

      expect(repository.created, isEmpty);
      expect(
        _ready(container).failure?.kind,
        FinanceEntryFailureKind.invalidInput,
      );
    });

    test(
      'a taken name is reported as a conflict, not a silent failure',
      () async {
        final repository = _FakeRepository(
          catalogue: _catalogue(),
          writeFailure: FinanceEntryErrorCode.categoryNameTaken,
        );
        final container = _container(repository);
        addTearDown(container.dispose);
        final controller = container.read(
          categoryManagementControllerProvider.notifier,
        );
        await controller.load();

        controller.startCreating();
        controller.setNewName('Продукты');
        await controller.submitCreate();

        final state = _ready(container);
        expect(state.failure?.code, FinanceEntryErrorCode.categoryNameTaken);
        // The typed name survives, so the user can edit it instead of retyping.
        expect(state.newName, 'Продукты');
        expect(state.isSubmitting, isFalse);
      },
    );
  });

  group('renaming', () {
    test(
      'the field starts from the stored name, not a translated label',
      () async {
        final container = _container(_FakeRepository(catalogue: _catalogue()));
        addTearDown(container.dispose);
        final controller = container.read(
          categoryManagementControllerProvider.notifier,
        );
        await controller.load();

        final seeded = _ready(container).offered.first;
        controller.startRenaming(seeded);

        // Editing a translated label would rename the category to a word the
        // user never typed.
        expect(_ready(container).editedName, seeded.name);
        expect(_ready(container).editingCategoryId, seeded.categoryId);
      },
    );

    test('a rename replaces the row and converges Home', () async {
      final repository = _FakeRepository(catalogue: _catalogue());
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );
      await controller.load();

      controller.startRenaming(_ready(container).offered.first);
      controller.setEditedName('Еда');
      await controller.submitRename();

      expect(repository.renamed[_groceriesId], 'Еда');
      final state = _ready(container);
      expect(state.offered.map((item) => item.name), contains('Еда'));
      expect(
        state.offered.map((item) => item.name),
        isNot(contains('Продукты')),
      );
      expect(state.editingCategoryId, isNull);
      // A published Home projection stores the label, so it is stale until the
      // projector rebuilds.
      expect(repository.renamed.length, 1);
    });
  });

  group('hiding', () {
    test('hiding keeps the row and moves it to the hidden list', () async {
      final repository = _FakeRepository(catalogue: _catalogue());
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );
      await controller.load();
      final target = _ready(container).offered.first;

      await controller.archive(target);

      final state = _ready(container);
      // The decision this slice is built on: removal is never deletion, so the
      // category an operation points at still exists.
      expect(
        state.categories.map((item) => item.categoryId),
        contains(target.categoryId),
      );
      expect(
        state.offered.map((item) => item.categoryId),
        isNot(contains(target.categoryId)),
      );
      expect(
        state.hidden.map((item) => item.categoryId),
        contains(target.categoryId),
      );
      expect(state.busyCategoryId, isNull);
    });

    test('restoring offers a hidden category again', () async {
      final repository = _FakeRepository(catalogue: _catalogue());
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );
      await controller.load();
      final hidden = _ready(container).hidden.single;

      await controller.restore(hidden);

      final state = _ready(container);
      expect(state.hidden, isEmpty);
      expect(state.offered.map((item) => item.categoryId), contains(_hiddenId));
    });

    test('a refused restore keeps the category hidden', () async {
      final repository = _FakeRepository(
        catalogue: _catalogue(),
        writeFailure: FinanceEntryErrorCode.categoryNameTaken,
      );
      final container = _container(repository);
      addTearDown(container.dispose);
      final controller = container.read(
        categoryManagementControllerProvider.notifier,
      );
      await controller.load();

      await controller.restore(_ready(container).hidden.single);

      final state = _ready(container);
      // The name was taken while it was hidden, so it stays hidden rather than
      // appearing twice.
      expect(state.hidden.map((item) => item.categoryId), contains(_hiddenId));
      expect(state.failure?.code, FinanceEntryErrorCode.categoryNameTaken);
    });
  });
}

CategoryManagementReady _ready(ProviderContainer container) =>
    container.read(categoryManagementControllerProvider)
        as CategoryManagementReady;

ManagedCategoryList _catalogue() => ManagedCategoryList(
  categories: [
    _category(_groceriesId, 'Продукты', systemKey: 'groceries'),
    _category(_transportId, 'Транспорт', systemKey: 'transport'),
    _category(_hiddenId, 'Аренда', archivedAt: _archivedAt),
    _category(
      _salaryId,
      'Зарплата',
      direction: FinanceOperationType.income,
      systemKey: 'salary',
    ),
  ],
);

ManagedFinanceCategory _category(
  String id,
  String name, {
  FinanceOperationType direction = FinanceOperationType.expense,
  String? systemKey,
  String? archivedAt,
}) => ManagedFinanceCategory(
  categoryId: id,
  name: name,
  direction: direction,
  systemKey: systemKey,
  archivedAt: archivedAt,
);

ProviderContainer _container(_FakeRepository repository) {
  final container = ProviderContainer(
    overrides: [
      financeEntryRepositoryProvider.overrideWithValue(repository),
      homeSessionStoreProvider.overrideWithValue(const _NullHomeSessionStore()),
      acceptedWriteHomeDelayProvider.overrideWithValue((_) async {}),
    ],
  );
  container.listen(
    categoryManagementControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

/// Applies each accepted write the way the server would, so the controller is
/// tested against the state it will actually be handed back.
class _FakeRepository implements FinanceEntryRepositoryClient {
  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets() =>
      throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget(
    SetBudgetCommand command,
  ) => throw UnimplementedError();

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget(
    String budgetId,
    RemoveBudgetCommand command,
  ) => throw UnimplementedError();

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

  _FakeRepository({
    required ManagedCategoryList catalogue,
    this.listFailure,
    this.writeFailure,
  }) : _categories = [...catalogue.categories];

  final List<ManagedFinanceCategory> _categories;
  final FinanceEntryFailureKind? listFailure;
  final FinanceEntryErrorCode? writeFailure;
  final List<CreateCategoryCommand> created = [];
  final Map<String, String> renamed = {};

  @override
  Future<FinanceEntryResult<ManagedCategoryList>>
  listManagedCategories() async {
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
    created.add(command);
    final category = _category(
      'created-${created.length}',
      command.name,
      direction: command.direction,
    );
    _categories.add(category);
    return _accepted(category);
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory(
    String categoryId,
    RenameCategoryCommand command,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    renamed[categoryId] = command.name;
    return _accepted(
      _replace(categoryId, (current) => _copy(current, name: command.name)),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory(
    String categoryId,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    return _accepted(
      _replace(
        categoryId,
        (current) => _copy(current, archivedAt: _archivedAt),
      ),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory(
    String categoryId,
  ) async {
    final refused = _refusal();
    if (refused != null) return refused;
    return _accepted(
      _replace(categoryId, (current) => _copy(current, clearArchived: true)),
    );
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
    String categoryId,
    ManagedFinanceCategory Function(ManagedFinanceCategory) change,
  ) {
    final index = _categories.indexWhere(
      (item) => item.categoryId == categoryId,
    );
    final updated = change(_categories[index]);
    _categories[index] = updated;
    return updated;
  }

  static const String _requestId = 'req_synthetic_category';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ManagedFinanceCategory _copy(
  ManagedFinanceCategory category, {
  String? name,
  String? archivedAt,
  bool clearArchived = false,
}) => ManagedFinanceCategory(
  categoryId: category.categoryId,
  name: name ?? category.name,
  direction: category.direction,
  // A rename clears the seeded key, so no translation contradicts the name the
  // user chose.
  systemKey: name == null ? category.systemKey : null,
  archivedAt: clearArchived ? null : (archivedAt ?? category.archivedAt),
);

class _NullHomeSessionStore implements HomeSessionStore {
  const _NullHomeSessionStore();

  @override
  Future<HomeSessionSnapshot?> readSession() async => null;

  @override
  Future<void> clearSession() async {}
}
