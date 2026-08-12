import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/data/finance_entry_repository.dart';
import '../../finance_entry/domain/finance_entry_models.dart';
import '../../finance_entry/domain/finance_entry_result.dart';

final profileControllerProvider =
    NotifierProvider.autoDispose<ProfileController, ProfileState>(
      ProfileController.new,
    );

sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoading extends ProfileState {
  const ProfileLoading();
}

@immutable
final class ProfileReady extends ProfileState {
  const ProfileReady(this.profile);

  final UserProfile profile;
}

final class ProfileAuthenticationRequired extends ProfileState {
  const ProfileAuthenticationRequired();
}

@immutable
final class ProfileFailure extends ProfileState {
  const ProfileFailure(this.failure);

  final FinanceEntryFailure failure;
}

/// Reads who is signed in and the durable facts of their account.
///
/// One request answers the whole screen on purpose. The authenticated session
/// stores only tokens, and the display name on Home comes from the Home
/// snapshot, so the in-memory identity is blank after an app restart — exactly
/// when a user opens this screen.
class ProfileController extends Notifier<ProfileState> {
  bool _requestInFlight = false;
  int _requestGeneration = 0;

  FinanceEntryRepositoryClient get _repository =>
      ref.read(financeEntryRepositoryProvider);

  @override
  ProfileState build() {
    ref.watch(authAccountEpochProvider);
    _requestGeneration += 1;
    _requestInFlight = false;
    return const ProfileLoading();
  }

  Future<void> load() async {
    if (_requestInFlight) return;
    final requestGeneration = _beginRequest();
    try {
      final result = await _repository.readProfile();
      if (!_isCurrentRequest(requestGeneration)) return;
      switch (result) {
        case FinanceEntrySuccess(:final value):
          state = ProfileReady(value);
        case FinanceEntryFailureResult(:final failure):
          state = _requiresAuthentication(failure)
              ? const ProfileAuthenticationRequired()
              : ProfileFailure(failure);
      }
    } on Object {
      if (_isCurrentRequest(requestGeneration)) {
        state = ProfileFailure(_unexpectedFailure());
      }
    } finally {
      _endRequest(requestGeneration);
    }
  }

  int _beginRequest() {
    _requestInFlight = true;
    _requestGeneration += 1;
    return _requestGeneration;
  }

  bool _isCurrentRequest(int requestGeneration) =>
      ref.mounted && requestGeneration == _requestGeneration;

  void _endRequest(int requestGeneration) {
    if (_isCurrentRequest(requestGeneration)) _requestInFlight = false;
  }
}

bool _requiresAuthentication(FinanceEntryFailure failure) =>
    failure.kind == FinanceEntryFailureKind.unauthenticated ||
    failure.kind == FinanceEntryFailureKind.unauthorized ||
    failure.kind == FinanceEntryFailureKind.sessionChanged;

FinanceEntryFailure _unexpectedFailure() => FinanceEntryFailure(
  kind: FinanceEntryFailureKind.unknown,
  requestId: 'req_local_profile_unknown',
);
