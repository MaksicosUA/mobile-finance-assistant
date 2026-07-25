import 'package:flutter/material.dart';

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
  });

  final ThemeMode themeMode;
  final AppAccent accent;
  final bool privacyMode;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppAccent? accent,
    bool? privacyMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      privacyMode: privacyMode ?? this.privacyMode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.themeMode == themeMode &&
        other.accent == accent &&
        other.privacyMode == privacyMode;
  }

  @override
  int get hashCode => Object.hash(themeMode, accent, privacyMode);
}
