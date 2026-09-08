import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/data/finance_entry_repository.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';
import '../../home/application/home_controller.dart';
import 'transfer_state.dart';

export 'transfer_state.dart';

final transferControllerProvider =
    NotifierProvider.autoDispose<TransferController, TransferState>(
      TransferController.new,
    );

/// Moves money between two of the user's wallets (ADR 0029).
///
/// Two amounts and no rate: what left and what arrived are both facts the user
/// witnessed, and the rate between them is shown rather than stored.
///
/// Deliberately outside the encrypted delivery outbox, which exists for
/// accepted financial writes that create income or expense (ADR 0009). A
/// transfer creates neither; a command id still makes a retry replay.
class TransferController extends Notifier<TransferState> {
  var _requestInFlight = false;
  var _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  TransferState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const TransferLoading();
  }

  Future<void> load() async {
    final generation = ++_requestGeneration;
    _requestInFlight = true;
    try {
      final result = await _repository.listAccounts();
      if (generation != _requestGeneration) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          ref
              .read(canonicalTimezoneProvider.notifier)
              .adopt(value.canonicalTimezone);
          state = value.accounts.length < 2
              ? const TransferSecondWalletRequired()
              : TransferReady(wallets: value.accounts);
        case FinanceEntryFailureResult(:final failure):
          state = TransferLoadFailure(failure);
      }
    } on Object {
      if (generation == _requestGeneration) {
        state = TransferLoadFailure(_unexpected());
      }
    } finally {
      if (generation == _requestGeneration) _requestInFlight = false;
    }
  }

  /// Forgets a confirmation the user has since edited away from.
  void discardReview() {
    final current = state;
    if (current is TransferReady && current.review != null) {
      state = current.copyWith(clearReview: true);
    }
  }

  Future<void> evaluate({
    required FinanceAccount from,
    required FinanceAccount to,
    required String fromAmount,
    required String toAmount,
    required DateTime occurredOn,
  }) async {
    final current = state;
    if (_requestInFlight || current is! TransferReady) return;
    final generation = ++_requestGeneration;
    _requestInFlight = true;
    state = current.copyWith(isSubmitting: true, clearReview: true);
    try {
      final capture = await ref
          .read(financeCaptureContextSourceProvider)
          .capture(canonicalTimezone: ref.read(canonicalTimezoneProvider));
      if (generation != _requestGeneration) return;
      final draft = FinanceTransferDraft(
        commandId: ref.read(financeCommandIdFactoryProvider)(),
        fromAccountId: from.accountId,
        fromAmount: normalizeMoneyInput(fromAmount),
        fromCurrency: from.currency,
        toAccountId: to.accountId,
        toAmount: normalizeMoneyInput(toAmount),
        toCurrency: to.currency,
        capturedAt: capture.capturedAtUtc.toIso8601String(),
        capturedTimezone: capture.capturedTimezone,
        occurredOn: _dateWire(occurredOn),
      );
      final result = await _repository.evaluateTransfer(draft);
      if (generation != _requestGeneration) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          switch (value) {
            case FinanceTransferNeedsConfirmation():
              state = current.copyWith(review: value, isSubmitting: false);
            case FinanceTransferRejected(:final issues):
              state = current.copyWith(isSubmitting: false, issues: issues);
          }
        case FinanceEntryFailureResult(:final failure):
          state = current.copyWith(
            isSubmitting: false,
            failure: failure,
            issues: failure.transferIssues,
          );
      }
    } on Object {
      if (generation == _requestGeneration) {
        state = current.copyWith(isSubmitting: false, failure: _unexpected());
      }
    } finally {
      if (generation == _requestGeneration) _requestInFlight = false;
    }
  }

  Future<void> confirm() async {
    final current = state;
    if (_requestInFlight || current is! TransferReady) return;
    final review = current.review;
    if (review == null) return;

    final generation = ++_requestGeneration;
    _requestInFlight = true;
    state = current.copyWith(review: review, isSubmitting: true);
    try {
      final result = await _repository.commitTransfer(
        FinanceTransferCommitCommand.fromReview(
          review: review,
          confirmedAt: ref.read(financeEntryClockProvider)(),
        ),
      );
      if (generation != _requestGeneration) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = TransferAccepted(value);
          // Both wallets moved, and Home holds a revision for each of them.
          await _refreshHome();
        case FinanceEntryFailureResult(:final failure):
          state = current.copyWith(
            review: review,
            isSubmitting: false,
            failure: failure,
            issues: failure.transferIssues,
          );
      }
    } on Object {
      if (generation == _requestGeneration) {
        state = current.copyWith(
          review: review,
          isSubmitting: false,
          failure: _unexpected(),
        );
      }
    } finally {
      if (generation == _requestGeneration) _requestInFlight = false;
    }
  }

  Future<void> _refreshHome() async {
    try {
      await ref.read(homeControllerProvider.notifier).refresh();
    } on Object {
      // A stale Home is not a reason to report a settled transfer as failed.
    }
  }

  FinanceEntryFailure _unexpected() => FinanceEntryFailure(
    kind: FinanceEntryFailureKind.unknown,
    requestId: 'req_local_transfer',
  );
}

String _dateWire(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
