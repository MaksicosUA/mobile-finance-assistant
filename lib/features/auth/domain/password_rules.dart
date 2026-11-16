import 'dart:convert';

/// Whether [value] is a password the server will take: twelve to 128
/// characters, and no more than 1024 bytes of them.
///
/// The server decides; this only saves a round trip for the obvious cases, so
/// it must never be stricter than the server is.
bool isAcceptablePassword(String value) {
  final length = value.runes.length;
  return length >= 12 && length <= 128 && utf8.encode(value).length <= 1024;
}
