import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/platform/file_share.dart';
import '../../home/data/home_cache.dart';
import '../../home/data/home_session_store.dart';
import '../../voice_entry/data/waiting_phrase_store.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/auth_session_store.dart';
import '../data/credentials_api.dart';
import '../data/credentials_repository.dart';
import '../domain/recovery_code.dart';

enum AuthMode {
  login,
  register,

  /// Replacing a forgotten password with a recovery code (ADR 0035).
  recover,
}

enum AuthNotice {
  none,
  sessionExpired,
  signedOut,

  /// The person asked to be erased; every device was signed out (ADR 0030).
  deletionScheduled,

  /// Signing in cancelled that request.
  deletionCancelled,

  /// The password was replaced with a recovery code, and the sign-in that
  /// should have followed did not happen (ADR 0035).
  passwordReset,
}

sealed class AuthState {
  const AuthState();
}

final class AuthBootstrapping extends AuthState {
  const AuthBootstrapping();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut({
    this.mode = AuthMode.login,
    this.notice = AuthNotice.none,
    this.issue,
    this.deletionDueAt,
  });

  final AuthMode mode;
  final AuthNotice notice;
  final AuthFailureKind? issue;

  /// When the account will be erased, for [AuthNotice.deletionScheduled].
  final DateTime? deletionDueAt;
}

final class AuthSubmitting extends AuthState {
  const AuthSubmitting(this.mode);

  final AuthMode mode;
}

final class AuthSigningOut extends AuthState {
  const AuthSigningOut();
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn({this.notice = AuthNotice.none});

  /// Something worth saying once the person is in — today only that their
  /// sign-in cancelled a scheduled erasure.
  final AuthNotice notice;
}

final authSessionEpochProvider = NotifierProvider<AuthSessionEpoch, int>(
  AuthSessionEpoch.new,
);

/// Changes only when the signed-in account boundary changes.
///
/// Access/refresh-token rotation advances [authSessionEpochProvider] but must
/// not discard an in-progress, explicitly reviewed Finance command for the
/// same account. Login, logout, account replacement, and fail-closed session
/// deletion advance both epochs.
final authAccountEpochProvider = NotifierProvider<AuthAccountEpoch, int>(
  AuthAccountEpoch.new,
);

class AuthSessionEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state += 1;
}

class AuthAccountEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void advance() => state += 1;
}

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  final cache = ref.watch(homeCacheProvider);
  return SecureAuthSessionStore(
    beforeSessionChange: () async {
      ref.read(authSessionEpochProvider.notifier).advance();
      ref.read(authAccountEpochProvider.notifier).advance();
      try {
        await cache.clear();
      } finally {
        // A copy of the previous person's record must not wait in the cache
        // for whoever signs in next (ADR 0030), whatever happened above.
        // Best-effort: a stuck file must not stop anyone signing out.
        try {
          await ref.read(fileShareProvider).clearExports();
        } on Object {
          // The next export empties the folder anyway.
        }
      }
    },
    afterTokenRotation: () async {
      ref.read(authSessionEpochProvider.notifier).advance();
    },
  );
});

final homeSessionStoreProvider = Provider<HomeSessionStore>(
  (ref) => ref.watch(authSessionStoreProvider),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!isNetworkBackendConfigured) {
    throw StateError('Authentication requires API_BASE_URL.');
  }
  final dio = Dio();
  ref.onDispose(() => dio.close(force: true));
  return AuthRepository(
    api: AuthApi(dio: dio, baseUri: Uri.parse(configuredApiBaseUrl)),
    sessionStore: ref.watch(authSessionStoreProvider),
  );
});

final credentialsRepositoryProvider = Provider<CredentialsRepositoryClient>((
  ref,
) {
  if (!isNetworkBackendConfigured) {
    throw StateError('Credentials require API_BASE_URL.');
  }
  // Read first: building it is what refuses a base address that is not HTTPS.
  final auth = ref.watch(authRepositoryProvider);
  final dio = Dio();
  ref.onDispose(() => dio.close(force: true));
  return CredentialsRepository(
    api: CredentialsApi(dio: dio, baseUri: Uri.parse(configuredApiBaseUrl)),
    auth: auth,
  );
});

/// A recovery code the person has been given and has not yet said they kept.
///
/// Memory only, and on purpose: the code exists so that losing this phone does
/// not lose the account, so the phone must never be where it is stored. While
/// one waits here it covers everything else on screen (see the auth gate).
final pendingRecoveryCodeProvider =
    NotifierProvider<PendingRecoveryCode, RecoveryCode?>(
      PendingRecoveryCode.new,
    );

class PendingRecoveryCode extends Notifier<RecoveryCode?> {
  @override
  RecoveryCode? build() => null;

  void show(RecoveryCode code) => state = code;

  /// The person says they have kept it. It is gone from the phone after this.
  void acknowledge() => state = null;
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  bool _bootstrapStarted = false;
  int _intentEpoch = 0;

  @override
  AuthState build() => const AuthBootstrapping();

