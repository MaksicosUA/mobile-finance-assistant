import 'package:flutter/foundation.dart';

import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

@immutable
final class AccountSetupInput {
  const AccountSetupInput({
    required this.name,
    required this.openingBalance,
    required this.openingBalanceOn,
  });

  final String name;
  final String openingBalance;
  final DateTime openingBalanceOn;
}

@immutable
final class OperationEntryInput {
  const OperationEntryInput({
    required this.type,
    required this.amount,
    required this.occurredOn,
    this.category,
    this.categoryId,
    this.merchant,
  });

  final FinanceOperationType type;
  final String amount;
  final DateTime occurredOn;

  /// What the user chose or typed, kept as written (ADR 0020).
  final String? category;

  /// The catalogue link, null when the user typed free text instead of
  /// choosing. Free text stays available so losing the picker never blocks
  /// recording money.
  final String? categoryId;
  final String? merchant;
}

enum FinanceEntryHomeStatus {
  updating,
  updated,
  projectionDelayed,
  authenticationRequired,
  sessionChanged,
  failed,
}

enum FinanceOperationDeliveryIssue {
  commandConflict,
  rejected,
  securityBlocked,
  invalidCommand,
}

sealed class FinanceEntryState {
  const FinanceEntryState();
}

final class FinanceEntryLoading extends FinanceEntryState {
  const FinanceEntryLoading();
}

final class FinanceEntryLoadFailure extends FinanceEntryState {
  const FinanceEntryLoadFailure(this.failure);

  final FinanceEntryFailure failure;
}

final class FinanceEntryAuthenticationRequired extends FinanceEntryState {
  const FinanceEntryAuthenticationRequired();
}

final class FinanceAccountEditing extends FinanceEntryState {
  FinanceAccountEditing({
    required this.initialInput,
    required this.latestOpeningDate,
    this.failure,
    this.isSubmitting = false,
    List<FinanceIssue> issues = const [],
  }) : issues = List.unmodifiable(issues);

  final AccountSetupInput initialInput;
  final DateTime latestOpeningDate;
  final FinanceEntryFailure? failure;
  final bool isSubmitting;
  final List<FinanceIssue> issues;
}

final class FinanceAccountReviewing extends FinanceEntryState {
  const FinanceAccountReviewing({
    required this.review,
    required this.latestOpeningDate,
    required this.latestOperationDate,
    this.failure,
    this.isSubmitting = false,
  });

  final FinanceAccountNeedsConfirmation review;
  final DateTime latestOpeningDate;
  final DateTime latestOperationDate;
  final FinanceEntryFailure? failure;
  final bool isSubmitting;
}

final class FinanceOperationEditing extends FinanceEntryState {
  FinanceOperationEditing({
    required this.account,
    required this.initialInput,
    required this.latestOperationDate,
    this.accountCreated = false,
    this.failure,
    this.isSubmitting = false,
    List<FinanceIssue> issues = const [],
  }) : issues = List.unmodifiable(issues);

  final FinanceAccount account;
  final OperationEntryInput initialInput;
  final DateTime latestOperationDate;
  final bool accountCreated;
  final FinanceEntryFailure? failure;
  final bool isSubmitting;
  final List<FinanceIssue> issues;
}

final class FinanceOperationReviewing extends FinanceEntryState {
  const FinanceOperationReviewing({
    required this.account,
    required this.review,
    required this.latestOperationDate,
    this.failure,
    this.isSubmitting = false,
  });

  final FinanceAccount account;
  final FinanceOperationNeedsConfirmation review;
  final DateTime latestOperationDate;
  final FinanceEntryFailure? failure;
  final bool isSubmitting;
}

final class FinanceOperationAccepted extends FinanceEntryState {
  const FinanceOperationAccepted({
    required this.account,
    required this.operation,
    required this.latestOperationDate,
    required this.homeStatus,
  });

  final FinanceAccount account;
  final CommittedFinanceOperation operation;
  final DateTime latestOperationDate;
  final FinanceEntryHomeStatus homeStatus;
}

/// The confirmed command is durable locally but is not authoritative yet.
final class FinanceOperationQueued extends FinanceEntryState {
  const FinanceOperationQueued({
    required this.account,
    required this.latestOperationDate,
    required this.authenticationRequired,
  });

  final FinanceAccount account;
  final DateTime latestOperationDate;
  final bool authenticationRequired;
}

/// The command was already accepted through an exact idempotent replay.
final class FinanceOperationAlreadySynced extends FinanceEntryState {
  const FinanceOperationAlreadySynced({
    required this.account,
    required this.latestOperationDate,
  });

  final FinanceAccount account;
  final DateTime latestOperationDate;
}

/// A durable command cannot retry automatically and needs user attention.
final class FinanceOperationDeliveryAttention extends FinanceEntryState {
  const FinanceOperationDeliveryAttention({
    required this.account,
    required this.latestOperationDate,
    required this.issue,
  });

  final FinanceAccount account;
  final DateTime latestOperationDate;
  final FinanceOperationDeliveryIssue issue;
}
