import 'package:flutter/foundation.dart';

const _schemaVersion = '1';

enum FinanceOperationType { expense, income }

enum FinanceOperationSource { manualText, voice }

extension FinanceOperationTypeWire on FinanceOperationType {
  String get wireName => switch (this) {
    FinanceOperationType.expense => 'expense',
    FinanceOperationType.income => 'income',
  };
}

extension FinanceOperationSourceWire on FinanceOperationSource {
  String get wireName => switch (this) {
    FinanceOperationSource.manualText => 'manual_text',
    FinanceOperationSource.voice => 'voice',
  };
}

enum FinanceIssueCode {
  accountAlreadyInitialized,
  openingBalanceDateInFuture,
  unsupportedCurrency,
  accountRequired,
  accountUnavailable,
  accountCurrencyMismatch,
  operationBeforeAccountBaseline,
  futureOccurredDate,
  relativeDateMismatch,
  occurredAtDateMismatch,
  confirmationBeforeCapture,
  unsupportedDateExpression,
}

enum FinanceBaselineIssueCode {
  baselineNotEarlier,
  baselineDateInFuture,
  baselineAfterExistingOperation,
}

enum FinanceIssueField {
  account,
  openingBalanceOn,
  currency,
  accountId,
  occurredOn,
  occurredAt,
  confirmedAt,
  sourceExpression,
}

@immutable
final class FinanceIssue {
  const FinanceIssue({required this.code, required this.field});

  final FinanceIssueCode code;
  final FinanceIssueField field;

  factory FinanceIssue.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'code', 'field'});
    return FinanceIssue(
      code: _issueCode(_requiredString(json, 'code')),
      field: _issueField(_requiredString(json, 'field')),
    );
  }
}

@immutable
final class FinanceAccountDraft {
  const FinanceAccountDraft({
    required this.commandId,
    required this.name,
    required this.currency,
    required this.openingBalance,
    required this.openingBalanceOn,
    required this.canonicalTimezone,
  }) : _canonicalWire = null;

  FinanceAccountDraft._canonical({
    required this.commandId,
    required this.name,
    required this.currency,
    required this.openingBalance,
    required this.openingBalanceOn,
    required this.canonicalTimezone,
    required Map<String, Object?> wire,
  }) : _canonicalWire = Map.unmodifiable(wire);

  final String commandId;
  final String name;
  final String currency;
  final String openingBalance;
  final String openingBalanceOn;
  final String canonicalTimezone;
  final Map<String, Object?>? _canonicalWire;

  factory FinanceAccountDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'name',
      'currency',
      'openingBalance',
      'openingBalanceOn',
      'canonicalTimezone',
    });
    _requireSchemaVersion(json);
    final commandId = _requiredUuid(json, 'commandId');
    final name = _boundedText(json, 'name', maximumLength: 100);
    final currency = _currency(json, 'currency');
    final openingBalance = _signedMoney(json, 'openingBalance');
    final openingBalanceOn = _date(json, 'openingBalanceOn');
    final canonicalTimezone = _timezone(json, 'canonicalTimezone');
    return FinanceAccountDraft._canonical(
      commandId: commandId,
      name: name,
      currency: currency,
      openingBalance: openingBalance,
      openingBalanceOn: openingBalanceOn,
      canonicalTimezone: canonicalTimezone,
      wire: Map<String, Object?>.from(json),
    );
  }

  Map<String, Object?> toJson() {
    final canonical = _canonicalWire;
    if (canonical != null) return Map<String, Object?>.from(canonical);
    return <String, Object?>{
      'schemaVersion': _schemaVersion,
      'commandId': commandId,
      'name': name,
      'currency': currency,
      'openingBalance': openingBalance,
      'openingBalanceOn': openingBalanceOn,
      'canonicalTimezone': canonicalTimezone,
    };
  }
}

sealed class FinanceAccountEvaluation {
  const FinanceAccountEvaluation({required this.draft});

  final FinanceAccountDraft draft;
}

@immutable
final class FinanceAccountNeedsConfirmation extends FinanceAccountEvaluation {
  const FinanceAccountNeedsConfirmation({
    required super.draft,
    required this.draftHash,
  });

  final String draftHash;
}

