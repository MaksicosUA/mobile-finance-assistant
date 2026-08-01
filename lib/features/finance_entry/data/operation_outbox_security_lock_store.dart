import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/operation_outbox.dart';
import 'operation_outbox_key_store.dart';

/// Persists only a versioned, non-sensitive reason that operation delivery is
/// blocked. There is deliberately no automatic clear API: recovery needs an
/// explicit product/security flow.
abstract interface class OperationOutboxSecurityLockStore {
  Future<OperationOutboxErrorCode?> read();

  Future<void> engage(OperationOutboxErrorCode code);
}

final class FlutterSecureStorageOperationOutboxSecurityLockStore
    implements OperationOutboxSecurityLockStore {
  const FlutterSecureStorageOperationOutboxSecurityLockStore({
    this.storage = operationOutboxSecureStorage,
    this.storageKey = 'operation_outbox.security_lock.v1',
  });

  static const String _markerPrefix = 'v1:';

  final FlutterSecureStorage storage;
  final String storageKey;

  @override
  Future<OperationOutboxErrorCode?> read() async {
    final marker = await storage.read(key: storageKey);
    if (marker == null) return null;
    if (marker.length > 64 || !marker.startsWith(_markerPrefix)) {
      throw const FormatException('Invalid outbox security lock marker.');
    }
    final code = OperationOutboxErrorCodeWire.parse(
      marker.substring(_markerPrefix.length),
    );
    if (!operationOutboxSecurityLockCodes.contains(code)) {
      throw const FormatException('Invalid outbox security lock reason.');
    }
    return code;
  }

  @override
  Future<void> engage(OperationOutboxErrorCode code) {
    if (!operationOutboxSecurityLockCodes.contains(code)) {
      throw ArgumentError.value(code, 'code', 'Not a security lock reason.');
    }
    return storage.write(
      key: storageKey,
      value: '$_markerPrefix${code.wireName}',
    );
  }
}
