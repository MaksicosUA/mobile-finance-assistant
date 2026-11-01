import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The suite reads Russian, the template language. A test environment reports
/// an American phone, and with four languages to choose from a screen pumped
/// without an explicit locale would otherwise come up in English. The region
/// is Germany so a first account starts in euro, the currency the fixtures use.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .localesTestValue = const [
    Locale('ru', 'DE'),
  ];
  await testMain();
}
