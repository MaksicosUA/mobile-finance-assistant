import 'package:flutter/foundation.dart';

import 'finance_entry_models.dart';

enum FinanceEntryFailureKind {
  invalidInput,
  unauthenticated,
  sessionChanged,
  interrupted,
  unauthorized,
  conflict,
  rejected,
  offline,
  timeout,
  serviceUnavailable,
  securityFailure,
  localStorage,
  malformedResponse,
  unknown,
}

enum FinanceEntryErrorCode {
  malformedAccount,
  malformedOperation,
  confirmationMismatch,
  commandConflict,
  accountAlreadyInitialized,
  accountRejected,
  operationRejected,
  authenticationUnavailable,
  financePersistenceUnavailable,
}

@immutable
final class FinanceEntryFailure {
  FinanceEntryFailure({
    required this.kind,
    required this.requestId,
    this.code,
    List<FinanceIssue> issues = const [],
  }) : issues = List.unmodifiable(issues);

  final FinanceEntryFailureKind kind;
  final String requestId;
  final FinanceEntryErrorCode? code;
  final List<FinanceIssue> issues;
}

sealed class FinanceEntryResult<T> {
  const FinanceEntryResult({required this.requestId});

  final String requestId;
}

@immutable
final class FinanceEntrySuccess<T> extends FinanceEntryResult<T> {
  const FinanceEntrySuccess({required super.requestId, required this.value});

  final T value;
}

@immutable
final class FinanceEntryFailureResult<T> extends FinanceEntryResult<T> {
  FinanceEntryFailureResult(this.failure) : super(requestId: failure.requestId);

  final FinanceEntryFailure failure;
}
