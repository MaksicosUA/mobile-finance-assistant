import 'package:flutter/material.dart';

class VoiceCta extends StatelessWidget {
  const VoiceCta({
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
        key: const Key('voice-cta'),
        onPressed: onPressed,
        icon: const Icon(Icons.mic_none_rounded, size: 22),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
