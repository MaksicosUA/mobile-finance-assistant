import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../home/data/home_session_store.dart';
import '../domain/auth_session.dart';

typedef AuthSessionChangeHook = Future<void> Function();

abstract interface class AuthSessionStore implements HomeSessionStore {
  Future<AuthSession?> readAuthSession();

  Future<AuthSession> saveAuthenticatedSession(AuthTokenBundle tokens);

  Future<AuthSession> rotateAuthenticatedSession({
    required AuthTokenBundle tokens,
    required AuthSession expectedSession,
  });

  /// Clears only when [expectedSession] is still current.
  Future<bool> clearSessionIfCurrent(AuthSession expectedSession);

  /// Clears a rotated session for the same account without touching a newly
  /// selected account.
  Future<bool> clearSessionForAccountScope(String expectedCacheScopeId);
}

abstract interface class AuthSessionSecureValueStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

final class FlutterSecureAuthSessionValueStore
    implements AuthSessionSecureValueStore {
  const FlutterSecureAuthSessionValueStore({
    this.storage = const FlutterSecureStorage(),
    this.storageKey = 'mfa_session_v1',
  });

  final FlutterSecureStorage storage;
  final String storageKey;

  @override
  Future<String?> read() => storage.read(key: storageKey);

  @override
  Future<void> write(String value) =>
      storage.write(key: storageKey, value: value);

  @override
  Future<void> delete() => storage.delete(key: storageKey);
}

