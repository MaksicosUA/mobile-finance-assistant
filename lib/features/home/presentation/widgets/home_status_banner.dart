import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

enum HomeBannerTone { neutral, warning, error }

class HomeStatusBanner extends StatelessWidget {
  const HomeStatusBanner({
    super.key,
    required this.title,
    required this.description,
    required this.tone,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final HomeBannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final foreground = switch (tone) {
      HomeBannerTone.neutral => colors.textSecondary,
      HomeBannerTone.warning =>
        theme.brightness == Brightness.dark
            ? const Color(0xFFFFC75A)
            : const Color(0xFF6B4500),
      HomeBannerTone.error => theme.colorScheme.error,
    };
    final background = switch (tone) {
      HomeBannerTone.neutral => colors.surfaceSecondary,
      HomeBannerTone.warning =>
        theme.brightness == Brightness.dark
            ? const Color(0xFF342A16)
            : const Color(0xFFFFF4D6),
      HomeBannerTone.error => theme.colorScheme.errorContainer,
    };
    final icon = switch (tone) {
      HomeBannerTone.neutral => Icons.info_outline_rounded,
      HomeBannerTone.warning => Icons.warning_amber_rounded,
      HomeBannerTone.error => Icons.error_outline_rounded,
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $description',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(icon, color: foreground, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(description, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeBlockUnavailableCard extends StatelessWidget {
  const HomeBlockUnavailableCard({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: context.appColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: context.appColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
