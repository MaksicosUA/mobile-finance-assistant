import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../../core/platform/file_share.dart';
import '../../home/data/home_cache.dart';
import '../../home/data/home_session_store.dart';
import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../data/auth_session_store.dart';

enum AuthMode { login, register }

enum AuthNotice {
  none,
  sessionExpired,
  signedOut,

  /// The person asked to be erased; every device was signed out (ADR 0030).
  deletionScheduled,

  /// Signing in cancelled that request.
  deletionCancelled,
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
      await cache.clear();
      // A copy of the previous person's record must not wait in the cache for
      // whoever signs in next (ADR 0030). Best-effort: a stuck file must not
      // stop anyone signing out.
      try {
        await ref.read(fileShareProvider).clearExports();
      } on Object {
        // The next export empties the folder anyway.
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
    if (intentEpoch == _intentEpoch) {
      _applySubmission(result, AuthMode.register);
    }
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
