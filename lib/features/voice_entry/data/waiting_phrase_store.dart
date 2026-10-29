import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_config.dart';
import '../domain/waiting_phrase.dart';

/// Where phrases said without a connection wait (ADR 0032). The fixture build
/// has no server to read them, so it keeps nothing.
final waitingPhraseStoreProvider = Provider<WaitingPhraseStore>(
  (ref) => isNetworkBackendConfigured
      ? EncryptedFileWaitingPhraseStore()
      : const NoWaitingPhraseStore(),
);

/// Phrases the server has not read, per account.
///
/// Every read and write names the account it is for. A file written for
/// another account is deleted, never shown: someone else's words must not
/// wait for whoever signs in next.
abstract interface class WaitingPhraseStore {
  /// The phrases still within their lifetime at [now], oldest first.
  Future<List<WaitingPhrase>> read({
    required String scopeId,
    required DateTime now,
  });

  /// Keeps [phrase] and answers what is waiting now, or null when
  /// [maximumWaitingPhrases] already are and it was not kept.
  Future<List<WaitingPhrase>?> add({
    required String scopeId,
    required WaitingPhrase phrase,
    required DateTime now,
  });

  Future<List<WaitingPhrase>> remove({
    required String scopeId,
    required String id,
    required DateTime now,
  });

  /// Deletes every phrase and the key that protected them.
  Future<void> clear();
}

final class NoWaitingPhraseStore implements WaitingPhraseStore {
  const NoWaitingPhraseStore();

  @override
  Future<List<WaitingPhrase>> read({
    required String scopeId,
    required DateTime now,
  }) async => const [];

  @override
  Future<List<WaitingPhrase>?> add({
    required String scopeId,
    required WaitingPhrase phrase,
    required DateTime now,
  }) async => null;

  @override
  Future<List<WaitingPhrase>> remove({
    required String scopeId,
    required String id,
    required DateTime now,
  }) async => const [];

  @override
  Future<void> clear() async {}
}

/// Stores only the random key; the phrases themselves never touch secure
/// storage values or preferences.
abstract interface class WaitingPhraseKeyStore {
  Future<List<int>?> read();

  Future<void> write(List<int> keyBytes);

  Future<void> delete();
}

