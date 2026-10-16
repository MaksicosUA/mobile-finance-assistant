import 'package:flutter/foundation.dart';

@immutable
final class AuthUser {
  const AuthUser({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// Token pair returned by the authentication service before local persistence.
@immutable
final class AuthTokenBundle {
  const AuthTokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAtUtc,
    required this.refreshExpiresAtUtc,
    required this.cacheScopeId,
    required this.user,
    this.deletionCancelled = false,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAtUtc;
  final DateTime refreshExpiresAtUtc;
  final String cacheScopeId;
  final AuthUser user;

  /// This sign-in cancelled an erasure the person had scheduled (ADR 0030).
  /// Said once and never stored: it describes the sign-in, not the session.
  final bool deletionCancelled;
}

/// Complete credential record held only in platform secure storage.
@immutable
final class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAtUtc,
    required this.refreshExpiresAtUtc,
    required this.cacheScopeId,
    required this.revision,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAtUtc;
  final DateTime refreshExpiresAtUtc;
  final String cacheScopeId;
  final String revision;

  bool isSameSession(AuthSession? other) {
    return other != null &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        other.accessExpiresAtUtc == accessExpiresAtUtc &&
        other.refreshExpiresAtUtc == refreshExpiresAtUtc &&
        other.cacheScopeId == cacheScopeId &&
        other.revision == revision;
  }
}
