import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/credentials_api.dart';
import '../domain/recovery_code.dart';
import 'auth_controller.dart';

/// Why a request to change a password or issue a code did not go through, in
/// the terms a screen can say.
enum CredentialIssue {
  /// The password given to confirm the request did not match.
  passwordRejected,

  /// The new password is outside what the server accepts.
  newPasswordRejected,
  throttled,

  /// The server could not be reached.
  unreachable,

  /// The server answered but could not do it.
  unavailable,

  /// The session has ended; signing in again is the way back.
  authenticationRequired,
}

sealed class CredentialFormState {
  const CredentialFormState();
}

@immutable
final class CredentialFormReady extends CredentialFormState {
  const CredentialFormReady({this.issue});

  /// Why the last attempt did not go through, if it did not.
  final CredentialIssue? issue;
}

final class CredentialFormSubmitting extends CredentialFormState {
  const CredentialFormSubmitting();
}

CredentialIssue _issueFor(CredentialFailureKind kind) {
  return switch (kind) {
    CredentialFailureKind.passwordRejected => CredentialIssue.passwordRejected,
    CredentialFailureKind.newPasswordRejected =>
      CredentialIssue.newPasswordRejected,
    CredentialFailureKind.throttled => CredentialIssue.throttled,
    CredentialFailureKind.offline ||
    CredentialFailureKind.timeout => CredentialIssue.unreachable,
    CredentialFailureKind.authenticationRequired =>
      CredentialIssue.authenticationRequired,
    // A reset is not sent from these screens, so its refusal cannot come
    // back; and the fields are bounded, so neither can a malformed request.
    CredentialFailureKind.recoveryRejected ||
    CredentialFailureKind.invalidInput ||
    CredentialFailureKind.unavailable ||
    CredentialFailureKind.malformedResponse ||
    CredentialFailureKind.unknown => CredentialIssue.unavailable,
  };
}

/// Whether the signed-in account has a recovery code, for Profile to say.
///
/// Null when it could not be read: the row then says nothing rather than
/// claiming there is no code.
final recoveryCodeStatusProvider =
    FutureProvider.autoDispose<RecoveryCodeStatus?>((ref) async {
      ref.watch(authAccountEpochProvider);
      try {
        final result = await ref
            .watch(credentialsRepositoryProvider)
            .readRecoveryCodeStatus();
        return switch (result) {
          CredentialSuccess(:final value) => value,
          CredentialFailure() => null,
        };
      } on Object {
        // A build with no backend has nothing to ask. Unknown, like any other
        // failure, and not an error to be retried.
        return null;
      }
    });

final recoveryCodeIssueControllerProvider =
    NotifierProvider.autoDispose<
      RecoveryCodeIssueController,
      CredentialFormState
    >(RecoveryCodeIssueController.new);

/// Asks the server for a new recovery code (ADR 0035).
///
/// The code is handed back to the screen rather than kept here: the screen has
/// to leave before the code can be shown above everything else.
class RecoveryCodeIssueController extends Notifier<CredentialFormState> {
  @override
  CredentialFormState build() {
    ref.watch(authAccountEpochProvider);
    return const CredentialFormReady();
  }

  /// The new code, or null when none was issued.
  ///
  /// Returned even if this controller has gone meanwhile: the server has
  /// already replaced the old code, and the new one exists only in the answer.
  Future<RecoveryCode?> submit(String password) async {
    if (state is CredentialFormSubmitting) return null;
    state = const CredentialFormSubmitting();
    final result = await ref
        .read(credentialsRepositoryProvider)
        .issueRecoveryCode(password: password);
    switch (result) {
      case CredentialSuccess(:final value):
        // Left submitting: the screen is about to go.
        return value;
      case CredentialFailure(:final kind):
        if (ref.mounted) state = CredentialFormReady(issue: _issueFor(kind));
        return null;
    }
  }
}

final passwordChangeControllerProvider =
    NotifierProvider.autoDispose<PasswordChangeController, CredentialFormState>(
      PasswordChangeController.new,
    );

/// Changes the password of the signed-in account (ADR 0035).
class PasswordChangeController extends Notifier<CredentialFormState> {
  @override
  CredentialFormState build() {
    ref.watch(authAccountEpochProvider);
    return const CredentialFormReady();
  }

  /// Whether the password was changed.
  Future<bool> submit({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (state is CredentialFormSubmitting) return false;
    state = const CredentialFormSubmitting();
    final result = await ref
        .read(credentialsRepositoryProvider)
        .changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
    switch (result) {
      case CredentialSuccess():
        if (ref.mounted) state = const CredentialFormReady();
        return true;
      case CredentialFailure(:final kind):
        if (ref.mounted) state = CredentialFormReady(issue: _issueFor(kind));
        return false;
    }
  }
}
