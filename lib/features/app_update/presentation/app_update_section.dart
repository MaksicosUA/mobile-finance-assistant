import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_version.dart';
import '../../../app/settings/settings_widgets.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/app_update_controller.dart';

/// The installed version, and a button that asks whether there is a newer one.
///
/// Deliberately a button rather than a check that runs on its own (ADR 0026).
/// The cost is that nobody is told an update exists; the benefit is that the
/// app never interrupts someone's finances because a timer expired.
class AppUpdateSection extends ConsumerWidget {
  const AppUpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final busy = state is AppUpdateChecking || state is AppUpdateDownloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SettingsActionRow(
            key: const Key('profile-check-update'),
            icon: Icons.system_update_outlined,
            label: l10n.appUpdateCheckAction,
            description: l10n.appUpdateCheckDescription,
            onPressed: busy ? null : () => unawaited(controller.check()),
          ),
        ),
        if (state is! AppUpdateIdle) ...[
          const SizedBox(height: AppSpacing.sm),
          _Status(state: state),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.profileVersion(appVersion),
          key: const Key('profile-version'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Status extends ConsumerWidget {
  const _Status({required this.state});

  final AppUpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      key: const Key('app-update-status'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: switch (state) {
        AppUpdateIdle() => const SizedBox.shrink(),
        AppUpdateChecking() => Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(l10n.appUpdateChecking)),
          ],
        ),
        AppUpdateUpToDate() => Text(
          l10n.appUpdateUpToDate,
          key: const Key('app-update-up-to-date'),
        ),
        AppUpdateAvailable(:final release) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              key: const Key('app-update-available'),
              l10n.appUpdateAvailable(
                release.versionName,
                l10n.appUpdateMegabytes(_megabytes(release.sizeBytes)),
              ),
              style: textTheme.titleSmall,
            ),
            if (release.notes != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(l10n.appUpdateNotesLabel, style: textTheme.labelMedium),
              Text(release.notes!, style: textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              key: const Key('app-update-download'),
              onPressed: () =>
                  unawaited(controller.downloadAndInstall(release)),
              child: Text(l10n.appUpdateDownloadAction),
            ),
          ],
        ),
        AppUpdateDownloading(:final progress) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              key: const Key('app-update-downloading'),
              l10n.appUpdateDownloading(
                progress == null ? 0 : (progress * 100).clamp(0, 100).round(),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Determinate only once the size is known, so the bar never
            // reports a percentage it had to invent.
            LinearProgressIndicator(value: progress),
          ],
        ),
        AppUpdateHandedToInstaller() => Text(
          l10n.appUpdateHandedToInstaller,
          key: const Key('app-update-handed-over'),
        ),
        AppUpdateNeedsPermission() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.appUpdateNeedsPermission,
              key: const Key('app-update-needs-permission'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              key: const Key('app-update-open-settings'),
              onPressed: () => unawaited(controller.openPermissionSettings()),
              child: Text(l10n.appUpdatePermissionAction),
            ),
          ],
        ),
        AppUpdateFailed(:final reason, :final release) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Never colour alone: the icon and the words say the same
                // thing.
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    key: const Key('app-update-failed'),
                    switch (reason) {
                      AppUpdateFailureReason.unreachable =>
                        l10n.appUpdateFailedUnreachable,
                      AppUpdateFailureReason.serverUnavailable =>
                        l10n.appUpdateFailedServer,
                      AppUpdateFailureReason.corruptedDownload =>
                        l10n.appUpdateFailedCorrupted,
                      AppUpdateFailureReason.installerUnavailable =>
                        l10n.appUpdateFailedInstaller,
                      AppUpdateFailureReason.authenticationRequired =>
                        l10n.appUpdateFailedAuth,
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              key: const Key('app-update-retry'),
              onPressed: () => unawaited(
                release == null
                    ? controller.check()
                    : controller.downloadAndInstall(release),
              ),
              child: Text(l10n.appUpdateRetryAction),
            ),
          ],
        ),
      },
    );
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(1);
}
