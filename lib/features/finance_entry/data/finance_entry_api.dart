import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';

typedef FinanceRequestIdFactory = String Function();

abstract interface class FinanceEntryApiClient {
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts({
    required String accessToken,
  });

  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount({
    required String accessToken,
    required FinanceAccountDraft draft,
  });

  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount({
    required String accessToken,
    required FinanceAccountCommitCommand command,
  });

  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline({
    required String accessToken,
    required FinanceBaselineDraft draft,
  });

  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline({
    required String accessToken,
    required FinanceBaselineCommitCommand command,
  });

  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation({
    required String accessToken,
    required FinanceOperationDraft draft,
  });

  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation({
    required String accessToken,
    required FinanceOperationCommitCommand command,
  });
}

/// Strict byte-bounded client for the authenticated Finance Core endpoints.
///
/// No interceptor is installed because request bodies, responses, and bearer
/// headers contain sensitive financial or authentication data.
final class FinanceEntryApi implements FinanceEntryApiClient {
  FinanceEntryApi({
    required Dio dio,
    required Uri baseUri,
    FinanceRequestIdFactory requestIdFactory = _newRequestId,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _dio = dio,
       _baseUri = _validatedBaseUri(baseUri),
       // ignore: prefer_initializing_formals
       _requestIdFactory = requestIdFactory {
    _requireTimeout(connectTimeout, 'connectTimeout');
    _requireTimeout(sendTimeout, 'sendTimeout');
    _requireTimeout(receiveTimeout, 'receiveTimeout');
    _dio.options.connectTimeout = connectTimeout;
    _dio.options.sendTimeout = sendTimeout;
    _dio.options.receiveTimeout = receiveTimeout;
  }

  static const int _maximumRequestBytes = 64 * 1024;
  static const int _maximumResponseBytes = 256 * 1024;

  final Dio _dio;
  final Uri _baseUri;
  final FinanceRequestIdFactory _requestIdFactory;

  @override
  Future<FinanceEntryResult<FinanceAccountSetup>> listAccounts({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/accounts',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.account,
      parse: _parseAccountSetup,
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountEvaluation>> evaluateAccount({
    required String accessToken,
    required FinanceAccountDraft draft,
  }) {
    try {
      validateAccountDraft(draft);
    } on Object {
      return Future.value(_localFailure(FinanceEntryFailureKind.invalidInput));
    }
    return _request(
      method: 'POST',
      path: '/api/v1/accounts/evaluate',
      accessToken: accessToken,
      body: <String, Object?>{'draft': draft.toJson()},
      acceptedStatuses: const {200},
      contract: _ContractKind.account,
      parse: _parseAccountEvaluation,
    );
  }

  @override
  Future<FinanceEntryResult<FinanceAccountCommit>> commitAccount({
    required String accessToken,
    required FinanceAccountCommitCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/accounts/commit',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.account,
      parse: (json, statusCode) =>
          _parseAccountCommit(json, statusCode: statusCode, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineEvaluation>> evaluateBaseline({
    required String accessToken,
    required FinanceBaselineDraft draft,
  }) {
    try {
      FinanceBaselineDraft.fromJson(draft.toJson());
    } on Object {
      return Future.value(_localFailure(FinanceEntryFailureKind.invalidInput));
    }
    return _request(
      method: 'POST',
      path: '/api/v1/accounts/baseline/evaluate',
      accessToken: accessToken,
      body: <String, Object?>{'draft': draft.toJson()},
      acceptedStatuses: const {200},
      contract: _ContractKind.baseline,
      parse: _parseBaselineEvaluation,
    );
  }

  @override
  Future<FinanceEntryResult<FinanceBaselineCommit>> commitBaseline({
    required String accessToken,
    required FinanceBaselineCommitCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/accounts/baseline/commit',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.baseline,
      parse: (json, statusCode) => _parseBaselineCommit(json, command: command),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation({
    required String accessToken,
    required FinanceOperationDraft draft,
  }) {
    try {
      validateOperationDraft(draft);
    } on Object {
      return Future.value(_localFailure(FinanceEntryFailureKind.invalidInput));
    }
    return _request(
      method: 'POST',
      path: '/api/v1/operations/evaluate',
      accessToken: accessToken,
      body: <String, Object?>{'draft': draft.toJson()},
      acceptedStatuses: const {200},
      contract: _ContractKind.operation,
      parse: _parseOperationEvaluation,
    );
  }

  @override
  Future<FinanceEntryResult<FinanceOperationCommit>> commitOperation({
    required String accessToken,
    required FinanceOperationCommitCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/operations/commit',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.operation,
      parse: (json, statusCode) =>
          _parseOperationCommit(json, statusCode: statusCode, command: command),
    );
  }

  Future<FinanceEntryResult<T>> _request<T>({
    required String method,
    required String path,
    required String accessToken,
    required Set<int> acceptedStatuses,
    required _ContractKind contract,
    required T Function(Map<String, Object?>, int) parse,
    Map<String, Object?>? body,
  }) async {
    final localRequestId = _safeRequestId(_requestIdFactory);
    var effectiveRequestId = localRequestId;
    final token = _safeAccessToken(accessToken);
    if (token == null) {
      return _failure(
        kind: FinanceEntryFailureKind.unauthenticated,
        requestId: localRequestId,
      );
    }

    if (body != null) {
      try {
        if (utf8.encode(jsonEncode(body)).length > _maximumRequestBytes) {
          return _failure(
            kind: FinanceEntryFailureKind.invalidInput,
            requestId: localRequestId,
          );
        }
      } on Object {
        return _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: localRequestId,
        );
      }
    }

    try {
      final response = await _dio.request<Object?>(
        _baseUri.resolve(path).toString(),
        data: body,
        options: Options(
          method: method,
          headers: <String, Object>{
            Headers.acceptHeader: Headers.jsonContentType,
            if (body != null)
              Headers.contentTypeHeader: Headers.jsonContentType,
            'Authorization': 'Bearer $token',
            'X-Correlation-ID': localRequestId,
          },
          responseType: ResponseType.bytes,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: true,
          validateStatus: (status) => status != null && status >= 200,
        ),
      );
      final requestId = _responseRequestId(response.headers, localRequestId);
      effectiveRequestId = requestId;
      final statusCode = response.statusCode;
      if (statusCode == null) {
        return _failure(
          kind: FinanceEntryFailureKind.malformedResponse,
          requestId: requestId,
        );
      }
      if (!acceptedStatuses.contains(statusCode)) {
        return _httpFailure<T>(
          statusCode: statusCode,
          bytes: _tryBoundedBytes(response.data),
          requestId: requestId,
          contract: contract,
        );
      }
      final json = _decodeObject(_boundedBytes(response.data));
      return FinanceEntrySuccess<T>(
        requestId: requestId,
        value: parse(json, statusCode),
      );
    } on DioException catch (error) {
      return _dioFailure<T>(error, localRequestId, contract);
    } on FormatException {
      return _failure(
        kind: FinanceEntryFailureKind.malformedResponse,
        requestId: effectiveRequestId,
      );
    } on Object {
      return _failure(
        kind: FinanceEntryFailureKind.unknown,
        requestId: effectiveRequestId,
      );
    }
  }
}

FinanceAccountSetup _parseAccountSetup(
  Map<String, Object?> json,
  int statusCode,
) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {
    'schemaVersion',
    'canonicalTimezone',
    'timezoneRevision',
    'accounts',
  });
  _requireSchema(json);
  final timezone = json['canonicalTimezone'];
  if (timezone != null && timezone is! String) {
    throw const FormatException('Invalid canonical timezone.');
  }
  final revision = json['timezoneRevision'];
  final rawAccounts = json['accounts'];
  if (revision is! int || rawAccounts is! List<Object?>) {
    throw const FormatException('Invalid account setup.');
  }
  final accounts = rawAccounts
      .map((value) {
        return FinanceAccount.fromJson(_object(value));
      })
      .toList(growable: false);
  return FinanceAccountSetup(
    canonicalTimezone: timezone as String?,
    timezoneRevision: revision,
    accounts: accounts,
  );
}

FinanceAccountEvaluation _parseAccountEvaluation(
  Map<String, Object?> json,
  int statusCode,
) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'draft',
    'draftHash',
    'issues',
  });
  _requireSchema(json);
  final draft = FinanceAccountDraft.fromJson(_object(json['draft']));
  final issues = _issues(json['issues'], contract: _ContractKind.account);
  return switch (json['decision']) {
    'NEEDS_CONFIRMATION' when issues.isEmpty => FinanceAccountNeedsConfirmation(
      draft: draft,
      draftHash: validateDraftHash(_requiredString(json, 'draftHash')),
    ),
    'REJECT' when json['draftHash'] == null && issues.isNotEmpty =>
      FinanceAccountRejected(draft: draft, issues: issues),
    _ => throw const FormatException('Invalid account evaluation.'),
  };
}

FinanceBaselineEvaluation _parseBaselineEvaluation(
  Map<String, Object?> json,
  int statusCode,
) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'draft',
    'draftHash',
    'currentOpeningBalanceOn',
    'earliestOperationOn',
    'issues',
  });
  _requireSchema(json);
  final draft = FinanceBaselineDraft.fromJson(_object(json['draft']));
  final current = _accountDate(json, 'currentOpeningBalanceOn');
  final earliest = _optionalAccountDate(json, 'earliestOperationOn');
  final issues = _baselineIssues(json['issues']);
  return switch (json['decision']) {
    'NEEDS_CONFIRMATION' when issues.isEmpty =>
      FinanceBaselineNeedsConfirmation(
        draft: draft,
        currentOpeningBalanceOn: current,
        earliestOperationOn: earliest,
        draftHash: validateDraftHash(_requiredString(json, 'draftHash')),
      ),
    'REJECT' when json['draftHash'] == null && issues.isNotEmpty =>
      FinanceBaselineRejected(
        draft: draft,
        currentOpeningBalanceOn: current,
        earliestOperationOn: earliest,
        issues: issues,
      ),
    _ => throw const FormatException('Invalid baseline evaluation.'),
  };
}

