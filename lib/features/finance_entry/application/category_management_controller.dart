import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'category_catalogue_controller.dart';
import 'category_management_state.dart';
import 'finance_entry_controller.dart';

export 'category_management_state.dart';

final categoryManagementControllerProvider =
    NotifierProvider.autoDispose<
      CategoryManagementController,
      CategoryManagementState
    >(CategoryManagementController.new);

/// Creates, renames, hides, and restores the user's own categories.
///
/// Removal is hiding and never deletion, so a category an operation points at
/// cannot disappear from under it (ADR 0020).
///
/// No command id is minted here. Every catalogue write is idempotent by target
/// state — renaming to the current name, hiding a hidden category, restoring an
/// active one all succeed and change nothing — so a retry converges without a
/// replay key. That is the difference from a financial command, which needs one
/// (ADR 0009).
class CategoryManagementController extends Notifier<CategoryManagementState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  CategoryManagementState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const CategoryManagementLoading();
  }

  Future<void> load() => _read(keepVisible: false);

  /// Re-reads the screen while the current reading stays visible.
  ///
  /// A pull that blanks usable data, or replaces it with an error page when
  /// the network blinks, is worse than no refresh at all. Returns `false` when
  /// the screen is still showing the older reading.
  ///
  /// The chosen direction and the hidden-rows switch are the user's, not the
  /// server's, so a refresh keeps them.
  Future<bool> refresh() => _read(keepVisible: true);

  Future<bool> _read({required bool keepVisible}) async {
    if (_requestInFlight) return true;
    final requestGeneration = _beginRequest();
    final retained = keepVisible && state is CategoryManagementReady;
    try {
      final result = await _repository.listManagedCategories();
      if (!_isCurrentRequest(requestGeneration)) return false;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          final current = state;
          state = CategoryManagementReady(
            direction: current is CategoryManagementReady
                ? current.direction
                : FinanceOperationType.expense,
            categories: value.categories,
            showHidden: current is CategoryManagementReady
                ? current.showHidden
                : false,
          );
          return true;
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const CategoryManagementAuthenticationRequired();
          } else if (!retained) {
            state = CategoryManagementFailure(failure);
          }
          return false;
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration) && !retained) {
        state = CategoryManagementFailure(_unexpectedFailure());
      }
      return false;
    } finally {
      _endRequest(requestGeneration);
    }
  }

  void selectDirection(FinanceOperationType direction) {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(
      direction: direction,
      isCreating: false,
      newName: '',
      clearEditing: true,
      clearFailure: true,
    );
  }

  void toggleHidden() {
    final current = state;
    if (current is! CategoryManagementReady) return;
    state = current.copyWith(showHidden: !current.showHidden);
  }

  void startCreating() {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(
      isCreating: true,
      newName: '',
      clearEditing: true,
      clearFailure: true,
    );
  }

  void cancelCreating() {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(
      isCreating: false,
      newName: '',
      clearFailure: true,
    );
  }

  void setNewName(String value) {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(newName: value, clearFailure: true);
  }

  void startRenaming(ManagedFinanceCategory category) {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(
      editingCategoryId: category.categoryId,
      // Prefilled with the stored name rather than the localized label: the
      // label may be a translation of a seeded key, and editing that would
      // silently rename the category to a word the user never typed.
      editedName: category.name,
      isCreating: false,
      clearFailure: true,
    );
  }

  void cancelRenaming() {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(
      clearEditing: true,
      editedName: '',
      clearFailure: true,
    );
  }

  void setEditedName(String value) {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    state = current.copyWith(editedName: value, clearFailure: true);
  }

  /// Creates a category and reports it back, so the screen can offer its words
  /// while the person is still thinking about what this category is for. A
  /// category with no words is matched only by its exact full name, and
  /// nothing used to say so (issue 0011).
  Future<ManagedFinanceCategory?> submitCreate() async {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return null;

    late final CreateCategoryCommand command;
    try {
      command = CreateCategoryCommand(
        name: validatedCategoryName(current.newName),
        direction: current.direction,
      );
    } on Object {
      state = current.copyWith(failure: _invalidInputFailure());
      return null;
    }

    return _write(
      current: current,
      request: () => _repository.createCategory(command),
      onAccepted: (latest, category) => latest.copyWith(
        categories: _merged(latest.categories, category),
        isCreating: false,
        newName: '',
      ),
    );
  }

  Future<void> submitRename() async {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    final categoryId = current.editingCategoryId;
    if (categoryId == null) return;

    late final RenameCategoryCommand command;
    try {
      command = RenameCategoryCommand(
        name: validatedCategoryName(current.editedName),
      );
      validateCategoryId(categoryId);
    } on Object {
      state = current.copyWith(failure: _invalidInputFailure());
      return;
    }

    await _write(
      current: current,
      busyCategoryId: categoryId,
      request: () => _repository.renameCategory(categoryId, command),
      onAccepted: (latest, category) => latest.copyWith(
        categories: _merged(latest.categories, category),
        editedName: '',
        clearEditing: true,
      ),
      // A published Home projection stores the label this category resolved
      // to, so it is stale until the projector rebuilds.
      convergesHome: true,
    );
  }

  /// Hides one category. It keeps every operation recorded against it.
  Future<void> archive(ManagedFinanceCategory category) async {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    await _write(
      current: current,
      busyCategoryId: category.categoryId,
      request: () => _repository.archiveCategory(category.categoryId),
      onAccepted: (latest, updated) =>
          latest.copyWith(categories: _merged(latest.categories, updated)),
    );
  }

  /// Offers a hidden category again.
  Future<void> restore(ManagedFinanceCategory category) async {
    final current = state;
    if (_requestInFlight || current is! CategoryManagementReady) return;
    await _write(
      current: current,
      busyCategoryId: category.categoryId,
      request: () => _repository.restoreCategory(category.categoryId),
      onAccepted: (latest, updated) =>
          latest.copyWith(categories: _merged(latest.categories, updated)),
    );
  }

  /// Runs one catalogue write and returns what the server accepted, or null if
  /// it refused. Callers that need to act on the new row — creating one leads
  /// to its words — use the value; the rest ignore it.
  Future<ManagedFinanceCategory?> _write({
    required CategoryManagementReady current,
    required Future<FinanceEntryResult<ManagedFinanceCategory>> Function()
    request,
    required CategoryManagementReady Function(
      CategoryManagementReady,
      ManagedFinanceCategory,
    )
    onAccepted,
    String? busyCategoryId,
    bool convergesHome = false,
  }) async {
    final requestGeneration = _beginRequest();
    state = current.copyWith(
      isSubmitting: true,
      busyCategoryId: busyCategoryId,
      clearFailure: true,
    );
    try {
      final result = await request();
      if (!_isCurrentRequest(requestGeneration)) return null;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          final latest = state;
          if (latest is! CategoryManagementReady) return null;
          state = onAccepted(
            latest,
            value,
          ).copyWith(isSubmitting: false, clearBusy: true, clearFailure: true);
          // The picker holds its own copy of the catalogue, so it would keep
          // offering a category this screen just hid.
          ref.invalidate(categoryCatalogueProvider);
          if (convergesHome) unawaited(_convergeHome());
          return value;
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const CategoryManagementAuthenticationRequired();
            return null;
          }
          final latest = state;
          if (latest is! CategoryManagementReady) return null;
          state = latest.copyWith(
            isSubmitting: false,
            clearBusy: true,
            failure: failure,
          );
          return null;
      }
    } on Object {
      final latest = state;
      if (_isCurrentRequest(requestGeneration) &&
          latest is CategoryManagementReady) {
        state = latest.copyWith(
          isSubmitting: false,
          clearBusy: true,
          failure: _unexpectedFailure(),
        );
      }
      return null;
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> _convergeHome() async {
    try {
      await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite();
    } on Object {
      // Best-effort: the rename is already stored server-side, and Home
      // refreshes on its own schedule.
      return;
    }
  }

  int _beginRequest() {
    _requestInFlight = true;
    _requestGeneration += 1;
    return _requestGeneration;
  }

  bool _isCurrentRequest(int requestGeneration) =>
      ref.mounted && requestGeneration == _requestGeneration;

  void _endRequest(int requestGeneration) {
    if (_isCurrentRequest(requestGeneration)) _requestInFlight = false;
  }
}

/// Replaces a category in place, or appends it, keeping one name order.
///
/// The server is the authority on what the row now is, so the returned
/// category replaces the local copy rather than being patched into it.
List<ManagedFinanceCategory> _merged(
  List<ManagedFinanceCategory> categories,
  ManagedFinanceCategory updated,
) {
  final merged =
      <ManagedFinanceCategory>[
        for (final category in categories)
          if (category.categoryId != updated.categoryId) category,
        updated,
      ]..sort((left, right) {
        final byDirection = left.direction.wireName.compareTo(
          right.direction.wireName,
        );
        if (byDirection != 0) return byDirection;
        final byName = left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        );
        return byName != 0
            ? byName
            : left.categoryId.compareTo(right.categoryId);
      });
  return List<ManagedFinanceCategory>.unmodifiable(merged);
}

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;

FinanceEntryFailure _invalidInputFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.invalidInput,
  requestId: 'req_local_category_input',
);

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_category_unknown',
);
