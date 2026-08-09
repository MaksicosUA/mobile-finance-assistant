import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/app/app_shell.dart';

void main() {
  testWidgets('pops nested routes before requiring sign-in', (tester) async {
    late BuildContext rootContext;
    var requireSignInCalls = 0;
    var rootWasVisibleBeforeSignIn = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            rootContext = context;
            return Scaffold(
              body: FilledButton(
                key: const Key('open-settings-route'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (settingsContext) => Scaffold(
                      body: FilledButton(
                        key: const Key('open-baseline-route'),
                        onPressed: () =>
                            Navigator.of(settingsContext).push<void>(
                              MaterialPageRoute<void>(
                                builder: (baselineContext) => Scaffold(
                                  body: FilledButton(
                                    key: const Key('require-sign-in'),
                                    onPressed: () => popToRootBeforeSignIn(
                                      context: baselineContext,
                                      requireSignIn: () async {
                                        requireSignInCalls += 1;
                                        rootWasVisibleBeforeSignIn =
                                            !Navigator.of(rootContext).canPop();
                                      },
                                    ),
                                    child: const Text('Sign in'),
                                  ),
                                ),
                              ),
                            ),
                        child: const Text('Baseline'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Settings'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-settings-route')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-baseline-route')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('require-sign-in')), findsOneWidget);

    await tester.tap(find.byKey(const Key('require-sign-in')));
    await tester.pumpAndSettle();

    expect(requireSignInCalls, 1);
    expect(rootWasVisibleBeforeSignIn, isTrue);
    expect(find.byKey(const Key('open-settings-route')), findsOneWidget);
    expect(find.byKey(const Key('open-baseline-route')), findsNothing);
    expect(find.byKey(const Key('require-sign-in')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
