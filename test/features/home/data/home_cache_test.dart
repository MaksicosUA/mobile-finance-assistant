import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/data/home_cache.dart';

/// The Home snapshot is encrypted at rest under a random key (ADR 0002).
void main() {
  late Directory directory;
  late _MemoryKeyStore keys;
  late EncryptedFileHomeCache cache;
  final aes = AesGcm.with256bits(nonceLength: 12);
  final aad = utf8.encode('mobile-finance-assistant.home-cache.v1');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('home_cache_');
    keys = _MemoryKeyStore();
    cache = EncryptedFileHomeCache(
      keyStore: keys,
      directoryProvider: () async => directory,
    );
  });

  tearDown(() => directory.delete(recursive: true));

  File file() => File('${directory.path}/home_snapshot.v1.cache');

  SecretBox sealed() {
    final envelope =
        jsonDecode(utf8.decode(file().readAsBytesSync()))
            as Map<String, Object?>;
    return SecretBox(
      base64Decode(envelope['ciphertext']! as String),
      nonce: base64Decode(envelope['nonce']! as String),
      mac: Mac(base64Decode(envelope['mac']! as String)),
    );
  }

  test('a snapshot reads back for its own scope only', () async {
    await cache.write(_entry());

    final entry = await cache.read(scopeId: 'scope-a');
    expect(entry?.etag, '"v1"');
    expect(entry?.payload['balance'], '12.50');
    expect(await cache.read(scopeId: 'scope-b'), isNull);
  });

  // The pure-Dart AES keeps a reference to the key bytes it is handed and
  // expands them at first use, so wiping them in a `finally` sealed every
  // snapshot under 32 zero bytes.
  test('the snapshot is sealed with the stored key, not with zeros', () async {
    await cache.write(_entry());

    expect(keys.bytes!.any((byte) => byte != 0), isTrue);
    await expectLater(
      aes.decrypt(
        sealed(),
        secretKey: SecretKeyData(List<int>.filled(32, 0)),
        aad: aad,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final clear = await aes.decrypt(
      sealed(),
      secretKey: SecretKeyData(List<int>.of(keys.bytes!)),
      aad: aad,
    );
    expect(utf8.decode(clear), contains('scope-a'));
  });

  test('a snapshot an older build sealed under zeros is a miss', () async {
    final inner = utf8.encode(
      jsonEncode({
        'schemaVersion': 3,
        'scopeId': 'scope-a',
        'etag': '"v1"',
        'storedAt': '2026-10-29T10:00:00.000Z',
        'expiresAt': '2026-10-29T10:05:00.000Z',
        'payload': {'balance': '12.50'},
      }),
    );
    final box = await aes.encrypt(
      inner,
      secretKey: SecretKeyData(List<int>.filled(32, 0)),
      nonce: aes.newNonce(),
      aad: aad,
    );
    file().writeAsStringSync(
      jsonEncode({
        'version': 1,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
    keys.bytes = List<int>.generate(32, (index) => index + 1);

    expect(await cache.read(scopeId: 'scope-a'), isNull);
    expect(file().existsSync(), isFalse);
    expect(keys.bytes, isNull);
  });
}

HomeCacheEntry _entry() => HomeCacheEntry(
  payload: const {'balance': '12.50'},
  etag: '"v1"',
  storedAtUtc: DateTime.utc(2026, 10, 29, 10),
  expiresAtUtc: DateTime.utc(2026, 10, 29, 10, 5),
  scopeId: 'scope-a',
);

final class _MemoryKeyStore implements HomeCacheKeyStore {
  List<int>? bytes;

  @override
  Future<List<int>?> read() async => bytes;

  @override
  Future<void> write(List<int> keyBytes) async => bytes = List.of(keyBytes);

  @override
  Future<void> delete() async => bytes = null;
}
