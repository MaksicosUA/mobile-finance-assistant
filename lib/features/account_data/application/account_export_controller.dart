import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/file_share.dart';
import '../../auth/application/auth_controller.dart';
import '../../finance_entry/application/finance_entry_controller.dart';
import '../../finance_entry/domain/finance_entry_result.dart';

final accountExportControllerProvider =
    NotifierProvider.autoDispose<AccountExportController, AccountExportState>(
      AccountExportController.new,
    );

sealed class AccountExportState {
  const AccountExportState();
}

final class AccountExportIdle extends AccountExportState {
  const AccountExportIdle();
}

final class AccountExportPreparing extends AccountExportState {
  const AccountExportPreparing();
}

/// Both files were handed to the share sheet. Where they went is the person's
/// choice and this app never learns it.
final class AccountExportShared extends AccountExportState {
  const AccountExportShared();
}

enum AccountExportFailure {
  /// The server could not be reached.
  unreachable,

  /// The server answered, but could not produce the record.
  unavailable,

  /// The session has ended; signing in again is the way back.
  authenticationRequired,

  /// The files were written, but no share sheet would open.
  shareUnavailable,

  /// The phone could not write the files.
  storage,
}

@immutable
final class AccountExportFailed extends AccountExportState {
  const AccountExportFailed(this.reason);

  final AccountExportFailure reason;
}

/// Takes the person's whole record out of the app, in two files (ADR 0030).
///
/// The complete record as JSON and the operations as a spreadsheet, both
/// written into the app's own cache and handed to Android's share sheet. The
/// person chooses the destination; this app sends nothing anywhere itself.
class AccountExportController extends Notifier<AccountExportState> {
  @override
  AccountExportState build() {
    ref.watch(authAccountEpochProvider);
    return const AccountExportIdle();
  }

  Future<void> exportAndShare() async {
    if (state is AccountExportPreparing) return;
    state = const AccountExportPreparing();
    final share = ref.read(fileShareProvider);
    final repository = ref.read(financeEntryRepositoryProvider);
    final day = _isoDay(ref.read(financeEntryClockProvider)());
    try {
      final directory = await share.freshExportDirectory();
      final record = File('${directory.path}/finance-export-$day.json');
      final table = File('${directory.path}/operations-$day.csv');
      for (final download in [
        () => repository.downloadAccountExport(savePath: record.path),
        () => repository.downloadOperationsTable(savePath: table.path),
      ]) {
        final result = await download();
        if (!ref.mounted) return;
        if (result case FinanceEntryFailureResult(:final failure)) {
          // Half an export is worse than none: it reads as complete.
          await share.clearExports();
          if (ref.mounted) state = AccountExportFailed(_reasonFor(failure));
          return;
        }
      }
      await share.share([record, table]);
      if (ref.mounted) state = const AccountExportShared();
    } on FileShareFailed {
      if (ref.mounted) {
        state = const AccountExportFailed(
          AccountExportFailure.shareUnavailable,
        );
      }
    } on Object {
      if (ref.mounted) {
        state = const AccountExportFailed(AccountExportFailure.storage);
      }
    }
  }

  static AccountExportFailure _reasonFor(FinanceEntryFailure failure) {
    return switch (failure.kind) {
      FinanceEntryFailureKind.unauthenticated ||
      FinanceEntryFailureKind.sessionChanged =>
        AccountExportFailure.authenticationRequired,
      FinanceEntryFailureKind.offline ||
      FinanceEntryFailureKind.timeout => AccountExportFailure.unreachable,
      _ => AccountExportFailure.unavailable,
    };
  }

  static String _isoDay(DateTime moment) {
    final local = moment.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
