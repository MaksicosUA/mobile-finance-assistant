import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app_version.dart';

void main() {
  test('the shown fallback version is the pubspec version', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().singleWhere((line) => line.startsWith('version:'));
    final declared = line.split(':')[1].trim().split('+').first;

    // Two sources for one number drift silently, and the profile screen exists
    // partly so nobody has to read a manifest to learn which build is running.
    expect(appVersionFallback, declared);
  });

  test('a build without the define still names a version', () {
    expect(appVersion, isNotEmpty);
    expect(appVersion, appVersionFallback);
  });
}
