import '../domain/auth_session.dart';
import 'auth_api.dart';
import 'auth_session_store.dart';

sealed class AuthSubmissionResult {
  const AuthSubmissionResult();
}

final class AuthSubmissionSuccess extends AuthSubmissionResult {
  const AuthSubmissionSuccess({this.deletionCancelled = false});

  /// The sign-in cancelled a scheduled erasure (ADR 0030).
  final bool deletionCancelled;
}

final class AuthSubmissionFailure extends AuthSubmissionResult {
  const AuthSubmissionFailure(this.kind);

  final AuthFailureKind kind;
}

enum AuthRefreshResult { recovered, invalid, transientFailure, sessionChanged }

/// Coordinates the transport with the single atomic secure-session record.
final class AuthRepository {
  AuthRepository({
    required AuthApiClient api,
    required AuthSessionStore sessionStore,
    DateTime Function() clock = _utcNow,
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _api = api,
       // ignore: prefer_initializing_formals
       _sessionStore = sessionStore,
       // ignore: prefer_initializing_formals
       _clock = clock;

  final AuthApiClient _api;
  final AuthSessionStore _sessionStore;
  final DateTime Function() _clock;

  Future<AuthRefreshResult>? _refreshInFlight;

  Future<AuthSession?> readSession() => _sessionStore.readAuthSession();

  bool accessTokenNeedsRefresh(
    AuthSession session, {
    Duration safetyWindow = const Duration(seconds: 30),
  }) {
    return !session.accessExpiresAtUtc.isAfter(
      _clock().toUtc().add(safetyWindow),
    );
  }

  Future<AuthSubmissionResult> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final result = await _api.register(
      displayName: displayName,
      email: email,
      password: password,
    );
    return _persistSubmission(result);
  }

  Future<AuthSubmissionResult> login({
    required String email,
    required String password,
  }) async {
    final result = await _api.login(email: email, password: password);
    return _persistSubmission(result);
  }

  Future<AuthRefreshResult> refreshSession() async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final operation = _refreshOnce();
    _refreshInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    }
  }

  Future<void> logout() async {
    final session = await _sessionStore.readAuthSession();
    if (session == null) {
      await _sessionStore.clearSession();
      return;
    }
    // Local deletion is the durable logout boundary. It happens before the
    // network request so an Activity/process kill cannot restore a session the
    // user already chose to close. A concurrent rotation for the same account
    // is also removed, while a newly selected account remains untouched.
    Object? localError;
    StackTrace? localStackTrace;
    try {
      await _sessionStore.clearSessionForAccountScope(session.cacheScopeId);
    } on Object catch (error, stackTrace) {
      localError = error;
      localStackTrace = stackTrace;
    }
    // A cache-cleanup error can be reported even after the secure credential
    // was deleted. Always attempt server revocation before surfacing it so a
    // copied refresh token does not remain valid after explicit logout.
    try {
      await _api.logout(refreshToken: session.refreshToken);
    } on Object {
      // Local deletion remains the durable logout boundary.
    }
    if (localError != null) {
      Error.throwWithStackTrace(localError, localStackTrace!);
    }
  }

  Future<void> clearLocalSession() => _sessionStore.clearSession();

  Future<AuthSubmissionResult> _persistSubmission(
    AuthSessionApiResult result,
  ) async {
    switch (result) {
      case AuthSessionApiFailure(:final kind):
        return AuthSubmissionFailure(kind);
      case AuthSessionApiData(:final tokens):
        try {
          await _sessionStore.saveAuthenticatedSession(tokens);
          return AuthSubmissionSuccess(
            deletionCancelled: tokens.deletionCancelled,
          );
        } on Object {
          try {
            await _api.logout(refreshToken: tokens.refreshToken);
          } on Object {
            // Best-effort revocation: no returned credential remains stored
            // locally and the orphaned server session expires independently.
          }
          return const AuthSubmissionFailure(AuthFailureKind.localStorage);
        }
    }
  }

  Future<AuthRefreshResult> _refreshOnce() async {
    final expected = await _sessionStore.readAuthSession();
    if (expected == null) return AuthRefreshResult.invalid;
    if (!expected.refreshExpiresAtUtc.isAfter(_clock().toUtc())) {
      final cleared = await _sessionStore.clearSessionIfCurrent(expected);
      return cleared
          ? AuthRefreshResult.invalid
          : AuthRefreshResult.sessionChanged;
    }

    final result = await _api.refresh(refreshToken: expected.refreshToken);
    switch (result) {
      case AuthSessionApiFailure(:final kind):
        if (kind == AuthFailureKind.invalidRefresh ||
            kind == AuthFailureKind.invalidInput) {
          final cleared = await _sessionStore.clearSessionIfCurrent(expected);
          return cleared
              ? AuthRefreshResult.invalid
              : AuthRefreshResult.sessionChanged;
        }
        return AuthRefreshResult.transientFailure;
      case AuthSessionApiData(:final tokens):
        if (tokens.cacheScopeId != expected.cacheScopeId) {
          final cleared = await _sessionStore.clearSessionIfCurrent(expected);
          return cleared
              ? AuthRefreshResult.invalid
              : AuthRefreshResult.sessionChanged;
        }
        try {
          await _sessionStore.rotateAuthenticatedSession(
            tokens: tokens,
            expectedSession: expected,
          );
          return AuthRefreshResult.recovered;
        } on Object {
          return _recoverAfterRotationPersistenceFailure(
            expected: expected,
            replacement: tokens,
          );
        }
    }
  }

  Future<AuthRefreshResult> _recoverAfterRotationPersistenceFailure({
    required AuthSession expected,
    required AuthTokenBundle replacement,
  }) async {
    AuthSession? current;
    try {
      current = await _sessionStore.readAuthSession();
    } on Object {
      // Continue with fail-closed cleanup below.
    }
    if (_isPersistedReplacement(current, replacement, expected.revision)) {
      return AuthRefreshResult.recovered;
    }
    if (current != null && current.cacheScopeId != expected.cacheScopeId) {
      return AuthRefreshResult.sessionChanged;
    }

    // The server has already consumed the old refresh token. Never report a
    // transient failure that would cause it to be replayed. Revoke the orphaned
    // replacement best-effort and remove any remaining credentials locally.
    try {
      await _api.logout(refreshToken: replacement.refreshToken);
    } on Object {
      // The local fail-closed boundary does not depend on network availability.
    }
    try {
      await _sessionStore.clearSessionForAccountScope(expected.cacheScopeId);
    } on Object {
      // The controller still moves to signed-out state. A later bootstrap will
      // retry validation instead of treating the consumed pair as recoverable.
    }
    return AuthRefreshResult.invalid;
  }
}

bool _isPersistedReplacement(
  AuthSession? current,
  AuthTokenBundle replacement,
  String expectedRevision,
) {
  return current != null &&
      current.accessToken == replacement.accessToken &&
      current.refreshToken == replacement.refreshToken &&
      current.accessExpiresAtUtc == replacement.accessExpiresAtUtc.toUtc() &&
      current.refreshExpiresAtUtc == replacement.refreshExpiresAtUtc.toUtc() &&
      current.cacheScopeId == replacement.cacheScopeId &&
      current.revision == expectedRevision;
}

DateTime _utcNow() => DateTime.now().toUtc();