FinanceBaselineCommit _parseBaselineCommit(
  Map<String, Object?> json, {
  required FinanceBaselineCommitCommand command,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'idempotentReplay',
    'previousOpeningBalanceOn',
    'account',
  });
  _requireSchema(json);
  if (json['decision'] != 'ACCEPT') {
    throw const FormatException('Invalid baseline commit.');
  }
  final replay = json['idempotentReplay'];
  if (replay is! bool) {
    throw const FormatException('Invalid baseline commit replay flag.');
  }
  final previous = _accountDate(json, 'previousOpeningBalanceOn');
  final account = FinanceAccount.fromJson(_object(json['account']));
  // The response must describe the correction that was actually confirmed,
  // and it must never move a baseline later than it already was.
  if (account.accountId != command.draft.accountId ||
      account.openingBalanceOn != command.draft.openingBalanceOn ||
      account.openingBalanceOn.compareTo(previous) > 0) {
    throw const FormatException('Baseline commit does not match the review.');
  }
  return FinanceBaselineCommit(
    idempotentReplay: replay,
    previousOpeningBalanceOn: previous,
    account: account,
  );
}

List<FinanceBaselineIssue> _baselineIssues(Object? value) {
  if (value is! List<Object?> || value.length > 16) {
    throw const FormatException('Invalid baseline issues.');
  }
  return List<FinanceBaselineIssue>.unmodifiable(
    value.map((item) => FinanceBaselineIssue.fromJson(_object(item))),
  );
}

