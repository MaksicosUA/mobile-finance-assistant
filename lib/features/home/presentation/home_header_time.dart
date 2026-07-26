import '../../../l10n/generated/app_localizations.dart';

enum HomeGreetingPeriod { night, morning, day, evening }

HomeGreetingPeriod homeGreetingPeriod(DateTime localNow) {
  final hour = localNow.hour;
  if (hour >= 5 && hour < 12) return HomeGreetingPeriod.morning;
  if (hour >= 12 && hour < 18) return HomeGreetingPeriod.day;
  if (hour >= 18 && hour < 23) return HomeGreetingPeriod.evening;
  return HomeGreetingPeriod.night;
}

String localizedHomeGreeting(
  AppLocalizations l10n, {
  required String userName,
  required DateTime localNow,
}) {
  return switch (homeGreetingPeriod(localNow)) {
    HomeGreetingPeriod.morning => l10n.greetingMorning(userName),
    HomeGreetingPeriod.day => l10n.greetingDay(userName),
    HomeGreetingPeriod.evening => l10n.greetingEvening(userName),
    HomeGreetingPeriod.night => l10n.greetingNight(userName),
  };
}

String sentenceCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
