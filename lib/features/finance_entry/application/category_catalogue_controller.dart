import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';

/// The user's category catalogue, loaded once per authenticated session.
///
/// It is kept out of [FinanceEntryState] on purpose: the entry flow builds its
/// editing state in many places, and threading a read-only list through all of
/// them would couple every transition to something none of them decide.
final categoryCatalogueProvider =
    NotifierProvider.autoDispose<
      CategoryCatalogueController,
      CategoryCatalogueState
    >(CategoryCatalogueController.new);

sealed class CategoryCatalogueState {
  const CategoryCatalogueState();
}

final class CategoryCatalogueLoading extends CategoryCatalogueState {
  const CategoryCatalogueLoading();
}

final class CategoryCatalogueReady extends CategoryCatalogueState {
  const CategoryCatalogueReady(this.catalogue);

  final FinanceCategoryList catalogue;
}

/// The catalogue could not be read.
///
/// The entry form stays usable: it falls back to free text, which is exactly
/// what it did before the catalogue existed. Losing the picker must not stop a
/// user from recording money.
final class CategoryCatalogueUnavailable extends CategoryCatalogueState {
  const CategoryCatalogueUnavailable();
}

class CategoryCatalogueController extends Notifier<CategoryCatalogueState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  @override
  CategoryCatalogueState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const CategoryCatalogueLoading();
  }

  Future<void> load() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    final requestGeneration = _requestGeneration;
    try {
      final result = await ref
          .read(financeEntryRepositoryProvider)
          .listCategories();
      if (!ref.mounted || requestGeneration != _requestGeneration) return;
      state = switch (result) {
        FinanceEntrySuccess(:final value) => CategoryCatalogueReady(value),
        FinanceEntryFailureResult() => const CategoryCatalogueUnavailable(),
      };
    } on Object {
      if (ref.mounted && requestGeneration == _requestGeneration) {
        state = const CategoryCatalogueUnavailable();
      }
    } finally {
      if (requestGeneration == _requestGeneration) _requestInFlight = false;
    }
  }

  /// The categories offered for one direction, empty when none are loaded.
  List<FinanceCategory> forDirection(FinanceOperationType direction) {
    final current = state;
    return current is CategoryCatalogueReady
        ? current.catalogue.forDirection(direction)
        : const [];
  }
}
