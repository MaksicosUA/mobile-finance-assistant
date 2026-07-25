import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';

class HomeLoadingView extends StatelessWidget {
  const HomeLoadingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.appColors.surfaceSecondary;
    return Semantics(
      key: const Key('home-loading'),
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Column(
          children: [
            _Skeleton(height: 170, color: color),
            const SizedBox(height: AppSpacing.lg),
            _Skeleton(height: 60, color: color),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: _Skeleton(height: 96, color: color)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _Skeleton(height: 96, color: color)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _Skeleton(height: 96, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}
