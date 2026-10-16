import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_widgets.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/account_export_controller.dart';
import 'account_deletion_page.dart';

/// The person's own data, in Profile: taking it along, and asking for it to be
/// erased (ADR 0030).
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SettingsActionRow(
            key: const Key('profile-export-data'),
            icon: Icons.file_download_outlined,
            label: l10n.accountExportAction,
            description: preparing
                ? l10n.accountExportPreparing
                : l10n.accountExportDescription,
            // Disabled while the files are being written: a second tap would
            // only empty the folder the first one is filling.
            onPressed: preparing
                ? null
                : () => ref
                      .read(accountExportControllerProvider.notifier)
                      .exportAndShare(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SettingsActionRow(
            key: const Key('profile-delete-account'),
            icon: Icons.delete_outline_rounded,
            label: l10n.accountDeletionAction,
            description: l10n.accountDeletionActionDescription,
            // The export started from the deletion screen reports its failures
            // through the listener above, which stays mounted beneath it.
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const AccountDeletionPage(),
              ),
            ),
          ),
        ),
      ],
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
