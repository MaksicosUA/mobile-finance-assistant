import 'package:flutter/foundation.dart';

import '../../finance_entry/domain/finance_entry_models.dart'
    show maximumEntryTextLength;

/// How long a phrase the server has not read may wait on the phone.
const waitingPhraseLifetime = Duration(days: 30);

/// How many phrases may wait at once. Past that a new one is not kept.
const maximumWaitingPhrases = 50;

/// A sentence said on Home that the server has not read yet (ADR 0032).
///
/// The words and the moment they were said, and nothing parsed: reading them
/// stays the server's job. The moment travels with them so that «вчера» means
/// the day before it was said, not the day before it was read (ADR 0007).
@immutable
final class WaitingPhrase {
  WaitingPhrase({
    required this.id,
    required String text,
    required DateTime saidAt,
    required this.saidInTimezone,
  }) : text = text.trim(),
       saidAt = saidAt.toUtc() {
    if (!_id.hasMatch(id)) {
      throw const FormatException('Invalid waiting phrase id.');
    }
    if (!isReadableSentence(this.text)) {
      throw const FormatException('Invalid waiting phrase text.');
    }
    if (!_timezone.hasMatch(saidInTimezone)) {
      throw const FormatException('Invalid waiting phrase timezone.');
    }
  }

  factory WaitingPhrase.fromJson(Map<String, Object?> json) {
    if (json.length != 4 ||
        !json.keys.toSet().containsAll(const {
          'id',
          'text',
          'saidAt',
          'saidInTimezone',
        })) {
      throw const FormatException('Unexpected waiting phrase fields.');
    }
    final id = json['id'];
    final text = json['text'];
    final saidAt = json['saidAt'];
    final timezone = json['saidInTimezone'];
    if (id is! String ||
        text is! String ||
        saidAt is! String ||
        timezone is! String) {
      throw const FormatException('Invalid waiting phrase fields.');
    }
    final instant = DateTime.parse(saidAt);
    if (!instant.isUtc) {
      throw const FormatException('A waiting phrase is timed in UTC.');
    }
    return WaitingPhrase(
      id: id,
      text: text,
      saidAt: instant,
      saidInTimezone: timezone,
    );
  }

  final String id;
  final String text;

  /// The instant the words were heard.
  final DateTime saidAt;

  /// The phone's zone at that instant, which the server needs to know what
  /// day it was.
  final String saidInTimezone;

  bool isExpiredAt(DateTime now) =>
      !now.toUtc().isBefore(saidAt.add(waitingPhraseLifetime));

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'saidAt': saidAt.toIso8601String(),
    'saidInTimezone': saidInTimezone,
  };

  /// Whether the server could read [text] at all; anything else is not worth
  /// keeping, because no connection would ever change the answer.
  static bool isReadableSentence(String text) {
    final sentence = text.trim();
    return sentence.isNotEmpty &&
        sentence.length <= maximumEntryTextLength &&
        !sentence.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
  }

  static final _id = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _timezone = RegExp(r'^[A-Za-z0-9_+\-/]{1,64}$');
}
