import 'package:flutter/widgets.dart';

/// A language the app speaks.
///
/// Each one is written in itself wherever it is offered, because the person
/// choosing may not be able to read the language the screen is in.
enum AppLanguage {
  russian('ru', 'ru-RU', 'Русский'),
  ukrainian('uk', 'uk-UA', 'Українська'),
  english('en', 'en-US', 'English'),
  german('de', 'de-DE', 'Deutsch');

  const AppLanguage(this.code, this.speechTag, this.nativeName);

  /// What the app stores, and what the server is told (ADR 0034).
  final String code;

  /// What the phone's recogniser listens for.
  final String speechTag;

  final String nativeName;

  Locale get locale => Locale(code);

  static AppLanguage? fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }
}

/// The first of the phone's languages the app speaks.
///
/// English when it speaks none of them: of the four, it is the one most people
/// can read when theirs is missing.
AppLanguage resolveAppLanguage(Iterable<Locale> phoneLocales) {
  for (final locale in phoneLocales) {
    final language = AppLanguage.fromCode(locale.languageCode);
    if (language != null) return language;
  }
  return AppLanguage.english;
}