@immutable
final class FinanceAccountRejected extends FinanceAccountEvaluation {
  FinanceAccountRejected({
    required super.draft,
    required List<FinanceIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final List<FinanceIssue> issues;
}

@immutable
final class FinanceAccountCommitCommand {
  const FinanceAccountCommitCommand._({
    required this.review,
    required this.confirmedAt,
  });

  final FinanceAccountNeedsConfirmation review;
  final String confirmedAt;

  factory FinanceAccountCommitCommand.fromReview({
    required FinanceAccountNeedsConfirmation review,
    required DateTime confirmedAt,
  }) {
    return FinanceAccountCommitCommand._(
      review: review,
      confirmedAt: _utcWireTimestamp(confirmedAt),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _schemaVersion,
    'draft': review.draft.toJson(),
    'draftHash': review.draftHash,
    'confirmedAt': confirmedAt,
  };
}

@immutable
final class FinanceAccount {
  const FinanceAccount({
    required this.accountId,
    required this.userId,
    required this.commandId,
    required this.name,
    required this.currency,
    required this.openingBalance,
    required this.openingBalanceOn,
    required this.openingTimezone,
    required this.confirmedAt,
    required this.createdAt,
  });

  final String accountId;
  final String userId;
  final String commandId;
  final String name;
  final String currency;
  final String openingBalance;
  final String openingBalanceOn;
  final String openingTimezone;
  final String confirmedAt;
  final String createdAt;

  factory FinanceAccount.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'accountId',
      'userId',
      'commandId',
      'name',
      'currency',
      'openingBalance',
      'openingBalanceOn',
      'openingTimezone',
      'status',
      'isDefault',
      'confirmedAt',
      'createdAt',
    });
    if (json['status'] != 'active' || json['isDefault'] != true) {
      throw const FormatException('Invalid Finance account state.');
    }
    return FinanceAccount(
      accountId: _requiredUuid(json, 'accountId'),
      userId: _requiredUuid(json, 'userId'),
      commandId: _requiredUuid(json, 'commandId'),
      name: _boundedText(json, 'name', maximumLength: 100),
      currency: _currency(json, 'currency'),
      openingBalance: _signedMoney(json, 'openingBalance'),
      openingBalanceOn: _date(json, 'openingBalanceOn'),
      openingTimezone: _timezone(json, 'openingTimezone'),
      confirmedAt: _timestamp(json, 'confirmedAt'),
      createdAt: _timestamp(json, 'createdAt'),
    );
  }
}

@immutable
final class FinanceAccountSetup {
  FinanceAccountSetup({
    required this.canonicalTimezone,
    required this.timezoneRevision,
    required List<FinanceAccount> accounts,
  }) : accounts = List.unmodifiable(accounts) {
    if (accounts.length > 1 || timezoneRevision < 0 || timezoneRevision > 1) {
      throw const FormatException('Invalid Finance account setup.');
    }
    if (accounts.isEmpty) {
      if (canonicalTimezone != null || timezoneRevision != 0) {
        throw const FormatException('Invalid empty Finance account setup.');
      }
    } else if (canonicalTimezone == null || timezoneRevision != 1) {
      throw const FormatException('Invalid initialized Finance account setup.');
    } else if (accounts.single.openingTimezone != canonicalTimezone) {
      throw const FormatException('Inconsistent Finance account timezone.');
    }
  }

  final String? canonicalTimezone;
  final int timezoneRevision;
  final List<FinanceAccount> accounts;

  bool get isInitialized => accounts.isNotEmpty;
  FinanceAccount? get account => accounts.isEmpty ? null : accounts.single;
}

@immutable
final class FinanceAccountCommit {
  const FinanceAccountCommit({
    required this.idempotentReplay,
    required this.canonicalTimezone,
    required this.timezoneRevision,
    required this.account,
  });

  final bool idempotentReplay;
  final String canonicalTimezone;
  final int timezoneRevision;
  final FinanceAccount account;
}

@immutable
final class FinanceBaselineIssue {
  const FinanceBaselineIssue({required this.code});

  final FinanceBaselineIssueCode code;

  factory FinanceBaselineIssue.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'code', 'field'});
    _requiredLiteral(json, 'field', 'openingBalanceOn');
    return FinanceBaselineIssue(
      code: _baselineIssueCode(_requiredString(json, 'code')),
    );
  }
}

/// An explicit request to move an account baseline date earlier (ADR 0016).
@immutable
final class FinanceBaselineDraft {
  const FinanceBaselineDraft({
    required this.commandId,
    required this.accountId,
    required this.openingBalanceOn,
  });

