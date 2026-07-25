import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.title,
    required this.dueLabel,
    required this.currentValue,
    required this.targetAndProgressLabel,
    required this.monthlyContributionLabel,
    required this.progressPercent,
    required this.semanticsLabel,
    this.onPressed,
  });

  final String title;
  final String dueLabel;
  final String currentValue;
  final String targetAndProgressLabel;
  final String monthlyContributionLabel;
  final String progressPercent;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final visualProgress =
        (double.tryParse(progressPercent) ?? 0).clamp(0, 100) / 100;
    final theme = Theme.of(context);

    return Semantics(
      key: const Key('primary-goal'),
      container: true,
      button: onPressed != null,
      label: semanticsLabel,
      value: '$progressPercent%',
      child: ExcludeSemantics(
        child: Card(
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(dueLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    runSpacing: AppSpacing.xxs,
                    children: [
                      Text(
                        currentValue,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        targetAndProgressLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: visualProgress,
                      color: theme.colorScheme.primary,
                      backgroundColor: context.appColors.surfaceSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    monthlyContributionLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GoalUnavailableCard extends StatelessWidget {
  const GoalUnavailableCard({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('goal-unavailable'),
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: CustomPaint(
          foregroundPainter: _DashedRoundedBorderPainter(
            color: context.appColors.border,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.appColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadius.card),
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
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.card),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in borderPath.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 6).clamp(0, metric.length)),
          paint,
        );
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