final class FlutterSecureStorageWaitingPhraseKeyStore
    implements WaitingPhraseKeyStore {
  const FlutterSecureStorageWaitingPhraseKeyStore({
    this.storage = const FlutterSecureStorage(),
    this.storageKey = 'waiting_phrases.aes_key.v1',
  });

  final FlutterSecureStorage storage;
  final String storageKey;

  @override
  Future<List<int>?> read() async {
    final encoded = await storage.read(key: storageKey);
    if (encoded == null) return null;
    if (encoded.length > 128) {
      throw const FormatException('Invalid waiting phrase key encoding.');
    }
    return Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<void> write(List<int> keyBytes) =>
      storage.write(key: storageKey, value: base64Encode(keyBytes));

  @override
  Future<void> delete() => storage.delete(key: storageKey);
}

/// One AES-256-GCM file in the app's support directory, its key in platform
/// secure storage — the Home snapshot's construction (ADR 0002).
///
/// The support directory rather than the cache one: the system may empty a
/// cache to free space, and these are words nobody else holds a copy of. A
/// file that cannot be decrypted is deleted all the same, because there is
/// nothing to recover it from.
final class EncryptedFileWaitingPhraseStore implements WaitingPhraseStore {
  EncryptedFileWaitingPhraseStore({
    WaitingPhraseKeyStore? keyStore,
    Future<Directory> Function()? directoryProvider,
  }) : _keyStore =
           keyStore ?? const FlutterSecureStorageWaitingPhraseKeyStore(),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _algorithm = AesGcm.with256bits(nonceLength: _nonceLength);

  static const int _envelopeVersion = 1;
  static const int _schemaVersion = 1;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const int _macLength = 16;
  static const int _maxFileBytes = 256 * 1024;
  static const String _fileName = 'waiting_phrases.v1.bin';
  static const String _temporaryFileName = 'waiting_phrases.v1.bin.tmp';
  static final List<int> _aad = Uint8List.fromList(
    utf8.encode('mobile-finance-assistant.waiting-phrases.v1'),
  );

  final WaitingPhraseKeyStore _keyStore;
  final Future<Directory> Function() _directoryProvider;
  final AesGcm _algorithm;

  Future<void> _queue = Future<void>.value();

  @override
  Future<List<WaitingPhrase>> read({
    required String scopeId,
    required DateTime now,
  }) => _serialized(() => _load(scopeId, now));

  @override
  Future<List<WaitingPhrase>?> add({
    required String scopeId,
    required WaitingPhrase phrase,
    required DateTime now,
  }) => _serialized(() async {
    final phrases = await _load(scopeId, now);
    if (phrases.any((waiting) => waiting.id == phrase.id)) return phrases;
    if (phrases.length >= maximumWaitingPhrases) return null;
    final next = List<WaitingPhrase>.unmodifiable([...phrases, phrase]);
    await _save(scopeId, next);
    return next;
  });

  @override
  Future<List<WaitingPhrase>> remove({
    required String scopeId,
    required String id,
    required DateTime now,
  }) => _serialized(() async {
    final phrases = await _load(scopeId, now);
    final next = List<WaitingPhrase>.unmodifiable(
      phrases.where((waiting) => waiting.id != id),
    );
    if (next.length != phrases.length) await _save(scopeId, next);
    return next;
  });

  @override
  Future<void> clear() => _serialized(_clear);

  Future<List<WaitingPhrase>> _load(String scopeId, DateTime now) async {
    final file = await _file(_fileName);
    if (!await file.exists()) return const [];
    late final _Contents contents;
    try {
      contents = await _decrypt(await file.readAsBytes());
    } on Object {
      await _clear();
      return const [];
    }
    if (contents.scopeId != scopeId) {
      await _clear();
      return const [];
    }
    final live = List<WaitingPhrase>.unmodifiable(
      contents.phrases.where((phrase) => !phrase.isExpiredAt(now)),
    );
    // Thirty days is a limit, not a hint: what has outlived it goes now.
    if (live.length != contents.phrases.length) await _save(scopeId, live);
    return live;
  }

  Future<void> _save(String scopeId, List<WaitingPhrase> phrases) async {
    if (phrases.isEmpty) {
      await _clear();
      return;
    }
    final clearText = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': _schemaVersion,
          'scopeId': scopeId,
          'phrases': [for (final phrase in phrases) phrase.toJson()],
        }),
      ),
    );
    final key = await _readOrCreateKey();
    late final SecretBox box;
    try {
      box = await _algorithm.encrypt(
        clearText,
        secretKey: key,
        nonce: _algorithm.newNonce(),
        aad: _aad,
      );
    } finally {
      key.destroy();
      clearText.fillRange(0, clearText.length, 0);
    }
    final envelope = utf8.encode(
      jsonEncode({
        'version': _envelopeVersion,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
    if (envelope.length > _maxFileBytes) {
      throw StateError('Waiting phrases exceed their size limit.');
    }
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final temporary = await _file(_temporaryFileName);
    try {
      await temporary.writeAsBytes(envelope, flush: true);
      await temporary.rename((await _file(_fileName)).path);
    } on Object {
      await _deleteQuietly(temporary);
      rethrow;
    }
  }

  Future<_Contents> _decrypt(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > _maxFileBytes) {
      throw const FormatException('Invalid waiting phrase file size.');
    }
    final envelope = _object(jsonDecode(utf8.decode(bytes)));
    _requireKeys(envelope, const {'version', 'nonce', 'ciphertext', 'mac'});
    if (envelope['version'] != _envelopeVersion) {
      throw const FormatException('Unsupported waiting phrase envelope.');
    }
    final nonce = base64Decode(envelope['nonce']! as String);
    final cipherText = base64Decode(envelope['ciphertext']! as String);
    final mac = base64Decode(envelope['mac']! as String);
    if (nonce.length != _nonceLength || mac.length != _macLength) {
      throw const FormatException('Invalid waiting phrase envelope.');
    }
    final key = await _readKey();
    if (key == null) {
      throw const FormatException('Missing waiting phrase key.');
    }
    late final Uint8List clearText;
    try {
      clearText = Uint8List.fromList(
        await _algorithm.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
          aad: _aad,
        ),
      );
    } finally {
      key.destroy();
    }
    try {
      final contents = _object(jsonDecode(utf8.decode(clearText)));
      _requireKeys(contents, const {'schemaVersion', 'scopeId', 'phrases'});
      final scopeId = contents['scopeId'];
      final phrases = contents['phrases'];
      if (contents['schemaVersion'] != _schemaVersion ||
          scopeId is! String ||
          phrases is! List) {
        throw const FormatException('Invalid waiting phrases.');
      }
      return _Contents(
        scopeId: scopeId,
        phrases: [
          for (final phrase in phrases) WaitingPhrase.fromJson(_object(phrase)),
        ],
      );
    } finally {
      clearText.fillRange(0, clearText.length, 0);
    }
  }

  Future<SecretKey?> _readKey() async {
    final stored = await _keyStore.read();
    if (stored == null) return null;
    if (stored.length != _keyLength) {
      throw const FormatException('Invalid waiting phrase key length.');
    }
    return _ownedKey(stored);
  }

  Future<SecretKey> _readOrCreateKey() async {
    final existing = await _readKey();
    if (existing != null) return existing;
    final generated = await _algorithm.newSecretKey();
    final bytes = Uint8List.fromList(await generated.extractBytes());
    generated.destroy();
    try {
      await _keyStore.write(bytes);
      return _ownedKey(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// A key over its own copy of [bytes], wiped when it is destroyed.
  ///
  /// Not `newSecretKeyFromBytes`: the pure-Dart AES keeps a reference to the
  /// list it is given and expands it only at the first use, so wiping the
  /// caller's bytes afterwards would encrypt everything under a key of zeros.
  static SecretKey _ownedKey(List<int> bytes) =>
      SecretKeyData(Uint8List.fromList(bytes), overwriteWhenDestroyed: true);

  Future<void> _clear() async {
    await _deleteQuietly(await _file(_fileName));
    await _deleteQuietly(await _file(_temporaryFileName));
    await _keyStore.delete();
  }

  Future<File> _file(String name) async {
    final directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _Contents {
  const _Contents({required this.scopeId, required this.phrases});

  final String scopeId;
  final List<WaitingPhrase> phrases;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('Expected a JSON object.');
  final object = <String, Object?>{};
  for (final MapEntry(:key, value: field) in value.entries) {
    if (key is! String) throw const FormatException('Expected string keys.');
    object[key] = field;
  }
  return object;
}

void _requireKeys(Map<String, Object?> object, Set<String> expected) {
  if (object.length != expected.length ||
      !object.keys.toSet().containsAll(expected)) {
    throw const FormatException('Unexpected waiting phrase fields.');
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on Object {
    // Deleting is best effort; a leftover file is unreadable without its key.
  }
}
