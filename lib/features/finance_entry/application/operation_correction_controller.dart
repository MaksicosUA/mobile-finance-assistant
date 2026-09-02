import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'finance_entry_controller.dart';

/// Correcting or removing one confirmed operation (ADR 0023).
///
/// Deliberately separate from [FinanceEntryController]: that one owns the
/// encrypted delivery outbox, and a correction must not enter it. Its target
/// is a row that is still on the server and still on the screen, so a lost
/// correction leaves the user exactly where they started.
@immutable
sealed class OperationCorrectionState {
  const OperationCorrectionState();
}

final class OperationCorrectionLoading extends OperationCorrectionState {
  const OperationCorrectionLoading();
}

final class OperationCorrectionUnavailable extends OperationCorrectionState {
  const OperationCorrectionUnavailable(this.failure);

  final FinanceEntryFailure failure;
}

final class OperationCorrectionAuthenticationRequired
    extends OperationCorrectionState {
  const OperationCorrectionAuthenticationRequired();
}

final class OperationCorrectionEditing extends OperationCorrectionState {
  const OperationCorrectionEditing({
    required this.account,
    required this.categories,
    required this.type,
    required this.amount,
    required this.occurredOn,
    required this.categoryId,
    this.isSubmitting = false,
    this.failure,
    this.issues = const [],
  });

  final FinanceAccount account;
  final List<FinanceCategory> categories;
  final FinanceOperationType type;
  final String amount;
  final DateTime occurredOn;
  final String? categoryId;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<FinanceIssue> issues;

  OperationCorrectionEditing copyWith({
    FinanceOperationType? type,
    String? amount,
    DateTime? occurredOn,
    String? categoryId,
    bool clearCategory = false,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    bool clearFailure = false,
    List<FinanceIssue>? issues,
  }) {
    return OperationCorrectionEditing(
      account: account,
      categories: categories,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      occurredOn: occurredOn ?? this.occurredOn,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearFailure ? null : (failure ?? this.failure),
      issues: issues ?? this.issues,
    );
  }
}

final class OperationCorrectionDone extends OperationCorrectionState {
  const OperationCorrectionDone({required this.removed});

  /// True when the operation was withdrawn without a replacement.
  final bool removed;
}

class OperationCorrectionController extends Notifier<OperationCorrectionState> {
  OperationHistoryItem? _target;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  OperationCorrectionState build() => const OperationCorrectionLoading();

  /// Reads the account and the catalogue the replacement draft needs.
  Future<void> open(OperationHistoryItem operation) async {
    _target = operation;
    state = const OperationCorrectionLoading();
    final accounts = await _repository.listAccounts();
    switch (accounts) {
      case FinanceEntryFailureResult(:final failure):
        state = _requiresAuthentication(failure)
            ? const OperationCorrectionAuthenticationRequired()
            : OperationCorrectionUnavailable(failure);
        return;
      case FinanceEntrySuccess(:final value):
        final account = value.account;
        if (account == null) {
          state = OperationCorrectionUnavailable(
            FinanceEntryFailure(
              kind: FinanceEntryFailureKind.serviceUnavailable,
              requestId: 'local',
            ),
          );
          return;
        }
        // A failed catalogue read is not fatal: the amount and the date can
        // still be corrected, and the category simply cannot be changed.
        final catalogue = await _repository.listCategories();
        state = OperationCorrectionEditing(
          account: account,
          categories: switch (catalogue) {
            FinanceEntrySuccess(:final value) => value.categories,
            FinanceEntryFailureResult() => const [],
          },
          type: operation.type,
          amount: operation.amount,
          occurredOn: DateTime.parse(operation.occurredOn),
          categoryId: operation.categoryId,
        );
    }
  }

  void editAmount(String value) =>
      _edit((current) => current.copyWith(amount: value));

  void editDate(DateTime value) =>
      _edit((current) => current.copyWith(occurredOn: value));

  void editType(FinanceOperationType value) {
    _edit((current) {
      // A category belongs to one direction, so flipping the direction cannot
      // keep it: the picker would offer a value it does not hold (ADR 0020).
      final keepsCategory = current.categories.any(
        (category) =>
            category.categoryId == current.categoryId &&
            category.direction == value,
      );
      return current.copyWith(type: value, clearCategory: !keepsCategory);
    });
  }

  void editCategory(String? categoryId) {
    _edit(
      (current) => categoryId == null
          ? current.copyWith(clearCategory: true)
          : current.copyWith(categoryId: categoryId),
    );
  }

