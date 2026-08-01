import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const operationOutboxSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: false,
    storageNamespace: 'mobile_finance_assistant_operation_outbox_v1',
  ),
);

/// Stores only the dedicated random outbox master key. Financial payloads are
/// never written to platform secure-storage values or SharedPreferences.
abstract interface class OperationOutboxKeyStore {
  Future<List<int>?> read();

  Future<void> write(List<int> keyBytes);

  Future<void> delete();
}

final class FlutterSecureStorageOperationOutboxKeyStore
    implements OperationOutboxKeyStore {
  const FlutterSecureStorageOperationOutboxKeyStore({
    this.storage = operationOutboxSecureStorage,
    this.storageKey = 'operation_outbox.master_key.v1',
  });

  final FlutterSecureStorage storage;
  final String storageKey;

  @override
  Future<List<int>?> read() async {
    final encoded = await storage.read(key: storageKey);
    if (encoded == null) return null;
    if (encoded.length > 128) {
      throw const FormatException('Invalid outbox key encoding.');
    }
    return Uint8List.fromList(base64Decode(encoded));
  }

  @override
  Future<void> write(List<int> keyBytes) =>
      storage.write(key: storageKey, value: base64Encode(keyBytes));

  @override
  Future<void> delete() => storage.delete(key: storageKey);
}
