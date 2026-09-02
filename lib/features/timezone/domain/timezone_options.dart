import 'package:flutter/foundation.dart';

/// One zone someone can pick, with a name they will recognise.
///
/// The identifier is what the server stores; the label is a city, because
/// "Europe/Kyiv" is an implementation detail and "Киев" is a place.
@immutable
final class TimezoneOption {
  const TimezoneOption(this.id, this.label);

  final String id;
  final String label;

  /// Whether [query] matches the city or the identifier.
  ///
  /// Case-insensitive on both, so "kyiv", "Киев" and "europe/k" all land.
  bool matches(String query) {
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
  TimezoneOption('Europe/Lisbon', 'Лиссабон'),
  TimezoneOption('Europe/Dublin', 'Дублин'),
  TimezoneOption('Europe/London', 'Лондон'),
  TimezoneOption('Atlantic/Canary', 'Канарские острова'),
  TimezoneOption('Europe/Madrid', 'Мадрид'),
  TimezoneOption('Europe/Paris', 'Париж'),
  TimezoneOption('Europe/Brussels', 'Брюссель'),
  TimezoneOption('Europe/Amsterdam', 'Амстердам'),
  TimezoneOption('Europe/Berlin', 'Берлин'),
  TimezoneOption('Europe/Zurich', 'Цюрих'),
  TimezoneOption('Europe/Vienna', 'Вена'),
  TimezoneOption('Europe/Prague', 'Прага'),
  TimezoneOption('Europe/Rome', 'Рим'),
  TimezoneOption('Europe/Warsaw', 'Варшава'),
  TimezoneOption('Europe/Budapest', 'Будапешт'),
  TimezoneOption('Europe/Stockholm', 'Стокгольм'),
  TimezoneOption('Europe/Oslo', 'Осло'),
  TimezoneOption('Europe/Copenhagen', 'Копенгаген'),
  TimezoneOption('Europe/Belgrade', 'Белград'),
  TimezoneOption('Europe/Zagreb', 'Загреб'),
  TimezoneOption('Europe/Ljubljana', 'Любляна'),
  TimezoneOption('Europe/Bratislava', 'Братислава'),
  TimezoneOption('Europe/Athens', 'Афины'),
  TimezoneOption('Europe/Bucharest', 'Бухарест'),
  TimezoneOption('Europe/Sofia', 'София'),
  TimezoneOption('Europe/Helsinki', 'Хельсинки'),
  TimezoneOption('Europe/Tallinn', 'Таллин'),
  TimezoneOption('Europe/Riga', 'Рига'),
  TimezoneOption('Europe/Vilnius', 'Вильнюс'),
  TimezoneOption('Europe/Kyiv', 'Киев'),
  TimezoneOption('Europe/Chisinau', 'Кишинёв'),
  TimezoneOption('Europe/Minsk', 'Минск'),
  TimezoneOption('Europe/Istanbul', 'Стамбул'),
  TimezoneOption('Europe/Moscow', 'Москва'),
  TimezoneOption('Asia/Tbilisi', 'Тбилиси'),
  TimezoneOption('Asia/Yerevan', 'Ереван'),
  TimezoneOption('Asia/Baku', 'Баку'),
  TimezoneOption('Asia/Nicosia', 'Никосия'),
  TimezoneOption('Asia/Jerusalem', 'Иерусалим'),
  TimezoneOption('Asia/Dubai', 'Дубай'),
  TimezoneOption('Asia/Tashkent', 'Ташкент'),
  TimezoneOption('Asia/Almaty', 'Алматы'),
  TimezoneOption('Asia/Bishkek', 'Бишкек'),
  TimezoneOption('Asia/Bangkok', 'Бангкок'),
  TimezoneOption('Asia/Singapore', 'Сингапур'),
  TimezoneOption('Asia/Hong_Kong', 'Гонконг'),
  TimezoneOption('Asia/Shanghai', 'Шанхай'),
  TimezoneOption('Asia/Seoul', 'Сеул'),
  TimezoneOption('Asia/Tokyo', 'Токио'),
  TimezoneOption('Australia/Perth', 'Перт'),
  TimezoneOption('Australia/Sydney', 'Сидней'),
  TimezoneOption('Pacific/Auckland', 'Окленд'),
  TimezoneOption('Africa/Cairo', 'Каир'),
  TimezoneOption('Africa/Johannesburg', 'Йоханнесбург'),
  TimezoneOption('America/Sao_Paulo', 'Сан-Паулу'),
  TimezoneOption('America/Argentina/Buenos_Aires', 'Буэнос-Айрес'),
  TimezoneOption('America/New_York', 'Нью-Йорк'),
  TimezoneOption('America/Toronto', 'Торонто'),
  TimezoneOption('America/Chicago', 'Чикаго'),
  TimezoneOption('America/Denver', 'Денвер'),
  TimezoneOption('America/Los_Angeles', 'Лос-Анджелес'),
  TimezoneOption('America/Mexico_City', 'Мехико'),
  TimezoneOption('UTC', 'UTC'),
];
