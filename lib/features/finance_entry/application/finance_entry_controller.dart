import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../../core/network/api_config.dart';
import '../../../core/platform/finance_capture_context.dart';
import '../../auth/application/auth_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/finance_command_id.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import '../domain/operation_outbox.dart';
import 'finance_entry_dependencies.dart';
import 'finance_entry_state.dart';
import 'operation_sync_controller.dart';

export 'finance_entry_state.dart';
export '../domain/finance_entry_models.dart' show FinanceOperationType;

typedef FinanceEntryClock = DateTime Function();

final financeEntryClockProvider = Provider<FinanceEntryClock>(
  (_) => DateTime.now,
);

final financeCommandIdFactoryProvider = Provider<FinanceCommandIdFactory>(
  (_) => newFinanceCommandId,
);

final financeCaptureContextSourceProvider =
    Provider<FinanceCaptureContextSource>(
      (_) => const PlatformFinanceCaptureContextSource(),
    );

final financeEntryApiProvider = financeEntryApiDependencyProvider;

final financeEntryRepositoryProvider = financeEntryRepositoryDependencyProvider;

final financeEntryControllerProvider =
    NotifierProvider.autoDispose<FinanceEntryController, FinanceEntryState>(
      FinanceEntryController.new,
    );

class FinanceEntryController extends Notifier<FinanceEntryState> {
  FinanceAccountCommitCommand? _accountCommit;
  FinanceOperationCommitCommand? _operationCommit;
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  DateTime get _now => ref.read(financeEntryClockProvider)();

