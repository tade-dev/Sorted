import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/motion/sorted_motion.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/onboarding/welcome_screen.dart';
import 'package:sorted/widgets/sorted_stamp.dart';

/// Welcome, reached the way Home sends a new seller to it: a real route
/// arriving over another, so there is a push to wait for.
Widget _host({bool reduce = false}) => ProviderScope(
  child: MaterialApp.router(
    theme: sortedTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: child!,
    ),
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => context.go('/welcome'),
                child: const Text('first launch'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/welcome',
          pageBuilder: (_, s) => sortedPushPage(s, const WelcomeScreen()),
        ),
      ],
    ),
  ),
);

final _slip = find.text('Order for Jess');
final _stamp = find.byType(SortedStamp);

double _opacity(WidgetTester tester, Finder target) => find
    .ancestor(of: target, matching: find.byType(FadeTransition))
    .evaluate()
    .map((e) => (e.widget as FadeTransition).opacity.value)
    .fold(1.0, (a, b) => a * b);

/// Real frames, so each animation starts its clock on a frame of its own.
Future<void> _frames(WidgetTester tester, Duration span) async {
  for (var i = 0; i < span.inMilliseconds ~/ 16; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _open(WidgetTester tester, {bool reduce = false}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(reduce: reduce));
  await tester.tap(find.text('first launch'));
  await tester.pump();
}

void main() {
  group('Welcome: the slip is put down, then stamped', () {
    testWidgets(
      'while the page is arriving the slip waits and nothing is stamped',
      (tester) async {
        await _open(tester);
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          find.text('From DM to paid.'),
          findsOneWidget,
          reason: 'the words come with the page',
        );
        expect(_opacity(tester, _slip), 0);
        expect(_stamp, findsNothing);
      },
    );

    testWidgets('once the page is still the slip lands, unstamped', (
      tester,
    ) async {
      await _open(tester);
      await _frames(tester, SortedDurations.medium + SortedDurations.short);
      expect(_opacity(tester, _slip), greaterThan(0));
      expect(_stamp, findsNothing, reason: 'the paper is still moving');
    });

    testWidgets('and the stamp hits it only after it has come to rest', (
      tester,
    ) async {
      await _open(tester);
      await _frames(
        tester,
        SortedDurations.medium + SortedDurations.long + SortedDurations.short,
      );
      expect(_stamp, findsOneWidget);
      await tester.pumpAndSettle();
      expect(_opacity(tester, _slip), 1);
    });

    testWidgets(
      'under reduced motion the slip fades and the stamp is just there',
      (tester) async {
        await _open(tester, reduce: true);
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          _stamp,
          findsOneWidget,
          reason: 'the stamp is design, not motion',
        );
        await tester.pumpAndSettle();
        expect(_opacity(tester, _slip), 1);
      },
    );
  });
}
