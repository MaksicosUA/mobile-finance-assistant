import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/finance_entry_models.dart';
import '../domain/operation_outbox.dart';

final class OperationOutboxEnvelopeMetadata {
  const OperationOutboxEnvelopeMetadata({
    required this.localId,
    required this.principalTag,
    required this.financeAccountTag,
    required this.commandTag,
    required this.state,
    required this.transitionSequence,
    required this.createdAtEpochMs,
    required this.stateChangedAtEpochMs,
    required this.attemptCount,
    this.homeConvergencePending = false,
    this.lastAttemptAtEpochMs,
    this.nextAttemptAtEpochMs,
    this.syncStartedAtEpochMs,
    this.syncedAtEpochMs,
    this.lastErrorCode,
  });

  final String localId;
  final String principalTag;
  final String financeAccountTag;
  final String commandTag;
  final OperationOutboxState state;
  final int transitionSequence;
  final int createdAtEpochMs;
  final int stateChangedAtEpochMs;
  final int? lastAttemptAtEpochMs;
  final int? nextAttemptAtEpochMs;
  final int? syncStartedAtEpochMs;
  final int? syncedAtEpochMs;
  final int attemptCount;
  final bool homeConvergencePending;
  final OperationOutboxErrorCode? lastErrorCode;
}

