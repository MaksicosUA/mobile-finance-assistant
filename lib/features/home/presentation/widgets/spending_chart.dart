import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../domain/home_snapshot.dart';

class SpendingChart extends StatelessWidget {
  const SpendingChart({
    super.key,
    required this.trend,
    required this.title,
    required this.periodDescription,
    required this.periodLabel,
    required this.detailsLabel,
    required this.emptyLabel,
    required this.semanticsLabel,
    required this.amountsHiddenLabel,
    required this.privacyEnabled,
    this.onOpenDetails,
  });

  final TrendSummary trend;
  final String title;
  final String periodDescription;
  final String periodLabel;
  final String detailsLabel;
  final String emptyLabel;
  final String semanticsLabel;
  final String amountsHiddenLabel;
  final bool privacyEnabled;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dates = _axisDates(context);

    return Card(
      key: const Key('spending-chart'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (textScale > 1.35)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Title(title: title, description: periodDescription),
                  const SizedBox(height: AppSpacing.xs),
                  _Actions(
                    periodLabel: periodLabel,
                    detailsLabel: detailsLabel,
                    onOpenDetails: onOpenDetails,
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Title(title: title, description: periodDescription),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _Actions(
                    periodLabel: periodLabel,
                    detailsLabel: detailsLabel,
                    onOpenDetails: onOpenDetails,
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              image: true,
              label: semanticsLabel,
              child: ExcludeSemantics(
                child: switch ((trend.points.isEmpty, privacyEnabled)) {
                  (true, _) => SizedBox(
                    height: 112,
                    child: Center(
                      child: Text(
                        emptyLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  (false, true) => SizedBox(
                    height: 112,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Center(
                        child: Text(
                          amountsHiddenLabel,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                  (false, false) => Column(
                    children: [
                      SizedBox(
                        height: 100,
                        child: CustomPaint(
                          painter: _TrendPainter(
                            amounts: trend.points
                                .map((point) => point.amount.amount)
                                .toList(growable: false),
                            lineColor: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final date in dates)
                            Flexible(
                              child: Text(
                                date,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _axisDates(BuildContext context) {
    if (trend.points.isEmpty) return const [];
    final localizations = MaterialLocalizations.of(context);
    final middle = trend.points.length ~/ 2;
    return [
      localizations.formatShortDate(trend.points.first.date),
      localizations.formatShortDate(trend.points[middle].date),
      localizations.formatShortDate(trend.points.last.date),
    ];
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.periodLabel,
    required this.detailsLabel,
    required this.onOpenDetails,
  });

  final String periodLabel;
  final String detailsLabel;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.appColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              periodLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (onOpenDetails != null)
          TextButton(
            key: const Key('open-trend-details'),
            onPressed: onOpenDetails,
            child: Text(detailsLabel),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.amounts, required this.lineColor});

  final List<String> amounts;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (amounts.isEmpty || size.isEmpty) return;
    final values = _scaledIntegers(amounts);
    final minValue = values.reduce(
      (left, right) => left < right ? left : right,
    );
    final maxValue = values.reduce(
      (left, right) => left > right ? left : right,
    );
    final range = maxValue - minValue;
    const topPadding = 8.0;
    const bottomPadding = 8.0;
    final drawableHeight = size.height - topPadding - bottomPadding;
    final line = Path();

    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : index * size.width / (values.length - 1);
      final ratio = range == BigInt.zero
          ? 0.5
          : ((values[index] - minValue).toDouble() / range.toDouble());
      final y = topPadding + drawableHeight * (1 - ratio);
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = lineColor.withValues(alpha: 0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Keeps money exact as scaled integers; only the dimensionless pixel ratio
  /// is converted to double for Canvas coordinates.
  List<BigInt> _scaledIntegers(List<String> source) {
    var maxScale = 0;
    for (final value in source) {
      final dot = value.indexOf('.');
      final scale = dot < 0 ? 0 : value.length - dot - 1;
      if (scale > maxScale) maxScale = scale;
    }

    return source
        .map((value) {
          final negative = value.startsWith('-');
          final unsigned = negative ? value.substring(1) : value;
          final parts = unsigned.split('.');
          final scale = parts.length == 1 ? 0 : parts[1].length;
          final digits = BigInt.parse(parts.join());
          final scaled = digits * BigInt.from(10).pow(maxScale - scale);
          return negative ? -scaled : scaled;
        })
        .toList(growable: false);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        !listEquals(oldDelegate.amounts, amounts);
  }
}
