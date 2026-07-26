import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

typedef HomeCacheDirectoryProvider = Future<Directory> Function();

final homeCacheProvider = Provider<HomeCache>(
  (ref) => EncryptedFileHomeCache(),
);

/// A validated Home response together with its cache metadata.
///
/// [payload], [etag], timestamps, and [scopeId] are all stored inside the
/// authenticated encrypted payload. None of them are exposed in the file
/// envelope.
final class HomeCacheEntry {
  HomeCacheEntry({
    required Map<String, Object?> payload,
    required this.etag,
    required DateTime storedAtUtc,
    required DateTime expiresAtUtc,
    required this.scopeId,
  }) : payload = _freezeJsonMap(payload),
       storedAtUtc = storedAtUtc.toUtc(),
       expiresAtUtc = expiresAtUtc.toUtc() {
    if (scopeId.trim().isEmpty ||
        scopeId.length > _maxScopeIdLength ||
        _containsControl(scopeId)) {
      throw ArgumentError.value(scopeId, 'scopeId', 'Invalid cache scope');
    }
    if (etag != null &&
        (etag!.isEmpty ||
            etag!.length > _maxEtagLength ||
            _containsControl(etag!))) {
      throw ArgumentError.value(etag, 'etag', 'Invalid ETag');
    }
    if (this.expiresAtUtc.isBefore(this.storedAtUtc)) {
      throw ArgumentError.value(
        expiresAtUtc,
        'expiresAtUtc',
        'Expiration cannot precede storage time',
      );
    }
  }

  final Map<String, Object?> payload;
  final String? etag;
  final DateTime storedAtUtc;
  final DateTime expiresAtUtc;

  /// An opaque account/session boundary used to prevent cross-account reads.
  final String scopeId;

  bool isFreshAt(DateTime now) => now.toUtc().isBefore(expiresAtUtc);

  bool isStaleAt(DateTime now) => !isFreshAt(now);
}

/// Storage boundary used by the repository and by in-memory test fakes.
abstract interface class HomeCache {
  Future<HomeCacheEntry?> read({required String scopeId});

  Future<void> write(HomeCacheEntry entry);

  /// Removes both the encrypted snapshot and its encryption key.
  Future<void> clear();
}

/// Stores only the random cache encryption key, never the Home payload.
abstract interface class HomeCacheKeyStore {
  Future<List<int>?> read();

  Future<void> write(List<int> keyBytes);

  Future<void> delete();
}

/// Platform secure-storage implementation for the Home cache encryption key.
final class FlutterSecureStorageHomeCacheKeyStore implements HomeCacheKeyStore {
  const FlutterSecureStorageHomeCacheKeyStore({
    this.storage = const FlutterSecureStorage(),
    this.storageKey = _defaultSecureStorageKey,
  });

  static const String _defaultSecureStorageKey = 'home_cache.aes_key.v1';

  final FlutterSecureStorage storage;
  final String storageKey;

  @override
  Future<List<int>?> read() async {
    final encoded = await storage.read(key: storageKey);
    if (encoded == null) {
      return null;
    }
    return Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<void> write(List<int> keyBytes) =>
      storage.write(key: storageKey, value: base64Encode(keyBytes));

  @override
  Future<void> delete() => storage.delete(key: storageKey);
}

/// A single-snapshot, authenticated encrypted cache for the Home aggregate.
///
/// The file is intentionally stored in the application cache directory. A
/// missing cache is always recoverable from the API, while the key remains in
/// platform secure storage and is deleted on [clear].
final class EncryptedFileHomeCache implements HomeCache {
  EncryptedFileHomeCache({
    HomeCacheKeyStore? keyStore,
    HomeCacheDirectoryProvider? directoryProvider,
    int maxFileBytes = _defaultMaxFileBytes,
  }) : _keyStore = keyStore ?? const FlutterSecureStorageHomeCacheKeyStore(),
       _directoryProvider = directoryProvider ?? getApplicationCacheDirectory,
       _maxFileBytes = maxFileBytes,
       _algorithm = AesGcm.with256bits(nonceLength: _nonceLength) {
    if (maxFileBytes <= 0) {
      throw ArgumentError.value(
        maxFileBytes,
        'maxFileBytes',
        'Must be positive',
      );
    }
  }

  static const int _envelopeVersion = 1;
  static const int _cacheSchemaVersion = 1;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const int _macLength = 16;
  static const int _defaultMaxFileBytes = 1024 * 1024;
  static const String _fileName = 'home_snapshot.v1.cache';
  static const String _temporaryFileName = 'home_snapshot.v1.cache.tmp';
  static final List<int> _aad = Uint8List.fromList(
    utf8.encode('mobile-finance-assistant.home-cache.v1'),
  );