FinanceAccountCommit _parseAccountCommit(
  Map<String, Object?> json, {
  required int statusCode,
  required FinanceAccountCommitCommand command,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'idempotentReplay',
    'canonicalTimezone',
    'timezoneRevision',
    'account',
  });
  _requireSchema(json);
  if (json['decision'] != 'ACCEPT' || json['timezoneRevision'] != 1) {
    throw const FormatException('Invalid account commit.');
  }
  final replay = json['idempotentReplay'];
  final timezone = json['canonicalTimezone'];
  if (replay is! bool || timezone is! String || (statusCode == 200) != replay) {
    throw const FormatException('Invalid account commit status.');
  }
  final account = FinanceAccount.fromJson(_object(json['account']));
  final draft = command.review.draft;
  if (account.commandId != draft.commandId ||
      account.name != draft.name ||
      account.currency != draft.currency ||
      account.openingBalance != draft.openingBalance ||
      account.openingBalanceOn != draft.openingBalanceOn ||
      account.openingTimezone != draft.canonicalTimezone ||
      !_sameInstant(account.confirmedAt, command.confirmedAt) ||
      timezone != account.openingTimezone) {
    throw const FormatException('Account commit does not match review.');
  }
  return FinanceAccountCommit(
    idempotentReplay: replay,
    canonicalTimezone: timezone,
    timezoneRevision: 1,
    account: account,
  );
}

