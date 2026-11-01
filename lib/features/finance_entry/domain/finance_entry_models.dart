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

/// Why a request to redraw an account's months was refused (ADR 0028).
enum FinanceTimezoneIssueCode {
  /// The account already reports in that zone; there is nothing to correct.
  timezoneUnchanged,

  /// Moving there would date a recorded operation in the future, and a
  /// future-dated operation is excluded from the balance until the day catches
  /// up. Refused rather than letting money vanish for hours.
  timezoneBehindRecordedOperations,
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
    required this.isDefault,
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

  /// Whether this is the wallet a screen means when it names none (ADR 0029).
  final bool isDefault;
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
    final isDefault = json['isDefault'];
    if (json['status'] != 'active' || isDefault is! bool) {
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
      isDefault: isDefault,
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
    // The revision counts how many times the timezone has been settled, and
    // it is correctable (ADR 0028), so it climbs. Zero still means unset.
    if (timezoneRevision < 0) {
      throw const FormatException('Invalid Finance account setup.');
    }
    if (accounts.isEmpty) {
      if (canonicalTimezone != null || timezoneRevision != 0) {
        throw const FormatException('Invalid empty Finance account setup.');
      }
      return;
    }
    if (canonicalTimezone == null || timezoneRevision < 1) {
      throw const FormatException('Invalid initialized Finance account setup.');
    }
    // A user may hold several wallets, one currency each, and exactly one of
    // them is the default (ADR 0029).
    if (accounts.where((account) => account.isDefault).length != 1) {
      throw const FormatException('Invalid Finance wallet set.');
    }
    // Months must not depend on which wallet is read (ADR 0028).
    for (final account in accounts) {
      if (account.openingTimezone != canonicalTimezone) {
        throw const FormatException('Inconsistent Finance account timezone.');
      }
    }
  }

  final String? canonicalTimezone;
  final int timezoneRevision;
  final List<FinanceAccount> accounts;

  bool get isInitialized => accounts.isNotEmpty;

  /// The wallet a screen means when it names none.
  FinanceAccount? get account => accounts.isEmpty
      ? null
      : accounts.firstWhere((candidate) => candidate.isDefault);
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

@immutable
final class FinanceTimezoneIssue {
  const FinanceTimezoneIssue({required this.code});

  final FinanceTimezoneIssueCode code;

  factory FinanceTimezoneIssue.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'code', 'field'});
    _requiredLiteral(json, 'field', 'canonicalTimezone');
    return FinanceTimezoneIssue(
      code: _timezoneIssueCode(_requiredString(json, 'code')),
    );
  }
}

/// Why a transfer between two wallets was refused (ADR 0029).
enum FinanceTransferIssueCode {
  walletUnavailable,
  walletCurrencyMismatch,
  transferBeforeWalletBaseline,
  futureOccurredDate,
  confirmationBeforeCapture,
}

@immutable
final class FinanceTransferIssue {
  const FinanceTransferIssue({required this.code, required this.field});

  final FinanceTransferIssueCode code;
  final String field;

  factory FinanceTransferIssue.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'code', 'field'});
    final field = _requiredString(json, 'field');
    if (!const {
      'fromAccountId',
      'toAccountId',
      'occurredOn',
      'confirmedAt',
    }.contains(field)) {
      throw const FormatException('Invalid transfer issue field.');
    }
    return FinanceTransferIssue(
      code: _transferIssueCode(_requiredString(json, 'code')),
      field: field,
    );
  }
}

/// One proposed movement between two of a user's wallets.
///
/// Two amounts and no rate: the rate follows from the pair and is never sent
/// or stored (ADR 0029).
@immutable
final class FinanceTransferDraft {
  const FinanceTransferDraft({
    required this.commandId,
    required this.fromAccountId,
    required this.fromAmount,
    required this.fromCurrency,
    required this.toAccountId,
    required this.toAmount,
    required this.toCurrency,
    required this.capturedAt,
    required this.capturedTimezone,
    required this.occurredOn,
  });

  final String commandId;
  final String fromAccountId;
  final String fromAmount;
  final String fromCurrency;
  final String toAccountId;
  final String toAmount;
  final String toCurrency;
  final String capturedAt;
  final String capturedTimezone;
  final String occurredOn;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'fromAccountId': fromAccountId,
    'fromAmount': fromAmount,
    'fromCurrency': fromCurrency,
    'toAccountId': toAccountId,
    'toAmount': toAmount,
    'toCurrency': toCurrency,
    'capturedAt': capturedAt,
    'capturedTimezone': capturedTimezone,
    'occurredOn': occurredOn,
  };

  factory FinanceTransferDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'fromAccountId',
      'fromAmount',
      'fromCurrency',
      'toAccountId',
      'toAmount',
      'toCurrency',
      'capturedAt',
      'capturedTimezone',
      'occurredOn',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    return FinanceTransferDraft(
      commandId: _requiredUuid(json, 'commandId'),
      fromAccountId: _requiredUuid(json, 'fromAccountId'),
      fromAmount: _positiveMoney(json, 'fromAmount'),
      fromCurrency: _currency(json, 'fromCurrency'),
      toAccountId: _requiredUuid(json, 'toAccountId'),
      toAmount: _positiveMoney(json, 'toAmount'),
      toCurrency: _currency(json, 'toCurrency'),
      capturedAt: _timestamp(json, 'capturedAt'),
      capturedTimezone: _timezone(json, 'capturedTimezone'),
      occurredOn: _date(json, 'occurredOn'),
    );
  }
}

sealed class FinanceTransferEvaluation {
  const FinanceTransferEvaluation();

  /// Parsed here rather than in the API layer, because the checks that make a
  /// draft trustworthy are private to this file.
  factory FinanceTransferEvaluation.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'decision',
      'draft',
      'draftHash',
      'issues',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    final draft = FinanceTransferDraft.fromJson(_asObject(json['draft']));
    final rawIssues = json['issues'];
    if (rawIssues is! List<Object?> || rawIssues.length > 8) {
      throw const FormatException('Invalid transfer issues.');
    }
    final issues = rawIssues
        .map((item) => FinanceTransferIssue.fromJson(_asObject(item)))
        .toList(growable: false);
    final hash = json['draftHash'];
    switch (_requiredString(json, 'decision')) {
      case 'NEEDS_CONFIRMATION':
        if (issues.isNotEmpty || hash is! String) {
          throw const FormatException('Inconsistent transfer evaluation.');
        }
        return FinanceTransferNeedsConfirmation(
          draft: draft,
          draftHash: validateDraftHash(hash),
        );
      case 'REJECT':
        if (issues.isEmpty || hash != null) {
          throw const FormatException('Inconsistent transfer rejection.');
        }
        return FinanceTransferRejected(issues: issues);
      default:
        throw const FormatException('Unsupported transfer decision.');
    }
  }
}

@immutable
final class FinanceTransferNeedsConfirmation extends FinanceTransferEvaluation {
  const FinanceTransferNeedsConfirmation({
    required this.draft,
    required this.draftHash,
  });

  final FinanceTransferDraft draft;
  final String draftHash;
}

@immutable
final class FinanceTransferRejected extends FinanceTransferEvaluation {
  FinanceTransferRejected({required List<FinanceTransferIssue> issues})
    : issues = List.unmodifiable(issues);

  final List<FinanceTransferIssue> issues;
}

@immutable
final class FinanceTransferCommitCommand {
  const FinanceTransferCommitCommand._({
    required this.draft,
    required this.draftHash,
    required this.confirmedAt,
  });

  factory FinanceTransferCommitCommand.fromReview({
    required FinanceTransferNeedsConfirmation review,
    required DateTime confirmedAt,
  }) {
    return FinanceTransferCommitCommand._(
      draft: review.draft,
      draftHash: validateDraftHash(review.draftHash),
      confirmedAt: _utcWireTimestamp(confirmedAt),
    );
  }

  final FinanceTransferDraft draft;
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
final class FinanceTransferCommitted {
  const FinanceTransferCommitted({
    required this.transferId,
    required this.idempotentReplay,
    required this.fromAmount,
    required this.fromCurrency,
    required this.toAmount,
    required this.toCurrency,
    required this.occurredOn,
  });

  final String transferId;
  final bool idempotentReplay;
  final String fromAmount;
  final String fromCurrency;
  final String toAmount;
  final String toCurrency;
  final String occurredOn;

  factory FinanceTransferCommitted.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'decision',
      'idempotentReplay',
      'transfer',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    _requiredLiteral(json, 'decision', 'ACCEPT');
    final replay = json['idempotentReplay'];
    if (replay is! bool) {
      throw const FormatException('Invalid transfer receipt.');
    }
    final transfer = _asObject(json['transfer']);
    _expectKeys(transfer, const {
      'transferId',
      'userId',
      'commandId',
      'fromAccountId',
      'fromAmount',
      'fromCurrency',
      'toAccountId',
      'toAmount',
      'toCurrency',
      'occurredOn',
      'status',
      'confirmedAt',
      'createdAt',
    });
    _requiredLiteral(transfer, 'status', 'confirmed');
    return FinanceTransferCommitted(
      transferId: _requiredUuid(transfer, 'transferId'),
      idempotentReplay: replay,
      fromAmount: _positiveMoney(transfer, 'fromAmount'),
      fromCurrency: _currency(transfer, 'fromCurrency'),
      toAmount: _positiveMoney(transfer, 'toAmount'),
      toCurrency: _currency(transfer, 'toCurrency'),
      occurredOn: _date(transfer, 'occurredOn'),
    );
  }
}

