import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// The one-tap way to record an operation: say it (ADR 0031).
///
/// Large on purpose — it is the reason Home exists. What it hears goes into the
/// same sentence field typing uses, so it records nothing by itself.
class VoiceEntryCta extends StatelessWidget {
  const VoiceEntryCta({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.listening,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;

  /// The recogniser is open; a second tap would only open another.
  final bool listening;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null && !listening;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      excludeSemantics: true,
      child: FilledButton.icon(
        key: const Key('voice-entry-cta'),
        // A minimum, not a fixed height: at 200% text the label grows the
        // button instead of being clipped by it.
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(72),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: theme.textTheme.titleMedium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.large),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        icon: listening
            ? const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Icon(Icons.mic_rounded, size: 32),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
