import 'package:flutter/foundation.dart';

/// A recovery code as the server handed it over, to be shown once (ADR 0035).
///
/// Held in memory only until the person says they have kept it. It is never
/// written to preferences, a cache or a log: the phone is exactly where it must
/// not be the only copy.
@immutable
final class RecoveryCode {
  const RecoveryCode({required this.value, required this.createdAtUtc});

  final String value;
  final DateTime createdAtUtc;
}

/// Whether the account has a recovery code, and since when. Never the code.
@immutable
final class RecoveryCodeStatus {
  const RecoveryCodeStatus({required this.exists, this.createdAtUtc});

  final bool exists;
  final DateTime? createdAtUtc;
}

/// Crockford's alphabet: no I, L, O or U.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const _length = 20;
// A hyphen, the dashes a phone substitutes for one (U+2010 to U+2014, and the
// minus sign U+2212), or any white space.
final _separators = RegExp(r'[\s\-\u2010-\u2014\u2212]');
final _issuedShape = RegExp(
  r'^[0-9A-HJKMNP-TV-Z]{5}(-[0-9A-HJKMNP-TV-Z]{5}){3}$',
);

/// The twenty characters of a recovery code however it was spaced or cased, or
/// null when [text] cannot be one.
///
/// The same reading the server gives it, so a slip is caught here instead of
/// spending one of a limited number of attempts. It says nothing about whether
/// the code is the right one. What is sent is this form, so whatever a
/// keyboard or a paste put between the groups never reaches the server.
String? canonicalRecoveryCode(String text) {
  final canonical = text
      .replaceAll(_separators, '')
      .toUpperCase()
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');
  if (canonical.length != _length) return null;
  for (var index = 0; index < canonical.length; index++) {
    if (!_alphabet.contains(canonical[index])) return null;
  }
  return canonical;
}

/// Whether [value] is a code exactly as the server writes one.
bool isIssuedRecoveryCode(String value) => _issuedShape.hasMatch(value);