/// An explicit request to change where an account's months are drawn.
///
/// One phase, not the evaluate/confirm handshake a baseline needs (ADR 0028):
/// no balance moves, because an operation keeps the local date it was captured
/// with. The command id makes a retry after a lost answer replay the same
/// correction rather than settle a second one.
@immutable
final class FinanceTimezoneCommand {
  const FinanceTimezoneCommand._({
    required this.commandId,
    required this.accountId,
    required this.canonicalTimezone,
    required this.requestedAt,
  });

  factory FinanceTimezoneCommand({
    required String commandId,
    required String accountId,
    required String canonicalTimezone,
    required DateTime requestedAt,
  }) {
    return FinanceTimezoneCommand._(
      commandId: commandId,
      accountId: accountId,
      canonicalTimezone: _validTimezone(canonicalTimezone),
      requestedAt: _utcWireTimestamp(requestedAt),
    );
  }

  final String commandId;
  final String accountId;
  final String canonicalTimezone;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'accountId': accountId,
    'canonicalTimezone': canonicalTimezone,
    'requestedAt': requestedAt,
  };
}

@immutable
final class FinanceTimezoneCorrected {
  const FinanceTimezoneCorrected({
    required this.accountId,
    required this.canonicalTimezone,
    required this.timezoneRevision,
    required this.idempotentReplay,
  });

  final String accountId;
  final String canonicalTimezone;
  final int timezoneRevision;
  final bool idempotentReplay;

  factory FinanceTimezoneCorrected.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'idempotentReplay',
      'accountId',
      'canonicalTimezone',
      'timezoneRevision',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    final revision = json['timezoneRevision'];
    final replay = json['idempotentReplay'];
    if (revision is! int || revision < 1 || replay is! bool) {
      throw const FormatException('Invalid timezone correction.');
    }
    return FinanceTimezoneCorrected(
      accountId: _requiredUuid(json, 'accountId'),
      canonicalTimezone: _timezone(json, 'canonicalTimezone'),
      timezoneRevision: revision,
      idempotentReplay: replay,
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
    this.categoryId,
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
    required this.categoryId,
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
  // What the user wrote, kept beside the catalogue link that groups it.
  final String? category;
  // The catalogue link. Null until the picker lands; the server treats an
  // absent link as "uncategorized" rather than guessing (ADR 0020).
  final String? categoryId;
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
    _expectKeys(
      json,
      const {
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
      },
      optional: const {'categoryId'},
    );
    _requireSchemaVersion(json);
    return FinanceOperationDraft._canonical(
      commandId: _requiredUuid(json, 'commandId'),
      type: _operationType(_requiredString(json, 'type')),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      accountId: _optionalUuid(json, 'accountId'),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      categoryId: _optionalUuid(json, 'categoryId'),
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
      'categoryId': categoryId,
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
    required this.categoryId,
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
  final String? categoryId;
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
    _expectKeys(
      json,
      const {
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
      },
      optional: const {'categoryId'},
    );
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
      categoryId: _optionalUuid(json, 'categoryId'),
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

/// One confirmed operation withdrawn from the ledger (ADR 0023).
///
/// The operation it names is never modified. This is the separate statement
/// that it stopped counting, and what replaced it if anything did.
@immutable
final class OperationReversal {
  const OperationReversal({
    required this.reversalId,
    required this.operationId,
    required this.replacementOperationId,
    required this.commandId,
    required this.confirmedAt,
    required this.createdAt,
  });

  final String reversalId;
  final String operationId;

  /// Null when the operation was removed rather than corrected.
  final String? replacementOperationId;
  final String commandId;
  final String confirmedAt;
  final String createdAt;

  factory OperationReversal.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'reversalId',
      'operationId',
      'replacementOperationId',
      'commandId',
      'confirmedAt',
      'createdAt',
    });
    return OperationReversal(
      reversalId: _requiredUuid(json, 'reversalId'),
      operationId: _requiredUuid(json, 'operationId'),
      replacementOperationId: json['replacementOperationId'] == null
          ? null
          : _requiredUuid(json, 'replacementOperationId'),
      commandId: _requiredUuid(json, 'commandId'),
      confirmedAt: _timestamp(json, 'confirmedAt'),
      createdAt: _timestamp(json, 'createdAt'),
    );
  }
}

/// Replace one confirmed operation with a reviewed draft (ADR 0023).
///
/// The target travels inside the command, so the identity of what is being
/// corrected is part of what a retry replays.
@immutable
final class OperationCorrectionCommand {
  const OperationCorrectionCommand({
    required this.targetOperationId,
    required this.review,
    required this.confirmedAt,
  });

  final String targetOperationId;
  final FinanceOperationNeedsConfirmation review;
  final String confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'targetOperationId': targetOperationId,
    'draft': review.draft.toJson(),
    'draftHash': review.draftHash,
    'confirmedAt': confirmedAt,
  };
}

/// Withdraw one confirmed operation without replacing it (ADR 0023).
@immutable
final class OperationRemovalCommand {
  const OperationRemovalCommand({
    required this.targetOperationId,
    required this.commandId,
    required this.confirmedAt,
  });

  final String targetOperationId;
  final String commandId;
  final String confirmedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'targetOperationId': targetOperationId,
    'commandId': commandId,
    'confirmedAt': confirmedAt,
  };
}

@immutable
final class OperationCorrected {
  const OperationCorrected({
    required this.idempotentReplay,
    required this.reversal,
    required this.operation,
  });

  final bool idempotentReplay;
  final OperationReversal reversal;
  final CommittedFinanceOperation operation;
}

@immutable
final class OperationRemoved {
  const OperationRemoved({
    required this.idempotentReplay,
    required this.reversal,
  });

  final bool idempotentReplay;
  final OperationReversal reversal;
}

/// Codes a planned-cost write may be refused with (ADR 0018).
enum PlannedCostIssueCode {
  accountUnavailable,
  accountCurrencyMismatch,
  unsupportedCurrency,
  planBeforeAccountBaseline,
  invalidLifecycleTransition,
  confirmingOperationMissing,
  // Reached only through a recurrence rule, which is the first planned cost
  // that can carry a catalogue link (ADR 0025).
  categoryUnavailable,
  categoryDirectionMismatch,
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

/// The terminal states a plan can be moved to (ADR 0018).
///
/// `skip` and `cancel` are distinct because recurrence will need them to mean
/// different things: skipping one month is not cancelling the plan.
enum PlannedCostTransition { confirm, skip, cancel }

@immutable
final class PlannedCostTransitionCommand {
  const PlannedCostTransitionCommand({
    required this.commandId,
    required this.transition,
    required this.requestedAt,
    this.operationCommandId,
  });

  factory PlannedCostTransitionCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'transition',
      'operationCommandId',
      'requestedAt',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    final transition = _plannedCostTransition(
      _requiredString(json, 'transition'),
    );
    final operationCommandId = json['operationCommandId'] == null
        ? null
        : _requiredUuid(json, 'operationCommandId');
    // Confirmation settles real money, so it must name the operation that did
    // it; nothing else may carry one.
    if ((transition == PlannedCostTransition.confirm) !=
        (operationCommandId != null)) {
      throw const FormatException('Invalid planned cost confirmation.');
    }
    return PlannedCostTransitionCommand(
      commandId: _requiredUuid(json, 'commandId'),
      transition: transition,
      operationCommandId: operationCommandId,
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final PlannedCostTransition transition;
  final String? operationCommandId;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'transition': transition.name,
    'operationCommandId': operationCommandId,
    'requestedAt': requestedAt,
  };
}

@immutable
final class PlannedCostSettled {
  const PlannedCostSettled({
    required this.plannedCost,
    required this.idempotentReplay,
  });

  final PlannedCost plannedCost;
  final bool idempotentReplay;
}

@immutable
final class PlannedCostList {
  PlannedCostList({required this.evaluatedOn, required List<PlannedCost> plans})
    : plans = List<PlannedCost>.unmodifiable(plans);

  /// The local date the server derived `isDue` against, so the client never
  /// has to guess which day the server considered "today".
  final String evaluatedOn;
  final List<PlannedCost> plans;
}

/// Validates an identifier before it is interpolated into a request path.
/// A non-UUID value must never reach the URL.
String validatePlannedCostId(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid planned cost id.');
  }
  return value;
}

void validatePlannedCostTransition(PlannedCostTransitionCommand command) {
  PlannedCostTransitionCommand.fromJson(command.toJson());
}

PlannedCostTransition _plannedCostTransition(String value) => switch (value) {
  'confirm' => PlannedCostTransition.confirm,
  'skip' => PlannedCostTransition.skip,
  'cancel' => PlannedCostTransition.cancel,
  _ => throw FormatException('Unsupported planned cost transition: $value'),
};

void validatePlannedCostDraft(PlannedCostDraft draft) {
  PlannedCostDraft.fromJson(draft.toJson());
}

PlannedCostIssueCode _plannedCostIssueCode(String value) => switch (value) {
  'ACCOUNT_UNAVAILABLE' => PlannedCostIssueCode.accountUnavailable,
  'ACCOUNT_CURRENCY_MISMATCH' => PlannedCostIssueCode.accountCurrencyMismatch,
  'UNSUPPORTED_CURRENCY' => PlannedCostIssueCode.unsupportedCurrency,
  'PLAN_BEFORE_ACCOUNT_BASELINE' =>
    PlannedCostIssueCode.planBeforeAccountBaseline,
  // The same refusal for the same reason, named for the rule rather than the
  // instance, so it reads the same way to the user.
  'RECURRENCE_BEFORE_ACCOUNT_BASELINE' =>
    PlannedCostIssueCode.planBeforeAccountBaseline,
  'CATEGORY_UNAVAILABLE' => PlannedCostIssueCode.categoryUnavailable,
  // A ceiling that was already withdrawn (ADR 0027).
  'BUDGET_ALREADY_REMOVED' => PlannedCostIssueCode.invalidLifecycleTransition,
  'CATEGORY_DIRECTION_MISMATCH' =>
    PlannedCostIssueCode.categoryDirectionMismatch,
  'INVALID_LIFECYCLE_TRANSITION' =>
    PlannedCostIssueCode.invalidLifecycleTransition,
  'CONFIRMING_OPERATION_MISSING' =>
    PlannedCostIssueCode.confirmingOperationMissing,
  _ => throw FormatException('Unsupported planned cost issue code: $value'),
};

