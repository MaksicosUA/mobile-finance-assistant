import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.accentSecondary,
    required this.border,
    required this.switchOff,
  });

  final Color background;
  final Color surface;
  final Color surfaceSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color accentSecondary;
  final Color border;
  final Color switchOff;

  static const light = AppColors(
    background: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFEDF2F7),
    textPrimary: Color(0xFF16324F),
    textSecondary: Color(0xFF5B6773),
    accentSecondary: Color(0xFF2667A8),
    border: Color(0xFFD8E1E8),
    switchOff: Color(0xFFC4D0DA),
  );

  static const dark = AppColors(
    background: Color(0xFF0D1621),
    surface: Color(0xFF152332),
    surfaceSecondary: Color(0xFF1B2C3D),
    textPrimary: Color(0xFFEDF4F7),
    textSecondary: Color(0xFFA8B5C2),
    accentSecondary: Color(0xFF68A9E8),
    border: Color(0xFF2B4052),
    switchOff: Color(0xFF3A5266),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSecondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? accentSecondary,
    Color? border,
    Color? switchOff,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      border: border ?? this.border,
      switchOff: switchOff ?? this.switchOff,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSecondary: Color.lerp(
        surfaceSecondary,
        other.surfaceSecondary,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      switchOff: Color.lerp(switchOff, other.switchOff, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
