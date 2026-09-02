import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_config.dart';
import '../features/auth/application/auth_controller.dart';

/// Where this account's months are drawn, as the server currently reports it.
///
/// The zone is chosen when the account is created and correctable afterwards
/// (ADR 0028), so it is runtime state rather than the compile-time default it
/// starts from. Two things depend on getting it right:
///
/// * Home asserts it on every read and the server refuses a stale one, naming
///   the zone it actually holds so this can be adopted and the read retried;
/// * every capture resolves the local day an operation falls on in this zone,
///   which is the date Finance Core freezes (ADR 0007).
///
/// Nothing here is authoritative. The server owns the value; this only carries
/// the last thing it said, and is never persisted — a restart starts from the
/// default and adopts the truth on the first read that reports one.
final canonicalTimezoneProvider =
    NotifierProvider<CanonicalTimezoneController, String>(
      CanonicalTimezoneController.new,
    );

class CanonicalTimezoneController extends Notifier<String> {
  @override
  String build() {
    // A different account draws its months somewhere else.
    ref.watch(authAccountEpochProvider);
    return configuredHomeApiTimezone;
  }

  /// Take the server's word for it.
  ///
  /// An unusable value is ignored rather than adopted: a stale zone still
  /// draws a month, while an invalid one would fail every request.
  void adopt(String? zone) {
    if (zone == null || !isUsableTimezoneName(zone) || zone == state) return;
    state = zone;
  }
}

const _unstableTimezoneKeys = {'Factory', 'localtime', 'posixrules'};
final _timezonePattern = RegExp(r'^[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+-]+)*$');

/// Whether [value] is shaped like a stable IANA identifier the server accepts.
///
/// The names excluded here are tzdb implementation details, not places:
/// `localtime` in particular can resolve differently on another host.
bool isUsableTimezoneName(String value) {
  return value.isNotEmpty &&
      value.length <= 128 &&
      value == value.trim() &&
      !_unstableTimezoneKeys.contains(value) &&
      _timezonePattern.hasMatch(value) &&
      !value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);
}