/// A goal's derived balance and declared monthly intent are legitimately zero,
/// so they cannot reuse the strictly positive money validator (ADR 0019).
String _nonNegativeMoney(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(
    r'^(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?|0(?:\.[0-9]{1,18})?)$',
  ).hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

/// One category from the user's own catalogue (ADR 0020).
///
/// Seeded rows carry a stable [systemKey] the app localizes; a renamed one
/// carries none, because the user's own name is then the right label.
@immutable
final class FinanceCategory {
  const FinanceCategory({
    required this.categoryId,
    required this.name,
    required this.direction,
    required this.systemKey,
  });

  factory FinanceCategory.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'categoryId',
      'name',
      'direction',
      'systemKey',
      'createdAt',
    });
    return FinanceCategory(
      categoryId: _requiredUuid(json, 'categoryId'),
      name: _boundedText(json, 'name', maximumLength: 100),
      direction: _categoryDirection(_requiredString(json, 'direction')),
      systemKey: json['systemKey'] == null
          ? null
          : _categorySystemKey(_requiredString(json, 'systemKey')),
    );
  }

  final String categoryId;
  final String name;
  final FinanceOperationType direction;
  final String? systemKey;
}

@immutable
final class FinanceCategoryList {
  FinanceCategoryList({required List<FinanceCategory> categories})
    : categories = List<FinanceCategory>.unmodifiable(categories);

  final List<FinanceCategory> categories;

  /// Categories offered for one direction. A purchase must never be offered a
  /// salary category, so the picker filters rather than showing everything.
  List<FinanceCategory> forDirection(FinanceOperationType direction) => [
    for (final category in categories)
      if (category.direction == direction) category,
  ];
}

/// One confirmed operation as the history screen reads it.
@immutable
final class OperationHistoryItem {
  const OperationHistoryItem({
    required this.operationId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.category,
    required this.categoryId,
    required this.categoryText,
    required this.merchant,
    required this.occurredOn,
    required this.occurredAt,
    required this.source,
    required this.createdAt,
  });

  factory OperationHistoryItem.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'operationId',
      'type',
      'amount',
      'currency',
      'accountId',
      'category',
      'categoryId',
      'categoryText',
      'merchant',
      'occurredOn',
      'occurredAt',
      'source',
      'status',
      'createdAt',
    });
    if (_requiredString(json, 'status') != 'confirmed') {
      throw const FormatException('Only confirmed operations are readable.');
    }
    return OperationHistoryItem(
      operationId: _requiredUuid(json, 'operationId'),
      type: _operationType(_requiredString(json, 'type')),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      accountId: json['accountId'] == null
          ? null
          : _requiredUuid(json, 'accountId'),
      category: json['category'] == null
          ? null
          : _boundedText(json, 'category', maximumLength: 100),
      categoryId: json['categoryId'] == null
          ? null
          : _requiredUuid(json, 'categoryId'),
      categoryText: json['categoryText'] == null
          ? null
          : _boundedText(json, 'categoryText', maximumLength: 100),
      merchant: json['merchant'] == null
          ? null
          : _boundedText(json, 'merchant', maximumLength: 160),
      occurredOn: _date(json, 'occurredOn'),
      occurredAt: _optionalTimestamp(json, 'occurredAt'),
      source: _operationSource(_requiredString(json, 'source')),
      createdAt: _timestamp(json, 'createdAt'),
    );
  }

  final String operationId;
  final FinanceOperationType type;
  final String amount;
  final String currency;
  final String? accountId;

  /// The linked category's current name, so a rename shows up here too.
  ///
  /// Null only when the operation was recorded with neither a link nor text.
  final String? category;
  final String? categoryId;

  /// What the user actually wrote. After a rename it differs from [category],
  /// and showing both is what makes a wrong link visible (ADR 0020).
  final String? categoryText;

  final String? merchant;
  final String occurredOn;
  final String? occurredAt;
  final FinanceOperationSource source;
  final String createdAt;

  /// Whether the stored text still says what the category is called.
  ///
  /// False after a rename, and the detail card shows both only then: repeating
  /// an identical value twice would be noise.
  bool get textDiffersFromCategory =>
      categoryText != null && categoryText != category;
}

@immutable
final class OperationHistoryList {
  OperationHistoryList({
    required List<OperationHistoryItem> operations,
    required this.nextCursor,
  }) : operations = List<OperationHistoryItem>.unmodifiable(operations);

  final List<OperationHistoryItem> operations;

  /// Absent on the last page. Opaque: only the server knows what it encodes.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

String validatedOperationCursor(String value) {
  if (value.isEmpty ||
      value.length > 256 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('Invalid operation cursor.');
  }
  return value;
}

/// A window the analytics screen can report.
enum AnalyticsPeriodKind {
  last7Days('last_7_days'),
  month('month'),
  quarter('quarter'),
  year('year'),
  custom('custom');

  const AnalyticsPeriodKind(this.wire);

  final String wire;
}

/// How wide one point of the balance line is.
enum AnalyticsBucket { day, week, month }

/// One category in the window, beside the window before it.
///
/// Covers the union of both windows, so a category spent on last month and not
/// this one appears with a zero: the drop is what a comparison is for.
@immutable
final class AnalyticsCategoryChange {
  const AnalyticsCategoryChange({
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.previousAmount,
  });

  factory AnalyticsCategoryChange.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'categoryId', 'name', 'amount', 'previousAmount'});
    final categoryId = json['categoryId'] == null
        ? null
        : _requiredUuid(json, 'categoryId');
    final name = json['name'] == null
        ? null
        : _boundedText(json, 'name', maximumLength: 100);
    if ((categoryId == null) != (name == null)) {
      throw const FormatException('Invalid analytics category row.');
    }
    return AnalyticsCategoryChange(
      categoryId: categoryId,
      name: name,
      amount: _signedMoney(json, 'amount'),
      previousAmount: _signedMoney(json, 'previousAmount'),
    );
  }

  final String? categoryId;
  final String? name;
  final String amount;
  final String previousAmount;
}

/// What the account was worth across the window.
@immutable
final class AnalyticsBalanceLine {
  AnalyticsBalanceLine({
    required this.bucket,
    required this.opening,
    required this.closing,
    required this.change,
    required List<AnalyticsTrendPoint> points,
  }) : points = List<AnalyticsTrendPoint>.unmodifiable(points);

  factory AnalyticsBalanceLine.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'bucket',
      'opening',
      'closing',
      'change',
      'points',
    });
    final raw = json['points'];
    if (raw is! List<Object?> || raw.isEmpty || raw.length > 400) {
      throw const FormatException('Invalid balance line.');
    }
    return AnalyticsBalanceLine(
      bucket: switch (_requiredString(json, 'bucket')) {
        'day' => AnalyticsBucket.day,
        'week' => AnalyticsBucket.week,
        'month' => AnalyticsBucket.month,
        _ => throw const FormatException('Unknown balance bucket.'),
      },
      opening: _signedMoney(json, 'opening'),
      closing: _signedMoney(json, 'closing'),
      change: _signedMoney(json, 'change'),
      points: [
        for (final item in raw) AnalyticsTrendPoint.fromJson(_asObject(item)),
      ],
    );
  }

  final AnalyticsBucket bucket;
  final String opening;
  final String closing;
  final String change;
  final List<AnalyticsTrendPoint> points;
}

/// One reported window: its totals, the window before it, and the line.
@immutable
final class AnalyticsWindow {
  AnalyticsWindow({
    required this.kind,
    required this.periodStart,
    required this.periodEnd,
    required this.previousStart,
    required this.previousEnd,
    required this.baseCurrency,
    required this.income,
    required this.expense,
    required this.netFlow,
    required this.previousIncome,
    required this.previousExpense,
    required this.previousNetFlow,
    required this.balance,
    required List<AnalyticsCategoryChange> expenseChanges,
    required List<AnalyticsCategoryChange> incomeChanges,
  }) : expenseChanges = List<AnalyticsCategoryChange>.unmodifiable(
         expenseChanges,
       ),
       incomeChanges = List<AnalyticsCategoryChange>.unmodifiable(
         incomeChanges,
       );

