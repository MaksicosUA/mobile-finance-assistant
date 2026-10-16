import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/application/operation_sync_controller.dart';
import '../../finance_entry/domain/finance_entry_result.dart';

/// Confirmed operations still waiting on this phone to reach the server.
///
/// They are not in the export, and they are lost if the account is erased. That
/// is said, not enforced: the encrypted outbox survives sign-out, so a sign-in
/// that cancels the erasure delivers them, and a delivery lock that is never
/// lifted automatically (ADR 0014) must not make erasure impossible.
final unsentOperationCountProvider = Provider<int>(
  (ref) => ref.watch(operationSyncControllerProvider).activeCount,
);

/// What happens once the server has accepted the request: the local session is
/// dropped and the sign-in screen says when the account will be erased.
/// Replaceable so a test can watch it without a real session store.
final accountDeletionCompletionProvider =
    Provider<Future<void> Function(DateTime dueAt)>(
      (ref) =>
          (dueAt) => ref
              .read(authControllerProvider.notifier)
              .accountDeletionScheduled(dueAt),
    );

final accountDeletionControllerProvider =
    NotifierProvider.autoDispose<
      AccountDeletionController,
      AccountDeletionState
    >(AccountDeletionController.new);

sealed class AccountDeletionState {
  const AccountDeletionState();
}

@immutable
final class AccountDeletionReady extends AccountDeletionState {
  const AccountDeletionReady({this.issue});

  /// Why the last attempt did not go through, if it did not.
  final AccountDeletionIssue? issue;
}

final class AccountDeletionSubmitting extends AccountDeletionState {
  const AccountDeletionSubmitting();
}

enum AccountDeletionIssue {
  /// The password did not match; nothing was scheduled.
  passwordRejected,

  /// The server could not be reached.
  unreachable,

  /// The server answered but could not take the request.
  unavailable,

  /// The session has ended; signing in again is the way back.
  authenticationRequired,
}

/// Asks the server to erase the person's account a week from now (ADR 0030).
///
/// Nothing on the phone is touched here: a refused or failed request leaves the
/// person signed in exactly as they were, and an accepted one is handed back to
/// the screen, which has to leave before the session does.
class AccountDeletionController extends Notifier<AccountDeletionState> {
  @override
  AccountDeletionState build() {
    ref.watch(authAccountEpochProvider);
    return const AccountDeletionReady();
  }

  /// When the account will be erased, or null when nothing was scheduled.
  ///
  /// The answer is returned even if this controller has gone meanwhile: the
  /// server has already signed every device out, and the phone must follow.
  Future<DateTime?> submit(String password) async {
    if (state is AccountDeletionSubmitting) return null;
    state = const AccountDeletionSubmitting();
    final result = await ref
        .read(financeEntryRepositoryProvider)
        .requestAccountDeletion(password: password);
    switch (result) {
      case FinanceEntrySuccess(:final value):
        // Left submitting: the screen is about to go, and the session with it.
        return value;
      case FinanceEntryFailureResult(:final failure):
        if (ref.mounted) {
          state = AccountDeletionReady(issue: _issueFor(failure));
        }
        return null;
    }
  }

  static AccountDeletionIssue _issueFor(FinanceEntryFailure failure) {
    if (failure.code == FinanceEntryErrorCode.passwordRejected) {
      return AccountDeletionIssue.passwordRejected;
    }
    return switch (failure.kind) {
      FinanceEntryFailureKind.unauthenticated ||
      FinanceEntryFailureKind.sessionChanged ||
      FinanceEntryFailureKind.unauthorized =>
        AccountDeletionIssue.authenticationRequired,
      FinanceEntryFailureKind.offline ||
      FinanceEntryFailureKind.timeout => AccountDeletionIssue.unreachable,
      _ => AccountDeletionIssue.unavailable,
    };
  }
}