FinanceOperationEvaluation _parseOperationEvaluation(
  Map<String, Object?> json,
  int statusCode,
) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'draft',
    'draftHash',
    'issues',
  });
  _requireSchema(json);
  final draft = FinanceOperationDraft.fromJson(_object(json['draft']));
  final issues = _issues(json['issues'], contract: _ContractKind.operation);
  return switch (json['decision']) {
    'NEEDS_CONFIRMATION' when issues.isEmpty =>
      FinanceOperationNeedsConfirmation(
        draft: draft,
        draftHash: validateDraftHash(_requiredString(json, 'draftHash')),
      ),
    'REJECT' when json['draftHash'] == null && issues.isNotEmpty =>
      FinanceOperationRejected(draft: draft, issues: issues),
    _ => throw const FormatException('Invalid operation evaluation.'),
  };
}

FinanceOperationCommit _parseOperationCommit(
  Map<String, Object?> json, {
  required int statusCode,
  required FinanceOperationCommitCommand command,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'idempotentReplay',
    'operation',
  });
  _requireSchema(json);
  if (json['decision'] != 'ACCEPT') {
    throw const FormatException('Invalid operation commit.');
  }
  final replay = json['idempotentReplay'];
  if (replay is! bool || (statusCode == 200) != replay) {
    throw const FormatException('Invalid operation commit status.');
  }
  final operation = CommittedFinanceOperation.fromJson(
    _object(json['operation']),
  );
  final draft = command.review.draft;
  if (operation.commandId != draft.commandId ||
      operation.type != draft.type ||
      operation.amount != draft.amount ||
      operation.currency != draft.currency ||
      operation.accountId != draft.accountId ||
      operation.category != draft.category ||
      operation.merchant != draft.merchant ||
      operation.capturedAt != draft.capturedAt ||
      operation.capturedTimezone != draft.capturedTimezone ||
      operation.sourceExpression != draft.sourceExpression ||
      operation.dateResolverVersion != draft.dateResolverVersion ||
      operation.occurredOn != draft.occurredOn ||
      operation.occurredAt != draft.occurredAt ||
      operation.source != draft.source ||
      !_sameInstant(operation.confirmedAt, command.confirmedAt)) {
    throw const FormatException('Operation commit does not match review.');
  }
  return FinanceOperationCommit(idempotentReplay: replay, operation: operation);
}