  factory AnalyticsWindow.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'generatedAt',
      'baseCurrency',
      'kind',
      'period',
      'previousPeriod',
      'totals',
      'previousTotals',
      'expenseByCategory',
      'incomeByCategory',
      'expenseChanges',
      'incomeChanges',
      'balance',
    });
    if (json['schemaVersion'] != '2') {
      throw const FormatException('Unsupported analytics schema version.');
    }
    final period = _nestedObject(json, 'period');
    _expectKeys(period, const {'from', 'to'});
    final previousPeriod = _nestedObject(json, 'previousPeriod');
    _expectKeys(previousPeriod, const {'from', 'to'});
    final totals = _nestedObject(json, 'totals');
    _expectKeys(totals, const {'income', 'expense', 'netFlow'});
    final previousTotals = _nestedObject(json, 'previousTotals');
    _expectKeys(previousTotals, const {'income', 'expense', 'netFlow'});
    return AnalyticsWindow(
      kind: switch (_requiredString(json, 'kind')) {
        'last_7_days' => AnalyticsPeriodKind.last7Days,
        'month' => AnalyticsPeriodKind.month,
        'quarter' => AnalyticsPeriodKind.quarter,
        'year' => AnalyticsPeriodKind.year,
        'custom' => AnalyticsPeriodKind.custom,
        _ => throw const FormatException('Unknown analytics period.'),
      },
      periodStart: _date(period, 'from'),
      periodEnd: _date(period, 'to'),
      previousStart: _date(previousPeriod, 'from'),
      previousEnd: _date(previousPeriod, 'to'),
      baseCurrency: _currency(json, 'baseCurrency'),
      income: _signedMoney(totals, 'income'),
      expense: _signedMoney(totals, 'expense'),
      netFlow: _signedMoney(totals, 'netFlow'),
      previousIncome: _signedMoney(previousTotals, 'income'),
      previousExpense: _signedMoney(previousTotals, 'expense'),
      previousNetFlow: _signedMoney(previousTotals, 'netFlow'),
      balance: AnalyticsBalanceLine.fromJson(_nestedObject(json, 'balance')),
      expenseChanges: _categoryChanges(json['expenseChanges']),
      incomeChanges: _categoryChanges(json['incomeChanges']),
    );
  }

  final AnalyticsPeriodKind kind;
  final String periodStart;
  final String periodEnd;
  final String previousStart;
  final String previousEnd;
  final String baseCurrency;
  final String income;
  final String expense;
  final String netFlow;
  final String previousIncome;
  final String previousExpense;
  final String previousNetFlow;
  final AnalyticsBalanceLine balance;

  /// Largest first, zeros included when the previous window had something.
  final List<AnalyticsCategoryChange> expenseChanges;
  final List<AnalyticsCategoryChange> incomeChanges;
}

List<AnalyticsCategoryChange> _categoryChanges(Object? raw) {
  if (raw is! List<Object?> || raw.length > 200) {
    throw const FormatException('Invalid analytics comparison.');
  }
  return [
    for (final item in raw) AnalyticsCategoryChange.fromJson(_asObject(item)),
  ];
}

/// What one category accounts for in the analysed month.
@immutable
final class AnalyticsCategoryTotal {
  const AnalyticsCategoryTotal({
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.sharePercent,
  });

  factory AnalyticsCategoryTotal.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'categoryId', 'name', 'amount', 'sharePercent'});
    final categoryId = json['categoryId'] == null
        ? null
        : _requiredUuid(json, 'categoryId');
    final name = json['name'] == null
        ? null
        : _boundedText(json, 'name', maximumLength: 100);
    if ((categoryId == null) != (name == null)) {
      throw const FormatException('A category total needs both or neither.');
    }
    return AnalyticsCategoryTotal(
      categoryId: categoryId,
      name: name,
      amount: _positiveMoney(json, 'amount'),
      sharePercent: _signedMoney(json, 'sharePercent'),
    );
  }

  /// Null for operations that carry no category link. The screen labels that
  /// line rather than hiding it, or the parts would stop summing to the whole.
  final String? categoryId;
  final String? name;
  final String amount;
  final String sharePercent;

  bool get isUncategorized => categoryId == null;
}

/// One analysed month: totals, both breakdowns, and the expense series.
@immutable
final class AnalyticsSummary {
  factory AnalyticsSummary.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'generatedAt',
      'baseCurrency',
      'period',
      'totals',
      'expenseByCategory',
      'incomeByCategory',
      'trend',
    });
    _requireSchemaVersion(json);
    final period = _nestedObject(json, 'period');
    _expectKeys(period, const {'from', 'to'});
    final totals = _nestedObject(json, 'totals');
    _expectKeys(totals, const {'income', 'expense', 'netFlow'});
    final trend = _nestedObject(json, 'trend');
    _expectKeys(trend, const {'metric', 'period', 'total', 'points'});
    if (trend['metric'] != 'expense' || trend['period'] != '7d') {
      throw const FormatException('Unsupported analytics trend.');
    }
    return AnalyticsSummary(
      periodStart: _date(period, 'from'),
      periodEnd: _date(period, 'to'),
      baseCurrency: _currency(json, 'baseCurrency'),
      income: _signedMoney(totals, 'income'),
      expense: _signedMoney(totals, 'expense'),
      netFlow: _signedMoney(totals, 'netFlow'),
      trendTotal: _signedMoney(trend, 'total'),
      expenseByCategory: _categoryTotals(json['expenseByCategory']),
      incomeByCategory: _categoryTotals(json['incomeByCategory']),
      trendPoints: _trendPoints(trend['points']),
    );
  }

  AnalyticsSummary({
    required this.periodStart,
    required this.periodEnd,
    required this.baseCurrency,
    required this.income,
    required this.expense,
    required this.netFlow,
    required this.trendTotal,
    required List<AnalyticsCategoryTotal> expenseByCategory,
    required List<AnalyticsCategoryTotal> incomeByCategory,
    required List<AnalyticsTrendPoint> trendPoints,
  }) : expenseByCategory = List<AnalyticsCategoryTotal>.unmodifiable(
         expenseByCategory,
       ),
       incomeByCategory = List<AnalyticsCategoryTotal>.unmodifiable(
         incomeByCategory,
       ),
       trendPoints = List<AnalyticsTrendPoint>.unmodifiable(trendPoints);

  final String periodStart;
  final String periodEnd;
  final String baseCurrency;
  final String income;
  final String expense;
  final String netFlow;
  final String trendTotal;

  /// Largest first. Only categories with something in the period are present.
  final List<AnalyticsCategoryTotal> expenseByCategory;
  final List<AnalyticsCategoryTotal> incomeByCategory;
  final List<AnalyticsTrendPoint> trendPoints;

  bool get isEmpty =>
      expenseByCategory.isEmpty &&
      incomeByCategory.isEmpty &&
      income == '0' &&
      expense == '0';
}

@immutable
final class AnalyticsTrendPoint {
  const AnalyticsTrendPoint({required this.date, required this.amount});

  factory AnalyticsTrendPoint.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'date', 'amount'});
    return AnalyticsTrendPoint(
      date: _date(json, 'date'),
      amount: _signedMoney(json, 'amount'),
    );
  }

  final String date;
  final String amount;
}

/// The shortest keyword a category may claim, mirroring the server rule.
///
/// Below this a keyword stops describing a category and starts matching
/// everything.
const int minimumCategoryKeywordLength = 3;

/// How many words one category may claim.
const int maximumCategoryKeywords = 32;

// Unicode property classes, not `\w`: Dart's `\w` is ASCII-only even with the
// unicode flag, so a Cyrillic keyword would be refused before it ever reached
// the server that happily accepts it.
final RegExp _categoryKeywordPattern = RegExp(
  r'^[\p{L}\p{N}]{3,40}$',
  unicode: true,
);

/// One spelling per word, so matching never depends on how it was typed.
///
/// Checked here as well as on the server so a mistyped word is answered
/// immediately instead of costing a round trip.
String validatedCategoryKeyword(String value) {
  final normalized = value.trim().toLowerCase();
  if (!_categoryKeywordPattern.hasMatch(normalized)) {
    throw const FormatException('Invalid category keyword.');
  }
  return normalized;
}

/// The words that lead to one category (ADR 0020 step 3).
@immutable
final class CategoryKeywords {
  CategoryKeywords({required this.categoryId, required List<String> keywords})
    : keywords = List<String>.unmodifiable(keywords);

  factory CategoryKeywords.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'categoryId', 'keywords'});
    _requireSchemaVersion(json);
    final raw = json['keywords'];
    if (raw is! List<Object?> || raw.length > maximumCategoryKeywords) {
      throw const FormatException('Invalid category keywords.');
    }
    final keywords = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw const FormatException('Invalid category keyword.');
      }
      keywords.add(validatedCategoryKeyword(item));
    }
    if (keywords.toSet().length != keywords.length) {
      throw const FormatException('A keyword appears at most once.');
    }
    return CategoryKeywords(
      categoryId: _requiredUuid(json, 'categoryId'),
      keywords: keywords,
    );
  }

  final String categoryId;
  final List<String> keywords;
}

/// The longest sentence the parse endpoint accepts.
///
/// The server enforces this; the client checks it only to avoid spending a
/// round trip on something that cannot be accepted.
const int maximumEntryTextLength = 280;

/// Why the parser could not fill a field.
///
/// Advisory, never an error: the user is looking at an editable form.
enum OperationParseGap {
  amountNotFound,
  ambiguousAmount,
  dateNotUnderstood,
  categoryNotMatched,
  currencyNotUnderstood,

  /// The sentence moves money between the person's own wallets, so no amount
  /// is proposed at all: booking either side as income or expense would invent
  /// money that never entered or left (ADR 0029).
  transferNotAnOperation,

  /// Nothing says which way the money went, and the words lead to a category of
  /// income. The form asks rather than letting expense stand as the default.
  directionNotClear,
}

/// What one written sentence appears to mean.
///
/// Not a draft and not confirmable: it carries no command id and no hash. The
/// client builds the ordinary draft from it and Finance Core still decides
/// (ADR 0022).
@immutable
final class OperationProposal {
  const OperationProposal({
    required this.type,
    required this.amount,
    required this.currency,
    required this.occurredOn,
    required this.sourceExpression,
    required this.categoryId,
    required this.category,
    this.otherCategoryId,
    this.gaps = const [],
  });