  final String commandId;
  final String accountId;
  final String openingBalanceOn;

  factory FinanceBaselineDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'accountId',
      'openingBalanceOn',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    return FinanceBaselineDraft(
      commandId: _requiredUuid(json, 'commandId'),
      accountId: _requiredUuid(json, 'accountId'),
      openingBalanceOn: _date(json, 'openingBalanceOn'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'accountId': accountId,
    'openingBalanceOn': openingBalanceOn,
  };
}

sealed class FinanceBaselineEvaluation {
  const FinanceBaselineEvaluation({
    required this.draft,
    required this.currentOpeningBalanceOn,
    required this.earliestOperationOn,
  });

  final FinanceBaselineDraft draft;

  /// The bound the user is currently stuck behind.
  final String currentOpeningBalanceOn;

  /// The oldest recorded operation, or null when none exists yet.
  final String? earliestOperationOn;
}

@immutable
final class FinanceBaselineNeedsConfirmation extends FinanceBaselineEvaluation {
  const FinanceBaselineNeedsConfirmation({
    required super.draft,
    required super.currentOpeningBalanceOn,
    required super.earliestOperationOn,
    required this.draftHash,
  });

  final String draftHash;
}

@immutable
final class FinanceBaselineRejected extends FinanceBaselineEvaluation {
  FinanceBaselineRejected({
    required super.draft,
    required super.currentOpeningBalanceOn,
    required super.earliestOperationOn,
    required List<FinanceBaselineIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final List<FinanceBaselineIssue> issues;
}

@immutable
final class FinanceBaselineCommitCommand {
  const FinanceBaselineCommitCommand._({
    required this.draft,
    required this.draftHash,
    required this.confirmedAt,
  });

  factory FinanceBaselineCommitCommand.fromReview({
    required FinanceBaselineNeedsConfirmation review,
    required DateTime confirmedAt,
  }) {
    return FinanceBaselineCommitCommand._(
      draft: review.draft,
      draftHash: validateDraftHash(review.draftHash),
      confirmedAt: _utcWireTimestamp(confirmedAt),
    );
  }

  final FinanceBaselineDraft draft;
  final String draftHash;
  final String confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'draft': draft.toJson(),
    'draftHash': draftHash,
    'confirmedAt': confirmedAt,
  };
}

@immutable
final class FinanceBaselineCommit {
  const FinanceBaselineCommit({
    required this.idempotentReplay,
    required this.previousOpeningBalanceOn,
    required this.account,
  });

  final bool idempotentReplay;
  final String previousOpeningBalanceOn;
  final FinanceAccount account;
}

@immutable
final class FinanceOperationDraft {
  const FinanceOperationDraft({
    required this.commandId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.category,
    required this.merchant,
    required this.capturedAt,
    required this.capturedTimezone,
    required this.sourceExpression,
    this.dateResolverVersion = 'calendar-relative-v1',
    required this.occurredOn,
    required this.occurredAt,
    required this.source,
  }) : _canonicalWire = null;

  FinanceOperationDraft._canonical({
    required this.commandId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.category,
    required this.merchant,
    required this.capturedAt,
    required this.capturedTimezone,
    required this.sourceExpression,
    required this.dateResolverVersion,
    required this.occurredOn,
    required this.occurredAt,
    required this.source,
    required Map<String, Object?> wire,
  }) : _canonicalWire = Map.unmodifiable(wire);

  final String commandId;
  final FinanceOperationType type;
  final String amount;
  final String currency;
  final String? accountId;
  final String? category;
  final String? merchant;
  final String capturedAt;
  final String capturedTimezone;
  final String? sourceExpression;
  final String dateResolverVersion;
  final String occurredOn;
  final String? occurredAt;
  final FinanceOperationSource source;
  final Map<String, Object?>? _canonicalWire;

