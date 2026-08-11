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

/// Derives the operation command identity for confirming one planned cost.
///
/// It must be deterministic, not random. Confirming a plan commits a real
/// operation first and only then transitions the plan (ADR 0018). If the
/// transition is lost — a dropped response, a crash, a killed app — the plan
/// stays outstanding and the user retries. With a fresh random command id that
/// retry would commit a *second* operation and charge the ledger twice; with a
/// derived one the server recognises the same command and replays the existing
/// operation idempotently.
///
/// The derivation XORs the plan's own UUID bytes with a fixed namespace and
/// restamps the version and variant nibbles. XOR is bijective, so distinct
/// plans always yield distinct identifiers.
///
/// Retrying with different content (say a corrected date) produces the same
/// command id with a different payload, which the server refuses as a command
/// conflict rather than silently recording a second operation. That refusal is
/// deliberate: a visible conflict is safer than a duplicated payment.
String plannedCostOperationCommandId(String plannedCostId) {
  final normalized = plannedCostId.replaceAll('-', '').toLowerCase();
  if (normalized.length != 32 ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(normalized)) {
    throw const FormatException('Invalid planned cost id.');
  }
  const namespace = <int>[
    0x9e,
    0x37,
    0x79,
    0xb9,
    0x7f,
    0x4a,
    0x7c,
    0x15,
    0xf3,
    0x9c,
    0xc0,
    0x60,
    0x5c,
    0xed,
    0xc8,
    0x34,
  ];
  final bytes = Uint8List(16);
  for (var index = 0; index < 16; index += 1) {
    final source = int.parse(
      normalized.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
    bytes[index] = source ^ namespace[index];
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