  factory OperationProposal.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'proposal'});
    _requireSchemaVersion(json);
    final proposal = _nestedObject(json, 'proposal');
    _expectKeys(proposal, const {
      'type',
      'amount',
      'currency',
      'occurredOn',
      'sourceExpression',
      'categoryId',
      'category',
      'otherCategoryId',
      'gaps',
    });
    return OperationProposal(
      type: _operationType(_requiredString(proposal, 'type')),
      // Null is a real answer: the amount is the one field the parser refuses
      // to guess.
      amount: proposal['amount'] == null
          ? null
          : _positiveMoney(proposal, 'amount'),
      currency: _currency(proposal, 'currency'),
      occurredOn: _date(proposal, 'occurredOn'),
      sourceExpression: _optionalBoundedText(
        proposal,
        'sourceExpression',
        maximumLength: 128,
      ),
      categoryId: _optionalUuid(proposal, 'categoryId'),
      category: _optionalBoundedText(proposal, 'category', maximumLength: 100),
      otherCategoryId: _optionalUuid(proposal, 'otherCategoryId'),
      gaps: _parseGaps(proposal['gaps']),
    );
  }

  final FinanceOperationType type;
  final String? amount;
  final String currency;
  final String occurredOn;
  final String? sourceExpression;
  final String? categoryId;
  final String? category;

  /// The category the same words reach if the money went the other way, so
  /// answering or correcting the direction does not mean choosing it again.
  final String? otherCategoryId;
  final List<OperationParseGap> gaps;

  /// The category these words reach in [direction], if any.
  String? categoryIdFor(FinanceOperationType direction) =>
      direction == type ? categoryId : otherCategoryId;
}

List<OperationParseGap> _parseGaps(Object? raw) {
  if (raw is! List<Object?> || raw.length > 8) {
    throw const FormatException('Invalid parse gaps.');
  }
  final gaps = <OperationParseGap>[];
  for (final item in raw) {
    if (item is! String) throw const FormatException('Invalid parse gap.');
    // A gap is advisory. An unknown code from a newer server is dropped
    // rather than failing the response: refusing to fill a form because of a
    // hint the client does not recognise would be worse than the hint.
    final gap = switch (item) {
      'AMOUNT_NOT_FOUND' => OperationParseGap.amountNotFound,
      'AMBIGUOUS_AMOUNT' => OperationParseGap.ambiguousAmount,
      'DATE_NOT_UNDERSTOOD' => OperationParseGap.dateNotUnderstood,
      'CATEGORY_NOT_MATCHED' => OperationParseGap.categoryNotMatched,
      'CURRENCY_NOT_UNDERSTOOD' => OperationParseGap.currencyNotUnderstood,
      'TRANSFER_NOT_AN_OPERATION' => OperationParseGap.transferNotAnOperation,
      'DIRECTION_NOT_CLEAR' => OperationParseGap.directionNotClear,
      _ => null,
    };
    if (gap != null) gaps.add(gap);
  }
  return List<OperationParseGap>.unmodifiable(gaps);
}

/// One half of an exchange, exactly as the sentence stated it.
@immutable
final class TransferProposalSide {
  const TransferProposalSide({required this.amount, required this.currency});

  final String amount;
  final String currency;
}

/// Both halves of an exchange read from one sentence (ADR 0029).
///
/// Carries no wallets and no rate: which wallet a currency means is resolved
/// from the list this client already holds, and a rate is never stored
/// anywhere — it is implied by two amounts the person witnessed.
@immutable
final class TransferProposal {
  const TransferProposal({
    required this.sent,
    required this.received,
    required this.occurredOn,
  });

  factory TransferProposal.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'proposal'});
    _requireSchemaVersion(json);
    final proposal = _nestedObject(json, 'proposal');
    _expectKeys(proposal, const {'sent', 'received', 'occurredOn'});
    return TransferProposal(
      sent: _transferSide(_nestedObject(proposal, 'sent')),
      received: _transferSide(_nestedObject(proposal, 'received')),
      occurredOn: _date(proposal, 'occurredOn'),
    );
  }

  final TransferProposalSide sent;
  final TransferProposalSide received;
  final String occurredOn;
}

TransferProposalSide _transferSide(Map<String, Object?> json) {
  _expectKeys(json, const {'amount', 'currency'});
  return TransferProposalSide(
    amount: _positiveMoney(json, 'amount'),
    currency: _currency(json, 'currency'),
  );
}

/// Who is signed in, and the durable facts of their account.
///
/// Deliberately carries no money. A balance belongs on Home, and a second
/// surface reporting it is a second thing that can disagree with the
/// authoritative projection.
@immutable
final class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.email,
    this.account,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'user', 'account'});
    _requireSchemaVersion(json);
    final user = _nestedObject(json, 'user');
    _expectKeys(user, const {'id', 'displayName', 'email'});
    final account = json['account'];
    return UserProfile(
      displayName: _boundedText(user, 'displayName', maximumLength: 100),
      email: _email(user, 'email'),
      // Null until the account is bootstrapped: a registered user without one
      // is a real state, not an error.
      account: account == null
          ? null
          : ProfileAccountFacts.fromJson(_asObject(account)),
    );
  }

  final String displayName;
  final String email;
  final ProfileAccountFacts? account;
}

@immutable
final class ProfileAccountFacts {
  const ProfileAccountFacts({
    required this.currency,
    required this.canonicalTimezone,
    required this.openingBalanceOn,
  });

  factory ProfileAccountFacts.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'id',
      'currency',
      'canonicalTimezone',
      'openingBalanceOn',
    });
    return ProfileAccountFacts(
      currency: _currency(json, 'currency'),
      canonicalTimezone: _timezone(json, 'canonicalTimezone'),
      openingBalanceOn: _date(json, 'openingBalanceOn'),
    );
  }

  final String currency;

  /// The timezone every local date is resolved in (ADR 0010).
  final String canonicalTimezone;

  /// The baseline no operation may precede (ADR 0016).
  final String openingBalanceOn;
}

/// A sign-in address as the server already validated it.
///
/// Bounded and control-free rather than re-validated: the client shows this
/// string, it never routes mail with it.
String _email(Map<String, Object?> json, String key) {
  final value = _boundedText(json, key, maximumLength: 254);
  if (!value.contains('@')) throw FormatException('Invalid $key.');
  return value;
}

List<AnalyticsCategoryTotal> _categoryTotals(Object? raw) {
  if (raw is! List<Object?> || raw.length > 200) {
    throw const FormatException('Invalid analytics breakdown.');
  }
  return raw
      .map((item) => AnalyticsCategoryTotal.fromJson(_asObject(item)))
      .toList(growable: false);
}

List<AnalyticsTrendPoint> _trendPoints(Object? raw) {
  if (raw is! List<Object?> || raw.length != 7) {
    throw const FormatException('A 7d trend carries exactly seven points.');
  }
  return raw
      .map((item) => AnalyticsTrendPoint.fromJson(_asObject(item)))
      .toList(growable: false);
}

Map<String, Object?> _nestedObject(Map<String, Object?> json, String key) =>
    _asObject(json[key]);

Map<String, Object?> _asObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

/// One category as the management screen sees it, hidden ones included.
///
/// Deliberately a separate type from [FinanceCategory]. The picker's listing is
/// parsed with a closed key set on both the envelope and each item, so an
/// additive field there would not degrade the picker — it would stop it
/// loading. Managing the catalogue is newer, so it reads its own
/// representation and leaves the older one untouched (ADR 0020).
@immutable
final class ManagedFinanceCategory {
  const ManagedFinanceCategory({
    required this.categoryId,
    required this.name,
    required this.direction,
    required this.systemKey,
    required this.archivedAt,
  });

  factory ManagedFinanceCategory.fromJson(Map<String, Object?> json) {
    _expectKeys(
      json,
      const {'categoryId', 'name', 'direction', 'systemKey', 'createdAt'},
      optional: const {'archivedAt'},
    );
    return ManagedFinanceCategory(
      categoryId: _requiredUuid(json, 'categoryId'),
      name: _boundedText(json, 'name', maximumLength: 100),
      direction: _categoryDirection(_requiredString(json, 'direction')),
      systemKey: json['systemKey'] == null
          ? null
          : _categorySystemKey(_requiredString(json, 'systemKey')),
      archivedAt: _optionalTimestamp(json, 'archivedAt'),
    );
  }

  final String categoryId;
  final String name;
  final FinanceOperationType direction;
  final String? systemKey;

  /// Null while the category is offered for new operations.
  ///
  /// Hiding is the only removal there is: the row survives, so every operation
  /// recorded against it keeps its grouping.
  final String? archivedAt;

  bool get isArchived => archivedAt != null;
}

@immutable
final class ManagedCategoryList {
  ManagedCategoryList({required List<ManagedFinanceCategory> categories})
    : categories = List<ManagedFinanceCategory>.unmodifiable(categories);

  final List<ManagedFinanceCategory> categories;

  List<ManagedFinanceCategory> offered(FinanceOperationType direction) => [
    for (final category in categories)
      if (category.direction == direction && !category.isArchived) category,
  ];

  List<ManagedFinanceCategory> hidden(FinanceOperationType direction) => [
    for (final category in categories)
      if (category.direction == direction && category.isArchived) category,
  ];
}

/// A new category the user asked for.
@immutable
final class CreateCategoryCommand {
  const CreateCategoryCommand({required this.name, required this.direction});

  final String name;
  final FinanceOperationType direction;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'name': name,
    'direction': direction.wireName,
  };
}

/// A new name for one existing category.
@immutable
final class RenameCategoryCommand {
  const RenameCategoryCommand({required this.name});

  final String name;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'name': name,
  };
}

/// Rejects a name the server would reject anyway, before spending a request.
///
/// Mirrors the server bound exactly: trimmed, non-empty, at most 100
/// characters, and free of control characters.
String validatedCategoryName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 100 || _containsControl(trimmed)) {
    throw const FormatException('Invalid category name.');
  }
  return trimmed;
}

FinanceOperationType _categoryDirection(String value) => switch (value) {
  'expense' => FinanceOperationType.expense,
  'income' => FinanceOperationType.income,
  _ => throw FormatException('Unsupported category direction: $value'),
};

