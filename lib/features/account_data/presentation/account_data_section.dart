import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_widgets.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/account_export_controller.dart';

/// The person's own data, in Profile: taking it along (ADR 0030).
class AccountDataSection extends ConsumerWidget {
  const AccountDataSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final export = ref.watch(accountExportControllerProvider);
    ref.listen<AccountExportState>(accountExportControllerProvider, (
      previous,
      next,
    ) {
      if (next is! AccountExportFailed) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(_failureMessage(l10n, next.reason))),
      );
    });
    final preparing = export is AccountExportPreparing;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SettingsActionRow(
        key: const Key('profile-export-data'),
        icon: Icons.file_download_outlined,
        label: l10n.accountExportAction,
        description: preparing
            ? l10n.accountExportPreparing
            : l10n.accountExportDescription,
        // Disabled while the files are being written: a second tap would only
        // empty the folder the first one is filling.
        onPressed: preparing
            ? null
            : () => ref
                  .read(accountExportControllerProvider.notifier)
                  .exportAndShare(),
      ),
    );
  }

  static String _failureMessage(
    AppLocalizations l10n,
    AccountExportFailure reason,
  ) {
    return switch (reason) {
      AccountExportFailure.unreachable => l10n.accountExportFailedUnreachable,
      AccountExportFailure.unavailable => l10n.accountExportFailedUnavailable,
      AccountExportFailure.authenticationRequired =>
        l10n.accountExportFailedAuthentication,
      AccountExportFailure.shareUnavailable => l10n.accountExportFailedShare,
      AccountExportFailure.storage => l10n.accountExportFailedStorage,
    };
  }
}
