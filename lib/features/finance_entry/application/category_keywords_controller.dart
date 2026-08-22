import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';

final categoryKeywordsControllerProvider =
    NotifierProvider.autoDispose<
      CategoryKeywordsController,
      CategoryKeywordsState
    >(CategoryKeywordsController.new);

sealed class CategoryKeywordsState {
  const CategoryKeywordsState();
}

final class CategoryKeywordsLoading extends CategoryKeywordsState {
  const CategoryKeywordsLoading();
}

@immutable
final class CategoryKeywordsReady extends CategoryKeywordsState {
  CategoryKeywordsReady({
    required this.categoryId,
    required List<String> keywords,
    this.isSubmitting = false,
    this.failure,
  }) : keywords = List<String>.unmodifiable(keywords);

  final String categoryId;
  final List<String> keywords;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;

  CategoryKeywordsReady copyWith({
    List<String>? keywords,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    bool clearFailure = false,
  }) => CategoryKeywordsReady(
    categoryId: categoryId,
    keywords: keywords ?? this.keywords,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

final class CategoryKeywordsAuthenticationRequired
    extends CategoryKeywordsState {
  const CategoryKeywordsAuthenticationRequired();
}

@immutable
final class CategoryKeywordsFailure extends CategoryKeywordsState {
  const CategoryKeywordsFailure(this.failure);

  final FinanceEntryFailure failure;
}

/// The words that lead to one category (ADR 0020 step 3).
///
/// Every write sends the whole set, so it is idempotent by target state: a
/// retry after a lost answer changes nothing, and there is no client command
/// id because a label is not money.
class CategoryKeywordsController extends Notifier<CategoryKeywordsState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  CategoryKeywordsState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const CategoryKeywordsLoading();
  }

  Future<void> load(String categoryId) async {
    final requestGeneration = _beginRequest();
    state = const CategoryKeywordsLoading();
    await _run(
      requestGeneration,
      () => _repository.listCategoryKeywords(categoryId),
      onFailure: (failure) => _requiresAuthentication(failure)
          ? const CategoryKeywordsAuthenticationRequired()
          : CategoryKeywordsFailure(failure),
    );
  }

  /// Re-reads the words while the ones on screen stay visible.
  ///
  /// A failed refresh reports itself on the card the words are on, so the
  /// vocabulary never disappears because a read failed.
  Future<bool> refresh(String categoryId) async {
    final current = state;
    if (current is! CategoryKeywordsReady) {
      await load(categoryId);
      return state is CategoryKeywordsReady;
    }
    if (_requestInFlight) return true;
    final requestGeneration = _beginRequest();
    return _run(
      requestGeneration,
      () => _repository.listCategoryKeywords(current.categoryId),
      onFailure: (failure) => _requiresAuthentication(failure)
          ? const CategoryKeywordsAuthenticationRequired()
          : current.copyWith(failure: failure),
    );
  }

  Future<void> add(String word) async {
    final current = state;
    if (current is! CategoryKeywordsReady || _requestInFlight) return;
    final String keyword;
    try {
      keyword = validatedCategoryKeyword(word);
    } on FormatException {
      state = current.copyWith(failure: _invalidInput());
      return;
    }
    if (current.keywords.contains(keyword)) return;
    await _replace(current, [...current.keywords, keyword]..sort());
  }

  Future<void> remove(String keyword) async {
    final current = state;
    if (current is! CategoryKeywordsReady || _requestInFlight) return;
    await _replace(current, [
      for (final existing in current.keywords)
        if (existing != keyword) existing,
    ]);
  }

  Future<void> _replace(
    CategoryKeywordsReady current,
    List<String> keywords,
  ) async {
    final requestGeneration = _beginRequest();
    state = current.copyWith(isSubmitting: true, clearFailure: true);
    await _run(
      requestGeneration,
      () => _repository.replaceCategoryKeywords(current.categoryId, keywords),
      // The screen keeps what it had: a refused word must not look as if the
      // rest of the vocabulary was lost too.
      onFailure: (failure) => _requiresAuthentication(failure)
          ? const CategoryKeywordsAuthenticationRequired()
          : current.copyWith(isSubmitting: false, failure: failure),
    );
  }

  Future<bool> _run(
    int requestGeneration,
    Future<FinanceEntryResult<CategoryKeywords>> Function() request, {
    required CategoryKeywordsState Function(FinanceEntryFailure) onFailure,
  }) async {
    try {
      final result = await request();
      if (!_isCurrentRequest(requestGeneration)) return false;
      state = switch (result) {
        FinanceEntrySuccess(:final value) => CategoryKeywordsReady(
          categoryId: value.categoryId,
          keywords: value.keywords,
        ),
        FinanceEntryFailureResult(:final failure) => onFailure(failure),
      };
      return result is FinanceEntrySuccess<CategoryKeywords>;
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = onFailure(_unexpected());
      }
      return false;
    } finally {
      _endRequest(requestGeneration);
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

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;

FinanceEntryFailure _invalidInput() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.invalidInput,
  requestId: 'req_local_keyword_invalid',
);

FinanceEntryFailure _unexpected() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_keyword_unknown',
);