String _categorySystemKey(String value) {
  if (!RegExp(r'^[a-z][a-z0-9_]{0,62}$').hasMatch(value)) {
    throw const FormatException('Invalid category system key.');
  }
  return value;
}

enum SavingsGoalIssueCode {
  accountUnavailable,
  accountCurrencyMismatch,
  unsupportedCurrency,
  targetBeforeAccountBaseline,
  contributionBeforeAccountBaseline,
  futureContributionDate,
  goalNotActive,
  withdrawalExceedsGoalBalance,
}

@immutable
final class SavingsGoalIssue {
  const SavingsGoalIssue({required this.code, required this.field});

  factory SavingsGoalIssue.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'code', 'field'});
    return SavingsGoalIssue(
      code: _goalIssueCode(_requiredString(json, 'code')),
      field: _requiredString(json, 'field'),
    );
  }

  final SavingsGoalIssueCode code;
  final String field;
}

/// A savings target before the server has accepted it.
///
/// Like a plan and unlike an operation, a goal needs no evaluate/confirm
/// handshake: nothing it can do moves the authoritative balance (ADR 0019).
@immutable
final class SavingsGoalDraft {
  const SavingsGoalDraft({
    required this.commandId,
    required this.accountId,
    required this.title,
    required this.targetAmount,
    required this.currency,
    required this.targetOn,
    required this.requestedAt,
    this.monthlyContribution,
  });

  factory SavingsGoalDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'accountId',
      'title',
      'targetAmount',
      'currency',
      'targetOn',
      'monthlyContribution',
      'requestedAt',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    return SavingsGoalDraft(
      commandId: _requiredUuid(json, 'commandId'),
      accountId: _requiredUuid(json, 'accountId'),
      title: _boundedText(json, 'title', maximumLength: 100),
      targetAmount: _positiveMoney(json, 'targetAmount'),
      currency: _currency(json, 'currency'),
      targetOn: _date(json, 'targetOn'),
      // Absence is expressed by omitting the field, never by sending zero, so
      // a client cannot say "no plan" two different ways.
      monthlyContribution: json['monthlyContribution'] == null
          ? null
          : _positiveMoney(json, 'monthlyContribution'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String accountId;
  final String title;
  final String targetAmount;
  final String currency;
  final String targetOn;
  final String? monthlyContribution;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'accountId': accountId,
    'title': title,
    'targetAmount': targetAmount,
    'currency': currency,
    'targetOn': targetOn,
    'monthlyContribution': monthlyContribution,
    'requestedAt': requestedAt,
  };
}

/// A goal as the server stores it, with the figures it derived from the ledger.
@immutable
final class SavingsGoal {
  const SavingsGoal({
    required this.goalId,
    required this.accountId,
    required this.title,
    required this.targetAmount,
    required this.currentAmount,
    required this.monthlyContribution,
    required this.currency,
    required this.targetOn,
    required this.status,
    required this.achieved,
    required this.progressPercent,
  });

  factory SavingsGoal.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'goalId',
      'userId',
      'accountId',
      'commandId',
      'title',
      'targetAmount',
      'currentAmount',
      'monthlyContribution',
      'currency',
      'targetOn',
      'status',
      'achieved',
      'progressPercent',
      'createdAt',
      'updatedAt',
    });
    final achieved = json['achieved'];
    if (achieved is! bool) throw const FormatException('Invalid achieved.');
    return SavingsGoal(
      goalId: _requiredUuid(json, 'goalId'),
      accountId: _requiredUuid(json, 'accountId'),
      title: _boundedText(json, 'title', maximumLength: 100),
      targetAmount: _positiveMoney(json, 'targetAmount'),
      currentAmount: _nonNegativeMoney(json, 'currentAmount'),
      monthlyContribution: _nonNegativeMoney(json, 'monthlyContribution'),
      currency: _currency(json, 'currency'),
      targetOn: _date(json, 'targetOn'),
      status: _boundedText(json, 'status', maximumLength: 16),
      achieved: achieved,
      progressPercent: _nonNegativeMoney(json, 'progressPercent'),
    );
  }

  final String goalId;
  final String accountId;
  final String title;
  final String targetAmount;
  final String currentAmount;
  final String monthlyContribution;
  final String currency;
  final String targetOn;
  final String status;
  final bool achieved;
  final String progressPercent;

  bool get isActive => status == 'active';
}

@immutable
final class SavingsGoalCreated {
  const SavingsGoalCreated({
    required this.goal,
    required this.idempotentReplay,
  });

  final SavingsGoal goal;
  final bool idempotentReplay;
}

@immutable
final class FinanceGoalCancelCommand {
  const FinanceGoalCancelCommand({
    required this.commandId,
    required this.requestedAt,
  });

  factory FinanceGoalCancelCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'commandId', 'requestedAt'});
    _requiredLiteral(json, 'schemaVersion', '1');
    return FinanceGoalCancelCommand(
      commandId: _requiredUuid(json, 'commandId'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'requestedAt': requestedAt,
  };
}

@immutable
final class SavingsGoalCancelled {
  const SavingsGoalCancelled({
    required this.goal,
    required this.idempotentReplay,
  });

  final SavingsGoal goal;
  final bool idempotentReplay;
}

/// The two directions of a ledger entry (ADR 0019).
///
/// Two positive directions rather than one signed amount: a sign error would
/// silently reverse what the entry means.
enum GoalContributionDirection { deposit, withdrawal }

@immutable
final class GoalContributionCommand {
  const GoalContributionCommand({
    required this.commandId,
    required this.direction,
    required this.amount,
    required this.requestedAt,
    this.occurredOn,
  });

  factory GoalContributionCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'direction',
      'amount',
      'occurredOn',
      'requestedAt',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    return GoalContributionCommand(
      commandId: _requiredUuid(json, 'commandId'),
      direction: _goalContributionDirection(_requiredString(json, 'direction')),
      amount: _positiveMoney(json, 'amount'),
      // Omitted means "today in the account timezone", which only the server
      // can resolve.
      occurredOn: json['occurredOn'] == null ? null : _date(json, 'occurredOn'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final GoalContributionDirection direction;
  final String amount;
  final String? occurredOn;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'direction': direction.name,
    'amount': amount,
    'occurredOn': occurredOn,
    'requestedAt': requestedAt,
  };
}

@immutable
final class GoalContribution {
  const GoalContribution({
    required this.contributionId,
    required this.goalId,
    required this.direction,
    required this.amount,
    required this.currency,
    required this.occurredOn,
  });

  factory GoalContribution.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'contributionId',
      'goalId',
      'userId',
      'commandId',
      'direction',
      'amount',
      'currency',
      'occurredOn',
      'createdAt',
    });
    return GoalContribution(
      contributionId: _requiredUuid(json, 'contributionId'),
      goalId: _requiredUuid(json, 'goalId'),
      direction: _goalContributionDirection(_requiredString(json, 'direction')),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      occurredOn: _date(json, 'occurredOn'),
    );
  }

  final String contributionId;
  final String goalId;
  final GoalContributionDirection direction;
  final String amount;
  final String currency;
  final String occurredOn;
}

@immutable
final class GoalContributionRecorded {
  const GoalContributionRecorded({
    required this.contribution,
    required this.goal,
    required this.idempotentReplay,
  });

  final GoalContribution contribution;

  /// The goal with the entry already applied, so the client never recomputes
  /// the derived total itself.
  final SavingsGoal goal;
  final bool idempotentReplay;
}

@immutable
final class SavingsGoalList {
  SavingsGoalList({required this.evaluatedOn, required List<SavingsGoal> goals})
    : goals = List<SavingsGoal>.unmodifiable(goals);

  /// The local date the server used, so the client never has to guess which
  /// day the server considered "today".
  final String evaluatedOn;
  final List<SavingsGoal> goals;
}

/// Validates an identifier before it is interpolated into a request path.
/// A non-UUID value must never reach the URL.
String validateGoalId(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid goal id.');
  }
  return value;
}

String validateCategoryId(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid category id.');
  }
  return value;
}

void validateSavingsGoalDraft(SavingsGoalDraft draft) {
  SavingsGoalDraft.fromJson(draft.toJson());
}

void validateGoalContributionCommand(GoalContributionCommand command) {
  GoalContributionCommand.fromJson(command.toJson());
}

GoalContributionDirection _goalContributionDirection(String value) =>
    switch (value) {
      'deposit' => GoalContributionDirection.deposit,
      'withdrawal' => GoalContributionDirection.withdrawal,
      _ => throw FormatException('Unsupported contribution direction: $value'),
    };

