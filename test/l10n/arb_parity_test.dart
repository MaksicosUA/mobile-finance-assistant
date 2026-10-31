import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/timezone/domain/timezone_options.dart';
import 'package:mobile_finance_assistant/features/wallets/domain/currency_options.dart';
import 'package:mobile_finance_assistant/l10n/generated/app_localizations.dart';

/// `flutter gen-l10n` fills a missing translation with the template in silence
/// and compiles a placeholder that was renamed. These are the checks it does
/// not make.
void main() {
  final template = _strings('ru');

  for (final language in const ['uk', 'en', 'de']) {
    group(language, () {
      final strings = _strings(language);

      test('has exactly the template\'s keys', () {
        expect(strings.keys.toSet(), template.keys.toSet());
      });

      test('keeps every placeholder', () {
        for (final key in template.keys) {
          expect(
            _placeholders(strings[key]!),
            _placeholders(template[key]!),
            reason: key,
          );
        }
      });

      test('keeps every branch of a choice', () {
        for (final key in template.keys.where(
          (key) => template[key]!.contains(', select,'),
        )) {
          expect(
            _branches(strings[key]!),
            _branches(template[key]!),
            reason: key,
          );
        }
      });

      test('leaves nothing blank', () {
        for (final entry in strings.entries) {
          expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        }
      });
    });
  }

  for (final language in const ['en', 'de']) {
    test('$language has no Russian left in it', () {
      final strings = _strings(language);
      final cyrillic = RegExp(r'[Ѐ-ӿ]');
      expect(
        strings.keys.where((key) => cyrillic.hasMatch(strings[key]!)),
        isEmpty,
      );
    });
  }

  for (final locale in AppLocalizations.supportedLocales) {
    test('${locale.languageCode} names every currency on offer', () {
      final l10n = lookupAppLocalizations(locale);
      for (final option in currencyOptions) {
        expect(l10n.currencyName(option.code), isNot(option.code));
      }
    });

    test('${locale.languageCode} names every city on offer', () {
      final l10n = lookupAppLocalizations(locale);
      for (final option in timezoneOptions.where((zone) => zone.id != 'UTC')) {
        final city = l10n.timezoneCity(option.id.replaceAll('/', '_'));
        expect(city, isNot('UTC'), reason: option.id);
      }
    });
  }

  test('Ukrainian has no Russian letters left in it', () {
    final strings = _strings('uk');
    final russianOnly = RegExp(r'[ыэъёЫЭЪЁ]');
    expect(
      strings.keys.where((key) => russianOnly.hasMatch(strings[key]!)),
      isEmpty,
    );
  });
}

Map<String, String> _strings(String language) {
  final decoded =
      jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final entry in decoded.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

Set<String> _placeholders(String message) {
  if (message.contains(', select,')) {
    return {message.substring(1, message.indexOf(','))};
  }
  return RegExp(
    r'\{(\w+)\}',
  ).allMatches(message).map((match) => match.group(1)!).toSet();
}

Set<String> _branches(String message) => RegExp(
  r'(\w+)\{',
).allMatches(message).map((match) => match.group(1)!).toSet();
