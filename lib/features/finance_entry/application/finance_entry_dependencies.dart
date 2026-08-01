import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_config.dart';
import '../../auth/application/auth_controller.dart';
import '../data/finance_entry_api.dart';
import '../data/finance_entry_repository.dart';

final financeEntryApiDependencyProvider = Provider<FinanceEntryApiClient>((
  ref,
) {
  if (!isNetworkBackendConfigured) {
    throw StateError('Finance entry requires API_BASE_URL.');
  }
  final dio = Dio();
  ref.onDispose(() => dio.close(force: true));
  return FinanceEntryApi(dio: dio, baseUri: Uri.parse(configuredApiBaseUrl));
});

final financeEntryRepositoryDependencyProvider =
    Provider<FinanceEntryRepositoryClient>((ref) {
      return FinanceEntryRepository(
        api: ref.watch(financeEntryApiDependencyProvider),
        sessionStore: ref.watch(authSessionStoreProvider),
        refreshSession: ref
            .read(authControllerProvider.notifier)
            .recoverSession,
      );
    });
