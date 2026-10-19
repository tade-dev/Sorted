import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/motion/sorted_motion.dart';

/// What the screen under test last heard.
bool? _arrived;

GoRouter _router() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (_, s) => sortedTabPage(
        s,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => context.push('/next'),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/next',
      pageBuilder: (_, s) => sortedPushPage(
        s,
        Scaffold(
          body: AfterArrival(
            builder: (_, arrived) {
              _arrived = arrived;
              return Text(arrived ? 'arrived' : 'arriving');
            },
          ),
        ),
      ),
    ),
  ],
);

void main() {
  setUp(() => _arrived = null);

  group('AfterArrival', () {
    testWidgets('waits while the page is still travelling', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_arrived, isFalse, reason: 'the push is still under way');
    });

    testWidgets('and lets go once it has landed', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(_arrived, isTrue);
      expect(find.text('arrived'), findsOneWidget);
    });

    testWidgets('on iOS too, where the push is the back-swipe route', (
      tester,
    ) async {
      // Reset inside the body: flutter_test checks the foundation debug vars
      // when the body returns, before tearDown gets a turn.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_arrived, isFalse);
      await tester.pumpAndSettle();
      expect(_arrived, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a screen with nothing to wait for has already arrived', (
      tester,
    ) async {
      // The first screen, or a test host: no transition is coming, so holding
      // the moment back would hold it forever.
      await tester.pumpWidget(
        MaterialApp(
          home: AfterArrival(
            builder: (_, arrived) {
              _arrived = arrived;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(_arrived, isTrue);
    });

    testWidgets('going back does not make it arrive a second time', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router()));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      GoRouter.of(tester.element(find.text('arrived'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_arrived, isTrue, reason: 'leaving is not arriving');
    });
  });
}
