import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/canonical_timezone.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/data/finance_entry_repository.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';
import '../../home/application/home_controller.dart';
import 'timezone_state.dart';

export 'timezone_state.dart';

final timezoneControllerProvider =
    NotifierProvider.autoDispose<TimezoneController, TimezoneState>(
      TimezoneController.new,
    );

/// Moves where this account's months are drawn (ADR 0028).
///
/// One phase, unlike the baseline correction: no balance moves, so there is
/// nothing to review before confirming. It also stays out of the encrypted
/// delivery outbox, which exists for accepted financial writes (ADR 0009) —
/// this changes no money.
class TimezoneController extends Notifier<TimezoneState> {
  var _requestInFlight = false;
  var _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  TimezoneState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const TimezoneLoading();
  }

  Future<void> load() async {
    final generation = ++_requestGeneration;
    _requestInFlight = true;
    try {
      final result = await _repository.listAccounts();
      if (generation != _requestGeneration) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          final account = value.account;
          if (account == null || value.canonicalTimezone == null) {
            state = const TimezoneAccountRequired();
            return;
          }
          ref
              .read(canonicalTimezoneProvider.notifier)
              .adopt(value.canonicalTimezone);
          state = TimezoneReady(
            accountId: account.accountId,
            canonicalTimezone: value.canonicalTimezone!,
            deviceTimezone: await _deviceTimezone(value.canonicalTimezone!),
          );
        case FinanceEntryFailureResult(:final failure):
          state = TimezoneLoadFailure(failure);
      }
    } on Object {
      if (generation == _requestGeneration) {
        state = TimezoneLoadFailure(_unexpectedFailure());
      }
    } finally {
      if (generation == _requestGeneration) _requestInFlight = false;
    }
  }

  Future<bool> correct(String zone) async {
    final current = state;
    if (_requestInFlight || current is! TimezoneReady) return false;
    if (!isUsableTimezoneName(zone)) return false;

    final generation = ++_requestGeneration;
    _requestInFlight = true;
    state = current.copyWith(isSubmitting: true);
    try {
      final result = await _repository.correctTimezone(
        FinanceTimezoneCommand(
          commandId: ref.read(financeCommandIdFactoryProvider)(),
          accountId: current.accountId,
          canonicalTimezone: zone,
          requestedAt: ref.read(financeEntryClockProvider)(),
        ),
      );
      if (generation != _requestGeneration) return false;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          // The server is the authority; adopt exactly what it settled on
          // rather than what was asked for.
          ref
              .read(canonicalTimezoneProvider.notifier)
              .adopt(value.canonicalTimezone);
          state = current.copyWith(
            canonicalTimezone: value.canonicalTimezone,
            isSubmitting: false,
          );
          // Home draws a month whose boundaries just moved, so the projected
          // snapshot it holds is answering the old question.
          await _refreshHome();
          return true;
        case FinanceEntryFailureResult(:final failure):
          state = current.copyWith(
            isSubmitting: false,
            failure: failure,
            issues: failure.timezoneIssues,
          );
          return false;
      }
    } on Object {
      if (generation == _requestGeneration) {
        state = current.copyWith(
          isSubmitting: false,
          failure: _unexpectedFailure(),
        );
      }
      return false;
    } finally {
      if (generation == _requestGeneration) _requestInFlight = false;
    }
  }

  Future<void> _refreshHome() async {
    try {
      await ref.read(homeControllerProvider.notifier).refresh();
    } on Object {
      // A stale Home is not a reason to report a settled correction as failed.
    }
  }

  /// What the phone is set to, or null when it cannot be asked.
  ///
  /// Reads through the same platform channel every capture uses, so it is the
  /// zone that would decide which day an operation falls on. Unavailable on a
  /// desktop test host, which is not an error.
  Future<String?> _deviceTimezone(String canonicalTimezone) async {
    try {
      final context = await ref
          .read(financeCaptureContextSourceProvider)
          .capture(canonicalTimezone: canonicalTimezone);
      final device = context.capturedTimezone;
      return device == canonicalTimezone || !isUsableTimezoneName(device)
          ? null
          : device;
    } on Object {
      return null;
    }
  }

  FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
    kind: FinanceEntryFailureKind.unknown,
    requestId: 'req_local_timezone',
  );
}