  final HomeCacheKeyStore _keyStore;
  final HomeCacheDirectoryProvider _directoryProvider;
  final int _maxFileBytes;
  final AesGcm _algorithm;

  Future<void> _operationQueue = Future<void>.value();

  @override
  Future<HomeCacheEntry?> read({required String scopeId}) =>
      _serialized(() => _readUnlocked(scopeId));

  @override
  Future<void> write(HomeCacheEntry entry) =>
      _serialized(() => _writeUnlocked(entry));

  @override
  Future<void> clear() => _serialized(_clearUnlocked);

  Future<HomeCacheEntry?> _readUnlocked(String scopeId) async {
    if (scopeId.trim().isEmpty ||
        scopeId.length > _maxScopeIdLength ||
        _containsControl(scopeId)) {
      await _clearBestEffort();
      return null;
    }

    try {
      final files = await _resolveFiles();
      if (!await files.target.exists()) {
        return null;
      }

      final fileLength = await files.target.length();
      if (fileLength <= 0 || fileLength > _maxFileBytes) {
        throw const FormatException('Invalid cache envelope size');
      }

      final envelopeBytes = await files.target.readAsBytes();
      if (envelopeBytes.length > _maxFileBytes) {
        throw const FormatException('Cache envelope is too large');
      }
      final envelope = _decodeEnvelope(envelopeBytes);

      final key = await _readKey();
      if (key == null) {
        throw const FormatException('Missing cache key');
      }

      late final Uint8List clearText;
      try {
        clearText = Uint8List.fromList(
          await _algorithm.decrypt(
            SecretBox(
              envelope.cipherText,
              nonce: envelope.nonce,
              mac: Mac(envelope.mac),
            ),
            secretKey: key,
            aad: _aad,
          ),
        );
      } finally {
        key.destroy();
      }

      try {
        final entry = _decodeEntry(clearText);
        if (entry.scopeId != scopeId) {
          throw const FormatException('Cache scope mismatch');
        }
        return entry;
      } finally {
        clearText.fillRange(0, clearText.length, 0);
      }
    } on Object {
      await _clearBestEffort();
      return null;
    }
  }

