import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';

final operationHistoryControllerProvider =
    NotifierProvider.autoDispose<
      OperationHistoryController,
      OperationHistoryState
    >(OperationHistoryController.new);

/// How many operations one request asks for.
///
/// Small enough that the first screenful arrives quickly, large enough that a
/// normal month rarely needs a second page.
const int operationHistoryPageSize = 30;

sealed class OperationHistoryState {
  const OperationHistoryState();
}

final class OperationHistoryLoading extends OperationHistoryState {
  const OperationHistoryLoading();
}

@immutable
final class OperationHistoryReady extends OperationHistoryState {
  OperationHistoryReady({
    required List<OperationHistoryItem> operations,
    required this.nextCursor,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  }) : operations = List<OperationHistoryItem>.unmodifiable(operations);

  final List<OperationHistoryItem> operations;

  /// Absent once the whole history has been read.
  final String? nextCursor;
  final bool isLoadingMore;

  /// A failed page keeps what was already read visible: losing the list
  /// because the next page failed would be worse than showing a retry.
  final bool loadMoreFailed;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => operations.isEmpty;

  OperationHistoryReady copyWith({
    List<OperationHistoryItem>? operations,
    String? nextCursor,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    bool clearCursor = false,
  }) {
    return OperationHistoryReady(
      operations: operations ?? this.operations,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }
}

final class OperationHistoryAuthenticationRequired
    extends OperationHistoryState {
  const OperationHistoryAuthenticationRequired();
}

@immutable
final class OperationHistoryFailure extends OperationHistoryState {
  const OperationHistoryFailure(this.failure);

  final FinanceEntryFailure failure;
}

/// Reads confirmed operations back, newest first (ADR 0020, step 4).
///
/// Read-only by design: this screen shows what was recorded and never changes
/// it. Correcting an operation is a Finance Core write with its own audit, and
/// it is not part of this slice.
class OperationHistoryController extends Notifier<OperationHistoryState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  OperationHistoryState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const OperationHistoryLoading();
  }

  Future<void> load() => _read(keepVisible: false);

  /// Re-reads the screen while the current reading stays visible.
  ///
  /// A pull that blanks usable data, or replaces it with an error page when
  /// the network blinks, is worse than no refresh at all. Returns `false` when
  /// the screen is still showing the older reading.
  ///
  /// A refresh reads the first page again, so a newly recorded operation
  /// appears at the top; pages already read below it are dropped rather than
  /// stitched onto a list that moved underneath them.
  Future<bool> refresh() => _read(keepVisible: true);

  Future<bool> _read({required bool keepVisible}) async {
    if (_requestInFlight) return true;
    final requestGeneration = _beginRequest();
    final retained = keepVisible && state is OperationHistoryReady;
    try {
      final result = await _repository.listOperations(
        limit: operationHistoryPageSize,
      );
      if (!_isCurrentRequest(requestGeneration)) return false;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = OperationHistoryReady(
            operations: value.operations,
            nextCursor: value.nextCursor,
          );
          return true;
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const OperationHistoryAuthenticationRequired();
          } else if (!retained) {
            state = OperationHistoryFailure(failure);
          }
          return false;
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration) && !retained) {
        state = OperationHistoryFailure(_unexpectedFailure());
      }
      return false;
    } finally {
      _endRequest(requestGeneration);
    }
  }

  /// Reads the next page and appends it.
  ///
  /// The cursor comes from the server, so a page boundary stays put even if an
  /// older operation is recorded between two requests.
  Future<void> loadMore() async {
    final current = state;
    if (_requestInFlight || current is! OperationHistoryReady) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;

    final requestGeneration = _beginRequest();
    state = current.copyWith(isLoadingMore: true, loadMoreFailed: false);
    try {
      final result = await _repository.listOperations(
        limit: operationHistoryPageSize,
        cursor: cursor,
      );
      if (!_isCurrentRequest(requestGeneration)) return;
      final latest = state;
      if (latest is! OperationHistoryReady) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = OperationHistoryReady(
            operations: [...latest.operations, ...value.operations],
            nextCursor: value.nextCursor,
          );
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const OperationHistoryAuthenticationRequired();
            return;
          }
          state = latest.copyWith(isLoadingMore: false, loadMoreFailed: true);
      }
    } on Object {
      final latest = state;
      if (_isCurrentRequest(requestGeneration) &&
          latest is OperationHistoryReady) {
        state = latest.copyWith(isLoadingMore: false, loadMoreFailed: true);
      }
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

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_operation_history_unknown',
);
