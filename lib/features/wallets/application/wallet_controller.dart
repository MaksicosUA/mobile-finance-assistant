import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/data/finance_entry_repository.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';
import '../../home/application/home_controller.dart';

final walletControllerProvider =
    NotifierProvider.autoDispose<WalletController, WalletState>(
      WalletController.new,
    );

sealed class WalletState {
  const WalletState();
}

final class WalletLoading extends WalletState {
  const WalletLoading();
}

/// A wallet is added to a profile that already exists, so the first account
/// has to be there before one can be opened (ADR 0029).
final class WalletAccountRequired extends WalletState {
  const WalletAccountRequired();
}

@immutable
final class WalletLoadFailure extends WalletState {
  const WalletLoadFailure(this.failure);

  final FinanceEntryFailure failure;
}

@immutable
final class WalletReady extends WalletState {
  WalletReady({
    required List<FinanceAccount> wallets,
    this.review,
    this.isSubmitting = false,
    this.failure,
    List<FinanceIssue> issues = const [],
  }) : wallets = List.unmodifiable(wallets),
       issues = List.unmodifiable(issues);

  final List<FinanceAccount> wallets;

  /// Cleared by any edit: a confirmation must not outlive its draft.
  final FinanceAccountNeedsConfirmation? review;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<FinanceIssue> issues;

  /// The currencies this profile already holds. Offered anyway — a person may
  /// keep a bank account and cash in the same currency (ADR 0029) — but worth
  /// showing, because the usual reason to open one is a currency they lack.
  Set<String> get heldCurrencies =>
      wallets.map((wallet) => wallet.currency).toSet();

  WalletReady copyWith({
    FinanceAccountNeedsConfirmation? review,
    bool clearReview = false,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    List<FinanceIssue>? issues,
  }) {
    return WalletReady(
      wallets: wallets,
      review: clearReview ? null : (review ?? this.review),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      issues: issues ?? const [],
    );
  }
}

@immutable
final class WalletOpened extends WalletState {
  const WalletOpened(this.account);

  final FinanceAccount account;
}

/// Opens a wallet in another currency (ADR 0029).
///
/// The same evaluate/review/commit pair the first account uses: an opening
/// balance is stock whichever wallet holds it, so it deserves the same explicit
/// confirmation. What the server settles once — the reporting timezone, the
/// base currency, the seeded catalogue — a later wallet inherits.
class WalletController extends Notifier<WalletState> {
  var _requestInFlight = false;
  var _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  WalletState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const WalletLoading();
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
          state = value.accounts.isEmpty
              ? const WalletAccountRequired()
              : WalletReady(wallets: value.accounts);
        case FinanceEntryFailureResult(:final failure):
          state = WalletLoadFailure(failure);
      }
    } on Object {
      if (generation == _requestGeneration) {
        state = WalletLoadFailure(_unexpected());
      }
    } finally {
      if (generation == _requestGeneration) _requestInFlight = false;
    }
  }

  void discardReview() {
    final current = state;
    if (current is WalletReady && current.review != null) {
      state = current.copyWith(clearReview: true);
    }
  }

  Future<void> evaluate({
    required String name,
    required String currency,
    required String openingBalance,
    required DateTime openingBalanceOn,
  }) async {
    final current = state;
    if (_requestInFlight || current is! WalletReady) return;
    final generation = ++_requestGeneration;
    _requestInFlight = true;
    state = current.copyWith(isSubmitting: true, clearReview: true);
    try {
      final draft = FinanceAccountDraft(
        commandId: ref.read(financeCommandIdFactoryProvider)(),
        name: name.trim(),
        currency: currency,
        openingBalance: normalizeMoneyInput(
          openingBalance,
          allowNegative: true,
        ),
        openingBalanceOn: _dateWire(openingBalanceOn),
        // The profile's zone, never a second one: months must not depend on
        // which wallet is read (ADR 0028).
        canonicalTimezone: ref.read(canonicalTimezoneProvider),
      );
      validateAccountDraft(draft);
      final result = await _repository.evaluateAccount(draft);
      if (generation != _requestGeneration) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          switch (value) {
            case FinanceAccountNeedsConfirmation():
              state = current.copyWith(review: value, isSubmitting: false);
            case FinanceAccountRejected(:final issues):
              state = current.copyWith(isSubmitting: false, issues: issues);
          }
        case FinanceEntryFailureResult(:final failure):
          state = current.copyWith(
            isSubmitting: false,
            failure: failure,
            issues: failure.issues,
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
    if (_requestInFlight || current is! WalletReady) return;
    final review = current.review;
    if (review == null) return;

    final generation = ++_requestGeneration;
    _requestInFlight = true;
    state = current.copyWith(review: review, isSubmitting: true);
    try {
      final result = await _repository.commitAccount(
        FinanceAccountCommitCommand.fromReview(
          review: review,
          confirmedAt: ref.read(financeEntryClockProvider)(),
        ),
      );
      if (generation != _requestGeneration) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = WalletOpened(value.account);
          await _refreshHome();
        case FinanceEntryFailureResult(:final failure):
          state = current.copyWith(
            review: review,
            isSubmitting: false,
            failure: failure,
            issues: failure.issues,
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
      // A stale Home is not a reason to report an opened wallet as failed.
    }
  }

  FinanceEntryFailure _unexpected() => FinanceEntryFailure(
    kind: FinanceEntryFailureKind.unknown,
    requestId: 'req_local_wallet',
  );
}

String _dateWire(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