  Future<void> _writeUnlocked(HomeCacheEntry entry) async {
    final innerBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'schemaVersion': _cacheSchemaVersion,
          'scopeId': entry.scopeId,
          'etag': entry.etag,
          'storedAt': entry.storedAtUtc.toIso8601String(),
          'expiresAt': entry.expiresAtUtc.toIso8601String(),
          'payload': entry.payload,
        }),
      ),
    );

    final key = await _readOrCreateKey();
    late final SecretBox secretBox;
    try {
      final nonce = _algorithm.newNonce();
      if (nonce.length != _nonceLength) {
        throw StateError('Unexpected AES-GCM nonce length');
      }
      secretBox = await _algorithm.encrypt(
        innerBytes,
        secretKey: key,
        nonce: nonce,
        aad: _aad,
      );
    } finally {
      key.destroy();
      innerBytes.fillRange(0, innerBytes.length, 0);
    }

    final envelopeBytes = utf8.encode(
      jsonEncode(<String, Object>{
        'version': _envelopeVersion,
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      }),
    );
    if (envelopeBytes.length > _maxFileBytes) {
      throw StateError('Encrypted Home cache exceeds its size limit');
    }

    final files = await _resolveFiles();
    await files.directory.create(recursive: true);
    try {
      await files.temporary.writeAsBytes(envelopeBytes, flush: true);
      await files.temporary.rename(files.target.path);
    } on Object {
      await _deleteBestEffort(files.temporary);
      rethrow;
    }
  }

  Future<SecretKey?> _readKey() async {
    final storedBytes = await _keyStore.read();
    if (storedBytes == null) {
      return null;
    }

    final keyBytes = Uint8List.fromList(storedBytes);
    try {
      if (keyBytes.length != _keyLength) {
        throw const FormatException('Invalid cache key length');
      }
      return await _algorithm.newSecretKeyFromBytes(keyBytes);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  Future<SecretKey> _readOrCreateKey() async {
    try {
      final existing = await _readKey();
      if (existing != null) {
        return existing;
      }
    } on Object {
      await _clearUnlocked();
    }

    final generated = await _algorithm.newSecretKey();
    final keyBytes = Uint8List.fromList(await generated.extractBytes());
    generated.destroy();
    try {
      if (keyBytes.length != _keyLength) {
        throw StateError('Unexpected AES-GCM key length');
      }
      await _keyStore.write(keyBytes);
      return await _algorithm.newSecretKeyFromBytes(keyBytes);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  _CacheEnvelope _decodeEnvelope(List<int> bytes) {
    final decoded = _decodeJsonObject(bytes);
    _requireExactKeys(decoded, const <String>{
      'version',
      'nonce',
      'ciphertext',
      'mac',
    });
    if (decoded['version'] != _envelopeVersion) {
      throw const FormatException('Unsupported cache envelope version');
    }

    final nonce = _decodeBase64Field(decoded, 'nonce');
    final cipherText = _decodeBase64Field(decoded, 'ciphertext');
    final mac = _decodeBase64Field(decoded, 'mac');
    if (nonce.length != _nonceLength ||
        cipherText.isEmpty ||
        mac.length != _macLength) {
      throw const FormatException('Invalid cache envelope fields');
    }
    return _CacheEnvelope(nonce: nonce, cipherText: cipherText, mac: mac);
  }

  HomeCacheEntry _decodeEntry(List<int> bytes) {
    final decoded = _decodeJsonObject(bytes);
    _requireExactKeys(decoded, const <String>{
      'schemaVersion',
      'scopeId',
      'etag',
      'storedAt',
      'expiresAt',
      'payload',
    });
    if (decoded['schemaVersion'] != _cacheSchemaVersion) {
      throw const FormatException('Unsupported Home cache schema');
    }

    final scopeId = decoded['scopeId'];
    final etag = decoded['etag'];
    final storedAtRaw = decoded['storedAt'];
    final expiresAtRaw = decoded['expiresAt'];
    if (scopeId is! String ||
        (etag != null && etag is! String) ||
        storedAtRaw is! String ||
        expiresAtRaw is! String) {
      throw const FormatException('Invalid Home cache metadata');
    }

    final storedAt = DateTime.parse(storedAtRaw);
    final expiresAt = DateTime.parse(expiresAtRaw);
    if (!storedAt.isUtc || !expiresAt.isUtc) {
      throw const FormatException('Home cache timestamps must be UTC');
    }

    return HomeCacheEntry(
      payload: _asJsonObject(decoded['payload']),
      etag: etag as String?,
      storedAtUtc: storedAt,
      expiresAtUtc: expiresAt,
      scopeId: scopeId,
    );
  }

  Map<String, Object?> _decodeJsonObject(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: false);
    return _asJsonObject(jsonDecode(text));
  }

  Future<void> _clearUnlocked() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      final files = await _resolveFiles();
      await _deleteIfPresent(files.target);
      await _deleteIfPresent(files.temporary);
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    try {
      await _keyStore.delete();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<void> _clearBestEffort() async {
    try {
      final files = await _resolveFiles();
      await _deleteBestEffort(files.target);
      await _deleteBestEffort(files.temporary);
    } on Object {
      // Fail closed without surfacing storage details from a cache read.
    }
    try {
      await _keyStore.delete();
    } on Object {
      // A cache read must degrade to a miss even if cleanup is unavailable.
    }
  }

  Future<_CacheFiles> _resolveFiles() async {
    final directory = await _directoryProvider();
    final separator = Platform.pathSeparator;
    return _CacheFiles(
      directory: directory,
      target: File('${directory.path}$separator$_fileName'),
      temporary: File('${directory.path}$separator$_temporaryFileName'),
    );
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
}

final class _CacheEnvelope {
  const _CacheEnvelope({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;
}

final class _CacheFiles {
  const _CacheFiles({
    required this.directory,
    required this.target,
    required this.temporary,
  });

  final Directory directory;
  final File target;
  final File temporary;
}

const int _maxScopeIdLength = 256;
const int _maxEtagLength = 1024;

bool _containsControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

Map<String, Object?> _freezeJsonMap(Map<String, Object?> source) =>
    _freezeJsonValue(source) as Map<String, Object?>;

Object? _freezeJsonValue(Object? value) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'payload', 'Non-finite JSON number');
    }
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'payload', 'JSON key must be a string');
      }
      result[key] = _freezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  throw ArgumentError.value(value, 'payload', 'Value is not JSON-compatible');
}

Map<String, Object?> _asJsonObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected a JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const FormatException('JSON object key must be a string');
    }
    result[key] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> object, Set<String> expected) {
  if (object.length != expected.length ||
      !object.keys.toSet().containsAll(expected)) {
    throw const FormatException('Unexpected cache fields');
  }
}

Uint8List _decodeBase64Field(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String) {
    throw const FormatException('Invalid base64 cache field');
  }
  return base64Decode(value);
}

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> _deleteBestEffort(File file) async {
  try {
    await _deleteIfPresent(file);
  } on Object {
    // Best-effort cleanup must not mask the original failure.
  }
}
