import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HomeSessionRecoveryResult { recovered, signOutRequired }

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

final homeSessionRecoveryProvider = Provider<HomeSessionRecovery>(
  (ref) => const ScenarioHomeSessionRecovery(),
);
