import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import 'app_colors.dart';
import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData light(AppAccent accent) {
    return _build(
      brightness: Brightness.light,
      colors: AppColors.light,
      accent: accent.color,
    );
  }

  static ThemeData dark(AppAccent accent) {
    return _build(
      brightness: Brightness.dark,
      colors: AppColors.dark,
      accent: accent.color,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required AppColors colors,
    required Color accent,
  }) {
    final onAccent = contrastForeground(accent);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    final colorScheme = baseScheme.copyWith(
      primary: accent,
      onPrimary: onAccent,
      secondary: colors.accentSecondary,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      outline: colors.border,
    );

    final textTheme = ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: colors.textSecondary,
          height: 1.35,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: colors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSizes.minTouchTarget),
          maximumSize: const Size.square(AppSizes.minTouchTarget),
        ),
      ),
      extensions: [colors],
    );
  }

  static Color contrastForeground(Color background) {
    const light = Colors.white;
    const dark = Colors.black;
    return contrastRatio(background, light) >= 4.5 ? light : dark;
  }

  static double contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = firstLuminance > secondLuminance
        ? firstLuminance
        : secondLuminance;
    final darker = firstLuminance > secondLuminance
        ? secondLuminance
        : firstLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