FinanceEntryResult<T> _httpFailure<T>({
  required int statusCode,
  required List<int>? bytes,
  required String requestId,
  required _ContractKind contract,
}) {
  if (statusCode == 401) {
    return _failure(
      kind: FinanceEntryFailureKind.unauthorized,
      requestId: requestId,
    );
  }
  if (statusCode == 404) {
    final detail = _tryErrorDetail(bytes, contract: contract);
    if (contract != _ContractKind.baseline ||
        detail?.code != FinanceEntryErrorCode.accountUnavailable) {
      return _failure(
        kind: FinanceEntryFailureKind.malformedResponse,
        requestId: requestId,
      );
    }
    return _failure(
      kind: FinanceEntryFailureKind.conflict,
      requestId: requestId,
      code: detail!.code,
    );
  }
  if (statusCode == 503 || statusCode == 429 || statusCode >= 500) {
    final detail = _tryErrorDetail(bytes, contract: contract);
    if (detail?.code == FinanceEntryErrorCode.accountUnavailable) {
      return _failure(
        kind: FinanceEntryFailureKind.malformedResponse,
        requestId: requestId,
      );
    }
    return _failure(
      kind: FinanceEntryFailureKind.serviceUnavailable,
      requestId: requestId,
      code: detail?.code,
    );
  }
  if (statusCode == 409 || statusCode == 422) {
    final detail = _tryErrorDetail(bytes, contract: contract);
    if (detail == null ||
        detail.code == FinanceEntryErrorCode.accountUnavailable) {
      return _failure(
        kind: FinanceEntryFailureKind.malformedResponse,
        requestId: requestId,
      );
    }
    final kind = switch (detail.code) {
      FinanceEntryErrorCode.accountRejected ||
      FinanceEntryErrorCode.baselineRejected ||
      FinanceEntryErrorCode.operationRejected =>
        FinanceEntryFailureKind.rejected,
      FinanceEntryErrorCode.malformedAccount ||
      FinanceEntryErrorCode.malformedOperation =>
        FinanceEntryFailureKind.invalidInput,
      _ when statusCode == 409 => FinanceEntryFailureKind.conflict,
      _ => FinanceEntryFailureKind.invalidInput,
    };
    return _failure(
      kind: kind,
      requestId: requestId,
      code: detail.code,
      issues: detail.issues,
      baselineIssues: detail.baselineIssues,
    );
  }
  return _failure(kind: FinanceEntryFailureKind.unknown, requestId: requestId);
}

FinanceEntryResult<T> _dioFailure<T>(
  DioException error,
  String localRequestId,
  _ContractKind contract,
) {
  final requestId = error.response == null
      ? localRequestId
      : _responseRequestId(error.response!.headers, localRequestId);
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => _failure(
      kind: FinanceEntryFailureKind.timeout,
      requestId: requestId,
    ),
    DioExceptionType.connectionError => _failure(
      kind: FinanceEntryFailureKind.offline,
      requestId: requestId,
    ),
    DioExceptionType.badResponse => _httpFailure(
      statusCode: error.response?.statusCode ?? 0,
      bytes: _tryBoundedBytes(error.response?.data),
      requestId: requestId,
      contract: contract,
    ),
    DioExceptionType.badCertificate => _failure(
      kind: FinanceEntryFailureKind.securityFailure,
      requestId: requestId,
    ),
    DioExceptionType.cancel || DioExceptionType.unknown => _failure(
      kind: FinanceEntryFailureKind.unknown,
      requestId: requestId,
    ),
  };
}

_ErrorDetail? _tryErrorDetail(
  List<int>? bytes, {
  required _ContractKind contract,
}) {
  if (bytes == null) return null;
  try {
    final root = _decodeObject(bytes);
    _expectKeys(root, const {'detail'});
    final detail = _object(root['detail']);
    final rawCode = _requiredString(detail, 'code');
    final isBaselineRejection = rawCode == 'BASELINE_REJECTED';
    _expectKeys(
      detail,
      isBaselineRejection
          ? const {'code', 'issues', 'baselineIssues'}
          : const {'code', 'issues'},
    );
    final code = _errorCode(rawCode);
    if (!_errorAllowed(code, contract)) {
      throw const FormatException('Wrong Finance error contract.');
    }
    final issueContract = contract == _ContractKind.operation
        ? _ContractKind.operation
        : _ContractKind.account;
    final issues = _issues(detail['issues'], contract: issueContract);
    final baselineIssues = isBaselineRejection
        ? _baselineIssues(detail['baselineIssues'])
        : const <FinanceBaselineIssue>[];
    final rejection =
        code == FinanceEntryErrorCode.accountRejected ||
        code == FinanceEntryErrorCode.baselineRejected ||
        code == FinanceEntryErrorCode.operationRejected;
    final hasMatchingIssues = code == FinanceEntryErrorCode.baselineRejected
        ? issues.isEmpty && baselineIssues.isNotEmpty
        : issues.isNotEmpty && baselineIssues.isEmpty;
    if (rejection != hasMatchingIssues) {
      throw const FormatException('Inconsistent Finance rejection detail.');
    }
    return _ErrorDetail(
      code: code,
      issues: issues,
      baselineIssues: baselineIssues,
    );
  } on Object {
    return null;
  }
}

