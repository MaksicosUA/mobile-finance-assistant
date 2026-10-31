import 'package:flutter/material.dart';

import '../language/app_language.dart';

enum AppAccent {
  teal(Color(0xFF1D8075)),
  blue(Color(0xFF2667A8)),
  purple(Color(0xFF7A5AF8)),
  terracotta(Color(0xFFB26A3A));

  const AppAccent(this.color);

  final Color color;
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.light,
    this.accent = AppAccent.teal,
    this.privacyMode = false,
    this.language,
  });

  final ThemeMode themeMode;
  final AppAccent accent;
  final bool privacyMode;

  /// Null means the app follows the phone.
  final AppLanguage? language;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppAccent? accent,
    bool? privacyMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      privacyMode: privacyMode ?? this.privacyMode,
      language: language,
    );
  }

  /// Separate from [copyWith] because null is a choice here, not an omission.
  AppSettings withLanguage(AppLanguage? language) {
    return AppSettings(
      themeMode: themeMode,
      accent: accent,
      privacyMode: privacyMode,
      language: language,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.accent == accent &&
        other.privacyMode == privacyMode &&
        other.language == language;
  }

  @override
  int get hashCode => Object.hash(themeMode, accent, privacyMode, language);
}