  Future<void> bootstrap() async {
    if (_bootstrapStarted || !isNetworkBackendConfigured) return;
    _bootstrapStarted = true;
    final repository = ref.read(authRepositoryProvider);
    try {
      final session = await repository.readSession();
      if (session == null) {
        state = const AuthSignedOut();
        return;
      }
      if (!repository.accessTokenNeedsRefresh(session)) {
        state = const AuthSignedIn();
        return;
      }
      await _applyRefreshResult(await repository.refreshSession());
    } on Object {
      // Secure storage may be temporarily unavailable. No credential value is
      // exposed, logged, or copied to a weaker persistence mechanism.
      state = const AuthSignedOut(issue: AuthFailureKind.localStorage);
    }
  }

  void showMode(AuthMode mode) {
    final current = state;
    if (current is AuthSubmitting || current is AuthSigningOut) return;
    state = AuthSignedOut(mode: mode);
  }

  Future<void> login({required String email, required String password}) async {
    if (state is AuthSubmitting || state is AuthSigningOut) return;
    final intentEpoch = ++_intentEpoch;
    state = const AuthSubmitting(AuthMode.login);
    final result = await ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
    if (intentEpoch == _intentEpoch) {
      _applySubmission(result, AuthMode.login);
    }
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (state is AuthSubmitting || state is AuthSigningOut) return;
    final intentEpoch = ++_intentEpoch;
    state = const AuthSubmitting(AuthMode.register);
    final result = await ref
        .read(authRepositoryProvider)
        .register(displayName: displayName, email: email, password: password);
    if (result is AuthSubmissionSuccess) {
      // Asked for now because the password is in hand, and a new account is
      // exactly the one that has no way back in yet. Not getting one does not
      // undo the registration: Profile offers it again.
      final code = await _firstRecoveryCode(password);
      if (code != null && intentEpoch == _intentEpoch) {
        ref.read(pendingRecoveryCodeProvider.notifier).show(code);
      }
    }
    if (intentEpoch == _intentEpoch) {
      _applySubmission(result, AuthMode.register);
    }
  }