  factory FinanceOperationDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'type',
      'amount',
      'currency',
      'accountId',
      'category',
      'merchant',
      'capturedAt',
      'capturedTimezone',
      'sourceExpression',
      'dateResolverVersion',
      'occurredOn',
      'occurredAt',
      'source',
    });
    _requireSchemaVersion(json);
    return FinanceOperationDraft._canonical(
      commandId: _requiredUuid(json, 'commandId'),
      type: _operationType(_requiredString(json, 'type')),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      accountId: _optionalUuid(json, 'accountId'),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      merchant: _optionalBoundedText(json, 'merchant', maximumLength: 160),
      capturedAt: _timestamp(json, 'capturedAt'),
      capturedTimezone: _timezone(json, 'capturedTimezone'),
      sourceExpression: _optionalBoundedText(
        json,
        'sourceExpression',
        maximumLength: 128,
      ),
      dateResolverVersion: _requiredLiteral(
        json,
        'dateResolverVersion',
        'calendar-relative-v1',
      ),
      occurredOn: _date(json, 'occurredOn'),
      occurredAt: _optionalTimestamp(json, 'occurredAt'),
      source: _operationSource(_requiredString(json, 'source')),
      wire: Map<String, Object?>.from(json),
    );
  }

  Map<String, Object?> toJson() {
    final canonical = _canonicalWire;
    if (canonical != null) return Map<String, Object?>.from(canonical);
    return <String, Object?>{
      'schemaVersion': _schemaVersion,
      'commandId': commandId,
      'type': type.wireName,
      'amount': amount,
      'currency': currency,
      'accountId': accountId,
      'category': category,
      'merchant': merchant,
      'capturedAt': capturedAt,
      'capturedTimezone': capturedTimezone,
      'sourceExpression': sourceExpression,
      'dateResolverVersion': dateResolverVersion,
      'occurredOn': occurredOn,
      'occurredAt': occurredAt,
      'source': source.wireName,
    };
  }
}

sealed class FinanceOperationEvaluation {
  const FinanceOperationEvaluation({required this.draft});

  final FinanceOperationDraft draft;
}

@immutable
final class FinanceOperationNeedsConfirmation
    extends FinanceOperationEvaluation {
  const FinanceOperationNeedsConfirmation({
    required super.draft,
    required this.draftHash,
  });

  final String draftHash;
}

@immutable
final class FinanceOperationRejected extends FinanceOperationEvaluation {
  FinanceOperationRejected({
    required super.draft,
    required List<FinanceIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final List<FinanceIssue> issues;
}

@immutable
final class FinanceOperationCommitCommand {
  const FinanceOperationCommitCommand._({
    required this.review,
    required this.confirmedAt,
  });

  final FinanceOperationNeedsConfirmation review;
  final String confirmedAt;

  factory FinanceOperationCommitCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'draft',
      'draftHash',
      'confirmedAt',
    });
    _requireSchemaVersion(json);
    final rawDraft = json['draft'];
    if (rawDraft is! Map) {
      throw const FormatException('Invalid operation draft.');
    }
    late final Map<String, Object?> draftJson;
    try {
      draftJson = Map<String, Object?>.from(rawDraft);
    } on Object {
      throw const FormatException('Invalid operation draft.');
    }
    final draft = FinanceOperationDraft.fromJson(draftJson);
    final draftHash = validateDraftHash(_requiredString(json, 'draftHash'));
    final confirmedAt = _timestamp(json, 'confirmedAt');
    if (DateTime.parse(
      confirmedAt,
    ).toUtc().isBefore(DateTime.parse(draft.capturedAt).toUtc())) {
      throw const FormatException('Confirmation precedes capture.');
    }
    return FinanceOperationCommitCommand._(
      review: FinanceOperationNeedsConfirmation(
        draft: draft,
        draftHash: draftHash,
      ),
      confirmedAt: confirmedAt,
    );
  }

  factory FinanceOperationCommitCommand.fromReview({
    required FinanceOperationNeedsConfirmation review,
    required DateTime confirmedAt,
  }) {
    final wireConfirmedAt = _utcWireTimestamp(confirmedAt);
    if (DateTime.parse(
      wireConfirmedAt,
    ).isBefore(DateTime.parse(review.draft.capturedAt))) {
      throw ArgumentError.value(
        confirmedAt,
        'confirmedAt',
        'Must not precede capturedAt.',
      );
    }
    return FinanceOperationCommitCommand._(
      review: review,
      confirmedAt: wireConfirmedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': _schemaVersion,
    'draft': review.draft.toJson(),
    'draftHash': review.draftHash,
    'confirmedAt': confirmedAt,
  };
}

