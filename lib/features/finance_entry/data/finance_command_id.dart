import 'dart:math';
import 'dart:typed_data';

typedef FinanceCommandIdFactory = String Function();

/// Generates RFC 4122 version-4 command identifiers without a package or clock.
String newFinanceCommandId() {
  final random = Random.secure();
  final bytes = Uint8List(16);
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = random.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
