import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_shell.dart';
import '../../../app/privacy/app_switcher_privacy.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../core/network/api_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/auth_controller.dart';
import 'auth_page.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool? _lastProtection;

  @override
  void initState() {
    super.initState();
    if (isNetworkBackendConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(authControllerProvider.notifier).bootstrap();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);
    if (!isNetworkBackendConfigured) {
      _setProtection(settings.privacyMode);
      return const AppShell();
    }

    final state = ref.watch(authControllerProvider);
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      // Said once, as the person arrives: their sign-in cancelled the erasure
      // they had asked for (ADR 0030).
      if (next is AuthSignedIn &&
          next.notice == AuthNotice.deletionCancelled &&
          previous is! AuthSignedIn) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            key: const Key('auth-deletion-cancelled'),
            content: Text(
              AppLocalizations.of(context).accountDeletionCancelled,
            ),
          ),
        );
      }
    });
    _setProtection(state is AuthSignedIn ? settings.privacyMode : true);
    return switch (state) {
      AuthBootstrapping() || AuthSigningOut() => const _AuthLoadingPage(),
      AuthSignedOut(
        :final mode,
        :final notice,
        :final issue,
        :final deletionDueAt,
      ) =>
        AuthPage(
          mode: mode,
          notice: notice,
          issue: issue,
          deletionDueAt: deletionDueAt,
          isSubmitting: false,
        ),
      AuthSubmitting(:final mode) => AuthPage(mode: mode, isSubmitting: true),
      AuthSignedIn() => const AppShell(),
    };
  }

  void _setProtection(bool protected) {
    if (_lastProtection == protected) return;
    _lastProtection = protected;
    unawaited(
      ref
          .read(appSwitcherPrivacyProvider)
          .setProtected(protected)
          .catchError((_) {}),
    );
  }
}

class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Semantics(
            key: const Key('auth-loading'),
            container: true,
            liveRegion: true,
            label: l10n.authLoadingLabel,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
    );
  }
}