  void _edit(
    OperationCorrectionEditing Function(OperationCorrectionEditing) change,
  ) {
    final current = state;
    if (current is! OperationCorrectionEditing || current.isSubmitting) return;
    state = change(current).copyWith(clearFailure: true, issues: const []);
  }

  /// Evaluates the replacement and, if Finance Core accepts it, corrects.
  ///
  /// The replacement is reviewed exactly like a new operation, so a correction
  /// can never write something the ordinary path would refuse.
  Future<void> submit() async {
    final current = state;
    final target = _target;
    if (current is! OperationCorrectionEditing ||
        current.isSubmitting ||
        target == null) {
      return;
    }
    state = current.copyWith(isSubmitting: true, clearFailure: true);

    final FinanceOperationDraft draft;
    try {
      draft = await _draft(current);
    } on Object {
      state = current.copyWith(isSubmitting: false, failure: _invalidInput());
      return;
    }

    final evaluation = await _repository.evaluateOperation(draft);
    switch (evaluation) {
      case FinanceEntryFailureResult(:final failure):
        _applyFailure(current, failure);
        return;
      case FinanceEntrySuccess(:final value):
        switch (value) {
          case FinanceOperationRejected(:final issues):
            state = current.copyWith(isSubmitting: false, issues: issues);
            return;
          case FinanceOperationNeedsConfirmation():
            final result = await _repository.correctOperation(
              OperationCorrectionCommand(
                targetOperationId: target.operationId,
                review: value,
                confirmedAt: _now(),
              ),
            );
            switch (result) {
              case FinanceEntrySuccess():
                state = const OperationCorrectionDone(removed: false);
              case FinanceEntryFailureResult(:final failure):
                _applyFailure(current, failure);
            }
        }
    }
  }

  /// Withdraws the operation without replacing it.
  Future<void> remove() async {
    final current = state;
    final target = _target;
    if (current is! OperationCorrectionEditing ||
        current.isSubmitting ||
        target == null) {
      return;
    }
    state = current.copyWith(isSubmitting: true, clearFailure: true);
    final result = await _repository.removeOperation(
      OperationRemovalCommand(
        targetOperationId: target.operationId,
        commandId: ref.read(financeCommandIdFactoryProvider)(),
        confirmedAt: _now(),
      ),
    );
    switch (result) {
      case FinanceEntrySuccess():
        state = const OperationCorrectionDone(removed: true);
      case FinanceEntryFailureResult(:final failure):
        _applyFailure(current, failure);
    }
  }

  Future<FinanceOperationDraft> _draft(
    OperationCorrectionEditing current,
  ) async {
    final capture = await ref
        .read(financeCaptureContextSourceProvider)
        .capture(canonicalTimezone: ref.read(canonicalTimezoneProvider));
    final category = current.categories
        .where((item) => item.categoryId == current.categoryId)
        .firstOrNull;
    final draft = FinanceOperationDraft(
      // The replacement is its own operation and carries its own command id;
      // the reversal that withdraws the original shares it, because both are
      // one command.
      commandId: ref.read(financeCommandIdFactoryProvider)(),
      type: current.type,
      amount: current.amount.trim().replaceAll(',', '.'),
      currency: current.account.currency,
      accountId: current.account.accountId,
      category: category?.name,
      categoryId: current.categoryId,
      merchant: null,
      capturedAt: capture.capturedAtUtc.toIso8601String(),
      capturedTimezone: capture.capturedTimezone,
      // The date is chosen explicitly here, so there is no phrase to resolve.
      sourceExpression: null,
      occurredOn: _dateWire(current.occurredOn),
      occurredAt: null,
      source: FinanceOperationSource.manualText,
    );
    validateOperationDraft(draft);
    return draft;
  }

  void _applyFailure(
    OperationCorrectionEditing current,
    FinanceEntryFailure failure,
  ) {
    if (_requiresAuthentication(failure)) {
      state = const OperationCorrectionAuthenticationRequired();
      return;
    }
    state = current.copyWith(isSubmitting: false, failure: failure);
  }

  String _now() =>
      ref.read(financeEntryClockProvider)().toUtc().toIso8601String();

  FinanceEntryFailure _invalidInput() => FinanceEntryFailure(
    kind: FinanceEntryFailureKind.invalidInput,
    requestId: 'local',
  );
}

String _dateWire(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;

final operationCorrectionControllerProvider =
    NotifierProvider.autoDispose<
      OperationCorrectionController,
      OperationCorrectionState
    >(OperationCorrectionController.new);