  /// Replaces a forgotten password with the recovery code, then signs in.
  Future<void> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    if (state is AuthSubmitting || state is AuthSigningOut) return;
    final intentEpoch = ++_intentEpoch;
    state = const AuthSubmitting(AuthMode.recover);
    CredentialResult<RecoveryCode> reset;
    try {
      reset = await ref
          .read(credentialsRepositoryProvider)
          .resetPassword(
            email: email,
            recoveryCode: recoveryCode,
            newPassword: newPassword,
          );
    } on Object {
      reset = const CredentialFailure(CredentialFailureKind.unknown);
    }
    switch (reset) {
      case CredentialFailure(:final kind):
        if (intentEpoch == _intentEpoch) {
          state = AuthSignedOut(
            mode: AuthMode.recover,
            issue: _resetIssue(kind),
          );
        }
      case CredentialSuccess(:final value):
        AuthSubmissionResult signIn;
        try {
          signIn = await ref
              .read(authRepositoryProvider)
              .login(email: email, password: newPassword);
        } on Object {
          signIn = const AuthSubmissionFailure(AuthFailureKind.unknown);
        }
        // Shown whatever else happened. The password is already changed, the
        // code that did it is spent, and its successor exists nowhere but in
        // this answer: dropping it would leave the account with no way back.
        ref.read(pendingRecoveryCodeProvider.notifier).show(value);
        if (intentEpoch != _intentEpoch) return;
        state = switch (signIn) {
          AuthSubmissionSuccess(:final deletionCancelled) => AuthSignedIn(
            notice: deletionCancelled
                ? AuthNotice.deletionCancelled
                : AuthNotice.none,
          ),
          AuthSubmissionFailure() => const AuthSignedOut(
            notice: AuthNotice.passwordReset,
          ),
        };
    }
  }

  Future<RecoveryCode?> _firstRecoveryCode(String password) async {
    try {
      final issued = await ref
          .read(credentialsRepositoryProvider)
          .issueRecoveryCode(password: password);
      return switch (issued) {
        CredentialSuccess(:final value) => value,
        CredentialFailure() => null,
      };
    } on Object {
      return null;
    }
  }

  static AuthFailureKind _resetIssue(CredentialFailureKind kind) {
    return switch (kind) {
      CredentialFailureKind.recoveryRejected =>
        AuthFailureKind.recoveryRejected,
      CredentialFailureKind.newPasswordRejected ||
      CredentialFailureKind.invalidInput ||
      // A reset has no password to confirm and no session to lose.
      CredentialFailureKind.passwordRejected ||
      CredentialFailureKind.authenticationRequired =>
        AuthFailureKind.invalidInput,
      CredentialFailureKind.throttled => AuthFailureKind.throttled,
      CredentialFailureKind.offline => AuthFailureKind.offline,
      CredentialFailureKind.timeout => AuthFailureKind.timeout,
      CredentialFailureKind.unavailable => AuthFailureKind.serviceUnavailable,
      CredentialFailureKind.malformedResponse =>
        AuthFailureKind.malformedResponse,
      CredentialFailureKind.unknown => AuthFailureKind.unknown,
    };
  }

  Future<AuthRefreshResult> recoverSession() async {
    if (state is! AuthSignedIn) return AuthRefreshResult.sessionChanged;
    final intentEpoch = _intentEpoch;
    final result = await ref.read(authRepositoryProvider).refreshSession();
    if (intentEpoch != _intentEpoch || state is! AuthSignedIn) {
      return AuthRefreshResult.sessionChanged;
    }
    return _applyRefreshResult(result, expectedIntentEpoch: intentEpoch);
  }

  Future<AuthRefreshResult> recoverSessionForHome() => recoverSession();

  Future<void> signOut() async {
    if (state is AuthSigningOut) return;
    final intentEpoch = ++_intentEpoch;
    state = const AuthSigningOut();
    await _forgetWaitingPhrases();
    try {
      await ref.read(authRepositoryProvider).logout();
    } on Object {
      try {
        await ref.read(authRepositoryProvider).clearLocalSession();
      } on Object {
        if (intentEpoch == _intentEpoch) {
          state = const AuthSignedOut(issue: AuthFailureKind.localStorage);
        }
        return;
      }
    }
    if (intentEpoch == _intentEpoch) {
      state = const AuthSignedOut(notice: AuthNotice.signedOut);
    }
  }

  /// The server accepted an erasure request and has already deleted every
  /// session, so there is nothing to revoke — only the local copy to drop.
  Future<void> accountDeletionScheduled(DateTime dueAt) async {
    final intentEpoch = ++_intentEpoch;
    await _forgetWaitingPhrases();
    try {
      await ref.read(authRepositoryProvider).clearLocalSession();
    } on Object {
      if (intentEpoch == _intentEpoch) {
        state = const AuthSignedOut(issue: AuthFailureKind.localStorage);
      }
      return;
    }
    if (intentEpoch == _intentEpoch) {
      state = AuthSignedOut(
        notice: AuthNotice.deletionScheduled,
        deletionDueAt: dueAt,
      );
    }
  }

  /// Phrases said without a connection go with the person who said them
  /// (ADR 0032). Only on a deliberate exit: a session that merely expired keeps
  /// them for the same account to read after signing in again.
  Future<void> _forgetWaitingPhrases() async {
    try {
      await ref.read(waitingPhraseStoreProvider).clear();
    } on Object {
      // The file is scoped to this account and unreadable without its key;
      // another account signing in deletes it on first read.
    }
  }

  Future<void> requireSignIn() async {
    final intentEpoch = ++_intentEpoch;
    try {
      await ref.read(authRepositoryProvider).clearLocalSession();
    } on Object {
      if (intentEpoch == _intentEpoch) {
        state = const AuthSignedOut(issue: AuthFailureKind.localStorage);
      }
      return;
    }
    if (intentEpoch == _intentEpoch) {
      state = const AuthSignedOut(notice: AuthNotice.sessionExpired);
    }
  }

  void _applySubmission(AuthSubmissionResult result, AuthMode mode) {
    state = switch (result) {
      AuthSubmissionSuccess(:final deletionCancelled) => AuthSignedIn(
        notice: deletionCancelled
            ? AuthNotice.deletionCancelled
            : AuthNotice.none,
      ),
      AuthSubmissionFailure(:final kind) => AuthSignedOut(
        mode: mode,
        issue: kind,
      ),
    };
  }

  Future<AuthRefreshResult> _applyRefreshResult(
    AuthRefreshResult result, {
    int? expectedIntentEpoch,
  }) async {
    if (_hasCompetingIntent(expectedIntentEpoch)) {
      return AuthRefreshResult.sessionChanged;
    }
    switch (result) {
      case AuthRefreshResult.recovered:
        state = const AuthSignedIn();
        return result;
      case AuthRefreshResult.invalid:
        state = const AuthSignedOut(notice: AuthNotice.sessionExpired);
        return result;
      case AuthRefreshResult.transientFailure:
        // Keep the local authenticated shell available so a valid encrypted
        // Home snapshot can still render offline. No token is downgraded.
        state = const AuthSignedIn();
        return result;
      case AuthRefreshResult.sessionChanged:
        final current = await ref.read(authRepositoryProvider).readSession();
        if (_hasCompetingIntent(expectedIntentEpoch)) {
          return AuthRefreshResult.sessionChanged;
        }
        if (current == null) {
          state = const AuthSignedOut(notice: AuthNotice.sessionExpired);
          return AuthRefreshResult.invalid;
        }
        state = const AuthSignedIn();
        return AuthRefreshResult.recovered;
    }
  }

  bool _hasCompetingIntent(int? expectedIntentEpoch) {
    return expectedIntentEpoch != null &&
        (expectedIntentEpoch != _intentEpoch || state is! AuthSignedIn);
  }
}