/// Atomic schema-v2 credential record stored as one platform-secure value.
///
/// The record contains no password, email, financial data, or JWT-derived
/// identity. Schema-v1 Home-only sessions are intentionally invalidated because
/// they cannot support refresh-token rotation safely.
final class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({
    AuthSessionSecureValueStore? valueStore,
    String Function()? revisionFactory,
    AuthSessionChangeHook? beforeSessionChange,
    AuthSessionChangeHook? afterTokenRotation,
  }) : _valueStore = valueStore ?? const FlutterSecureAuthSessionValueStore(),
       _revisionFactory = revisionFactory ?? _newRevision,
       _beforeSessionChange = beforeSessionChange ?? _noSessionChangeHook,
       _afterTokenRotation = afterTokenRotation ?? _noSessionChangeHook;

  static const int _schemaVersion = 2;
  static const int _maximumEncodedLength = 24 * 1024;

  final AuthSessionSecureValueStore _valueStore;
  final String Function() _revisionFactory;
  final AuthSessionChangeHook _beforeSessionChange;
  final AuthSessionChangeHook _afterTokenRotation;

  Future<void> _operationQueue = Future<void>.value();

  @override
  Future<AuthSession?> readAuthSession() => _serialized(_readUnlocked);

  @override
  Future<HomeSessionSnapshot?> readSession() async {
    final session = await readAuthSession();
    if (session == null) return null;
    return HomeSessionSnapshot(
      accessToken: session.accessToken,
      cacheScopeId: session.cacheScopeId,
      revision: session.revision,
    );
  }

  @override
  Future<AuthSession> saveAuthenticatedSession(AuthTokenBundle tokens) {
    final session = _sessionFromTokens(
      tokens,
      revision: _requiredRevision(_revisionFactory()),
    );
    return _serialized(() async {
      try {
        await _beforeSessionChange();
        await _writeSession(session);
        return session;
      } on Object catch (error, stackTrace) {
        // A failed cache invalidation or account replacement must not let the
        // previous account's credential silently reappear after a restart.
        try {
          await _valueStore.delete();
        } on Object {
          // Preserve the original secure-write failure for the caller.
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  @override
  Future<AuthSession> rotateAuthenticatedSession({
    required AuthTokenBundle tokens,
    required AuthSession expectedSession,
  }) {
    final replacement = _sessionFromTokens(
      tokens,
      revision: expectedSession.revision,
    );
    if (replacement.cacheScopeId != expectedSession.cacheScopeId) {
      throw const FormatException('Authentication account scope changed.');
    }

    return _serialized(() async {
      final current = await _readUnlocked();
      if (!expectedSession.isSameSession(current)) {
        throw StateError('The authentication session changed before refresh.');
      }
      await _writeSession(replacement);
      // Notify request owners only after both rotated tokens are durable.
      await _afterTokenRotation();
      return replacement;
    });
  }

  @override
  Future<bool> clearSessionIfCurrent(AuthSession expectedSession) {
    return _serialized(() async {
      final current = await _readUnlocked();
      if (!expectedSession.isSameSession(current)) return false;
      await _clearUnlocked();
      return true;
    });
  }

  @override
  Future<bool> clearSessionForAccountScope(String expectedCacheScopeId) {
    final scope = _requiredScope(expectedCacheScopeId);
    return _serialized(() async {
      final current = await _readUnlocked();
      if (current == null || current.cacheScopeId != scope) return false;
      await _clearUnlocked();
      return true;
    });
  }

  @override
  Future<void> clearSession() => _serialized(_clearUnlocked);

  Future<void> _clearUnlocked() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _beforeSessionChange();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _valueStore.delete();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _writeSession(AuthSession session) {
    return _valueStore.write(
      jsonEncode(<String, Object>{
        'schemaVersion': _schemaVersion,
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
        'accessExpiresAtUtc': session.accessExpiresAtUtc.toIso8601String(),
        'refreshExpiresAtUtc': session.refreshExpiresAtUtc.toIso8601String(),
        'cacheScopeId': session.cacheScopeId,
        'revision': session.revision,
      }),
    );
  }

  Future<AuthSession?> _readUnlocked() async {
    try {
      final encoded = await _valueStore.read();
      if (encoded == null) return null;
      if (encoded.length > _maximumEncodedLength) {
        throw const FormatException('Authentication session is too large.');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?> ||
          decoded.length != 7 ||
          decoded['schemaVersion'] != _schemaVersion) {
        throw const FormatException('Unsupported authentication session.');
      }
      final accessToken = decoded['accessToken'];
      final refreshToken = decoded['refreshToken'];
      final accessExpiry = decoded['accessExpiresAtUtc'];
      final refreshExpiry = decoded['refreshExpiresAtUtc'];
      final cacheScopeId = decoded['cacheScopeId'];
      final revision = decoded['revision'];
      if (accessToken is! String ||
          refreshToken is! String ||
          accessExpiry is! String ||
          refreshExpiry is! String ||
          cacheScopeId is! String ||
          revision is! String) {
        throw const FormatException('Invalid authentication session.');
      }
      return AuthSession(
        accessToken: _requiredToken(accessToken),
        refreshToken: _requiredToken(refreshToken),
        accessExpiresAtUtc: _requiredUtcTimestamp(accessExpiry),
        refreshExpiresAtUtc: _requiredUtcTimestamp(refreshExpiry),
        cacheScopeId: _requiredScope(cacheScopeId),
        revision: _requiredRevision(revision),
      );
    } on Object {
      // A partial, legacy, or corrupt credential must never be used. Invalidate
      // the associated encrypted Home cache before deleting it best-effort.
      try {
        await _beforeSessionChange();
      } on Object {
        // Continue credential deletion even when cache cleanup fails.
      }
      try {
        await _valueStore.delete();
      } on Object {
        // The caller still observes signed-out state. No value is logged or
        // downgraded to plaintext storage.
      }
      return null;
    }
  }
}

AuthSession _sessionFromTokens(
  AuthTokenBundle tokens, {
  required String revision,
}) {
  final accessExpiry = tokens.accessExpiresAtUtc.toUtc();
  final refreshExpiry = tokens.refreshExpiresAtUtc.toUtc();
  if (!refreshExpiry.isAfter(accessExpiry)) {
    throw const FormatException('Refresh expiry must follow access expiry.');
  }
  return AuthSession(
    accessToken: _requiredToken(tokens.accessToken),
    refreshToken: _requiredToken(tokens.refreshToken),
    accessExpiresAtUtc: accessExpiry,
    refreshExpiresAtUtc: refreshExpiry,
    cacheScopeId: _requiredScope(tokens.cacheScopeId),
    revision: _requiredRevision(revision),
  );
}

String _requiredToken(String value) {
  return validSessionToken(value) ??
      (throw const FormatException('Invalid authentication token.'));
}

String _requiredScope(String value) {
  return validCacheScopeId(value) ??
      (throw const FormatException('Invalid authentication cache scope.'));
}

String _requiredRevision(String value) {
  return validSessionRevision(value) ??
      (throw const FormatException('Invalid authentication revision.'));
}

DateTime _requiredUtcTimestamp(String value) {
  if (!value.endsWith('Z')) {
    throw const FormatException('Authentication timestamp must be UTC.');
  }
  final parsed = DateTime.parse(value);
  if (!parsed.isUtc) {
    throw const FormatException('Authentication timestamp must be UTC.');
  }
  return parsed;
}

String _newRevision() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _noSessionChangeHook() async {}