@immutable
final class CommittedFinanceOperation {
  const CommittedFinanceOperation({
    required this.operationId,
    required this.userId,
    required this.commandId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.category,
    required this.merchant,
    required this.capturedAt,
    required this.capturedTimezone,
    required this.sourceExpression,
    required this.dateResolverVersion,
    required this.occurredOn,
    required this.occurredAt,
    required this.source,
    required this.confirmedAt,
    required this.createdAt,
  });

  final String operationId;
  final String userId;
  final String commandId;
  final FinanceOperationType type;
  final String amount;
  final String currency;
  final String? accountId;
  final String? category;
  final String? merchant;
  final String capturedAt;
  final String capturedTimezone;
  final String? sourceExpression;
  final String dateResolverVersion;
  final String occurredOn;
  final String? occurredAt;
  final FinanceOperationSource source;
  final String confirmedAt;
  final String createdAt;

  factory CommittedFinanceOperation.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'operationId',
      'userId',
      'commandId',
      'type',
      'amount',
      'currency',
      'accountId',
      'category',
      'merchant',
      'capturedAt',
      'capturedTimezone',
      'sourceExpression',
      'dateResolverVersion',
      'occurredOn',
      'occurredAt',
      'source',
      'status',
      'confirmedAt',
      'createdAt',
    });
    if (json['status'] != 'confirmed') {
      throw const FormatException('Invalid Finance operation status.');
    }
    return CommittedFinanceOperation(
      operationId: _requiredUuid(json, 'operationId'),
      userId: _requiredUuid(json, 'userId'),
      commandId: _requiredUuid(json, 'commandId'),
      type: _operationType(_requiredString(json, 'type')),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      accountId: _optionalUuid(json, 'accountId'),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      merchant: _optionalBoundedText(json, 'merchant', maximumLength: 160),
      capturedAt: _timestamp(json, 'capturedAt'),
      capturedTimezone: _timezone(json, 'capturedTimezone'),
      sourceExpression: _optionalBoundedText(
        json,
        'sourceExpression',
        maximumLength: 128,
      ),
      dateResolverVersion: _requiredLiteral(
        json,
        'dateResolverVersion',
        'calendar-relative-v1',
      ),
      occurredOn: _date(json, 'occurredOn'),
      occurredAt: _optionalTimestamp(json, 'occurredAt'),
      source: _operationSource(_requiredString(json, 'source')),
      confirmedAt: _timestamp(json, 'confirmedAt'),
      createdAt: _timestamp(json, 'createdAt'),
    );
  }
}

@immutable
final class FinanceOperationCommit {
  const FinanceOperationCommit({
    required this.idempotentReplay,
    required this.operation,
  });

  final bool idempotentReplay;
  final CommittedFinanceOperation operation;
}

/// Codes a planned-cost write may be refused with (ADR 0018).
enum PlannedCostIssueCode {
  accountUnavailable,
  accountCurrencyMismatch,
  unsupportedCurrency,
  planBeforeAccountBaseline,
  invalidLifecycleTransition,
  confirmingOperationMissing,
}

@immutable
final class PlannedCostIssue {
  const PlannedCostIssue({required this.code, required this.field});

  factory PlannedCostIssue.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'code', 'field'});
    return PlannedCostIssue(
      code: _plannedCostIssueCode(_requiredString(json, 'code')),
      field: _requiredString(json, 'field'),
    );
  }

  final PlannedCostIssueCode code;
  final String field;
}

/// An intended future payment before the server has accepted it.
///
/// A plan is a forecast, so unlike an operation it needs no evaluate/confirm
/// handshake: nothing it can do moves the authoritative balance (ADR 0018).
@immutable
final class PlannedCostDraft {
  const PlannedCostDraft({
    required this.commandId,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.title,
    required this.plannedOn,
    required this.requestedAt,
    this.category,
  });

  factory PlannedCostDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'accountId',
      'amount',
      'currency',
      'title',
      'category',
      'plannedOn',
      'requestedAt',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    return PlannedCostDraft(
      commandId: _requiredUuid(json, 'commandId'),
      accountId: _requiredUuid(json, 'accountId'),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      title: _boundedText(json, 'title', maximumLength: 100),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      plannedOn: _date(json, 'plannedOn'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String accountId;
  final String amount;
  final String currency;
  final String title;
  final String? category;
  final String plannedOn;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'accountId': accountId,
    'amount': amount,
    'currency': currency,
    'title': title,
    'category': category,
    'plannedOn': plannedOn,
    'requestedAt': requestedAt,
  };
}

/// A plan as the server stores it.
@immutable
final class PlannedCost {
  const PlannedCost({
    required this.plannedCostId,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.title,
    required this.plannedOn,
    required this.status,
    required this.isDue,
    this.category,
  });