SavingsGoalIssueCode _goalIssueCode(String value) => switch (value) {
  'ACCOUNT_UNAVAILABLE' => SavingsGoalIssueCode.accountUnavailable,
  'ACCOUNT_CURRENCY_MISMATCH' => SavingsGoalIssueCode.accountCurrencyMismatch,
  'UNSUPPORTED_CURRENCY' => SavingsGoalIssueCode.unsupportedCurrency,
  'TARGET_BEFORE_ACCOUNT_BASELINE' =>
    SavingsGoalIssueCode.targetBeforeAccountBaseline,
  'CONTRIBUTION_BEFORE_ACCOUNT_BASELINE' =>
    SavingsGoalIssueCode.contributionBeforeAccountBaseline,
  'FUTURE_CONTRIBUTION_DATE' => SavingsGoalIssueCode.futureContributionDate,
  'GOAL_NOT_ACTIVE' => SavingsGoalIssueCode.goalNotActive,
  'WITHDRAWAL_EXCEEDS_GOAL_BALANCE' =>
    SavingsGoalIssueCode.withdrawalExceedsGoalBalance,
  _ => throw FormatException('Unsupported goal issue code: $value'),
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

FinanceTransferIssueCode _transferIssueCode(String value) => switch (value) {
  'WALLET_UNAVAILABLE' => FinanceTransferIssueCode.walletUnavailable,
  'WALLET_CURRENCY_MISMATCH' => FinanceTransferIssueCode.walletCurrencyMismatch,
  'TRANSFER_BEFORE_WALLET_BASELINE' =>
    FinanceTransferIssueCode.transferBeforeWalletBaseline,
  'FUTURE_OCCURRED_DATE' => FinanceTransferIssueCode.futureOccurredDate,
  'CONFIRMATION_BEFORE_CAPTURE' =>
    FinanceTransferIssueCode.confirmationBeforeCapture,
  _ => throw FormatException('Unsupported transfer issue code: $value'),
};

FinanceTimezoneIssueCode _timezoneIssueCode(String value) => switch (value) {
  'TIMEZONE_UNCHANGED' => FinanceTimezoneIssueCode.timezoneUnchanged,
  'TIMEZONE_BEHIND_RECORDED_OPERATIONS' =>
    FinanceTimezoneIssueCode.timezoneBehindRecordedOperations,
  _ => throw FormatException('Unsupported timezone issue code: $value'),
};

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

/// Rejects unknown fields, and requires every field except [optional].
///
/// [optional] exists for additively introduced fields. A payload written before
/// such a field existed must still load: the encrypted outbox persists a
/// command before its first send (ADR 0014), so an app update that made an
/// older stored command unreadable would trip the fail-closed delivery lock
/// over a field the command never needed.
void _expectKeys(
  Map<String, Object?> json,
  Set<String> expected, {
  Set<String> optional = const <String>{},
}) {
  final keys = json.keys.toSet();
  if (!keys.containsAll(expected) ||
      !expected.union(optional).containsAll(keys)) {
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

String _timezone(Map<String, Object?> json, String key) =>
    _validTimezone(_requiredString(json, key));

String _validTimezone(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      value != value.trim() ||
      _containsControl(value) ||
      const {'Factory', 'localtime', 'posixrules'}.contains(value)) {
    throw const FormatException('Invalid IANA timezone.');
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

// --- recurring planned costs (ADR 0025) --------------------------------------

/// How often a rule repeats. Monthly only for now; weekly and yearly reuse the
/// same anchor arithmetic and are added deliberately, not by accident.
enum PlannedCostFrequency { monthly }

/// Whether a rule still generates instances.
enum PlannedCostRecurrenceStatus { active, ended }

/// Request to record one repeating intended payment.
///
/// `dayOfMonth` is the day the user meant, kept unclamped: 31 stays 31, and
/// the server shortens it into each month that is too short. Storing an
/// already-clamped day would lose the intent after the first February.
@immutable
final class PlannedCostRecurrenceDraft {
  const PlannedCostRecurrenceDraft({
    required this.commandId,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.title,
    required this.dayOfMonth,
    required this.startsOn,
    required this.requestedAt,
    this.category,
    this.categoryId,
    this.endsOn,
  });

  factory PlannedCostRecurrenceDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'accountId',
      'amount',
      'currency',
      'title',
      'category',
      'categoryId',
      'frequency',
      'dayOfMonth',
      'startsOn',
      'endsOn',
      'requestedAt',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    _requiredLiteral(json, 'frequency', 'monthly');
    final startsOn = _date(json, 'startsOn');
    final endsOn = json['endsOn'] == null ? null : _date(json, 'endsOn');
    if (endsOn != null && endsOn.compareTo(startsOn) < 0) {
      throw const FormatException('endsOn must not precede startsOn.');
    }
    return PlannedCostRecurrenceDraft(
      commandId: _requiredUuid(json, 'commandId'),
      accountId: _requiredUuid(json, 'accountId'),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      title: _boundedText(json, 'title', maximumLength: 100),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      categoryId: _optionalUuid(json, 'categoryId'),
      dayOfMonth: _dayOfMonth(json, 'dayOfMonth'),
      startsOn: startsOn,
      endsOn: endsOn,
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String accountId;
  final String amount;
  final String currency;
  final String title;
  final String? category;
  final String? categoryId;
  final int dayOfMonth;
  final String startsOn;
  final String? endsOn;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'accountId': accountId,
    'amount': amount,
    'currency': currency,
    'title': title,
    'category': category,
    'categoryId': categoryId,
    'frequency': 'monthly',
    'dayOfMonth': dayOfMonth,
    'startsOn': startsOn,
    'endsOn': endsOn,
    'requestedAt': requestedAt,
  };
}

/// Command that stops a rule from generating anything further.
@immutable
final class EndPlannedCostRecurrenceCommand {
  const EndPlannedCostRecurrenceCommand({
    required this.commandId,
    required this.requestedAt,
  });

  factory EndPlannedCostRecurrenceCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'commandId', 'requestedAt'});
    _requiredLiteral(json, 'schemaVersion', '1');
    return EndPlannedCostRecurrenceCommand(
      commandId: _requiredUuid(json, 'commandId'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'requestedAt': requestedAt,
  };
}

@immutable
final class PlannedCostRecurrence {
  const PlannedCostRecurrence({
    required this.recurrenceId,
    required this.accountId,
    required this.amount,
    required this.currency,
    required this.title,
    required this.dayOfMonth,
    required this.startsOn,
    required this.status,
    this.category,
    this.categoryId,
    this.endsOn,
  });

  factory PlannedCostRecurrence.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'recurrenceId',
      'userId',
      'accountId',
      'commandId',
      'amount',
      'currency',
      'title',
      'category',
      'categoryId',
      'frequency',
      'dayOfMonth',
      'startsOn',
      'endsOn',
      'status',
      'createdAt',
      'updatedAt',
    });
    _requiredLiteral(json, 'frequency', 'monthly');
    return PlannedCostRecurrence(
      recurrenceId: _requiredUuid(json, 'recurrenceId'),
      accountId: _requiredUuid(json, 'accountId'),
      amount: _positiveMoney(json, 'amount'),
      currency: _currency(json, 'currency'),
      title: _boundedText(json, 'title', maximumLength: 100),
      category: _optionalBoundedText(json, 'category', maximumLength: 100),
      categoryId: _optionalUuid(json, 'categoryId'),
      dayOfMonth: _dayOfMonth(json, 'dayOfMonth'),
      startsOn: _date(json, 'startsOn'),
      endsOn: json['endsOn'] == null ? null : _date(json, 'endsOn'),
      status: _recurrenceStatus(_requiredString(json, 'status')),
    );
  }

  final String recurrenceId;
  final String accountId;
  final String amount;
  final String currency;
  final String title;
  final String? category;
  final String? categoryId;
  final int dayOfMonth;
  final String startsOn;
  final String? endsOn;
  final PlannedCostRecurrenceStatus status;

  /// True when the anchor lands on the end of every month, which is what
  /// clamping makes «31st» and «last day of the month» mean identically.
  bool get isLastDayOfMonth => dayOfMonth == 31;
}

/// One outstanding instance a rule has already written.
@immutable
final class PlannedCostRecurrenceInstance {
  const PlannedCostRecurrenceInstance({
    required this.plannedCostId,
    required this.plannedOn,
  });

  factory PlannedCostRecurrenceInstance.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'plannedCostId', 'plannedOn'});
    return PlannedCostRecurrenceInstance(
      plannedCostId: _requiredUuid(json, 'plannedCostId'),
      plannedOn: _date(json, 'plannedOn'),
    );
  }

  final String plannedCostId;
  final String plannedOn;
}

/// A rule with the outstanding instances it owns.
@immutable
final class PlannedCostRecurrenceListItem {
  PlannedCostRecurrenceListItem({
    required this.recurrence,
    required List<PlannedCostRecurrenceInstance> upcoming,
  }) : upcoming = List<PlannedCostRecurrenceInstance>.unmodifiable(upcoming);

  factory PlannedCostRecurrenceListItem.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'recurrence', 'upcoming'});
    final raw = json['upcoming'];
    if (raw is! List) throw const FormatException('Invalid upcoming.');
    return PlannedCostRecurrenceListItem(
      recurrence: PlannedCostRecurrence.fromJson(
        _nestedObject(json, 'recurrence'),
      ),
      upcoming: raw
          .map(
            (item) => PlannedCostRecurrenceInstance.fromJson(_asObject(item)),
          )
          .toList(growable: false),
    );
  }

  final PlannedCostRecurrence recurrence;
  final List<PlannedCostRecurrenceInstance> upcoming;
}

@immutable
final class PlannedCostRecurrenceCreated {
  PlannedCostRecurrenceCreated({
    required this.recurrence,
    required this.idempotentReplay,
    required List<String> occurrences,
  }) : occurrences = List<String>.unmodifiable(occurrences);

  final PlannedCostRecurrence recurrence;
  final bool idempotentReplay;

  /// The dates the rule has just materialised, so the screen can show where
  /// the anchor actually lands before a short month surprises anyone.
  final List<String> occurrences;
}

@immutable
final class PlannedCostRecurrenceEnded {
  const PlannedCostRecurrenceEnded({
    required this.recurrence,
    required this.cancelledOccurrences,
  });

  final PlannedCostRecurrence recurrence;

  /// Future instances nobody had acted on, withdrawn with the rule. An
  /// instance already due survives, because it is an obligation that arrived.
  final int cancelledOccurrences;
}

@immutable
final class PlannedCostRecurrenceList {
  PlannedCostRecurrenceList({
    required List<PlannedCostRecurrenceListItem> recurrences,
  }) : recurrences = List<PlannedCostRecurrenceListItem>.unmodifiable(
         recurrences,
       );

