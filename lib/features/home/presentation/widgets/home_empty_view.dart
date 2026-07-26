import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import 'voice_cta.dart';

class HomeEmptyView extends StatelessWidget {
  const HomeEmptyView({
    super.key,
    required this.title,
    required this.description,
    required this.voiceLabel,
    required this.voiceSemanticsLabel,
    required this.onVoicePressed,
  });

  final String title;
  final String description;
  final String voiceLabel;
  final String voiceSemanticsLabel;
  final VoidCallback? onVoicePressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('home-empty'),
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: context.appColors.surfaceSecondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic_none_rounded,
              size: 30,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          VoiceCta(
            label: voiceLabel,
            semanticsLabel: voiceSemanticsLabel,
            onPressed: onVoicePressed,
          ),
        ],
      ),
    );
  }
}
