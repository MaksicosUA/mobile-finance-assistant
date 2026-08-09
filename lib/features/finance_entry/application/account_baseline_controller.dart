import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../home/application/home_controller.dart';
import '../data/finance_entry_repository.dart';
import '../domain/finance_entry_models.dart';
import '../domain/finance_entry_result.dart';
import 'account_baseline_state.dart';
import 'finance_entry_controller.dart';

export 'account_baseline_state.dart';

final accountBaselineControllerProvider =
    NotifierProvider.autoDispose<
      AccountBaselineController,
      AccountBaselineState
    >(AccountBaselineController.new);

class AccountBaselineController extends Notifier<AccountBaselineState> {
  FinanceBaselineCommitCommand? _commitCommand;
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  DateTime get _now => ref.read(financeEntryClockProvider)();

  @override
  AccountBaselineState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    _commitCommand = null;
    return const AccountBaselineLoading();
  }

  Future<void> load() => _load();

  void selectDate(DateTime value) {
    final current = state;
    if (_requestInFlight || current is! AccountBaselineEditing) return;
    final selected = _dateOnly(value);
    if (selected.isBefore(current.earliestDate) ||
        selected.isAfter(current.latestDate)) {
      state = AccountBaselineEditing(
        account: current.account,
        selectedDate: current.selectedDate,
        earliestDate: current.earliestDate,
        latestDate: current.latestDate,
        failure: _invalidInputFailure(),
      );
      return;
    }
    _commitCommand = null;
    state = AccountBaselineEditing(
      account: current.account,
      selectedDate: selected,
      earliestDate: current.earliestDate,
      latestDate: current.latestDate,
    );
  }

  Future<void> evaluate() async {
    final current = state;
    if (_requestInFlight || current is! AccountBaselineEditing) return;

    late final FinanceBaselineDraft draft;
    try {
      if (current.selectedDate.isBefore(current.earliestDate) ||
          current.selectedDate.isAfter(current.latestDate)) {
        throw const FormatException('Baseline date is outside local bounds.');
      }
      draft = FinanceBaselineDraft.fromJson(
        FinanceBaselineDraft(
          commandId: ref.read(financeCommandIdFactoryProvider)(),
          accountId: current.account.accountId,
          openingBalanceOn: _dateWire(current.selectedDate),
        ).toJson(),
      );
    } on Object {
      state = AccountBaselineEditing(
        account: current.account,
        selectedDate: current.selectedDate,
        earliestDate: current.earliestDate,
        latestDate: current.latestDate,
        failure: _invalidInputFailure(),
      );
      return;
    }

    final requestGeneration = _beginRequest();
    _commitCommand = null;
    state = AccountBaselineEditing(
      account: current.account,
      selectedDate: current.selectedDate,
      earliestDate: current.earliestDate,
      latestDate: current.latestDate,
      isSubmitting: true,
    );
    try {
      final result = await _repository.evaluateBaseline(draft);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          if (!_sameDraft(value.draft, draft)) {
            state = AccountBaselineEditing(
              account: current.account,
              selectedDate: current.selectedDate,
              earliestDate: current.earliestDate,
              latestDate: current.latestDate,
              failure: _malformedResponseFailure(result.requestId),
            );
            return;
          }
          if (value.currentOpeningBalanceOn !=
              current.account.openingBalanceOn) {
            _endRequest(requestGeneration);
            await _load();
            return;
          }
          final bounds = _bounds(value.currentOpeningBalanceOn);
          if (bounds == null) {
            state = const AccountBaselineUnavailable(
              AccountBaselineUnavailableReason.minimumDate,
            );
            return;
          }
          switch (value) {
            case FinanceBaselineNeedsConfirmation():
              state = AccountBaselineReviewing(
                account: current.account,
                review: value,
                earliestDate: bounds.earliest,
                latestDate: bounds.latest,
              );
            case FinanceBaselineRejected(:final issues):
              final selected = _dateOnly(current.selectedDate);
              state = AccountBaselineEditing(
                account: current.account,
                selectedDate:
                    selected.isBefore(bounds.earliest) ||
                        selected.isAfter(bounds.latest)
                    ? bounds.latest
                    : selected,
                earliestDate: bounds.earliest,
                latestDate: bounds.latest,
                issues: issues,
              );
          }
        case FinanceEntryFailureResult(:final failure):
          if (_isAccountUnavailable(failure)) {
            _endRequest(requestGeneration);
            await _load();
            return;
          }
          _applyEvaluationFailure(current, failure);
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = AccountBaselineEditing(
          account: current.account,
          selectedDate: current.selectedDate,
          earliestDate: current.earliestDate,
          latestDate: current.latestDate,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  void edit() {
    final current = state;
    if (_requestInFlight || current is! AccountBaselineReviewing) return;
    _commitCommand = null;
    state = AccountBaselineEditing(
      account: current.account,
      selectedDate: _parseDate(current.review.draft.openingBalanceOn),
      earliestDate: current.earliestDate,
      latestDate: current.latestDate,
    );
  }

  Future<void> confirm() async {
    final current = state;
    if (_requestInFlight || current is! AccountBaselineReviewing) return;
    try {
      _commitCommand ??= FinanceBaselineCommitCommand.fromReview(
        review: current.review,
        confirmedAt: _now,
      );
    } on Object {
      state = AccountBaselineReviewing(
        account: current.account,
        review: current.review,
        earliestDate: current.earliestDate,
        latestDate: current.latestDate,
        failure: _invalidInputFailure(),
      );
      return;
    }

    final requestGeneration = _beginRequest();
    state = AccountBaselineReviewing(
      account: current.account,
      review: current.review,
      earliestDate: current.earliestDate,
      latestDate: current.latestDate,
      isSubmitting: true,
    );
    try {
      final result = await _repository.commitBaseline(_commitCommand!);
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          if (!_commitMatchesLoadedAccount(
            value,
            loadedAccount: current.account,
            review: current.review,
          )) {
            state = AccountBaselineReviewing(
              account: current.account,
              review: current.review,
              earliestDate: current.earliestDate,
              latestDate: current.latestDate,
              failure: _malformedResponseFailure(result.requestId),
            );
            return;
          }
          _commitCommand = null;
          state = AccountBaselineAccepted(
            commit: value,
            homeStatus: AccountBaselineHomeStatus.pending,
          );
          ref.invalidate(financeEntryControllerProvider);
          unawaited(
            _convergeHomeAfterAcceptedBaseline(value, requestGeneration),
          );
        case FinanceEntryFailureResult(:final failure):
          if (_isAccountUnavailable(failure)) {
            _commitCommand = null;
            _endRequest(requestGeneration);
            await _load();
            return;
          }
          if (_isDeterministicBaselineRejection(failure)) {
            _commitCommand = null;
            _endRequest(requestGeneration);
            await _load(
              retainedFailure: failure,
              retainedIssues: failure.baselineIssues,
            );
            return;
          }
          if (_sessionChanged(failure)) {
            _discardSensitiveState(failure);
          } else if (_requiresAuthentication(failure)) {
            _commitCommand = null;
            state = const AccountBaselineAuthenticationRequired();
          } else {
            state = AccountBaselineReviewing(
              account: current.account,
              review: current.review,
              earliestDate: current.earliestDate,
              latestDate: current.latestDate,
              failure: failure,
            );
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = AccountBaselineReviewing(
          account: current.account,
          review: current.review,
          earliestDate: current.earliestDate,
          latestDate: current.latestDate,
          failure: _unexpectedFailure(),
        );
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  Future<void> _load({
    FinanceEntryFailure? retainedFailure,
    List<FinanceBaselineIssue> retainedIssues = const [],
  }) async {
    if (_requestInFlight) return;
    final requestGeneration = _beginRequest();
    _commitCommand = null;
    state = const AccountBaselineLoading();
    try {
      final result = await _repository.listAccounts();
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          if (!value.isInitialized) {
            state = const AccountBaselineUnavailable(
              AccountBaselineUnavailableReason.accountRequired,
            );
            return;
          }
          state = _editingState(
            value.account!,
            failure: retainedFailure,
            issues: retainedIssues,
          );
        case FinanceEntryFailureResult(:final failure):
          if (_requiresAuthentication(failure)) {
            state = const AccountBaselineAuthenticationRequired();
          } else {
            state = AccountBaselineFailure(failure);
          }
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = AccountBaselineFailure(_unexpectedFailure());
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  AccountBaselineState _editingState(
    FinanceAccount account, {
    FinanceEntryFailure? failure,
    List<FinanceBaselineIssue> issues = const [],
  }) {
    final bounds = _bounds(account.openingBalanceOn);
    if (bounds == null) {
      return const AccountBaselineUnavailable(
        AccountBaselineUnavailableReason.minimumDate,
      );
    }
    return AccountBaselineEditing(
      account: account,
      selectedDate: bounds.latest,
      earliestDate: bounds.earliest,
      latestDate: bounds.latest,
      failure: failure,
      issues: issues,
    );
  }

  void _applyEvaluationFailure(
    AccountBaselineEditing previous,
    FinanceEntryFailure failure,
  ) {
    if (_sessionChanged(failure)) {
      _discardSensitiveState(failure);
    } else if (_requiresAuthentication(failure)) {
      state = const AccountBaselineAuthenticationRequired();
    } else {
      state = AccountBaselineEditing(
        account: previous.account,
        selectedDate: previous.selectedDate,
        earliestDate: previous.earliestDate,
        latestDate: previous.latestDate,
        failure: failure,
        issues: failure.baselineIssues,
      );
    }
  }

  Future<void> _convergeHomeAfterAcceptedBaseline(
    FinanceBaselineCommit commit,
    int requestGeneration,
  ) async {
    AccountBaselineHomeStatus homeStatus;
    try {
      final result = await ref
          .read(homeControllerProvider.notifier)
          .convergeAfterAcceptedWrite();
      homeStatus = _homeStatus(result);
    } on Object {
      homeStatus = AccountBaselineHomeStatus.failed;
    }
    if (!_isCurrentRequest(requestGeneration)) return;
    final current = state;
    if (current is AccountBaselineAccepted &&
        identical(current.commit, commit)) {
      state = AccountBaselineAccepted(commit: commit, homeStatus: homeStatus);
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
    _commitCommand = null;
    state = AccountBaselineFailure(failure);
  }
}

typedef _BaselineBounds = ({DateTime earliest, DateTime latest});

_BaselineBounds? _bounds(String currentOpeningBalanceOn) {
  final current = _parseDate(currentOpeningBalanceOn);
  final earliest = DateTime.utc(1900);
  if (!current.isAfter(earliest)) return null;
  return (
    earliest: earliest,
    latest: current.subtract(const Duration(days: 1)),
  );
}

bool _sameDraft(FinanceBaselineDraft left, FinanceBaselineDraft right) =>
    left.commandId == right.commandId &&
    left.accountId == right.accountId &&
    left.openingBalanceOn == right.openingBalanceOn;

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized;

bool _sessionChanged(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.sessionChanged;

bool _isDeterministicBaselineRejection(FinanceEntryFailure failure) =>
    failure.code == FinanceEntryErrorCode.baselineRejected;

bool _isAccountUnavailable(FinanceEntryFailure failure) =>
    failure.code == FinanceEntryErrorCode.accountUnavailable;

bool _commitMatchesLoadedAccount(
  FinanceBaselineCommit commit, {
  required FinanceAccount loadedAccount,
  required FinanceBaselineNeedsConfirmation review,
}) {
  final account = commit.account;
  return commit.previousOpeningBalanceOn == loadedAccount.openingBalanceOn &&
      commit.previousOpeningBalanceOn == review.currentOpeningBalanceOn &&
      account.openingBalanceOn == review.draft.openingBalanceOn &&
      account.accountId == loadedAccount.accountId &&
      account.userId == loadedAccount.userId &&
      account.commandId == loadedAccount.commandId &&
      account.name == loadedAccount.name &&
      account.currency == loadedAccount.currency &&
      account.openingBalance == loadedAccount.openingBalance &&
      account.openingTimezone == loadedAccount.openingTimezone &&
      _sameInstant(account.confirmedAt, loadedAccount.confirmedAt) &&
      _sameInstant(account.createdAt, loadedAccount.createdAt);
}

bool _sameInstant(String left, String right) {
  try {
    return DateTime.parse(
      left,
    ).toUtc().isAtSameMomentAs(DateTime.parse(right).toUtc());
  } on FormatException {
    return false;
  }
}

AccountBaselineHomeStatus _homeStatus(
  AcceptedWriteHomeConvergenceResult result,
) => switch (result) {
  AcceptedWriteHomeConvergenceResult.updated =>
    AccountBaselineHomeStatus.updated,
  AcceptedWriteHomeConvergenceResult.projectionDelayed =>
    AccountBaselineHomeStatus.projectionDelayed,
  AcceptedWriteHomeConvergenceResult.authenticationRequired =>
    AccountBaselineHomeStatus.authenticationRequired,
  AcceptedWriteHomeConvergenceResult.sessionChanged =>
    AccountBaselineHomeStatus.sessionChanged,
  AcceptedWriteHomeConvergenceResult.failed => AccountBaselineHomeStatus.failed,
};

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
  requestId: 'req_local_account_baseline_input',
);

FinanceEntryFailure _malformedResponseFailure(String requestId) =>
    FinanceEntryFailure(
      kind: FinanceEntryFailureKind.malformedResponse,
      requestId: requestId,
    );

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_account_baseline',
);
