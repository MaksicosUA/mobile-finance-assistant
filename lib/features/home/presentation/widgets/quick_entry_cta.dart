import 'package:flutter/material.dart';

/// The one-tap way to record an operation.
///
/// It carries a keyboard rather than a microphone: a sentence is read by the
/// deterministic parser (ADR 0022), and voice will feed that same path once
/// audio capture and its retention policy exist.
class QuickEntryCta extends StatelessWidget {
  const QuickEntryCta({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      child: FilledButton.icon(
        key: const Key('quick-entry-cta'),
        onPressed: onPressed,
        icon: const Icon(Icons.edit_note_rounded, size: 22),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
