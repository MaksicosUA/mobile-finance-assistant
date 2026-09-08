import 'package:flutter/foundation.dart';

import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';

sealed class TransferState {
  const TransferState();
}

final class TransferLoading extends TransferState {
  const TransferLoading();
}

/// A transfer needs two wallets, and a profile may hold one.
final class TransferSecondWalletRequired extends TransferState {
  const TransferSecondWalletRequired();
}

@immutable
final class TransferLoadFailure extends TransferState {
  const TransferLoadFailure(this.failure);

  final FinanceEntryFailure failure;
}

@immutable
final class TransferReady extends TransferState {
  TransferReady({
    required List<FinanceAccount> wallets,
    this.review,
    this.isSubmitting = false,
    this.failure,
    List<FinanceTransferIssue> issues = const [],
  }) : wallets = List.unmodifiable(wallets),
       issues = List.unmodifiable(issues);

  final List<FinanceAccount> wallets;

  /// Set once the server has agreed, and cleared by any edit: a confirmation
  /// must never outlive the draft it was given for.
  final FinanceTransferNeedsConfirmation? review;
  final bool isSubmitting;
  final FinanceEntryFailure? failure;
  final List<FinanceTransferIssue> issues;

  TransferReady copyWith({
    FinanceTransferNeedsConfirmation? review,
    bool clearReview = false,
    bool? isSubmitting,
    FinanceEntryFailure? failure,
    List<FinanceTransferIssue>? issues,
  }) {
    return TransferReady(
      wallets: wallets,
      review: clearReview ? null : (review ?? this.review),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      issues: issues ?? const [],
    );
  }
}

@immutable
final class TransferAccepted extends TransferState {
  const TransferAccepted(this.transfer);

  final FinanceTransferCommitted transfer;
}
