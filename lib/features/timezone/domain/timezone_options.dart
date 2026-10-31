import 'package:flutter/foundation.dart';

/// One zone someone can pick, with a name they will recognise.
///
/// The identifier is what the server stores; what a person reads is a city,
/// because "Europe/Kyiv" is an implementation detail and "Киев" is a place.
@immutable
final class TimezoneOption {
  const TimezoneOption(this.id);

  final String id;

  /// Whether [query] matches the city, as [label] names it in the language the
  /// screen is in, or the identifier.
  ///
  /// Case-insensitive on both, so "kyiv", "Киев" and "europe/k" all land.
  bool matches(String query, {required String label}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return label.toLowerCase().contains(needle) ||
        id.toLowerCase().contains(needle);
  }
}

/// The zones offered in the picker.
///
/// Deliberately a curated list rather than the whole tz database: Flutter does
/// not ship one, and 400 identifiers with no offsets beside them would be a
/// worse answer than sixty cities. The server still accepts any valid IANA
/// name, so nothing here is a limit on what an account may use — a zone the
/// account already holds is shown even when it is not on this list.
const timezoneOptions = <TimezoneOption>[
  TimezoneOption('Europe/Lisbon'),
  TimezoneOption('Europe/Dublin'),
  TimezoneOption('Europe/London'),
  TimezoneOption('Atlantic/Canary'),
  TimezoneOption('Europe/Madrid'),
  TimezoneOption('Europe/Paris'),
  TimezoneOption('Europe/Brussels'),
  TimezoneOption('Europe/Amsterdam'),
  TimezoneOption('Europe/Berlin'),
  TimezoneOption('Europe/Zurich'),
  TimezoneOption('Europe/Vienna'),
  TimezoneOption('Europe/Prague'),
  TimezoneOption('Europe/Rome'),
  TimezoneOption('Europe/Warsaw'),
  TimezoneOption('Europe/Budapest'),
  TimezoneOption('Europe/Stockholm'),
  TimezoneOption('Europe/Oslo'),
  TimezoneOption('Europe/Copenhagen'),
  TimezoneOption('Europe/Belgrade'),
  TimezoneOption('Europe/Zagreb'),
  TimezoneOption('Europe/Ljubljana'),
  TimezoneOption('Europe/Bratislava'),
  TimezoneOption('Europe/Athens'),
  TimezoneOption('Europe/Bucharest'),
  TimezoneOption('Europe/Sofia'),
  TimezoneOption('Europe/Helsinki'),
  TimezoneOption('Europe/Tallinn'),
  TimezoneOption('Europe/Riga'),
  TimezoneOption('Europe/Vilnius'),
  TimezoneOption('Europe/Kyiv'),
  TimezoneOption('Europe/Chisinau'),
  TimezoneOption('Europe/Minsk'),
  TimezoneOption('Europe/Istanbul'),
  TimezoneOption('Europe/Moscow'),
  TimezoneOption('Asia/Tbilisi'),
  TimezoneOption('Asia/Yerevan'),
  TimezoneOption('Asia/Baku'),
  TimezoneOption('Asia/Nicosia'),
  TimezoneOption('Asia/Jerusalem'),
  TimezoneOption('Asia/Dubai'),
  TimezoneOption('Asia/Tashkent'),
  TimezoneOption('Asia/Almaty'),
  TimezoneOption('Asia/Bishkek'),
  TimezoneOption('Asia/Bangkok'),
  TimezoneOption('Asia/Singapore'),
  TimezoneOption('Asia/Hong_Kong'),
  TimezoneOption('Asia/Shanghai'),
  TimezoneOption('Asia/Seoul'),
  TimezoneOption('Asia/Tokyo'),
  TimezoneOption('Australia/Perth'),
  TimezoneOption('Australia/Sydney'),
  TimezoneOption('Pacific/Auckland'),
  TimezoneOption('Africa/Cairo'),
  TimezoneOption('Africa/Johannesburg'),
  TimezoneOption('America/Sao_Paulo'),
  TimezoneOption('America/Argentina/Buenos_Aires'),
  TimezoneOption('America/New_York'),
  TimezoneOption('America/Toronto'),
  TimezoneOption('America/Chicago'),
  TimezoneOption('America/Denver'),
  TimezoneOption('America/Los_Angeles'),
  TimezoneOption('America/Mexico_City'),
  TimezoneOption('UTC'),
];