  factory PlannedCost.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'plannedCostId',
      'userId',
      'accountId',
      'commandId',
      'amount',
      'currency',
      'title',
      'category',
      'plannedOn',
      'status',
      'isDue',
      'confirmedOperationId',
      'createdAt',
      'updatedAt',
    });
    final isDue = json['isDue'];
    if (isDue is! bool) throw const FormatException('Invalid isDue.');
    return PlannedCost(
      plannedCostId: _requiredUuid(json, 'plannedCostId'),
      accountId: _requiredUuid(json, 'accountId'),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      title: _boundedText(json, 'title', maximumLength: 100),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      plannedOn: _date(json, 'plannedOn'),
      status: _boundedText(json, 'status', maximumLength: 16),
      isDue: isDue,
    );
  }

  final String plannedCostId;
  final String accountId;
  final String amount;
  final String currency;
  final String title;
  final String? category;
  final String plannedOn;
  final String status;
  final bool isDue;
}

@immutable
final class PlannedCostCreated {
  const PlannedCostCreated({
    required this.plannedCost,
    required this.idempotentReplay,
  });

  final PlannedCost plannedCost;
  final bool idempotentReplay;
}

void validatePlannedCostDraft(PlannedCostDraft draft) {
  PlannedCostDraft.fromJson(draft.toJson());
}

PlannedCostIssueCode _plannedCostIssueCode(String value) => switch (value) {
  'ACCOUNT_UNAVAILABLE' => PlannedCostIssueCode.accountUnavailable,
  'ACCOUNT_CURRENCY_MISMATCH' => PlannedCostIssueCode.accountCurrencyMismatch,
  'UNSUPPORTED_CURRENCY' => PlannedCostIssueCode.unsupportedCurrency,
  'PLAN_BEFORE_ACCOUNT_BASELINE' =>
    PlannedCostIssueCode.planBeforeAccountBaseline,
  'INVALID_LIFECYCLE_TRANSITION' =>
    PlannedCostIssueCode.invalidLifecycleTransition,
  'CONFIRMING_OPERATION_MISSING' =>
    PlannedCostIssueCode.confirmingOperationMissing,
  _ => throw FormatException('Unsupported planned cost issue code: $value'),
};

String plannedCostWireTimestamp(DateTime value) => _utcWireTimestamp(value);

String plannedCostWireDate(DateTime value) {
  final utc = DateTime.utc(value.year, value.month, value.day);
  if (utc.year < 1900 || utc.year > 2100) {
    throw ArgumentError.value(value, 'value', 'Date is outside v1 range.');
  }
  return utc.toIso8601String().substring(0, 10);
}

void validateAccountDraft(FinanceAccountDraft draft) {
  FinanceAccountDraft.fromJson(draft.toJson());
}

void validateOperationDraft(FinanceOperationDraft draft) {
  FinanceOperationDraft.fromJson(draft.toJson());
}

FinanceBaselineIssueCode _baselineIssueCode(String value) => switch (value) {
  'BASELINE_NOT_EARLIER' => FinanceBaselineIssueCode.baselineNotEarlier,
  'BASELINE_DATE_IN_FUTURE' => FinanceBaselineIssueCode.baselineDateInFuture,
  'BASELINE_AFTER_EXISTING_OPERATION' =>
    FinanceBaselineIssueCode.baselineAfterExistingOperation,
  _ => throw FormatException('Unsupported baseline issue code: $value'),
};

String validateDraftHash(String value) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid draft hash.');
  }
  return value;
}

String _utcWireTimestamp(DateTime value) {
  final utc = value.toUtc();
  if (utc.year < 1900 || utc.year > 2100) {
    throw ArgumentError.value(value, 'value', 'Timestamp is outside v1 range.');
  }
  return utc.toIso8601String();
}

void _expectKeys(Map<String, Object?> json, Set<String> expected) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw const FormatException('Unexpected Finance contract fields.');
  }
}