final class OperationOutboxEncryptedEnvelope {
  const OperationOutboxEncryptedEnvelope({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;
}

final class OperationOutboxPayload {
  const OperationOutboxPayload({
    required this.principalScopeId,
    required this.financeAccountId,
    required this.commandId,
    required this.confirmedCommandSha256,
    required this.confirmedCommand,
    required this.serverOperationId,
  });

  final String principalScopeId;
  final String financeAccountId;
  final String commandId;
  final String confirmedCommandSha256;
  final FinanceOperationCommitCommand? confirmedCommand;
  final String? serverOperationId;

  bool get isTombstone => confirmedCommand == null;
}

/// AES-256-GCM codec with HKDF-separated encryption and opaque-index keys.
final class OperationOutboxCodec {
  OperationOutboxCodec._({
    required this._encryptionKey,
    required this._indexKey,
    required this._maxPayloadBytes,
  }) : _algorithm = AesGcm.with256bits(nonceLength: _nonceLength);

  static const int envelopeVersion = 1;
  static const int payloadVersion = 1;
  static const int masterKeyLength = 32;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const int defaultMaxPayloadBytes = 72 * 1024;

  final SecretKeyData _encryptionKey;
  final SecretKeyData _indexKey;
  final int _maxPayloadBytes;
  final AesGcm _algorithm;
  final Hmac _hmac = Hmac.sha256();
  final Sha256 _sha256 = Sha256();
  bool _disposed = false;

  static Future<OperationOutboxCodec> create(
    List<int> masterKeyBytes, {
    int maxPayloadBytes = defaultMaxPayloadBytes,
  }) async {
    if (masterKeyBytes.length != masterKeyLength) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.locked,
        'The outbox master key is invalid.',
      );
    }
    if (maxPayloadBytes <= 0) {
      throw ArgumentError.value(
        maxPayloadBytes,
        'maxPayloadBytes',
        'Must be positive.',
      );
    }

    final masterBytes = Uint8List.fromList(masterKeyBytes);
    final masterKey = SecretKeyData(masterBytes);
    SecretKeyData? encryptionKey;
    SecretKeyData? indexKey;
    try {
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: masterKeyLength);
      encryptionKey = await hkdf.deriveKey(
        secretKey: masterKey,
        info: utf8.encode(
          'mobile-finance-assistant.operation-outbox.encryption.v1',
        ),
      );
      indexKey = await hkdf.deriveKey(
        secretKey: masterKey,
        info: utf8.encode('mobile-finance-assistant.operation-outbox.index.v1'),
      );
      return OperationOutboxCodec._(
        encryptionKey: encryptionKey,
        indexKey: indexKey,
        maxPayloadBytes: maxPayloadBytes,
      );
    } on Object {
      encryptionKey?.destroy();
      indexKey?.destroy();
      rethrow;
    } finally {
      masterKey.destroy();
      masterBytes.fillRange(0, masterBytes.length, 0);
    }
  }

  Future<String> principalTag(String principalScopeId) =>
      _tag('principal\u0000$principalScopeId');

  Future<String> financeAccountTag(String financeAccountId) =>
      _tag('account\u0000$financeAccountId');

  Future<String> commandTag({
    required String principalScopeId,
    required String commandId,
  }) => _tag('command\u0000$principalScopeId\u0000$commandId');

  Future<String> confirmedCommandDigest(
    FinanceOperationCommitCommand command,
  ) async {
    _ensureOpen();
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(_canonicalJson(command.toJson()))),
    );
    try {
      final hash = await _sha256.hash(bytes);
      return _hex(hash.bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<OperationOutboxEncryptedEnvelope> encrypt({
    required OperationOutboxEnvelopeMetadata metadata,
    required OperationOutboxPayload payload,
  }) async {
    _ensureOpen();
    await _validatePayloadForEncryption(payload);
    await _validateIdentity(metadata: metadata, payload: payload);
    final cleartext = Uint8List.fromList(
      utf8.encode(jsonEncode(_payloadToJson(payload))),
    );
    if (cleartext.isEmpty || cleartext.length > _maxPayloadBytes) {
      cleartext.fillRange(0, cleartext.length, 0);
      throw const OperationOutboxException(
        OperationOutboxErrorCode.capacityExceeded,
        'The confirmed command is too large.',
      );
    }

    try {
      final nonce = _algorithm.newNonce();
      final secretBox = await _algorithm.encrypt(
        cleartext,
        secretKey: _encryptionKey,
        nonce: nonce,
        aad: _aad(metadata),
      );
      if (secretBox.nonce.length != _nonceLength ||
          secretBox.mac.bytes.length != _macLength) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.storageUnavailable,
          'Unexpected encryption envelope.',
        );
      }
      return OperationOutboxEncryptedEnvelope(
        nonce: Uint8List.fromList(secretBox.nonce),
        ciphertext: Uint8List.fromList(secretBox.cipherText),
        mac: Uint8List.fromList(secretBox.mac.bytes),
      );
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<OperationOutboxPayload> decrypt({
    required OperationOutboxEnvelopeMetadata metadata,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> mac,
  }) async {
    _ensureOpen();
    if (nonce.length != _nonceLength ||
        ciphertext.isEmpty ||
        ciphertext.length > _maxPayloadBytes ||
        mac.length != _macLength) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The encrypted outbox envelope is invalid.',
      );
    }

    late final Uint8List cleartext;
    try {
      cleartext = Uint8List.fromList(
        await _algorithm.decrypt(
          SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
          secretKey: _encryptionKey,
          aad: _aad(metadata),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The encrypted outbox payload failed authentication.',
      );
    }

    try {
      if (cleartext.isEmpty || cleartext.length > _maxPayloadBytes) {
        throw const FormatException('Invalid decrypted payload size.');
      }
      final decoded = jsonDecode(utf8.decode(cleartext, allowMalformed: false));
      if (decoded is! Map) {
        throw const FormatException('Invalid outbox payload.');
      }
      final payload = await _payloadFromJson(
        Map<String, Object?>.from(decoded),
      );
      await _validateIdentity(metadata: metadata, payload: payload);
      return payload;
    } on OperationOutboxException {
      rethrow;
    } on Object {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The encrypted outbox payload is invalid.',
      );
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _encryptionKey.destroy();
    _indexKey.destroy();
  }

  Future<String> _tag(String value) async {
    _ensureOpen();
    final bytes = Uint8List.fromList(utf8.encode(value));
    try {
      final mac = await _hmac.calculateMac(bytes, secretKey: _indexKey);
      return base64UrlEncode(mac.bytes).replaceAll('=', '');
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Map<String, Object?> _payloadToJson(
    OperationOutboxPayload payload,
  ) => <String, Object?>{
    'payloadVersion': payloadVersion,
    'kind': payload.isTombstone ? 'synced_tombstone' : 'confirmed_operation',
    'principalScopeId': payload.principalScopeId,
    'financeAccountId': payload.financeAccountId,
    'commandId': payload.commandId,
    'confirmedCommand': payload.confirmedCommand?.toJson(),
    'confirmedCommandSha256': payload.confirmedCommandSha256,
    'serverOperationId': payload.serverOperationId,
  };

  Future<OperationOutboxPayload> _payloadFromJson(
    Map<String, Object?> json,
  ) async {
    _requireExactKeys(json, const <String>{
      'payloadVersion',
      'kind',
      'principalScopeId',
      'financeAccountId',
      'commandId',
      'confirmedCommand',
      'confirmedCommandSha256',
      'serverOperationId',
    });
    if (json['payloadVersion'] != payloadVersion) {
      throw const FormatException('Unsupported outbox payload version.');
    }
    final kind = _requiredString(json, 'kind');
    final principalScopeId = _requiredBoundedString(
      json,
      'principalScopeId',
      maximumLength: 512,
    );
    final financeAccountId = _requiredUuid(json, 'financeAccountId');
    final commandId = _requiredUuid(json, 'commandId');
    final confirmedCommandSha256 = _requiredString(
      json,
      'confirmedCommandSha256',
    );
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(confirmedCommandSha256)) {
      throw const FormatException('Invalid confirmed command digest.');
    }

    final rawCommand = json['confirmedCommand'];
    final rawServerOperationId = json['serverOperationId'];
    FinanceOperationCommitCommand? command;
    String? serverOperationId;
    if (kind == 'confirmed_operation') {
      if (rawCommand is! Map || rawServerOperationId != null) {
        throw const FormatException('Invalid confirmed outbox payload.');
      }
      command = FinanceOperationCommitCommand.fromJson(
        Map<String, Object?>.from(rawCommand),
      );
      if (command.review.draft.commandId != commandId ||
          command.review.draft.accountId != financeAccountId) {
        throw const FormatException('Confirmed command identity mismatch.');
      }
      final actualDigest = await confirmedCommandDigest(command);
      if (!_constantTimeStringEquals(actualDigest, confirmedCommandSha256)) {
        throw const FormatException('Confirmed command digest mismatch.');
      }
    } else if (kind == 'synced_tombstone') {
      if (rawCommand != null || rawServerOperationId is! String) {
        throw const FormatException('Invalid synced outbox tombstone.');
      }
      serverOperationId = _uuid(rawServerOperationId, 'serverOperationId');
    } else {
      throw const FormatException('Unsupported outbox payload kind.');
    }

    return OperationOutboxPayload(
      principalScopeId: principalScopeId,
      financeAccountId: financeAccountId,
      commandId: commandId,
      confirmedCommandSha256: confirmedCommandSha256,
      confirmedCommand: command,
      serverOperationId: serverOperationId,
    );
  }

  Future<void> _validateIdentity({
    required OperationOutboxEnvelopeMetadata metadata,
    required OperationOutboxPayload payload,
  }) async {
    final expectedPrincipalTag = await principalTag(payload.principalScopeId);
    final expectedAccountTag = await financeAccountTag(
      payload.financeAccountId,
    );
    final expectedCommandTag = await commandTag(
      principalScopeId: payload.principalScopeId,
      commandId: payload.commandId,
    );
    if (!_constantTimeStringEquals(
          metadata.principalTag,
          expectedPrincipalTag,
        ) ||
        !_constantTimeStringEquals(
          metadata.financeAccountTag,
          expectedAccountTag,
        ) ||
        !_constantTimeStringEquals(metadata.commandTag, expectedCommandTag)) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The outbox payload identity does not match its envelope.',
      );
    }
  }

  Future<void> _validatePayloadForEncryption(
    OperationOutboxPayload payload,
  ) async {
    _requiredBoundedString(
      <String, Object?>{'principalScopeId': payload.principalScopeId},
      'principalScopeId',
      maximumLength: 512,
    );
    _uuid(payload.financeAccountId, 'financeAccountId');
    _uuid(payload.commandId, 'commandId');
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(payload.confirmedCommandSha256)) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The confirmed command digest is invalid.',
      );
    }

    final command = payload.confirmedCommand;
    if (command == null) {
      final serverOperationId = payload.serverOperationId;
      if (serverOperationId == null) {
        throw const OperationOutboxException(
          OperationOutboxErrorCode.corruptPayload,
          'A synced tombstone requires a server operation identity.',
        );
      }
      _uuid(serverOperationId, 'serverOperationId');
      return;
    }
    if (payload.serverOperationId != null ||
        command.review.draft.commandId != payload.commandId ||
        command.review.draft.accountId != payload.financeAccountId) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The confirmed command identity is invalid.',
      );
    }
    final actualDigest = await confirmedCommandDigest(command);
    if (!_constantTimeStringEquals(
      actualDigest,
      payload.confirmedCommandSha256,
    )) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The confirmed command digest does not match.',
      );
    }
  }

  Uint8List _aad(OperationOutboxEnvelopeMetadata metadata) {
    _validateMetadata(metadata);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<Object?>[
          'mobile-finance-assistant.operation-outbox.v1',
          envelopeVersion,
          payloadVersion,
          metadata.localId,
          metadata.principalTag,
          metadata.financeAccountTag,
          metadata.commandTag,
          metadata.state.wireName,
          metadata.transitionSequence,
          metadata.createdAtEpochMs,
          metadata.stateChangedAtEpochMs,
          metadata.lastAttemptAtEpochMs,
          metadata.nextAttemptAtEpochMs,
          metadata.syncStartedAtEpochMs,
          metadata.syncedAtEpochMs,
          metadata.attemptCount,
          metadata.homeConvergencePending ? 1 : 0,
          metadata.lastErrorCode?.wireName,
        ]),
      ),
    );
  }

  void _validateMetadata(OperationOutboxEnvelopeMetadata metadata) {
    if (!_uuidPattern.hasMatch(metadata.localId) ||
        !_tagPattern.hasMatch(metadata.principalTag) ||
        !_tagPattern.hasMatch(metadata.financeAccountTag) ||
        !_tagPattern.hasMatch(metadata.commandTag) ||
        metadata.transitionSequence < 0 ||
        metadata.createdAtEpochMs < 0 ||
        metadata.stateChangedAtEpochMs < metadata.createdAtEpochMs ||
        metadata.attemptCount < 0 ||
        (metadata.homeConvergencePending &&
            metadata.state != OperationOutboxState.synced) ||
        <int?>[
          metadata.lastAttemptAtEpochMs,
          metadata.nextAttemptAtEpochMs,
          metadata.syncStartedAtEpochMs,
          metadata.syncedAtEpochMs,
        ].whereType<int>().any((value) => value < 0)) {
      throw const OperationOutboxException(
        OperationOutboxErrorCode.corruptPayload,
        'The outbox metadata is invalid.',
      );
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('OperationOutboxCodec is disposed.');
    }
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _tagPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

String _requiredBoundedString(
  Map<String, Object?> json,
  String key, {
  required int maximumLength,
}) {
  final value = _requiredString(json, key);
  if (value.isEmpty ||
      value.length > maximumLength ||
      value != value.trim() ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

String _requiredUuid(Map<String, Object?> json, String key) =>
    _uuid(_requiredString(json, key), key);

String _uuid(String value, String key) {
  if (!_uuidPattern.hasMatch(value)) throw FormatException('Invalid $key.');
  return value;
}

void _requireExactKeys(Map<String, Object?> json, Set<String> expected) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw const FormatException('Unexpected outbox payload fields.');
  }
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

bool _constantTimeStringEquals(String left, String right) {
  var difference = left.length ^ right.length;
  final maximum = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < maximum; index += 1) {
    final leftCode = index < left.length ? left.codeUnitAt(index) : 0;
    final rightCode = index < right.length ? right.codeUnitAt(index) : 0;
    difference |= leftCode ^ rightCode;
  }
  return difference == 0;
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}