List<FinanceIssue> _issues(Object? raw, {required _ContractKind contract}) {
  if (raw is! List<Object?> || raw.length > 16) {
    throw const FormatException('Invalid Finance issues.');
  }
  final issues = raw
      .map((item) {
        final issue = FinanceIssue.fromJson(_object(item));
        if (!_issueAllowed(issue.code, contract)) {
          throw const FormatException('Wrong Finance issue contract.');
        }
        return issue;
      })
      .toList(growable: false);
  return issues;
}

bool _issueAllowed(FinanceIssueCode code, _ContractKind contract) {
  return switch (contract) {
    _ContractKind.account => const {
      FinanceIssueCode.accountAlreadyInitialized,
      FinanceIssueCode.openingBalanceDateInFuture,
      FinanceIssueCode.unsupportedCurrency,
    }.contains(code),
    _ContractKind.baseline => false,
    _ContractKind.operation => const {
      FinanceIssueCode.accountRequired,
      FinanceIssueCode.accountUnavailable,
      FinanceIssueCode.accountCurrencyMismatch,
      FinanceIssueCode.operationBeforeAccountBaseline,
      FinanceIssueCode.futureOccurredDate,
      FinanceIssueCode.relativeDateMismatch,
      FinanceIssueCode.occurredAtDateMismatch,
      FinanceIssueCode.confirmationBeforeCapture,
      FinanceIssueCode.unsupportedDateExpression,
      FinanceIssueCode.unsupportedCurrency,
    }.contains(code),
  };
}

bool _errorAllowed(FinanceEntryErrorCode code, _ContractKind contract) {
  const shared = {
    FinanceEntryErrorCode.confirmationMismatch,
    FinanceEntryErrorCode.commandConflict,
    FinanceEntryErrorCode.authenticationUnavailable,
    FinanceEntryErrorCode.financePersistenceUnavailable,
  };
  if (shared.contains(code)) return true;
  return switch (contract) {
    _ContractKind.account => const {
      FinanceEntryErrorCode.malformedAccount,
      FinanceEntryErrorCode.accountAlreadyInitialized,
      FinanceEntryErrorCode.accountRejected,
    }.contains(code),
    _ContractKind.baseline => const {
      FinanceEntryErrorCode.malformedAccount,
      FinanceEntryErrorCode.confirmationMismatch,
      FinanceEntryErrorCode.commandConflict,
      FinanceEntryErrorCode.accountAlreadyInitialized,
      FinanceEntryErrorCode.accountRejected,
      FinanceEntryErrorCode.accountUnavailable,
      FinanceEntryErrorCode.baselineRejected,
      FinanceEntryErrorCode.authenticationUnavailable,
      FinanceEntryErrorCode.financePersistenceUnavailable,
    }.contains(code),
    _ContractKind.operation => const {
      FinanceEntryErrorCode.malformedOperation,
      FinanceEntryErrorCode.operationRejected,
    }.contains(code),
  };
}

FinanceEntryErrorCode _errorCode(String value) => switch (value) {
  'MALFORMED_ACCOUNT' => FinanceEntryErrorCode.malformedAccount,
  'MALFORMED_OPERATION' => FinanceEntryErrorCode.malformedOperation,
  'CONFIRMATION_MISMATCH' => FinanceEntryErrorCode.confirmationMismatch,
  'COMMAND_CONFLICT' => FinanceEntryErrorCode.commandConflict,
  'ACCOUNT_ALREADY_INITIALIZED' =>
    FinanceEntryErrorCode.accountAlreadyInitialized,
  'ACCOUNT_REJECTED' => FinanceEntryErrorCode.accountRejected,
  'ACCOUNT_UNAVAILABLE' => FinanceEntryErrorCode.accountUnavailable,
  'BASELINE_REJECTED' => FinanceEntryErrorCode.baselineRejected,
  'OPERATION_REJECTED' => FinanceEntryErrorCode.operationRejected,
  'AUTHENTICATION_UNAVAILABLE' =>
    FinanceEntryErrorCode.authenticationUnavailable,
  'FINANCE_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.financePersistenceUnavailable,
  _ => throw const FormatException('Unknown Finance error code.'),
};

