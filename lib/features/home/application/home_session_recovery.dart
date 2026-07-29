import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_repository.dart';

enum HomeSessionRecoveryResult { recovered, transientFailure, signOutRequired }

abstract interface class HomeSessionRecovery {
  Future<HomeSessionRecoveryResult> refreshSession();
}

class ScenarioHomeSessionRecovery implements HomeSessionRecovery {
  const ScenarioHomeSessionRecovery({
    this.result = HomeSessionRecoveryResult.signOutRequired,
  });

  final HomeSessionRecoveryResult result;

  @override
  Future<HomeSessionRecoveryResult> refreshSession() async => result;
}

final class AuthHomeSessionRecovery implements HomeSessionRecovery {
  const AuthHomeSessionRecovery(this._recover);

  final Future<AuthRefreshResult> Function() _recover;

  @override
  Future<HomeSessionRecoveryResult> refreshSession() async {
    final result = await _recover();
    return switch (result) {
      AuthRefreshResult.recovered => HomeSessionRecoveryResult.recovered,
      AuthRefreshResult.transientFailure =>
        HomeSessionRecoveryResult.transientFailure,
      AuthRefreshResult.invalid || AuthRefreshResult.sessionChanged =>
        HomeSessionRecoveryResult.signOutRequired,
    };
  }
}

final homeSessionRecoveryProvider = Provider<HomeSessionRecovery>(
  (ref) => isNetworkBackendConfigured
      ? AuthHomeSessionRecovery(
          ref.read(authControllerProvider.notifier).recoverSession,
        )
      : const ScenarioHomeSessionRecovery(),
);
