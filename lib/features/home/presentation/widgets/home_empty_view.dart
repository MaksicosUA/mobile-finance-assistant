import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import 'quick_entry_cta.dart';

class HomeEmptyView extends StatelessWidget {
  const HomeEmptyView({
    super.key,
    required this.title,
    required this.description,
    required this.entryLabel,
    required this.entrySemanticsLabel,
    required this.onEntryPressed,
    required this.manualLabel,
    required this.onManualPressed,
  });

  final String title;
  final String description;
  final String entryLabel;
  final String entrySemanticsLabel;
  final VoidCallback? onEntryPressed;
  final String manualLabel;
  final VoidCallback? onManualPressed;

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
          QuickEntryCta(
            label: entryLabel,
            semanticsLabel: entrySemanticsLabel,
            onPressed: onEntryPressed,
          ),
          if (onManualPressed != null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('home-empty-manual-entry'),
              onPressed: onManualPressed,
              icon: const Icon(Icons.edit_outlined),
              label: Text(manualLabel),
            ),
          ],
        ],
      ),
    );
  }
}