FinanceEntryFailureResult<T> _failure<T>({
  required FinanceEntryFailureKind kind,
  required String requestId,
  FinanceEntryErrorCode? code,
  List<FinanceIssue> issues = const [],
  List<FinanceBaselineIssue> baselineIssues = const [],
}) {
  return FinanceEntryFailureResult<T>(
    FinanceEntryFailure(
      kind: kind,
      requestId: requestId,
      code: code,
      issues: issues,
      baselineIssues: baselineIssues,
    ),
  );
}

FinanceEntryFailureResult<T> _localFailure<T>(FinanceEntryFailureKind kind) {
  return _failure(kind: kind, requestId: 'req_local_finance_entry');
}

List<int> _boundedBytes(Object? raw) {
  final bytes = _tryBoundedBytes(raw);
  if (bytes == null) throw const FormatException('Invalid response body.');
  return bytes;
}

List<int>? _tryBoundedBytes(Object? raw) {
  if (raw is! List<int> ||
      raw.isEmpty ||
      raw.length > FinanceEntryApi._maximumResponseBytes) {
    return null;
  }
  return raw;
}

Map<String, Object?> _decodeObject(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  return _object(decoded);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('Expected JSON object.');
  try {
    return Map<String, Object?>.from(value);
  } on Object {
    throw const FormatException('Invalid JSON object.');
  }
}

void _expectKeys(Map<String, Object?> json, Set<String> expected) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw const FormatException('Unexpected Finance response fields.');
  }
}

void _requireSchema(Map<String, Object?> json) {
  if (json['schemaVersion'] != '1') {
    throw const FormatException('Unsupported Finance schema version.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

String? _safeAccessToken(String value) {
  if (value.isEmpty || value.length > 8192 || _containsControl(value)) {
    return null;
  }
  return value;
}

String _safeRequestId(FinanceRequestIdFactory factory) {
  try {
    final value = factory();
    if (value.isNotEmpty && value.length <= 128 && !_containsControl(value)) {
      return value;
    }
  } on Object {
    // Fall through to a locally generated opaque value.
  }
  return _newRequestId();
}

String _responseRequestId(Headers headers, String fallback) {
  final values = headers['x-request-id'];
  if (values == null || values.length != 1) return fallback;
  final value = values.single;
  if (value.isEmpty || value.length > 128 || _containsControl(value)) {
    return fallback;
  }
  return value;
}

String _newRequestId() {
  final random = Random.secure();
  final values = List<int>.generate(16, (_) => random.nextInt(256));
  return 'req_${values.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
}

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme ||
      !value.hasAuthority ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment) {
    throw ArgumentError.value(value, 'baseUri', 'Invalid API base URI.');
  }
  if (value.scheme != 'https' &&
      !(value.scheme == 'http' && _isLoopback(value.host))) {
    throw ArgumentError.value(
      value,
      'baseUri',
      'HTTPS is required except for loopback development.',
    );
  }
  return value;
}

bool _isLoopback(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

void _requireTimeout(Duration value, String name) {
  if (value <= Duration.zero || value > const Duration(minutes: 1)) {
    throw ArgumentError.value(
      value,
      name,
      'Must be between zero and one minute.',
    );
  }
}

bool _containsControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

bool _sameInstant(String first, String second) =>
    DateTime.parse(first).toUtc() == DateTime.parse(second).toUtc();

String _accountDate(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null ||
      parsed.toIso8601String().substring(0, 10) != value ||
      parsed.year < 1900 ||
      parsed.year > 2100) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String? _optionalAccountDate(Map<String, Object?> json, String key) {
  if (json[key] == null) return null;
  return _accountDate(json, key);
}

enum _ContractKind { account, baseline, operation }

final class _ErrorDetail {
  const _ErrorDetail({
    required this.code,
    required this.issues,
    required this.baselineIssues,
  });

  final FinanceEntryErrorCode code;
  final List<FinanceIssue> issues;
  final List<FinanceBaselineIssue> baselineIssues;
}
