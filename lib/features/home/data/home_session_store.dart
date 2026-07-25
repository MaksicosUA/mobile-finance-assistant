import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef HomeSessionChangeHook = Future<void> Function();

final class HomeSessionSnapshot {
  HomeSessionSnapshot({
    required String accessToken,
    required String cacheScopeId,
    required String revision,
  }) : accessToken =
           _validToken(accessToken) ??
           (throw const FormatException('Invalid access token.')),
       cacheScopeId =
           _validScope(cacheScopeId) ??
           (throw const FormatException('Invalid cache scope.')),
       revision =
           _validRevision(revision) ??
           (throw const FormatException('Invalid session revision.'));

  final String accessToken;
  final String cacheScopeId;
  final String revision;

  String get scopedCacheScopeId => '$cacheScopeId.$revision';

  bool isSameSession(HomeSessionSnapshot? other) {
    return other != null &&
        other.accessToken == accessToken &&
        other.cacheScopeId == cacheScopeId &&
        other.revision == revision;
  }
}

/// Minimal session view needed by the read-only Home data layer.
///
/// The authentication feature owns creation and refresh. Home can only read or
/// clear the session and cannot derive identity from a bearer token.
abstract interface class HomeSessionStore {
  Future<HomeSessionSnapshot?> readSession();

  Future<void> saveSession({
    required String accessToken,
    required String cacheScopeId,
  });

  Future<void> refreshAccessToken({
    required String accessToken,
    required HomeSessionSnapshot expectedSession,
  });

  Future<void> clearSession();
}

abstract interface class HomeSessionSecureValueStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

final class FlutterSecureHomeSessionValueStore
    implements HomeSessionSecureValueStore {
  const FlutterSecureHomeSessionValueStore({
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

/// Stores the bearer token and opaque account scope as one secure value.
///
/// The random revision changes whenever authentication writes a new session,
/// preventing a cache entry from being silently reused after account changes.
final class SecureHomeSessionStore implements HomeSessionStore {
  SecureHomeSessionStore({
    HomeSessionSecureValueStore? valueStore,
    String Function()? revisionFactory,
    HomeSessionChangeHook? beforeSessionChange,
    HomeSessionChangeHook? afterTokenRefresh,
  }) : _valueStore = valueStore ?? const FlutterSecureHomeSessionValueStore(),
       _revisionFactory = revisionFactory ?? _newRevision,
       _beforeSessionChange = beforeSessionChange ?? _noSessionChangeHook,
       _afterTokenRefresh = afterTokenRefresh ?? _noSessionChangeHook;

  static const int _schemaVersion = 1;

  final HomeSessionSecureValueStore _valueStore;
  final String Function() _revisionFactory;
  final HomeSessionChangeHook _beforeSessionChange;
  final HomeSessionChangeHook _afterTokenRefresh;

  Future<void> _operationQueue = Future<void>.value();

  @override
  Future<HomeSessionSnapshot?> readSession() => _serialized(_readUnlocked);

  @override
  Future<void> saveSession({
    required String accessToken,
    required String cacheScopeId,
  }) {
    final token = _validToken(accessToken);
    final scope = _validScope(cacheScopeId);
    final revision = _validRevision(_revisionFactory());
    if (token == null || scope == null || revision == null) {
      throw const FormatException('Invalid Home session metadata.');
    }

    return _serialized(() async {
      await _beforeSessionChange();
      await _writeSession(
        accessToken: token,
        cacheScopeId: scope,
        revision: revision,
      );
    });
  }

  @override
  Future<void> refreshAccessToken({
    required String accessToken,
    required HomeSessionSnapshot expectedSession,
  }) {
    final token = _validToken(accessToken);
    if (token == null) {
      throw const FormatException('A valid access token is required.');
    }

    return _serialized(() async {
      final current = await _readUnlocked();
      if (current == null || !expectedSession.isSameSession(current)) {
        throw StateError('The Home session changed before token refresh.');
      }

      await _writeSession(
        accessToken: token,
        cacheScopeId: current.cacheScopeId,
        revision: current.revision,
      );
      // Notify request owners only after the secure value is durably replaced.
      // A failed write therefore leaves both the old session and its epoch
      // usable instead of stranding the UI in a new, credential-less epoch.
      await _afterTokenRefresh();
    });
  }

  @override
  Future<void> clearSession() {
    return _serialized(() async {
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
    });
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

  Future<void> _writeSession({
    required String accessToken,
    required String cacheScopeId,
    required String revision,
  }) {
    return _valueStore.write(
      jsonEncode(<String, Object>{
        'schemaVersion': _schemaVersion,
        'accessToken': accessToken,
        'cacheScopeId': cacheScopeId,
        'revision': revision,
      }),
    );
  }

  Future<HomeSessionSnapshot?> _readUnlocked() async {
    try {
      final encoded = await _valueStore.read();
      if (encoded == null) return null;
      if (encoded.length > 12 * 1024) {
        throw const FormatException('Home session value is too large.');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?> ||
          decoded.length != 4 ||
          decoded['schemaVersion'] != _schemaVersion) {
        throw const FormatException('Unsupported Home session value.');
      }
      final token = decoded['accessToken'];
      final scope = decoded['cacheScopeId'];
      final revision = decoded['revision'];
      if (token is! String || scope is! String || revision is! String) {
        throw const FormatException('Invalid Home session value.');
      }

      final validToken = _validToken(token);
      final validScope = _validScope(scope);
      final validRevision = _validRevision(revision);
      if (validToken == null || validScope == null || validRevision == null) {
        throw const FormatException('Invalid Home session value.');
      }
      return HomeSessionSnapshot(
        accessToken: validToken,
        cacheScopeId: validScope,
        revision: validRevision,
      );
    } catch (_) {
      try {
        await _beforeSessionChange();
      } catch (_) {
        // Continue deleting the unusable credential even if cache cleanup
        // fails. The caller still observes a signed-out session.
      }
      try {
        await _valueStore.delete();
      } catch (_) {
        // Invalid secure state remains a signed-out cache miss. No value is
        // logged or downgraded to SharedPreferences/plaintext storage.
      }
      return null;
    }
  }
}

String? _validToken(String value) {
  final result = value.trim();
  if (result.isEmpty ||
      result.length > 8192 ||
      result.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    return null;
  }
  return result;
}

String? _validScope(String value) {
  final result = value.trim();
  return RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result) ? result : null;
}

String? _validRevision(String value) {
  final result = value.trim();
  return RegExp(r'^[a-f0-9]{32}$').hasMatch(result) ? result : null;
}

String _newRevision() {
  final random = Random.secure();
  return List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _noSessionChangeHook() async {}