  @override
  FinanceEntryState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    _accountCommit = null;
    _operationCommit = null;
    return const FinanceEntryLoading();
  }

  Future<void> load() async {
    if (_requestInFlight) return;
    final requestGeneration = _beginRequest();
    _accountCommit = null;
    _operationCommit = null;
    state = const FinanceEntryLoading();
    try {
      final result = await _repository.listAccounts();
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          final timeContext = await _captureTimeContext();
          if (!_isCurrentRequest(requestGeneration)) return;
          if (!value.isInitialized) {
            state = FinanceAccountEditing(
              initialInput: _defaultAccountInput(
                timeContext.canonicalLocalDate,
              ),
              latestOpeningDate: timeContext.canonicalLocalDate,
            );
            return;
          }
          final account = value.account!;
          // The account is where the canonical zone actually lives, and it is
          // correctable (ADR 0028) — so this reads it rather than comparing it
          // against a compile-time default and refusing to load. The two
          // copies having to agree is enforced by the model itself.
          ref
              .read(canonicalTimezoneProvider.notifier)
              .adopt(value.canonicalTimezone);
          state = FinanceOperationEditing(
            account: account,
            initialInput: _defaultOperationInput(
              account,
              timeContext.osLocalDate,
            ),
            latestOperationDate: timeContext.osLocalDate,
          );
        case FinanceEntryFailureResult(:final failure):
          _applyLoadFailure(failure);
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = FinanceEntryLoadFailure(_unexpectedFailure());
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> evaluateAccount(AccountSetupInput input) async {
    final current = state;
    if (_requestInFlight || current is! FinanceAccountEditing) return;
    late final String name;
    late final String openingBalance;
    late final String openingBalanceOn;
    try {
      name = _requiredText(input.name, maximumLength: 100);
      openingBalance = normalizeMoneyInput(
        input.openingBalance,
        allowNegative: true,
      );
      openingBalanceOn = _dateWire(input.openingBalanceOn);
    } on Object {
      state = FinanceAccountEditing(
        initialInput: input,
        latestOpeningDate: current.latestOpeningDate,
        failure: _invalidInputFailure(),
      );
      return;
    }

    final requestGeneration = _beginRequest();
    state = FinanceAccountEditing(
      initialInput: input,
      latestOpeningDate: current.latestOpeningDate,
      isSubmitting: true,
    );
    try {
      final timeContext = await _captureTimeContext();
      if (!_isCurrentRequest(requestGeneration)) return;
      if (_dateOnly(
        input.openingBalanceOn,
      ).isAfter(timeContext.canonicalLocalDate)) {
        state = FinanceAccountEditing(
          initialInput: input,
          latestOpeningDate: timeContext.canonicalLocalDate,
          failure: _invalidInputFailure(),
        );
        return;
      }
      final draft = FinanceAccountDraft(
        commandId: ref.read(financeCommandIdFactoryProvider)(),
        name: name,
        currency: 'EUR',
        openingBalance: openingBalance,
        openingBalanceOn: openingBalanceOn,
        canonicalTimezone: configuredHomeApiTimezone,
      );
      validateAccountDraft(draft);
      final result = await _repository.evaluateAccount(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          switch (value) {
            case FinanceAccountNeedsConfirmation():
              _accountCommit = null;
              state = FinanceAccountReviewing(
                review: value,
                latestOpeningDate: timeContext.canonicalLocalDate,
                latestOperationDate: timeContext.osLocalDate,
              );
            case FinanceAccountRejected(:final issues):
              state = FinanceAccountEditing(
                initialInput: input,
                latestOpeningDate: timeContext.canonicalLocalDate,
                issues: issues,
              );
          }
        case FinanceEntryFailureResult(:final failure):
          if (_sessionChanged(failure)) {
            _discardSensitiveState(failure);
          } else if (_requiresAuthentication(failure)) {
            state = const FinanceEntryAuthenticationRequired();
          } else {
            state = FinanceAccountEditing(
              initialInput: input,
              latestOpeningDate: timeContext.canonicalLocalDate,
              failure: failure,
              issues: failure.issues,
            );
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = FinanceAccountEditing(
          initialInput: input,
          latestOpeningDate: current.latestOpeningDate,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> confirmAccount() async {
    final current = state;
    if (_requestInFlight || current is! FinanceAccountReviewing) return;
    try {
      _accountCommit ??= FinanceAccountCommitCommand.fromReview(
        review: current.review,
        confirmedAt: _now,
      );
    } on Object {
      state = FinanceAccountReviewing(
        review: current.review,
        latestOpeningDate: current.latestOpeningDate,
        latestOperationDate: current.latestOperationDate,
        failure: _invalidInputFailure(),
      );
      return;
    }

    final requestGeneration = _beginRequest();
    state = FinanceAccountReviewing(
      review: current.review,
      latestOpeningDate: current.latestOpeningDate,
      latestOperationDate: current.latestOperationDate,
      isSubmitting: true,
    );
    try {
      final result = await _repository.commitAccount(_accountCommit!);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          _accountCommit = null;
          final account = value.account;
          state = FinanceOperationEditing(
            account: account,
            initialInput: _defaultOperationInput(
              account,
              current.latestOperationDate,
            ),
            latestOperationDate: current.latestOperationDate,
            accountCreated: true,
          );
          unawaited(_convergeHomeAfterAcceptedAccount());
        case FinanceEntryFailureResult(:final failure):
          if (_sessionChanged(failure)) {
            _discardSensitiveState(failure);
          } else if (_requiresAuthentication(failure)) {
            state = const FinanceEntryAuthenticationRequired();
          } else if (failure.code ==
              FinanceEntryErrorCode.accountAlreadyInitialized) {
            _endRequest(requestGeneration);
            await load();
            return;
          } else {
            state = FinanceAccountReviewing(
              review: current.review,
              latestOpeningDate: current.latestOpeningDate,
              latestOperationDate: current.latestOperationDate,
              failure: failure,
            );
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = FinanceAccountReviewing(
          review: current.review,
          latestOpeningDate: current.latestOpeningDate,
          latestOperationDate: current.latestOperationDate,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  void editAccount() {
    final current = state;
    if (_requestInFlight || current is! FinanceAccountReviewing) return;
    _accountCommit = null;
    final draft = current.review.draft;
    state = FinanceAccountEditing(
      initialInput: AccountSetupInput(
        name: draft.name,
        openingBalance: draft.openingBalance,
        openingBalanceOn: _parseDate(draft.openingBalanceOn),
      ),
      latestOpeningDate: current.latestOpeningDate,
    );
  }

  Future<void> evaluateOperation(OperationEntryInput input) async {
    final current = state;
    if (_requestInFlight || current is! FinanceOperationEditing) return;
    late final DateTime occurredOn;
    late final String amount;
    late final String? category;
    late final String? merchant;
    try {
      occurredOn = _dateOnly(input.occurredOn);
      final openingOn = _parseDate(current.account.openingBalanceOn);
      if (occurredOn.isBefore(openingOn)) {
        throw const FormatException('Operation date is outside the ledger.');
      }
      amount = normalizeMoneyInput(input.amount);
      category = _optionalText(input.category, maximumLength: 100);
      merchant = _optionalText(input.merchant, maximumLength: 160);
      // A link without its text would leave the operation with a group and no
      // record of what the user actually chose.
      if (input.categoryId != null && category == null) {
        throw const FormatException('A linked category needs its name.');
      }
    } on Object {
      state = FinanceOperationEditing(
        account: current.account,
        initialInput: input,
        latestOperationDate: current.latestOperationDate,
        failure: _invalidInputFailure(),
      );
      return;
    }

    final requestGeneration = _beginRequest();
    state = FinanceOperationEditing(
      account: current.account,
      initialInput: input,
      latestOperationDate: current.latestOperationDate,
      isSubmitting: true,
    );
    try {
      final timeContext = await _captureTimeContext();
      if (!_isCurrentRequest(requestGeneration)) return;
      if (occurredOn.isAfter(timeContext.osLocalDate)) {
        state = FinanceOperationEditing(
          account: current.account,
          initialInput: input,
          latestOperationDate: timeContext.osLocalDate,
          failure: _invalidInputFailure(),
        );
        return;
      }
      final draft = FinanceOperationDraft(
        commandId: ref.read(financeCommandIdFactoryProvider)(),
        type: input.type,
        amount: amount,
        currency: current.account.currency,
        accountId: current.account.accountId,
        category: category,
        categoryId: input.categoryId,
        merchant: merchant,
        capturedAt: timeContext.capturedAtUtc.toIso8601String(),
        capturedTimezone: timeContext.capturedTimezone,
        sourceExpression: null,
        occurredOn: _dateWire(occurredOn),
        occurredAt: null,
        source: FinanceOperationSource.manualText,
      );
      validateOperationDraft(draft);
      final result = await _repository.evaluateOperation(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          switch (value) {
            case FinanceOperationNeedsConfirmation():
              _operationCommit = null;
              state = FinanceOperationReviewing(
                account: current.account,
                review: value,
                latestOperationDate: timeContext.osLocalDate,
              );
            case FinanceOperationRejected(:final issues):
              state = FinanceOperationEditing(
                account: current.account,
                initialInput: input,
                latestOperationDate: timeContext.osLocalDate,
                issues: issues,
              );
          }
        case FinanceEntryFailureResult(:final failure):
          if (_sessionChanged(failure)) {
            _discardSensitiveState(failure);
          } else if (_requiresAuthentication(failure)) {
            state = const FinanceEntryAuthenticationRequired();
          } else {
            state = FinanceOperationEditing(
              account: current.account,
              initialInput: input,
              latestOperationDate: timeContext.osLocalDate,
              failure: failure,
              issues: failure.issues,
            );
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = FinanceOperationEditing(
          account: current.account,
          initialInput: input,
          latestOperationDate: current.latestOperationDate,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> confirmOperation() async {
    final current = state;
    if (_requestInFlight || current is! FinanceOperationReviewing) return;
    try {
      _operationCommit ??= FinanceOperationCommitCommand.fromReview(
        review: current.review,
        confirmedAt: _now,
      );
    } on Object {
      state = FinanceOperationReviewing(
        account: current.account,
        review: current.review,
        latestOperationDate: current.latestOperationDate,
        failure: _invalidInputFailure(),
      );
      return;
    }

    final requestGeneration = _beginRequest();
    state = FinanceOperationReviewing(
      account: current.account,
      review: current.review,
      latestOperationDate: current.latestOperationDate,
      isSubmitting: true,
    );
    try {
      final result = await ref
          .read(operationDeliveryCoordinatorProvider)
          .enqueueAndSynchronize(
            expectedPrincipalScopeId: current.account.userId,
            command: _operationCommit!,
            onAccepted: (commit) {
              if (!_isCurrentRequest(requestGeneration)) return;
              _operationCommit = null;
              state = FinanceOperationAccepted(
                account: current.account,
                operation: commit.operation,
                latestOperationDate: current.latestOperationDate,
                homeStatus: FinanceEntryHomeStatus.updating,
              );
            },
          );
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case OperationDeliveryAccepted(:final commit, :final homeStatus):
          _operationCommit = null;
          final operation = commit.operation;
          state = FinanceOperationAccepted(
            account: current.account,
            operation: operation,
            latestOperationDate: current.latestOperationDate,
            homeStatus: _homeStatus(homeStatus),
          );
        case OperationDeliveryAlreadySynced():
          _operationCommit = null;
          state = FinanceOperationAlreadySynced(
            account: current.account,
            latestOperationDate: current.latestOperationDate,
          );
        case OperationDeliveryQueued(:final code):
          _operationCommit = null;
          state = FinanceOperationQueued(
            account: current.account,
            latestOperationDate: current.latestOperationDate,
            authenticationRequired: const {
              OperationOutboxErrorCode.authenticationRequired,
              OperationOutboxErrorCode.sessionChanged,
              OperationOutboxErrorCode.unauthorized,
            }.contains(code),
          );
        case OperationDeliveryPermanentFailure(:final code):
          _operationCommit = null;
          state = FinanceOperationDeliveryAttention(
            account: current.account,
            latestOperationDate: current.latestOperationDate,
            issue: _deliveryIssue(code),
          );
        case OperationDeliveryAuthenticationRequired():
          _operationCommit = null;
          state = const FinanceEntryAuthenticationRequired();
        case OperationDeliveryStorageFailure():
          state = FinanceOperationReviewing(
            account: current.account,
            review: current.review,
            latestOperationDate: current.latestOperationDate,
            failure: _localStorageFailure(),
          );
      }
    } on Object {
      if (!_isCurrentRequest(requestGeneration)) return;
      if (state case FinanceOperationAccepted(
        :final account,
        :final operation,
      )) {
        state = FinanceOperationAccepted(
          account: account,
          operation: operation,
          latestOperationDate: current.latestOperationDate,
          homeStatus: FinanceEntryHomeStatus.failed,
        );
      } else {
        state = FinanceOperationReviewing(
          account: current.account,
          review: current.review,
          latestOperationDate: current.latestOperationDate,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  void editOperation() {
    final current = state;
    if (_requestInFlight || current is! FinanceOperationReviewing) return;
    _operationCommit = null;
    final draft = current.review.draft;
    state = FinanceOperationEditing(
      account: current.account,
      initialInput: OperationEntryInput(
        type: draft.type,
        amount: draft.amount,
        occurredOn: _parseDate(draft.occurredOn),
        category: draft.category,
        merchant: draft.merchant,
      ),
      latestOperationDate: current.latestOperationDate,
    );
  }

  void addAnotherOperation() {
    final current = state;
    if (_requestInFlight ||
        ref.read(operationSyncControllerProvider).phase ==
            OperationSyncPhase.locked) {
      return;
    }
    late final FinanceAccount account;
    late final DateTime latestOperationDate;
    switch (current) {
      case FinanceOperationAccepted(
            account: final value,
            latestOperationDate: final date,
          ) ||
          FinanceOperationQueued(
            account: final value,
            latestOperationDate: final date,
          ) ||
          FinanceOperationAlreadySynced(
            account: final value,
            latestOperationDate: final date,
          ):
        account = value;
        latestOperationDate = date;
      case FinanceOperationDeliveryAttention(
            account: final value,
            latestOperationDate: final date,
            issue: final issue,
          )
          when issue != FinanceOperationDeliveryIssue.securityBlocked:
        account = value;
        latestOperationDate = date;
      default:
        return;
    }
    state = FinanceOperationEditing(
      account: account,
      initialInput: _defaultOperationInput(account, latestOperationDate),
      latestOperationDate: latestOperationDate,
    );
  }

  AccountSetupInput _defaultAccountInput(DateTime canonicalLocalDate) =>
      AccountSetupInput(
        name: '',
        openingBalance: '0',
        openingBalanceOn: canonicalLocalDate,
      );

  OperationEntryInput _defaultOperationInput(
    FinanceAccount account,
    DateTime capturedLocalDate,
  ) {
    final openingOn = _parseDate(account.openingBalanceOn);
    return OperationEntryInput(
      type: FinanceOperationType.expense,
      amount: '',
      occurredOn: capturedLocalDate.isBefore(openingOn)
          ? openingOn
          : capturedLocalDate,
    );
  }

  Future<FinanceCaptureContext> _captureTimeContext() {
    return ref
        .read(financeCaptureContextSourceProvider)
        .capture(canonicalTimezone: ref.read(canonicalTimezoneProvider));
  }

  void _applyLoadFailure(FinanceEntryFailure failure) {
    if (_sessionChanged(failure)) {
      _discardSensitiveState(failure);
    } else {
      state = _requiresAuthentication(failure)
          ? const FinanceEntryAuthenticationRequired()
          : FinanceEntryLoadFailure(failure);
    }
  }

  int _beginRequest() {
    _requestInFlight = true;
    _requestGeneration += 1;
    return _requestGeneration;
  }

  bool _isCurrentRequest(int requestGeneration) =>
      ref.mounted && requestGeneration == _requestGeneration;

  void _endRequest(int requestGeneration) {
    if (_isCurrentRequest(requestGeneration)) _requestInFlight = false;
  }

  void _discardSensitiveState(FinanceEntryFailure failure) {
    _requestGeneration += 1;
    _requestInFlight = false;
    _accountCommit = null;
    _operationCommit = null;
    state = FinanceEntryLoadFailure(failure);
  }

  Future<void> _convergeHomeAfterAcceptedAccount() async {
    try {
      await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite();
    } on Object {
      // The account is already authoritative. Home exposes its own retained
      // refresh/failure state and must never turn a successful account commit
      // back into a failed financial write.
    }
  }
}

String normalizeMoneyInput(String value, {bool allowNegative = false}) {
  final normalized = value.trim().replaceAll(',', '.');
  final pattern = allowNegative
      ? RegExp(
          r'^-?(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?|0(?:\.[0-9]{1,18})?)$',
        )
      : RegExp(
          r'^(?:[1-9][0-9]{0,19}(?:\.[0-9]{1,18})?|0\.(?!0{1,18}$)[0-9]{1,18})$',
        );
  if (!pattern.hasMatch(normalized)) {
    throw const FormatException('Invalid decimal money input.');
  }
  return normalized;
}

bool _requiresAuthentication(FinanceEntryFailure failure) {
  return failure.kind == FinanceEntryFailureKind.unauthenticated ||
      failure.kind == FinanceEntryFailureKind.unauthorized;
}

bool _sessionChanged(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.sessionChanged;

FinanceEntryHomeStatus _homeStatus(
  AcceptedWriteHomeConvergenceResult result,
) => switch (result) {
  AcceptedWriteHomeConvergenceResult.updated => FinanceEntryHomeStatus.updated,
  AcceptedWriteHomeConvergenceResult.projectionDelayed =>
    FinanceEntryHomeStatus.projectionDelayed,
  AcceptedWriteHomeConvergenceResult.authenticationRequired =>
    FinanceEntryHomeStatus.authenticationRequired,
  AcceptedWriteHomeConvergenceResult.sessionChanged =>
    FinanceEntryHomeStatus.sessionChanged,
  AcceptedWriteHomeConvergenceResult.failed => FinanceEntryHomeStatus.failed,
};

String _requiredText(String value, {required int maximumLength}) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maximumLength ||
      _containsControl(normalized)) {
    throw const FormatException('Invalid required text.');
  }
  return normalized;
}

String? _optionalText(String? value, {required int maximumLength}) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return null;
  if (normalized.length > maximumLength || _containsControl(normalized)) {
    throw const FormatException('Invalid optional text.');
  }
  return normalized;
}

bool _containsControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _dateWire(DateTime value) {
  final date = _dateOnly(value);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime _parseDate(String value) {
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || _dateWire(parsed) != value) {
    throw const FormatException('Invalid calendar date.');
  }
  return parsed;
}

FinanceEntryFailure _invalidInputFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.invalidInput,
  requestId: 'req_local_finance_input',
);

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_finance_entry',
);

FinanceEntryFailure _localStorageFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.localStorage,
  requestId: 'req_local_finance_outbox',
);

FinanceOperationDeliveryIssue _deliveryIssue(OperationOutboxErrorCode code) =>
    switch (code) {
      OperationOutboxErrorCode.commandConflict =>
        FinanceOperationDeliveryIssue.commandConflict,
      OperationOutboxErrorCode.financeRejected =>
        FinanceOperationDeliveryIssue.rejected,
      OperationOutboxErrorCode.securityBlocked ||
      OperationOutboxErrorCode.responseScopeMismatch ||
      OperationOutboxErrorCode.locked ||
      OperationOutboxErrorCode.corruptPayload =>
        FinanceOperationDeliveryIssue.securityBlocked,
      _ => FinanceOperationDeliveryIssue.invalidCommand,
    };
