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

  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone({
    required String accessToken,
    required FinanceTimezoneCommand command,
  });

  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer({
    required String accessToken,
    required FinanceTransferDraft draft,
  });

  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer({
    required String accessToken,
    required FinanceTransferCommitCommand command,
  });

  Future<FinanceEntryResult<FinanceOperationEvaluation>> evaluateOperation({
    required String accessToken,
    required FinanceOperationDraft draft,
  });

  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost({
    required String accessToken,
    required PlannedCostDraft draft,
  });

  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts({
    required String accessToken,
  });

  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost({
    required String accessToken,
    required String plannedCostId,
    required PlannedCostTransitionCommand command,
  });

  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence({
    required String accessToken,
    required PlannedCostRecurrenceDraft draft,
  });

  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences({required String accessToken});

  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence({
    required String accessToken,
    required String recurrenceId,
    required EndPlannedCostRecurrenceCommand command,
  });

  Future<FinanceEntryResult<FinanceCategoryList>> listCategories({
    required String accessToken,
  });

  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required String accessToken,
    required int limit,
    String? cursor,
  });

  Future<FinanceEntryResult<OperationCorrected>> correctOperation({
    required String accessToken,
    required OperationCorrectionCommand command,
  });

  Future<FinanceEntryResult<OperationRemoved>> removeOperation({
    required String accessToken,
    required OperationRemovalCommand command,
  });

  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics({
    required String accessToken,
  });

  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets({
    required String accessToken,
  });

  Future<FinanceEntryResult<BudgetWritten>> setBudget({
    required String accessToken,
    required SetBudgetCommand command,
  });

  Future<FinanceEntryResult<BudgetWritten>> removeBudget({
    required String accessToken,
    required String budgetId,
    required RemoveBudgetCommand command,
  });

  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate({
    required String accessToken,
  });

  /// Downloads the published build to [savePath], reporting progress.
  ///
  /// Separate from every other call because it is the one response measured in
  /// tens of megabytes: it is streamed to a file rather than decoded.
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String accessToken,
    required String savePath,
    required void Function(int received, int total) onProgress,
  });

  /// Saves every fact the person owns, as stored, to [savePath] (ADR 0030).
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String accessToken,
    required String savePath,
  });

  /// Saves the person's operations, as a spreadsheet, to [savePath].
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String accessToken,
    required String savePath,
  });

  /// Schedules erasure of the person's own account a week out and signs every
  /// device out (ADR 0030). Answers when the erasure will happen.
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String accessToken,
    required String password,
  });

  Future<FinanceEntryResult<UserProfile>> readProfile({
    required String accessToken,
  });

  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required String accessToken,
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  });

  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String accessToken,
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  });

  /// Reads the same sentence as an exchange. Answers null inside a success
  /// when it is not one.
  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String accessToken,
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  });

  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories({
    required String accessToken,
  });

  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory({
    required String accessToken,
    required CreateCategoryCommand command,
  });

  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory({
    required String accessToken,
    required String categoryId,
    required RenameCategoryCommand command,
  });

  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory({
    required String accessToken,
    required String categoryId,
  });

  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory({
    required String accessToken,
    required String categoryId,
  });

  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords({
    required String accessToken,
    required String categoryId,
  });

  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords({
    required String accessToken,
    required String categoryId,
    required List<String> keywords,
  });

  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal({
    required String accessToken,
    required SavingsGoalDraft draft,
  });

  Future<FinanceEntryResult<SavingsGoalList>> listGoals({
    required String accessToken,
  });

  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution({
    required String accessToken,
    required String goalId,
    required GoalContributionCommand command,
  });

  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal({
    required String accessToken,
    required String goalId,
    required FinanceGoalCancelCommand command,
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
  Future<FinanceEntryResult<FinanceTimezoneCorrected>> correctTimezone({
    required String accessToken,
    required FinanceTimezoneCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/accounts/timezone',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.timezone,
      parse: (json, statusCode) => FinanceTimezoneCorrected.fromJson(json),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTransferEvaluation>> evaluateTransfer({
    required String accessToken,
    required FinanceTransferDraft draft,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/transfers/evaluate',
      accessToken: accessToken,
      body: <String, Object?>{'draft': draft.toJson()},
      acceptedStatuses: const {200},
      contract: _ContractKind.transfer,
      parse: (json, statusCode) => FinanceTransferEvaluation.fromJson(json),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceTransferCommitted>> commitTransfer({
    required String accessToken,
    required FinanceTransferCommitCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/transfers/commit',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.transfer,
      parse: (json, statusCode) => FinanceTransferCommitted.fromJson(json),
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

  @override
  Future<FinanceEntryResult<OperationCorrected>> correctOperation({
    required String accessToken,
    required OperationCorrectionCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/operations/correction',
      accessToken: accessToken,
      body: command.toJson(),
      // 201 on the first accepted command, 200 on an idempotent replay.
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.operationReversal,
      parse: (json, statusCode) => _parseOperationCorrected(
        json,
        statusCode: statusCode,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<OperationRemoved>> removeOperation({
    required String accessToken,
    required OperationRemovalCommand command,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/operations/removal',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.operationReversal,
      parse: (json, statusCode) => _parseOperationRemoved(
        json,
        statusCode: statusCode,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostCreated>> createPlannedCost({
    required String accessToken,
    required PlannedCostDraft draft,
  }) {
    try {
      validatePlannedCostDraft(draft);
    } on Object {
      return Future<FinanceEntryResult<PlannedCostCreated>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/planned-costs',
      accessToken: accessToken,
      body: draft.toJson(),
      // 201 on the first accepted command, 200 on an idempotent replay.
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.plannedCost,
      parse: (json, statusCode) =>
          _parsePlannedCostCreated(json, statusCode: statusCode, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostList>> listPlannedCosts({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/planned-costs',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.plannedCost,
      parse: (json, statusCode) => _parsePlannedCostList(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostSettled>> transitionPlannedCost({
    required String accessToken,
    required String plannedCostId,
    required PlannedCostTransitionCommand command,
  }) {
    try {
      validatePlannedCostTransition(command);
      validatePlannedCostId(plannedCostId);
    } on Object {
      return Future<FinanceEntryResult<PlannedCostSettled>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/planned-costs/$plannedCostId/transition',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.plannedCost,
      parse: (json, statusCode) => _parsePlannedCostSettled(
        json,
        statusCode: statusCode,
        plannedCostId: plannedCostId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>
  createPlannedCostRecurrence({
    required String accessToken,
    required PlannedCostRecurrenceDraft draft,
  }) {
    try {
      validatePlannedCostRecurrenceDraft(draft);
    } on Object {
      return Future<FinanceEntryResult<PlannedCostRecurrenceCreated>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/planned-cost-recurrences',
      accessToken: accessToken,
      body: draft.toJson(),
      // 201 on the first accepted command, 200 on an idempotent replay.
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.plannedCostRecurrence,
      parse: (json, statusCode) =>
          _parseRecurrenceCreated(json, statusCode: statusCode, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceList>>
  listPlannedCostRecurrences({required String accessToken}) {
    return _request(
      method: 'GET',
      path: '/api/v1/planned-cost-recurrences',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.plannedCostRecurrence,
      parse: (json, statusCode) => _parseRecurrenceList(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>
  endPlannedCostRecurrence({
    required String accessToken,
    required String recurrenceId,
    required EndPlannedCostRecurrenceCommand command,
  }) {
    try {
      validateEndPlannedCostRecurrence(command);
      validateRecurrenceId(recurrenceId);
    } on Object {
      return Future<FinanceEntryResult<PlannedCostRecurrenceEnded>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/planned-cost-recurrences/$recurrenceId/end',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.plannedCostRecurrence,
      parse: (json, statusCode) => _parseRecurrenceEnded(
        json,
        statusCode: statusCode,
        recurrenceId: recurrenceId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<FinanceCategoryList>> listCategories({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/categories',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseCategoryList(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<OperationHistoryList>> listOperations({
    required String accessToken,
    required int limit,
    String? cursor,
  }) {
    try {
      if (limit < 1 || limit > 100) throw const FormatException('limit');
      if (cursor != null) validatedOperationCursor(cursor);
    } on Object {
      return Future<FinanceEntryResult<OperationHistoryList>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    final query = cursor == null
        ? 'limit=$limit'
        : 'limit=$limit&cursor=${Uri.encodeQueryComponent(cursor)}';
    return _request(
      method: 'GET',
      path: '/api/v1/operations?$query',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.operation,
      parse: (json, statusCode) => _parseOperationHistory(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<AnalyticsSummary>> readAnalytics({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/analytics',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.analytics,
      parse: (json, statusCode) => _parseAnalytics(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<CategoryKeywords>> listCategoryKeywords({
    required String accessToken,
    required String categoryId,
  }) {
    try {
      validateCategoryId(categoryId);
    } on Object {
      return Future<FinanceEntryResult<CategoryKeywords>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'GET',
      path: '/api/v1/categories/$categoryId/keywords',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseCategoryKeywords(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<CategoryKeywords>> replaceCategoryKeywords({
    required String accessToken,
    required String categoryId,
    required List<String> keywords,
  }) {
    final List<String> normalized;
    try {
      validateCategoryId(categoryId);
      normalized = [
        for (final word in keywords) validatedCategoryKeyword(word),
      ];
      if (normalized.toSet().length != normalized.length ||
          normalized.length > maximumCategoryKeywords) {
        throw const FormatException('Invalid category keywords.');
      }
    } on Object {
      return Future<FinanceEntryResult<CategoryKeywords>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    // The whole set travels, so the write stays idempotent by target state.
    return _request(
      method: 'PUT',
      path: '/api/v1/categories/$categoryId/keywords',
      accessToken: accessToken,
      body: <String, Object?>{'schemaVersion': '1', 'keywords': normalized},
      acceptedStatuses: const {200},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseCategoryKeywords(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetsSnapshot>> readBudgets({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/budgets',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.budget,
      parse: (json, statusCode) {
        if (statusCode != 200) throw const FormatException('Invalid status.');
        return BudgetsSnapshot.fromJson(json);
      },
    );
  }

  @override
  Future<FinanceEntryResult<BudgetWritten>> setBudget({
    required String accessToken,
    required SetBudgetCommand command,
  }) {
    try {
      validateSetBudget(command);
    } on Object {
      return Future<FinanceEntryResult<BudgetWritten>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      // Idempotent by target state: saying 400 twice leaves one ceiling of 400.
      method: 'PUT',
      path: '/api/v1/budgets',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.budget,
      parse: (json, statusCode) => _parseBudgetWritten(
        json,
        statusCode: statusCode,
        expectedCategoryId: command.categoryId,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<BudgetWritten>> removeBudget({
    required String accessToken,
    required String budgetId,
    required RemoveBudgetCommand command,
  }) {
    try {
      validateRemoveBudget(command);
      validateBudgetId(budgetId);
    } on Object {
      return Future<FinanceEntryResult<BudgetWritten>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/budgets/$budgetId/remove',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.budget,
      parse: (json, statusCode) {
        if (statusCode != 200) throw const FormatException('Invalid status.');
        final written = BudgetWritten.fromRemovalJson(json);
        if (written.budgetId != budgetId) {
          throw const FormatException('Server removed a different budget.');
        }
        return written;
      },
    );
  }

  @override
  Future<FinanceEntryResult<AppUpdateManifest>> readAppUpdate({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/app/update',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.appRelease,
      parse: (json, statusCode) {
        if (statusCode != 200) throw const FormatException('Invalid status.');
        return AppUpdateManifest.fromJson(json);
      },
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadAppRelease({
    required String accessToken,
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) {
    return _downloadTo(
      '/api/v1/app/download',
      accessToken: accessToken,
      savePath: savePath,
      onProgress: onProgress,
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadAccountExport({
    required String accessToken,
    required String savePath,
  }) {
    return _downloadTo(
      '/api/v1/account/export',
      accessToken: accessToken,
      savePath: savePath,
    );
  }

  @override
  Future<FinanceEntryResult<void>> downloadOperationsTable({
    required String accessToken,
    required String savePath,
  }) {
    return _downloadTo(
      '/api/v1/account/export/operations.csv',
      accessToken: accessToken,
      savePath: savePath,
    );
  }

  @override
  Future<FinanceEntryResult<DateTime>> requestAccountDeletion({
    required String accessToken,
    required String password,
  }) {
    return _request(
      method: 'POST',
      path: '/api/v1/account/deletion',
      accessToken: accessToken,
      body: <String, Object?>{'schemaVersion': '1', 'password': password},
      acceptedStatuses: const {202},
      contract: _ContractKind.accountData,
      parse: (json, statusCode) => _parseDeletionScheduled(json, statusCode),
    );
  }

  /// Streams one authenticated response straight into a file.
  ///
  /// For the answers that are files rather than values — a build tens of
  /// megabytes long, or a copy of someone's whole financial record — which are
  /// written to disk as they arrive instead of being decoded in memory.
  Future<FinanceEntryResult<void>> _downloadTo(
    String path, {
    required String accessToken,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    final requestId = _safeRequestId(_requestIdFactory);
    final token = _safeAccessToken(accessToken);
    if (token == null) {
      return _failure(
        kind: FinanceEntryFailureKind.unauthenticated,
        requestId: requestId,
      );
    }
    try {
      await _dio.download(
        _baseUri.resolve(path).toString(),
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          headers: <String, Object>{
            'Authorization': 'Bearer $token',
            'X-Correlation-ID': requestId,
          },
          followRedirects: false,
          maxRedirects: 0,
          // Anything but 200 is a failure here: there is no partial answer to
          // interpret, only a file that did or did not arrive.
          validateStatus: (status) => status == 200,
        ),
      );
      return FinanceEntrySuccess<void>(requestId: requestId, value: null);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        return _failure(
          kind: FinanceEntryFailureKind.unauthenticated,
          requestId: requestId,
        );
      }
      return _failure(
        kind: switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout => FinanceEntryFailureKind.timeout,
          DioExceptionType.connectionError => FinanceEntryFailureKind.offline,
          _ =>
            statusCode == null
                ? FinanceEntryFailureKind.offline
                : FinanceEntryFailureKind.serviceUnavailable,
        },
        requestId: requestId,
      );
    } on Object {
      return _failure(
        kind: FinanceEntryFailureKind.unknown,
        requestId: requestId,
      );
    }
  }

  @override
  Future<FinanceEntryResult<UserProfile>> readProfile({
    required String accessToken,
  }) {
    // No identifier in the path: the caller is always the subject, so asking
    // for someone else's profile is unrepresentable rather than rejected.
    return _request(
      method: 'GET',
      path: '/api/v1/profile',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.profile,
      parse: (json, statusCode) => _parseProfile(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<AnalyticsWindow>> readAnalyticsWindow({
    required String accessToken,
    required AnalyticsPeriodKind period,
    String? from,
    String? to,
    String? accountId,
  }) {
    final custom = period == AnalyticsPeriodKind.custom;
    if (custom != (from != null && to != null)) {
      // Bounds belong to a custom window and only to it; sending them with a
      // named one asks for a window the user did not choose.
      return Future<FinanceEntryResult<AnalyticsWindow>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    final query = StringBuffer('period=${period.wire}');
    if (custom) {
      query.write('&from=${Uri.encodeQueryComponent(from!)}');
      query.write('&to=${Uri.encodeQueryComponent(to!)}');
    }
    // Naming none means the default wallet, which is what the balance card
    // shows. Figures are never added across wallets (ADR 0029).
    if (accountId != null) {
      query.write('&accountId=${Uri.encodeQueryComponent(accountId)}');
    }
    return _request(
      method: 'GET',
      path: '/api/v1/analytics/v2?$query',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.analytics,
      parse: (json, statusCode) => _parseAnalyticsWindow(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<OperationProposal>> parseOperationText({
    required String accessToken,
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) {
    final sentence = text.trim();
    if (sentence.isEmpty ||
        sentence.length > maximumEntryTextLength ||
        _containsControl(sentence)) {
      return Future<FinanceEntryResult<OperationProposal>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/operations/parse',
      accessToken: accessToken,
      body: <String, Object?>{
        'schemaVersion': '1',
        'text': sentence,
        'capturedAt': capturedAt,
        'capturedTimezone': capturedTimezone,
      },
      acceptedStatuses: const {200},
      contract: _ContractKind.textEntry,
      parse: (json, statusCode) => _parseProposal(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<TransferProposal?>> parseTransferText({
    required String accessToken,
    required String text,
    required String capturedAt,
    required String capturedTimezone,
  }) {
    final sentence = text.trim();
    if (sentence.isEmpty ||
        sentence.length > maximumEntryTextLength ||
        _containsControl(sentence)) {
      return Future<FinanceEntryResult<TransferProposal?>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/transfers/parse',
      accessToken: accessToken,
      body: <String, Object?>{
        'schemaVersion': '1',
        'text': sentence,
        'capturedAt': capturedAt,
        'capturedTimezone': capturedTimezone,
      },
      acceptedStatuses: const {200},
      contract: _ContractKind.textEntry,
      parse: (json, statusCode) => _parseTransferProposal(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedCategoryList>> listManagedCategories({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/categories/managed',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseManagedCategoryList(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> createCategory({
    required String accessToken,
    required CreateCategoryCommand command,
  }) {
    try {
      validatedCategoryName(command.name);
    } on Object {
      return Future<FinanceEntryResult<ManagedFinanceCategory>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/categories',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {201},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseCategory(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> renameCategory({
    required String accessToken,
    required String categoryId,
    required RenameCategoryCommand command,
  }) {
    try {
      validatedCategoryName(command.name);
      validateCategoryId(categoryId);
    } on Object {
      return Future<FinanceEntryResult<ManagedFinanceCategory>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'PATCH',
      path: '/api/v1/categories/$categoryId',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseCategory(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> archiveCategory({
    required String accessToken,
    required String categoryId,
  }) => _categoryTransition(
    accessToken: accessToken,
    categoryId: categoryId,
    action: 'archive',
  );

  @override
  Future<FinanceEntryResult<ManagedFinanceCategory>> restoreCategory({
    required String accessToken,
    required String categoryId,
  }) => _categoryTransition(
    accessToken: accessToken,
    categoryId: categoryId,
    action: 'restore',
  );

  Future<FinanceEntryResult<ManagedFinanceCategory>> _categoryTransition({
    required String accessToken,
    required String categoryId,
    required String action,
  }) {
    try {
      validateCategoryId(categoryId);
    } on Object {
      return Future<FinanceEntryResult<ManagedFinanceCategory>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/categories/$categoryId/$action',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.category,
      parse: (json, statusCode) => _parseCategory(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCreated>> createGoal({
    required String accessToken,
    required SavingsGoalDraft draft,
  }) {
    try {
      validateSavingsGoalDraft(draft);
    } on Object {
      return Future<FinanceEntryResult<SavingsGoalCreated>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/goals',
      accessToken: accessToken,
      body: draft.toJson(),
      // 201 on the first accepted command, 200 on an idempotent replay.
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.goal,
      parse: (json, statusCode) =>
          _parseGoalCreated(json, statusCode: statusCode, draft: draft),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalList>> listGoals({
    required String accessToken,
  }) {
    return _request(
      method: 'GET',
      path: '/api/v1/goals',
      accessToken: accessToken,
      acceptedStatuses: const {200},
      contract: _ContractKind.goal,
      parse: (json, statusCode) => _parseGoalList(json, statusCode),
    );
  }

  @override
  Future<FinanceEntryResult<GoalContributionRecorded>> recordGoalContribution({
    required String accessToken,
    required String goalId,
    required GoalContributionCommand command,
  }) {
    try {
      validateGoalContributionCommand(command);
      validateGoalId(goalId);
    } on Object {
      return Future<FinanceEntryResult<GoalContributionRecorded>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/goals/$goalId/contributions',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200, 201},
      contract: _ContractKind.goal,
      parse: (json, statusCode) => _parseGoalContributionRecorded(
        json,
        statusCode: statusCode,
        goalId: goalId,
        command: command,
      ),
    );
  }

  @override
  Future<FinanceEntryResult<SavingsGoalCancelled>> cancelGoal({
    required String accessToken,
    required String goalId,
    required FinanceGoalCancelCommand command,
  }) {
    try {
      validateGoalId(goalId);
    } on Object {
      return Future<FinanceEntryResult<SavingsGoalCancelled>>.value(
        _failure(
          kind: FinanceEntryFailureKind.invalidInput,
          requestId: _safeRequestId(_requestIdFactory),
        ),
      );
    }
    return _request(
      method: 'POST',
      path: '/api/v1/goals/$goalId/cancel',
      accessToken: accessToken,
      body: command.toJson(),
      acceptedStatuses: const {200},
      contract: _ContractKind.goal,
      parse: (json, statusCode) =>
          _parseGoalCancelled(json, statusCode: statusCode, goalId: goalId),
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

PlannedCostCreated _parsePlannedCostCreated(
  Map<String, Object?> json, {
  required int statusCode,
  required PlannedCostDraft draft,
}) {
  _expectKeys(json, const {'schemaVersion', 'idempotentReplay', 'plannedCost'});
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  // A replay is exactly the 200 case; a first acceptance is exactly 201.
  if (replay != (statusCode == 200)) {
    throw const FormatException('Replay flag disagrees with status.');
  }
  final plannedCost = PlannedCost.fromJson(_object(json['plannedCost']));
  if (plannedCost.accountId != draft.accountId ||
      plannedCost.plannedOn != draft.plannedOn ||
      plannedCost.title != draft.title ||
      plannedCost.currency != draft.currency) {
    throw const FormatException('Server plan does not match the command.');
  }
  return PlannedCostCreated(plannedCost: plannedCost, idempotentReplay: replay);
}

BudgetWritten _parseBudgetWritten(
  Map<String, Object?> json, {
  required int statusCode,
  required String? expectedCategoryId,
}) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  final written = BudgetWritten.fromSetJson(json);
  if (written.categoryId != expectedCategoryId) {
    throw const FormatException('Server set a ceiling on another category.');
  }
  return written;
}

PlannedCostRecurrenceCreated _parseRecurrenceCreated(
  Map<String, Object?> json, {
  required int statusCode,
  required PlannedCostRecurrenceDraft draft,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'idempotentReplay',
    'recurrence',
    'occurrences',
  });
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  // A replay is exactly the 200 case; a first acceptance is exactly 201.
  if (replay != (statusCode == 200)) {
    throw const FormatException('Replay flag disagrees with status.');
  }
  final recurrence = PlannedCostRecurrence.fromJson(
    _object(json['recurrence']),
  );
  if (recurrence.accountId != draft.accountId ||
      recurrence.title != draft.title ||
      recurrence.currency != draft.currency ||
      recurrence.dayOfMonth != draft.dayOfMonth) {
    throw const FormatException('Server rule does not match the command.');
  }
  return PlannedCostRecurrenceCreated(
    recurrence: recurrence,
    idempotentReplay: replay,
    occurrences: _occurrenceDates(json['occurrences']),
  );
}

PlannedCostRecurrenceList _parseRecurrenceList(
  Map<String, Object?> json,
  int status,
) {
  if (status != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'recurrences'});
  _requireSchema(json);
  final raw = json['recurrences'];
  if (raw is! List<Object?> || raw.length > 200) {
    throw const FormatException('Invalid recurrence list.');
  }
  return PlannedCostRecurrenceList(
    recurrences: raw
        .map((item) => PlannedCostRecurrenceListItem.fromJson(_object(item)))
        .toList(growable: false),
  );
}

PlannedCostRecurrenceEnded _parseRecurrenceEnded(
  Map<String, Object?> json, {
  required int statusCode,
  required String recurrenceId,
}) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {
    'schemaVersion',
    'idempotentReplay',
    'recurrence',
    'cancelledOccurrences',
  });
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  final recurrence = PlannedCostRecurrence.fromJson(
    _object(json['recurrence']),
  );
  if (recurrence.recurrenceId != recurrenceId) {
    throw const FormatException('Server ended a different rule.');
  }
  // An ended rule is terminal; a server still reporting it active would leave
  // the screen offering to end something it just ended.
  if (recurrence.status != PlannedCostRecurrenceStatus.ended) {
    throw const FormatException('Ended rule is still active.');
  }
  final cancelled = json['cancelledOccurrences'];
  if (cancelled is! int || cancelled < 0) {
    throw const FormatException('Invalid cancelledOccurrences.');
  }
  return PlannedCostRecurrenceEnded(
    recurrence: recurrence,
    cancelledOccurrences: cancelled,
  );
}

List<String> _occurrenceDates(Object? raw) {
  if (raw is! List<Object?> || raw.length > 64) {
    throw const FormatException('Invalid occurrences.');
  }
  return raw
      .map((item) => _accountDate(<String, Object?>{'date': item}, 'date'))
      .toList(growable: false);
}

PlannedCostList _parsePlannedCostList(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'evaluatedOn', 'plannedCosts'});
  _requireSchema(json);
  final raw = json['plannedCosts'];
  if (raw is! List<Object?> || raw.length > 200) {
    throw const FormatException('Invalid planned cost list.');
  }
  return PlannedCostList(
    evaluatedOn: _accountDate(json, 'evaluatedOn'),
    plans: raw
        .map((item) => PlannedCost.fromJson(_object(item)))
        .toList(growable: false),
  );
}

PlannedCostSettled _parsePlannedCostSettled(
  Map<String, Object?> json, {
  required int statusCode,
  required String plannedCostId,
}) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'idempotentReplay', 'plannedCost'});
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  final plannedCost = PlannedCost.fromJson(_object(json['plannedCost']));
  if (plannedCost.plannedCostId != plannedCostId) {
    throw const FormatException('Server settled a different plan.');
  }
  // A settled plan is terminal; a server still reporting it outstanding would
  // contradict the transition it just acknowledged.
  if (plannedCost.status == 'planned' || plannedCost.isDue) {
    throw const FormatException('Settled plan is still outstanding.');
  }
  return PlannedCostSettled(plannedCost: plannedCost, idempotentReplay: replay);
}

FinanceCategoryList _parseCategoryList(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'categories'});
  _requireSchema(json);
  final raw = json['categories'];
  if (raw is! List<Object?> || raw.length > 500) {
    throw const FormatException('Invalid category list.');
  }
  final categories = raw
      .map((item) => FinanceCategory.fromJson(_object(item)))
      .toList(growable: false);
  // The catalogue exists so one name means one category. A listing that shows
  // the same name twice in one direction contradicts that, so it is malformed
  // rather than something to render.
  final seen = <String>{};
  for (final category in categories) {
    if (!seen.add(
      '${category.direction.wireName}:${category.name.toLowerCase()}',
    )) {
      throw const FormatException('Duplicate category name in one direction.');
    }
  }
  return FinanceCategoryList(categories: categories);
}

AnalyticsSummary _parseAnalytics(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  return AnalyticsSummary.fromJson(json);
}

UserProfile _parseProfile(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  return UserProfile.fromJson(json);
}

CategoryKeywords _parseCategoryKeywords(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  return CategoryKeywords.fromJson(json);
}

AnalyticsWindow _parseAnalyticsWindow(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  return AnalyticsWindow.fromJson(json);
}

DateTime _parseDeletionScheduled(Map<String, Object?> json, int status) {
  if (status != 202) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'deletionDueAt'});
  _requireSchema(json);
  final raw = json['deletionDueAt'];
  final due = raw is String ? DateTime.tryParse(raw) : null;
  if (due == null) throw const FormatException('Invalid erasure date.');
  return due.toUtc();
}

OperationProposal _parseProposal(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  return OperationProposal.fromJson(json);
}

TransferProposal? _parseTransferProposal(
  Map<String, Object?> json,
  int status,
) {
  if (status != 200) throw const FormatException('Invalid status.');
  // A sentence that is not an exchange is a plain answer, not a failure.
  if (json['proposal'] == null) return null;
  return TransferProposal.fromJson(json);
}

OperationHistoryList _parseOperationHistory(
  Map<String, Object?> json,
  int status,
) {
  if (status != 200) throw const FormatException('Invalid status.');
  _expectKeys(
    json,
    const {'schemaVersion', 'operations'},
    optional: const {'nextCursor'},
  );
  _requireSchema(json);
  final raw = json['operations'];
  if (raw is! List<Object?> || raw.length > 100) {
    throw const FormatException('Invalid operation page.');
  }
  final cursor = json['nextCursor'];
  return OperationHistoryList(
    operations: raw
        .map((item) => OperationHistoryItem.fromJson(_object(item)))
        .toList(growable: false),
    nextCursor: cursor == null
        ? null
        : validatedOperationCursor(_requiredString(json, 'nextCursor')),
  );
}

ManagedCategoryList _parseManagedCategoryList(
  Map<String, Object?> json,
  int status,
) {
  if (status != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'categories'});
  _requireSchema(json);
  final raw = json['categories'];
  if (raw is! List<Object?> || raw.length > 500) {
    throw const FormatException('Invalid category list.');
  }
  final categories = raw
      .map((item) => ManagedFinanceCategory.fromJson(_object(item)))
      .toList(growable: false);
  // Only offered names must be unique. A hidden category may share a name with
  // an offered one, because the uniqueness the server enforces excludes hidden
  // rows — which is what makes a name reusable after hiding it.
  final seen = <String>{};
  for (final category in categories) {
    if (category.isArchived) continue;
    if (!seen.add(
      '${category.direction.wireName}:${category.name.toLowerCase()}',
    )) {
      throw const FormatException('Duplicate category name in one direction.');
    }
  }
  return ManagedCategoryList(categories: categories);
}

ManagedFinanceCategory _parseCategory(Map<String, Object?> json, int status) {
  if (status != 200 && status != 201) {
    throw const FormatException('Invalid status.');
  }
  _expectKeys(json, const {'schemaVersion', 'category'});
  _requireSchema(json);
  return ManagedFinanceCategory.fromJson(_object(json['category']));
}

SavingsGoalCreated _parseGoalCreated(
  Map<String, Object?> json, {
  required int statusCode,
  required SavingsGoalDraft draft,
}) {
  _expectKeys(json, const {'schemaVersion', 'idempotentReplay', 'goal'});
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  // A replay is exactly the 200 case; a first acceptance is exactly 201.
  if (replay != (statusCode == 200)) {
    throw const FormatException('Replay flag disagrees with status.');
  }
  final goal = SavingsGoal.fromJson(_object(json['goal']));
  if (goal.accountId != draft.accountId ||
      goal.title != draft.title ||
      goal.targetOn != draft.targetOn ||
      goal.currency != draft.currency) {
    throw const FormatException('Server goal does not match the command.');
  }
  return SavingsGoalCreated(goal: goal, idempotentReplay: replay);
}

SavingsGoalList _parseGoalList(Map<String, Object?> json, int status) {
  if (status != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'evaluatedOn', 'goals'});
  _requireSchema(json);
  final raw = json['goals'];
  if (raw is! List<Object?> || raw.length > 200) {
    throw const FormatException('Invalid goal list.');
  }
  return SavingsGoalList(
    evaluatedOn: _accountDate(json, 'evaluatedOn'),
    goals: raw
        .map((item) => SavingsGoal.fromJson(_object(item)))
        .toList(growable: false),
  );
}

GoalContributionRecorded _parseGoalContributionRecorded(
  Map<String, Object?> json, {
  required int statusCode,
  required String goalId,
  required GoalContributionCommand command,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'idempotentReplay',
    'contribution',
    'goal',
  });
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  if (replay != (statusCode == 200)) {
    throw const FormatException('Replay flag disagrees with status.');
  }
  final contribution = GoalContribution.fromJson(_object(json['contribution']));
  final goal = SavingsGoal.fromJson(_object(json['goal']));
  if (contribution.goalId != goalId || goal.goalId != goalId) {
    throw const FormatException('Server answered about a different goal.');
  }
  if (contribution.direction != command.direction ||
      contribution.amount != command.amount) {
    throw const FormatException('Server entry does not match the command.');
  }
  return GoalContributionRecorded(
    contribution: contribution,
    goal: goal,
    idempotentReplay: replay,
  );
}

SavingsGoalCancelled _parseGoalCancelled(
  Map<String, Object?> json, {
  required int statusCode,
  required String goalId,
}) {
  if (statusCode != 200) throw const FormatException('Invalid status.');
  _expectKeys(json, const {'schemaVersion', 'idempotentReplay', 'goal'});
  _requireSchema(json);
  final replay = json['idempotentReplay'];
  if (replay is! bool) throw const FormatException('Invalid idempotentReplay.');
  final goal = SavingsGoal.fromJson(_object(json['goal']));
  if (goal.goalId != goalId) {
    throw const FormatException('Server cancelled a different goal.');
  }
  // A server still reporting the goal active would contradict the
  // cancellation it just acknowledged.
  if (goal.isActive) {
    throw const FormatException('Cancelled goal is still active.');
  }
  return SavingsGoalCancelled(goal: goal, idempotentReplay: replay);
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

List<FinanceTimezoneIssue> _timezoneIssues(Object? value) {
  if (value is! List<Object?> || value.isEmpty || value.length > 4) {
    throw const FormatException('Invalid timezone issues.');
  }
  return value
      .map((item) => FinanceTimezoneIssue.fromJson(_object(item)))
      .toList(growable: false);
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

OperationCorrected _parseOperationCorrected(
  Map<String, Object?> json, {
  required int statusCode,
  required OperationCorrectionCommand command,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'idempotentReplay',
    'reversal',
    'operation',
  });
  _requireSchema(json);
  if (json['decision'] != 'ACCEPT') {
    throw const FormatException('Invalid operation correction.');
  }
  final replay = json['idempotentReplay'];
  if (replay is! bool || (statusCode == 200) != replay) {
    throw const FormatException('Invalid operation correction status.');
  }
  final reversal = OperationReversal.fromJson(_object(json['reversal']));
  final operation = CommittedFinanceOperation.fromJson(
    _object(json['operation']),
  );
  final draft = command.review.draft;
  if (reversal.operationId != command.targetOperationId ||
      reversal.replacementOperationId != operation.operationId ||
      operation.commandId != draft.commandId ||
      operation.amount != draft.amount ||
      operation.type != draft.type ||
      operation.occurredOn != draft.occurredOn ||
      operation.categoryId != draft.categoryId) {
    // The receipt has to describe the correction that was asked for. A
    // mismatch means something else was withdrawn or written.
    throw const FormatException('Correction does not match the command.');
  }
  return OperationCorrected(
    idempotentReplay: replay,
    reversal: reversal,
    operation: operation,
  );
}

OperationRemoved _parseOperationRemoved(
  Map<String, Object?> json, {
  required int statusCode,
  required OperationRemovalCommand command,
}) {
  _expectKeys(json, const {
    'schemaVersion',
    'decision',
    'idempotentReplay',
    'reversal',
  });
  _requireSchema(json);
  if (json['decision'] != 'ACCEPT') {
    throw const FormatException('Invalid operation removal.');
  }
  final replay = json['idempotentReplay'];
  if (replay is! bool || (statusCode == 200) != replay) {
    throw const FormatException('Invalid operation removal status.');
  }
  final reversal = OperationReversal.fromJson(_object(json['reversal']));
  if (reversal.operationId != command.targetOperationId ||
      reversal.commandId != command.commandId ||
      // A removal that came back carrying a replacement removed nothing.
      reversal.replacementOperationId != null) {
    throw const FormatException('Removal does not match the command.');
  }
  return OperationRemoved(idempotentReplay: replay, reversal: reversal);
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
  // A wrong password when asking to be erased is a refusal of that request,
  // not of the session — which is why the server answers 403 and never 401.
  if (statusCode == 403 && contract == _ContractKind.accountData) {
    final detail = _tryErrorDetail(bytes, contract: contract);
    if (detail?.code == FinanceEntryErrorCode.passwordRejected) {
      return _failure(
        kind: FinanceEntryFailureKind.rejected,
        requestId: requestId,
        code: detail!.code,
      );
    }
    return _failure(
      kind: FinanceEntryFailureKind.malformedResponse,
      requestId: requestId,
    );
  }
  if (statusCode == 404) {
    final detail = _tryErrorDetail(bytes, contract: contract);
    // A goal the client listed can be gone by the time it acts on it, which is
    // a stale view rather than a broken response.
    if (contract == _ContractKind.goal &&
        detail?.code == FinanceEntryErrorCode.goalNotFound) {
      return _failure(
        kind: FinanceEntryFailureKind.conflict,
        requestId: requestId,
        code: detail!.code,
      );
    }
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
      FinanceEntryErrorCode.operationRejected ||
      FinanceEntryErrorCode.plannedCostRejected ||
      FinanceEntryErrorCode.goalRejected ||
      FinanceEntryErrorCode.timezoneRejected =>
        FinanceEntryFailureKind.rejected,
      FinanceEntryErrorCode.malformedAccount ||
      FinanceEntryErrorCode.malformedOperation ||
      FinanceEntryErrorCode.malformedPlannedCost ||
      FinanceEntryErrorCode.malformedGoalCommand =>
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
      plannedCostIssues: detail.plannedCostIssues,
      goalIssues: detail.goalIssues,
      timezoneIssues: detail.timezoneIssues,
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
    final isTimezoneRejection = rawCode == 'TIMEZONE_REJECTED';
    // Contracts that submit no draft carry a code and no issue list at all.
    // The catalogue is one of them, and its keyword conflict adds the word and
    // the category that already owns it so the user can act on the refusal.
    final isCodeOnly =
        contract == _ContractKind.analytics ||
        contract == _ContractKind.profile ||
        contract == _ContractKind.accountData ||
        contract == _ContractKind.textEntry ||
        contract == _ContractKind.category;
    _expectKeys(
      detail,
      switch ((isBaselineRejection, isTimezoneRejection, isCodeOnly)) {
        (true, _, _) => const {'code', 'issues', 'baselineIssues'},
        (_, true, _) => const {'code', 'issues', 'timezoneIssues'},
        (_, _, true) => const {'code'},
        _ => const {'code', 'issues'},
      },
      optional: contract == _ContractKind.category
          ? const {'keyword', 'owner'}
          : const <String>{},
    );
    final code = _errorCode(rawCode);
    if (!_errorAllowed(code, contract)) {
      throw const FormatException('Wrong Finance error contract.');
    }
    if (isCodeOnly) {
      return _ErrorDetail(
        code: code,
        issues: const <FinanceIssue>[],
        baselineIssues: const <FinanceBaselineIssue>[],
        plannedCostIssues: const <PlannedCostIssue>[],
      );
    }
    // Planned cost issues are a separate code space (ADR 0018), so they are
    // parsed into their own list instead of being forced into FinanceIssue.
    if (contract == _ContractKind.goal) {
      // Goal issues are their own code space (ADR 0019), parsed into their own
      // list rather than forced into FinanceIssue.
      final goalIssues = _goalIssues(detail['issues']);
      final rejected = code == FinanceEntryErrorCode.goalRejected;
      if (rejected != goalIssues.isNotEmpty) {
        throw const FormatException('Inconsistent goal detail.');
      }
      return _ErrorDetail(
        code: code,
        issues: const <FinanceIssue>[],
        baselineIssues: const <FinanceBaselineIssue>[],
        plannedCostIssues: const <PlannedCostIssue>[],
        goalIssues: goalIssues,
      );
    }
    if (contract == _ContractKind.plannedCost ||
        contract == _ContractKind.plannedCostRecurrence ||
        contract == _ContractKind.budget) {
      // A rule reuses the planned-cost issue space: the refusals mean the same
      // things and read the same way, so a second enum would only duplicate
      // the messages.
      final plannedCostIssues = _plannedCostIssues(detail['issues']);
      final rejected =
          code == FinanceEntryErrorCode.plannedCostRejected ||
          code == FinanceEntryErrorCode.recurrenceRejected ||
          code == FinanceEntryErrorCode.budgetRejected;
      if (rejected != plannedCostIssues.isNotEmpty) {
        throw const FormatException('Inconsistent planned cost detail.');
      }
      return _ErrorDetail(
        code: code,
        issues: const <FinanceIssue>[],
        baselineIssues: const <FinanceBaselineIssue>[],
        plannedCostIssues: plannedCostIssues,
      );
    }
    if (contract == _ContractKind.timezone) {
      // Timezone refusals are their own code space (ADR 0028), parsed into
      // their own list rather than forced into FinanceIssue.
      final timezoneIssues = _timezoneIssues(detail['timezoneIssues']);
      final rejected = code == FinanceEntryErrorCode.timezoneRejected;
      if (rejected != timezoneIssues.isNotEmpty ||
          _issues(
            detail['issues'] ?? const <Object?>[],
            contract: _ContractKind.account,
          ).isNotEmpty) {
        throw const FormatException('Inconsistent timezone detail.');
      }
      return _ErrorDetail(
        code: code,
        issues: const <FinanceIssue>[],
        baselineIssues: const <FinanceBaselineIssue>[],
        plannedCostIssues: const <PlannedCostIssue>[],
        timezoneIssues: timezoneIssues,
      );
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
      plannedCostIssues: const <PlannedCostIssue>[],
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
    // Analytics reports no per-field issues: there is no draft to reject.
    _ContractKind.analytics => false,
    // The profile is a read. Nothing is submitted, so nothing is rejected.
    _ContractKind.profile => false,
    // Asking to be erased carries a password, not a draft; it is refused with
    // a code alone.
    _ContractKind.accountData => false,
    // Parsing proposes; it rejects nothing, because it decides nothing.
    _ContractKind.textEntry => false,
    // A timezone refusal is its own code space (ADR 0028); this list is
    // always empty on that contract.
    _ContractKind.timezone => false,
    // So is a transfer refusal (ADR 0029).
    _ContractKind.transfer => false,
    _ContractKind.account => const {
      FinanceIssueCode.accountAlreadyInitialized,
      FinanceIssueCode.openingBalanceDateInFuture,
      FinanceIssueCode.unsupportedCurrency,
    }.contains(code),
    _ContractKind.baseline => false,
    // Planned cost and goal rejections use their own issue codes, never
    // FinanceIssue.
    _ContractKind.plannedCost => false,
    _ContractKind.plannedCostRecurrence => false,
    // Asking about an update submits nothing, so nothing is rejected.
    _ContractKind.appRelease => false,
    // A ceiling is refused with its own issue codes, never FinanceIssue.
    _ContractKind.budget => false,
    _ContractKind.goal => false,
    _ContractKind.category => false,
    // A correction is validated exactly like a new operation, so it can be
    // refused for exactly the same reasons.
    _ContractKind.operation || _ContractKind.operationReversal => const {
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
    _ContractKind.operationReversal => const {
      FinanceEntryErrorCode.malformedOperation,
      FinanceEntryErrorCode.operationRejected,
      FinanceEntryErrorCode.operationNotFound,
      FinanceEntryErrorCode.operationAlreadyReversed,
    }.contains(code),
    _ContractKind.plannedCost => const {
      FinanceEntryErrorCode.malformedPlannedCost,
      FinanceEntryErrorCode.plannedCostRejected,
      FinanceEntryErrorCode.plannedCostNotFound,
      FinanceEntryErrorCode.plannedCostPersistenceUnavailable,
    }.contains(code),
    _ContractKind.plannedCostRecurrence => const {
      FinanceEntryErrorCode.malformedRecurrence,
      FinanceEntryErrorCode.recurrenceRejected,
      FinanceEntryErrorCode.recurrenceNotFound,
      FinanceEntryErrorCode.recurrencePersistenceUnavailable,
    }.contains(code),
    _ContractKind.goal => const {
      FinanceEntryErrorCode.malformedGoalCommand,
      FinanceEntryErrorCode.goalRejected,
      FinanceEntryErrorCode.goalNotFound,
      FinanceEntryErrorCode.goalPersistenceUnavailable,
    }.contains(code),
    _ContractKind.analytics => const {
      FinanceEntryErrorCode.analyticsUnavailable,
      FinanceEntryErrorCode.malformedAnalyticsQuery,
    }.contains(code),
    _ContractKind.profile => const {
      FinanceEntryErrorCode.profileUnavailable,
    }.contains(code),
    _ContractKind.accountData => const {
      FinanceEntryErrorCode.accountDataUnavailable,
      FinanceEntryErrorCode.malformedAccountRequest,
      FinanceEntryErrorCode.passwordRejected,
    }.contains(code),
    _ContractKind.timezone => const {
      FinanceEntryErrorCode.malformedAccount,
      FinanceEntryErrorCode.accountUnavailable,
      FinanceEntryErrorCode.timezoneRejected,
    }.contains(code),
    _ContractKind.transfer => const {
      FinanceEntryErrorCode.malformedTransfer,
      FinanceEntryErrorCode.transferRejected,
      FinanceEntryErrorCode.transferPersistenceUnavailable,
    }.contains(code),
    _ContractKind.textEntry => const {
      FinanceEntryErrorCode.textEntryUnavailable,
    }.contains(code),
    _ContractKind.appRelease => const {
      FinanceEntryErrorCode.appReleaseUnavailable,
      FinanceEntryErrorCode.appReleaseNotFound,
    }.contains(code),
    _ContractKind.budget => const {
      FinanceEntryErrorCode.malformedBudget,
      FinanceEntryErrorCode.budgetRejected,
      FinanceEntryErrorCode.budgetNotFound,
      FinanceEntryErrorCode.budgetPersistenceUnavailable,
    }.contains(code),
    _ContractKind.category => const {
      FinanceEntryErrorCode.malformedCategoryCommand,
      FinanceEntryErrorCode.categoryNotFound,
      FinanceEntryErrorCode.categoryNameTaken,
      FinanceEntryErrorCode.categoryArchived,
      FinanceEntryErrorCode.categoryKeywordTaken,
      FinanceEntryErrorCode.categoryPersistenceUnavailable,
    }.contains(code),
  };
}

List<SavingsGoalIssue> _goalIssues(Object? raw) {
  if (raw is! List<Object?> || raw.length > 16) {
    throw const FormatException('Invalid goal issues.');
  }
  return raw
      .map((item) => SavingsGoalIssue.fromJson(_object(item)))
      .toList(growable: false);
}

List<PlannedCostIssue> _plannedCostIssues(Object? raw) {
  if (raw is! List<Object?> || raw.length > 16) {
    throw const FormatException('Invalid planned cost issues.');
  }
  return raw
      .map((item) => PlannedCostIssue.fromJson(_object(item)))
      .toList(growable: false);
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
  'TIMEZONE_REJECTED' => FinanceEntryErrorCode.timezoneRejected,
  'MALFORMED_TRANSFER' => FinanceEntryErrorCode.malformedTransfer,
  'TRANSFER_REJECTED' => FinanceEntryErrorCode.transferRejected,
  'TRANSFER_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.transferPersistenceUnavailable,
  'OPERATION_REJECTED' => FinanceEntryErrorCode.operationRejected,
  'OPERATION_NOT_FOUND' => FinanceEntryErrorCode.operationNotFound,
  'OPERATION_ALREADY_REVERSED' =>
    FinanceEntryErrorCode.operationAlreadyReversed,
  'MALFORMED_GOAL_COMMAND' => FinanceEntryErrorCode.malformedGoalCommand,
  'GOAL_REJECTED' => FinanceEntryErrorCode.goalRejected,
  'GOAL_NOT_FOUND' => FinanceEntryErrorCode.goalNotFound,
  'GOAL_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.goalPersistenceUnavailable,
  'MALFORMED_CATEGORY_COMMAND' =>
    FinanceEntryErrorCode.malformedCategoryCommand,
  'CATEGORY_NOT_FOUND' => FinanceEntryErrorCode.categoryNotFound,
  'CATEGORY_NAME_TAKEN' => FinanceEntryErrorCode.categoryNameTaken,
  'CATEGORY_ARCHIVED' => FinanceEntryErrorCode.categoryArchived,
  'CATEGORY_KEYWORD_TAKEN' => FinanceEntryErrorCode.categoryKeywordTaken,
  'CATEGORY_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.categoryPersistenceUnavailable,
  'ANALYTICS_UNAVAILABLE' => FinanceEntryErrorCode.analyticsUnavailable,
  'PROFILE_UNAVAILABLE' => FinanceEntryErrorCode.profileUnavailable,
  'ACCOUNT_DATA_UNAVAILABLE' => FinanceEntryErrorCode.accountDataUnavailable,
  'MALFORMED_ACCOUNT_REQUEST' => FinanceEntryErrorCode.malformedAccountRequest,
  'PASSWORD_REJECTED' => FinanceEntryErrorCode.passwordRejected,
  'TEXT_ENTRY_UNAVAILABLE' => FinanceEntryErrorCode.textEntryUnavailable,
  'MALFORMED_ANALYTICS_QUERY' => FinanceEntryErrorCode.malformedAnalyticsQuery,
  'MALFORMED_PLANNED_COST' => FinanceEntryErrorCode.malformedPlannedCost,
  'PLANNED_COST_REJECTED' => FinanceEntryErrorCode.plannedCostRejected,
  'PLANNED_COST_NOT_FOUND' => FinanceEntryErrorCode.plannedCostNotFound,
  'PLANNED_COST_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.plannedCostPersistenceUnavailable,
  'MALFORMED_RECURRENCE' => FinanceEntryErrorCode.malformedRecurrence,
  'RECURRENCE_REJECTED' => FinanceEntryErrorCode.recurrenceRejected,
  'RECURRENCE_NOT_FOUND' => FinanceEntryErrorCode.recurrenceNotFound,
  'RECURRENCE_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.recurrencePersistenceUnavailable,
  'MALFORMED_BUDGET' => FinanceEntryErrorCode.malformedBudget,
  'BUDGET_REJECTED' => FinanceEntryErrorCode.budgetRejected,
  'BUDGET_NOT_FOUND' => FinanceEntryErrorCode.budgetNotFound,
  'BUDGET_PERSISTENCE_UNAVAILABLE' =>
    FinanceEntryErrorCode.budgetPersistenceUnavailable,
  'APP_RELEASE_UNAVAILABLE' => FinanceEntryErrorCode.appReleaseUnavailable,
  'APP_RELEASE_NOT_FOUND' => FinanceEntryErrorCode.appReleaseNotFound,
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
  List<PlannedCostIssue> plannedCostIssues = const [],
  List<SavingsGoalIssue> goalIssues = const [],
  List<FinanceTimezoneIssue> timezoneIssues = const [],
}) {
  return FinanceEntryFailureResult<T>(
    FinanceEntryFailure(
      kind: kind,
      requestId: requestId,
      code: code,
      issues: issues,
      baselineIssues: baselineIssues,
      plannedCostIssues: plannedCostIssues,
      goalIssues: goalIssues,
      timezoneIssues: timezoneIssues,
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

/// Rejects unknown fields, and requires every field except [optional].
///
/// [optional] exists for fields the server may legitimately omit — a paging
/// cursor is absent on the last page — so their absence is not a malformed
/// response. Unknown keys are still refused.
void _expectKeys(
  Map<String, Object?> json,
  Set<String> expected, {
  Set<String> optional = const <String>{},
}) {
  final keys = json.keys.toSet();
  if (!keys.containsAll(expected) ||
      !expected.union(optional).containsAll(keys)) {
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

enum _ContractKind {
  account,
  // The person's own account: export and scheduled erasure (ADR 0030).
  accountData,
  baseline,
  operation,
  operationReversal,
  plannedCost,
  plannedCostRecurrence,
  goal,
  category,
  analytics,
  profile,
  textEntry,
  appRelease,
  budget,
  timezone,
  transfer,
}

final class _ErrorDetail {
  const _ErrorDetail({
    required this.code,
    required this.issues,
    required this.baselineIssues,
    required this.plannedCostIssues,
    this.goalIssues = const <SavingsGoalIssue>[],
    this.timezoneIssues = const <FinanceTimezoneIssue>[],
  });

  final FinanceEntryErrorCode code;
  final List<FinanceIssue> issues;
  final List<FinanceBaselineIssue> baselineIssues;
  final List<PlannedCostIssue> plannedCostIssues;
  final List<SavingsGoalIssue> goalIssues;
  final List<FinanceTimezoneIssue> timezoneIssues;
}