void _requireSchemaVersion(Map<String, Object?> json) {
  if (json['schemaVersion'] != _schemaVersion) {
    throw const FormatException('Unsupported Finance schema version.');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

String _requiredLiteral(
  Map<String, Object?> json,
  String key,
  String expected,
) {
  final value = _requiredString(json, key);
  if (value != expected) throw FormatException('Invalid $key.');
  return value;
}

String _boundedText(
  Map<String, Object?> json,
  String key, {
  required int maximumLength,
}) {
  final value = _requiredString(json, key);
  if (value.isEmpty ||
      value.length > maximumLength ||
      value != value.trim() ||
      _containsControl(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String? _optionalBoundedText(
  Map<String, Object?> json,
  String key, {
  required int maximumLength,
}) {
  if (json[key] == null) return null;
  return _boundedText(json, key, maximumLength: maximumLength);
}

String _currency(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String _signedMoney(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(
    r'^-?(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?|0(?:\.[0-9]{1,18})?)$',
  ).hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String _positiveMoney(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(
    r'^(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?|0\.(?!0{1,18}$)[0-9]{1,18})$',
  ).hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String _requiredUuid(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!_uuidPattern.hasMatch(value)) throw FormatException('Invalid $key.');
  return value;
}

String? _optionalUuid(Map<String, Object?> json, String key) {
  if (json[key] == null) return null;
  return _requiredUuid(json, key);
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String _date(Map<String, Object?> json, String key) {
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

String _timestamp(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !_hasTimezoneSuffix(value) ||
      parsed.toUtc().year < 1900 ||
      parsed.toUtc().year > 2100) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String? _optionalTimestamp(Map<String, Object?> json, String key) {
  if (json[key] == null) return null;
  return _timestamp(json, key);
}

bool _hasTimezoneSuffix(String value) =>
    RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value);

String _timezone(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (value.isEmpty ||
      value.length > 128 ||
      value != value.trim() ||
      _containsControl(value) ||
      const {'Factory', 'localtime', 'posixrules'}.contains(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

FinanceOperationType _operationType(String value) => switch (value) {
  'expense' => FinanceOperationType.expense,
  'income' => FinanceOperationType.income,
  _ => throw const FormatException('Invalid operation type.'),
};

FinanceOperationSource _operationSource(String value) => switch (value) {
  'manual_text' => FinanceOperationSource.manualText,
  'voice' => FinanceOperationSource.voice,
  _ => throw const FormatException('Invalid operation source.'),
};

FinanceIssueCode _issueCode(String value) => switch (value) {
  'ACCOUNT_ALREADY_INITIALIZED' => FinanceIssueCode.accountAlreadyInitialized,
  'OPENING_BALANCE_DATE_IN_FUTURE' =>
    FinanceIssueCode.openingBalanceDateInFuture,
  'UNSUPPORTED_CURRENCY' => FinanceIssueCode.unsupportedCurrency,
  'ACCOUNT_REQUIRED' => FinanceIssueCode.accountRequired,
  'ACCOUNT_UNAVAILABLE' => FinanceIssueCode.accountUnavailable,
  'ACCOUNT_CURRENCY_MISMATCH' => FinanceIssueCode.accountCurrencyMismatch,
  'OPERATION_BEFORE_ACCOUNT_BASELINE' =>
    FinanceIssueCode.operationBeforeAccountBaseline,
  'FUTURE_OCCURRED_DATE' => FinanceIssueCode.futureOccurredDate,
  'RELATIVE_DATE_MISMATCH' => FinanceIssueCode.relativeDateMismatch,
  'OCCURRED_AT_DATE_MISMATCH' => FinanceIssueCode.occurredAtDateMismatch,
  'CONFIRMATION_BEFORE_CAPTURE' => FinanceIssueCode.confirmationBeforeCapture,
  'UNSUPPORTED_DATE_EXPRESSION' => FinanceIssueCode.unsupportedDateExpression,
  _ => throw const FormatException('Unknown Finance issue code.'),
};

FinanceIssueField _issueField(String value) => switch (value) {
  'account' => FinanceIssueField.account,
  'openingBalanceOn' => FinanceIssueField.openingBalanceOn,
  'currency' => FinanceIssueField.currency,
  'accountId' => FinanceIssueField.accountId,
  'occurredOn' => FinanceIssueField.occurredOn,
  'occurredAt' => FinanceIssueField.occurredAt,
  'confirmedAt' => FinanceIssueField.confirmedAt,
  'sourceExpression' => FinanceIssueField.sourceExpression,
  _ => throw const FormatException('Unknown Finance issue field.'),
};

bool _containsControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
