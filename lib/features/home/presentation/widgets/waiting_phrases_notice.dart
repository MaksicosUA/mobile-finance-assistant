import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// Says that phrases said without a connection are waiting to be read
/// (ADR 0032), and opens them.
///
/// A count and nothing else: the words carry amounts, and Home shows them
/// nowhere, privacy mode or not.
class WaitingPhrasesNotice extends StatelessWidget {
  const WaitingPhrasesNotice({
    super.key,
    required this.title,
    required this.description,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final String title;
  final String description;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Card(
        key: const Key('waiting-phrases-notice'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.schedule_send_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(description, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
