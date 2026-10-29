import 'package:flutter/material.dart';

/// Opens the sentence field with the keyboard up.
///
/// A sentence is read by the deterministic parser (ADR 0022). On a populated
/// Home it sits under the microphone as the quieter way to the same field; on
/// a first-use Home, where there is no account to record into yet, it is the
/// only way in.
class QuickEntryCta extends StatelessWidget {
  const QuickEntryCta({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  /// Drawn as an outline beside a larger primary action.
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      child: secondary
          ? OutlinedButton.icon(
              key: const Key('quick-entry-cta'),
              onPressed: onPressed,
              icon: const Icon(Icons.keyboard_alt_outlined, size: 22),
              label: Text(label, textAlign: TextAlign.center),
            )
          : FilledButton.icon(
              key: const Key('quick-entry-cta'),
              onPressed: onPressed,
              icon: const Icon(Icons.edit_note_rounded, size: 22),
              label: Text(label, textAlign: TextAlign.center),
            ),
    );
  }
}
