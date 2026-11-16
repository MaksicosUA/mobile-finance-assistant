import '../domain/auth_session.dart';
import '../domain/recovery_code.dart';
import 'auth_repository.dart';
import 'credentials_api.dart';

abstract interface class CredentialsRepositoryClient {
  /// Whether the signed-in account has a recovery code, and since when.
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus();

  /// A new recovery code for the signed-in account; the one before it stops
  /// working.
  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String password,
  });

  /// A new password; every other device is signed out, this one stays.
  Future<CredentialResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Replaces a forgotten password. Opens no session: the answer is the next
  /// recovery code, and signing in afterwards is the ordinary sign-in.
  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  });
}

/// Puts the current access token on the requests that need one (ADR 0035).
///
/// The token is refreshed beforehand when it is about to expire, and a request
/// is never sent twice: these carry a password, and replaying one on a
/// person's behalf after a refusal is not this layer's decision.
final class CredentialsRepository implements CredentialsRepositoryClient {
  CredentialsRepository({
    required CredentialsApiClient api,
    required AuthRepository auth,
  }) : // Public dependency names intentionally differ from private fields.
       // ignore: prefer_initializing_formals
       _api = api,
       // ignore: prefer_initializing_formals
       _auth = auth;

  final CredentialsApiClient _api;
  final AuthRepository _auth;

  @override
  Future<CredentialResult<RecoveryCodeStatus>> readRecoveryCodeStatus() {
    return _signedIn(
      (accessToken) => _api.readRecoveryCodeStatus(accessToken: accessToken),
    );
  }

  @override
  Future<CredentialResult<RecoveryCode>> issueRecoveryCode({
    required String password,
  }) {
    return _signedIn(
      (accessToken) =>
          _api.issueRecoveryCode(accessToken: accessToken, password: password),
    );
  }

  @override
  Future<CredentialResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _signedIn(
      (accessToken) => _api.changePassword(
        accessToken: accessToken,
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
  }

  @override
  Future<CredentialResult<RecoveryCode>> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) {
    return _api.resetPassword(
      email: email,
      recoveryCode: recoveryCode,
      newPassword: newPassword,
    );
  }

  Future<CredentialResult<T>> _signedIn<T>(
    Future<CredentialResult<T>> Function(String accessToken) request,
  ) async {
    final AuthSession? session;
    try {
      session = await _currentSession();
    } on Object {
      // Secure storage could not be read. Nothing was sent.
      return CredentialFailure<T>(CredentialFailureKind.unknown);
    }
    if (session == null) {
      return CredentialFailure<T>(CredentialFailureKind.authenticationRequired);
    }
    return request(session.accessToken);
  }

  /// The session to act as, refreshed first when its token is about to expire.
  /// Null when nobody is signed in, or when the account changed meanwhile:
  /// what was typed for one account is never sent as another.
  Future<AuthSession?> _currentSession() async {
    final initial = await _auth.readSession();
    if (initial == null || !_auth.accessTokenNeedsRefresh(initial)) {
      return initial;
    }
    switch (await _auth.refreshSession()) {
      case AuthRefreshResult.invalid:
        return null;
      case AuthRefreshResult.transientFailure:
        // Sent with the token in hand: if it has in fact expired the server
        // says so, and that is reported as a session that has ended.
        return initial;
      case AuthRefreshResult.recovered:
      case AuthRefreshResult.sessionChanged:
        final current = await _auth.readSession();
        if (current == null || current.cacheScopeId != initial.cacheScopeId) {
          return null;
        }
        return current;
    }
  }
}
