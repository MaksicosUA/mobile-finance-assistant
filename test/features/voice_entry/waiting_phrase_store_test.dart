import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/voice_entry/data/waiting_phrase_store.dart';
import 'package:mobile_finance_assistant/features/voice_entry/domain/waiting_phrase.dart';

/// Where a phrase said without a connection waits (ADR 0032).
void main() {
  late Directory directory;
  late _MemoryKeyStore keys;
  late EncryptedFileWaitingPhraseStore store;
  final now = DateTime.utc(2026, 10, 29, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('waiting_phrases_');
    keys = _MemoryKeyStore();
    store = EncryptedFileWaitingPhraseStore(
      keyStore: keys,
      directoryProvider: () async => directory,
    );
  });

  tearDown(() => directory.delete(recursive: true));

  File file() => File('${directory.path}/waiting_phrases.v1.bin');

  test('keeps phrases in order, and never in the clear', () async {
    await store.add(scopeId: 'scope-a', phrase: _phrase(1), now: now);
    await store.add(scopeId: 'scope-a', phrase: _phrase(2), now: now);

    final waiting = await store.read(scopeId: 'scope-a', now: now);
    expect(waiting.map((phrase) => phrase.id), [_id(1), _id(2)]);
    expect(waiting.first.text, 'Купил кофе за 3,50 номер 1');
    expect(waiting.first.saidAt, DateTime.utc(2026, 10, 27, 9));
    expect(waiting.first.saidInTimezone, 'Europe/Kyiv');

    final onDisk = utf8.decode(await file().readAsBytes());
    expect(onDisk, isNot(contains('кофе')));
    expect(onDisk, isNot(contains('scope-a')));
    expect(onDisk, isNot(contains('Europe/Kyiv')));
  });

  // The pure-Dart AES keeps a reference to the key bytes it is handed, so
  // wiping them after use silently sealed everything under zeros.
  test('the file is sealed with the stored key, not with zeros', () async {
    await store.add(scopeId: 'scope-a', phrase: _phrase(1), now: now);
    final envelope =
        jsonDecode(utf8.decode(await file().readAsBytes()))
            as Map<String, Object?>;
    final box = SecretBox(
      base64Decode(envelope['ciphertext']! as String),
      nonce: base64Decode(envelope['nonce']! as String),
      mac: Mac(base64Decode(envelope['mac']! as String)),
    );
    final aes = AesGcm.with256bits(nonceLength: 12);
    final aad = utf8.encode('mobile-finance-assistant.waiting-phrases.v1');

    expect(keys.bytes!.any((byte) => byte != 0), isTrue);
    await expectLater(
      aes.decrypt(
        box,
        secretKey: SecretKeyData(List<int>.filled(32, 0)),
        aad: aad,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final clear = await aes.decrypt(
      box,
      secretKey: SecretKeyData(List<int>.of(keys.bytes!)),
      aad: aad,
    );
    expect(utf8.decode(clear), contains('scope-a'));
  });

  test('another account sees nothing, and the phrases are gone', () async {
    await store.add(scopeId: 'scope-a', phrase: _phrase(1), now: now);

    expect(await store.read(scopeId: 'scope-b', now: now), isEmpty);
    expect(file().existsSync(), isFalse);
    expect(keys.bytes, isNull);
    // Not hidden from the second account only: deleted for everyone.
    expect(await store.read(scopeId: 'scope-a', now: now), isEmpty);
  });

  test('thirty days is a limit: an older phrase is deleted unread', () async {
    final old = WaitingPhrase(
      id: _id(1),
      text: 'Заплатил 80 за свет',
      saidAt: now.subtract(const Duration(days: 30)),
      saidInTimezone: 'Europe/Kyiv',
    );
    final recent = WaitingPhrase(
      id: _id(2),
      text: 'Заплатил 90 за воду',
      saidAt: now.subtract(const Duration(days: 29, hours: 23)),
      saidInTimezone: 'Europe/Kyiv',
    );
    await store.add(scopeId: 'scope-a', phrase: old, now: old.saidAt);
    await store.add(scopeId: 'scope-a', phrase: recent, now: old.saidAt);

    final waiting = await store.read(scopeId: 'scope-a', now: now);
    expect(waiting.map((phrase) => phrase.id), [_id(2)]);
    // Rewritten, not just filtered on the way out.
    final later = await store.read(
      scopeId: 'scope-a',
      now: old.saidAt.add(const Duration(days: 1)),
    );
    expect(later.map((phrase) => phrase.id), [_id(2)]);
  });

  test('fifty wait at most; the fifty-first is not kept', () async {
    for (var index = 1; index <= maximumWaitingPhrases; index += 1) {
      expect(
        await store.add(scopeId: 'scope-a', phrase: _phrase(index), now: now),
        isNotNull,
      );
    }

    expect(
      await store.add(scopeId: 'scope-a', phrase: _phrase(51), now: now),
      isNull,
    );
    expect(
      await store.read(scopeId: 'scope-a', now: now),
      hasLength(maximumWaitingPhrases),
    );
  });

  test('removing the last phrase leaves no file and no key', () async {
    await store.add(scopeId: 'scope-a', phrase: _phrase(1), now: now);

    expect(await store.remove(scopeId: 'scope-a', id: _id(1), now: now), []);
    expect(file().existsSync(), isFalse);
    expect(keys.bytes, isNull);
  });

  test('a file that cannot be decrypted is deleted, not shown', () async {
    await store.add(scopeId: 'scope-a', phrase: _phrase(1), now: now);
    keys.bytes = List<int>.filled(32, 7);

    expect(await store.read(scopeId: 'scope-a', now: now), isEmpty);
    expect(file().existsSync(), isFalse);
  });

  test('nothing the server could not read is accepted', () {
    expect(
      () => WaitingPhrase(
        id: _id(1),
        text: '   ',
        saidAt: now,
        saidInTimezone: 'Europe/Kyiv',
      ),
      throwsFormatException,
    );
    expect(
      () => WaitingPhrase(
        id: _id(1),
        text: 'а' * 281,
        saidAt: now,
        saidInTimezone: 'Europe/Kyiv',
      ),
      throwsFormatException,
    );
  });
}

String _id(int index) =>
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

WaitingPhrase _phrase(int index) => WaitingPhrase(
  id: _id(index),
  text: 'Купил кофе за 3,50 номер $index',
  saidAt: DateTime.utc(2026, 10, 27, 9),
  saidInTimezone: 'Europe/Kyiv',
);

final class _MemoryKeyStore implements WaitingPhraseKeyStore {
  List<int>? bytes;

  @override
  Future<List<int>?> read() async => bytes;

  @override
  Future<void> write(List<int> keyBytes) async => bytes = List.of(keyBytes);

  @override
  Future<void> delete() async => bytes = null;
}