  final List<PlannedCostRecurrenceListItem> recurrences;
}

void validatePlannedCostRecurrenceDraft(PlannedCostRecurrenceDraft draft) {
  PlannedCostRecurrenceDraft.fromJson(draft.toJson());
}

void validateEndPlannedCostRecurrence(EndPlannedCostRecurrenceCommand command) {
  EndPlannedCostRecurrenceCommand.fromJson(command.toJson());
}

/// Validates an identifier before it is interpolated into a request path.
String validateRecurrenceId(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid recurrence id.');
  }
  return value;
}

int _dayOfMonth(Map<String, Object?> json, String key) {
  final value = json[key];
  // 29, 30 and 31 are accepted rather than refused: refusing them was one of
  // the answers to February this design rejected (ADR 0025).
  if (value is! int || value < 1 || value > 31) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

PlannedCostRecurrenceStatus _recurrenceStatus(String value) => switch (value) {
  'active' => PlannedCostRecurrenceStatus.active,
  'ended' => PlannedCostRecurrenceStatus.ended,
  _ => throw FormatException('Unsupported recurrence status: $value'),
};

// --- the update a device may install (ADR 0026) -------------------------------

/// One published Android build, as the server describes it.
///
/// Nothing here is financial data. It describes a file: which version, how big,
/// and what it hashes to.
@immutable
final class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.sizeBytes,
    required this.sha256,
    required this.publishedAt,
    this.notes,
  });

  factory AppRelease.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'versionCode',
      'versionName',
      'sizeBytes',
      'sha256',
      'notes',
      'publishedAt',
    });
    final versionCode = json['versionCode'];
    if (versionCode is! int || versionCode < 1) {
      throw const FormatException('Invalid versionCode.');
    }
    final sizeBytes = json['sizeBytes'];
    // Bounded so a manifest cannot describe a download that would never end.
    if (sizeBytes is! int || sizeBytes < 1 || sizeBytes > 512 * 1024 * 1024) {
      throw const FormatException('Invalid sizeBytes.');
    }
    final versionName = _requiredString(json, 'versionName');
    if (!RegExp(r'^\d+(\.\d+){3}$').hasMatch(versionName)) {
      throw const FormatException('Invalid versionName.');
    }
    final digest = _requiredString(json, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid sha256.');
    }
    return AppRelease(
      versionCode: versionCode,
      versionName: versionName,
      sizeBytes: sizeBytes,
      sha256: digest,
      notes: _optionalBoundedText(json, 'notes', maximumLength: 500),
      publishedAt: _timestamp(json, 'publishedAt'),
    );
  }

  final int versionCode;
  final String versionName;
  final int sizeBytes;
  final String sha256;
  final String? notes;
  final String publishedAt;

  /// Whether a device on [installedVersionCode] has something to install.
  ///
  /// Equal is not newer, and older is refused outright: Android rejects a
  /// downgrade anyway, and offering one produces a failure to read.
  bool isNewerThan(int installedVersionCode) =>
      versionCode > installedVersionCode;
}

/// What the server answered when asked about updates.
@immutable
final class AppUpdateManifest {
  const AppUpdateManifest({required this.release});

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'release'});
    _requiredLiteral(json, 'schemaVersion', '1');
    final release = json['release'];
    return AppUpdateManifest(
      release: release == null ? null : AppRelease.fromJson(_asObject(release)),
    );
  }

  /// Null when the deployment has published nothing, which is a normal answer
  /// rather than a failure.
  final AppRelease? release;
}

// --- monthly budgets (ADR 0027) ----------------------------------------------

/// One ceiling and how the month stands against it.
///
/// Only the limit is stored server-side. Spent, remaining and overspent are
/// derived there from committed operations and arrive already computed, so two
/// screens cannot reach two answers.
@immutable
final class Budget {
  const Budget({
    required this.budgetId,
    required this.limit,
    required this.spent,
    required this.remaining,
    required this.planned,
    required this.overspent,
    this.categoryId,
    this.name,
  });

  factory Budget.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'budgetId',
      'categoryId',
      'name',
      'limit',
      'spent',
      'remaining',
      'planned',
      'overspent',
    });
    final overspent = json['overspent'];
    if (overspent is! bool) throw const FormatException('Invalid overspent.');
    final categoryId = _optionalUuid(json, 'categoryId');
    final name = _optionalBoundedText(json, 'name', maximumLength: 100);
    // The overall ceiling carries neither; a category line carries both.
    if ((categoryId == null) != (name == null)) {
      throw const FormatException('A named budget must carry its category.');
    }
    return Budget(
      budgetId: _requiredUuid(json, 'budgetId'),
      categoryId: categoryId,
      name: name,
      limit: _positiveMoney(json, 'limit'),
      spent: _nonNegativeMoney(json, 'spent'),
      // Signed: going over is a negative remainder, not a floor at zero.
      remaining: _signedMoney(json, 'remaining'),
      planned: _nonNegativeMoney(json, 'planned'),
      overspent: overspent,
    );
  }

  final String budgetId;

  /// Null for the overall monthly ceiling, which is a meaning rather than a
  /// missing value.
  final String? categoryId;
  final String? name;
  final String limit;
  final String spent;
  final String remaining;

  /// What is still planned this period. Shown beside the remainder and never
  /// subtracted from it (ADR 0018, ADR 0027).
  final String planned;
  final bool overspent;

  bool get isOverall => categoryId == null;
}

@immutable
final class BudgetsSnapshot {
  BudgetsSnapshot({
    required this.periodFrom,
    required this.periodTo,
    required this.currency,
    required this.overall,
    required List<Budget> categories,
  }) : categories = List<Budget>.unmodifiable(categories);

  factory BudgetsSnapshot.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'period',
      'currency',
      'overall',
      'categories',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    final period = _nestedObject(json, 'period');
    _expectKeys(period, const {'from', 'to'});
    final raw = json['categories'];
    if (raw is! List || raw.length > 200) {
      throw const FormatException('Invalid budget list.');
    }
    final overall = json['overall'];
    return BudgetsSnapshot(
      periodFrom: _date(period, 'from'),
      periodTo: _date(period, 'to'),
      currency: _currency(json, 'currency'),
      overall: overall == null ? null : Budget.fromJson(_asObject(overall)),
      categories: raw
          .map((item) => Budget.fromJson(_asObject(item)))
          .toList(growable: false),
    );
  }

  final String periodFrom;
  final String periodTo;
  final String currency;
  final Budget? overall;
  final List<Budget> categories;

  bool get isEmpty => overall == null && categories.isEmpty;
}

/// Declares or changes one ceiling. Idempotent by its target state: saying 400
/// twice leaves one ceiling of 400.
@immutable
final class SetBudgetCommand {
  const SetBudgetCommand({
    required this.commandId,
    required this.accountId,
    required this.limit,
    required this.currency,
    required this.requestedAt,
    this.categoryId,
  });

  factory SetBudgetCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'commandId',
      'accountId',
      'categoryId',
      'limit',
      'currency',
      'requestedAt',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    return SetBudgetCommand(
      commandId: _requiredUuid(json, 'commandId'),
      accountId: _requiredUuid(json, 'accountId'),
      categoryId: _optionalUuid(json, 'categoryId'),
      limit: _positiveMoney(json, 'limit'),
      currency: _currency(json, 'currency'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String accountId;
  final String? categoryId;
  final String limit;
  final String currency;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'accountId': accountId,
    'categoryId': categoryId,
    'limit': limit,
    'currency': currency,
    'requestedAt': requestedAt,
  };
}

@immutable
final class RemoveBudgetCommand {
  const RemoveBudgetCommand({
    required this.commandId,
    required this.requestedAt,
  });

  factory RemoveBudgetCommand.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'commandId', 'requestedAt'});
    _requiredLiteral(json, 'schemaVersion', '1');
    return RemoveBudgetCommand(
      commandId: _requiredUuid(json, 'commandId'),
      requestedAt: _timestamp(json, 'requestedAt'),
    );
  }

  final String commandId;
  final String requestedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': '1',
    'commandId': commandId,
    'requestedAt': requestedAt,
  };
}

@immutable
final class BudgetWritten {
  const BudgetWritten({required this.budgetId, this.categoryId});

  factory BudgetWritten.fromSetJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'idempotentReplay',
      'budgetId',
      'categoryId',
      'limit',
    });
    _requiredLiteral(json, 'schemaVersion', '1');
    if (json['idempotentReplay'] is! bool) {
      throw const FormatException('Invalid idempotentReplay.');
    }
    // Parsed even though it is not kept: a limit the server cannot express as
    // a decimal string is a malformed answer, not a field to skip.
    _positiveMoney(json, 'limit');
    return BudgetWritten(
      budgetId: _requiredUuid(json, 'budgetId'),
      categoryId: _optionalUuid(json, 'categoryId'),
    );
  }

  factory BudgetWritten.fromRemovalJson(Map<String, Object?> json) {
    _expectKeys(json, const {'schemaVersion', 'idempotentReplay', 'budgetId'});
    _requiredLiteral(json, 'schemaVersion', '1');
    if (json['idempotentReplay'] is! bool) {
      throw const FormatException('Invalid idempotentReplay.');
    }
    return BudgetWritten(budgetId: _requiredUuid(json, 'budgetId'));
  }

  final String budgetId;
  final String? categoryId;
}

void validateSetBudget(SetBudgetCommand command) {
  SetBudgetCommand.fromJson(command.toJson());
}

void validateRemoveBudget(RemoveBudgetCommand command) {
  RemoveBudgetCommand.fromJson(command.toJson());
}

/// Validates an identifier before it is interpolated into a request path.
String validateBudgetId(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid budget id.');
  }
  return value;
}
