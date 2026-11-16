import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/settings_widgets.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/credentials_controller.dart';
import 'password_change_page.dart';
import 'recovery_code_issue_page.dart';

/// The person's own password and recovery code, in Profile (ADR 0035).
class CredentialsSection extends ConsumerWidget {
  const CredentialsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Nothing is said while it is unknown: "not created" would be a claim.
    final status = ref.watch(recoveryCodeStatusProvider).value;
    final created = status?.createdAtUtc;
    final codeValue = switch (status) {
      null => null,
      _ when created != null => l10n.recoveryCodeStatusCreated(
        created.toLocal(),
      ),
      _ => l10n.recoveryCodeStatusMissing,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(l10n.securitySection),
        const SizedBox(height: AppSpacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SettingsActionRow(
            key: const Key('profile-recovery-code'),
            icon: Icons.key_outlined,
            label: l10n.recoveryCodeAction,
            value: codeValue,
            description: l10n.recoveryCodeActionDescription,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const RecoveryCodeIssuePage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SettingsActionRow(
            key: const Key('profile-change-password'),
            icon: Icons.password_rounded,
            label: l10n.passwordChangeAction,
            description: l10n.passwordChangeActionDescription,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const PasswordChangePage(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
