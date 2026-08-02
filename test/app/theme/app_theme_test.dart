import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/settings/app_settings.dart';
import 'package:mobile_finance_assistant/app/theme/app_theme.dart';

void main() {
  test('every selectable accent has an AA text contrast', () {
    for (final accent in AppAccent.values) {
      final foreground = AppTheme.contrastForeground(accent.color);
      expect(
        AppTheme.contrastRatio(accent.color, foreground),
        greaterThanOrEqualTo(4.5),
        reason: accent.name,
      );
    }
  });
}
