import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/motion/page_transitions.dart';

typedef _Transition = Widget Function(
    BuildContext, Animation<double>, Animation<double>, Widget);

/// Renders [builder] frozen at a point in the transition, so the test can ask
/// where the page actually ended up on screen.
Future<void> _at(
  WidgetTester tester,
  _Transition builder, {
  required double t,
  double secondary = 0,
  bool reduce = false,
}) =>
    tester.pumpWidget(MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => builder(
            context,
            AlwaysStoppedAnimation(t),
            AlwaysStoppedAnimation(secondary),
            const ColoredBox(key: Key('page'), color: Color(0xFF111111)),
          ),
        ),
      ),
    ));

/// Where the page is actually painted.
///
/// Measured from two transformed corners rather than `getSize`, which reports
/// the layout size and so cannot see a scale at all.
Rect _rect(WidgetTester tester) {
  final page = find.byKey(const Key('page'));
  return Rect.fromPoints(tester.getTopLeft(page), tester.getBottomRight(page));
}

Offset _where(WidgetTester tester) => _rect(tester).topLeft;

Size _screen(WidgetTester tester) => tester.getSize(find.byType(Directionality));

/// Everything the transition is doing to opacity, combined.
double _opacity(WidgetTester tester) => find
    .byType(FadeTransition)
    .evaluate()
    .map((e) => (e.widget as FadeTransition).opacity.value)
    .fold(1.0, (a, b) => a * b);

void main() {
  group('push: a shared horizontal axis', () {
    testWidgets('the incoming page starts off to the right and faded', (tester) async {
      await _at(tester, sortedPushTransition, t: 0);
      expect(_where(tester).dx, greaterThan(0));
      expect(_opacity(tester), lessThan(1.0));
    });

    testWidgets('and lands exactly in place', (tester) async {
      await _at(tester, sortedPushTransition, t: 1);
      expect(_where(tester), Offset.zero);
      expect(_opacity(tester), 1.0);
    });

    testWidgets('the outgoing page goes the same way, less far', (tester) async {
      // Same axis, same direction: that is what makes a push read as one
      // surface moving rather than two unrelated screens.
      await _at(tester, sortedPushTransition, t: 1, secondary: 1);
      final out = _where(tester);
      await _at(tester, sortedPushTransition, t: 0);
      final incoming = _where(tester);
      expect(out.dx, lessThan(0));
      expect(out.dx.abs(), lessThan(incoming.dx.abs()));
      expect(out.dy, 0);
    });

    testWidgets('it never moves vertically', (tester) async {
      await _at(tester, sortedPushTransition, t: 0.4);
      expect(_where(tester).dy, 0);
    });

    testWidgets('under reduced motion it only cross-fades', (tester) async {
      await _at(tester, sortedPushTransition, t: 0.3, reduce: true);
      expect(_where(tester), Offset.zero);
      expect(_opacity(tester), lessThan(1.0));
      await _at(tester, sortedPushTransition, t: 1, reduce: true);
      expect(_opacity(tester), 1.0);
    });
  });

  group('tab: fade through, no axis', () {
    testWidgets('tabs are peers, so nothing slides sideways', (tester) async {
      // It may scale, which moves its corners, but its centre must not drift.
      await _at(tester, sortedTabTransition, t: 0.2);
      expect(_rect(tester).center.dx,
          moreOrLessEquals(_screen(tester).width / 2, epsilon: 0.01));
    });

    testWidgets('the incoming tab grows very slightly into place', (tester) async {
      await _at(tester, sortedTabTransition, t: 0);
      final start = _rect(tester).width;
      await _at(tester, sortedTabTransition, t: 1);
      final end = _rect(tester).width;
      expect(start, lessThan(end));
      // A hint, not a zoom: more than a few percent looks like a bad modal.
      expect(start / end, greaterThan(0.95));
      expect(_opacity(tester), 1.0);
    });

    testWidgets('under reduced motion it holds its size', (tester) async {
      await _at(tester, sortedTabTransition, t: 0, reduce: true);
      final start = _rect(tester).width;
      await _at(tester, sortedTabTransition, t: 1, reduce: true);
      expect(_rect(tester).width, start);
    });
  });

  group('sheet: up from the bottom', () {
    testWidgets('it starts below the screen', (tester) async {
      await _at(tester, sortedSheetTransition, t: 0);
      expect(_where(tester).dy, greaterThanOrEqualTo(_screen(tester).height));
    });

    testWidgets('and settles at the top', (tester) async {
      await _at(tester, sortedSheetTransition, t: 1);
      expect(_where(tester), Offset.zero);
    });

    testWidgets('it never moves sideways', (tester) async {
      await _at(tester, sortedSheetTransition, t: 0.5);
      expect(_where(tester).dx, 0);
    });

    testWidgets('under reduced motion it fades in where it will sit', (tester) async {
      await _at(tester, sortedSheetTransition, t: 0.3, reduce: true);
      expect(_where(tester), Offset.zero);
      expect(_opacity(tester), lessThan(1.0));
    });
  });

  group('the pages wire the transitions up', () {
    test('each kind gets its own duration, and reverse is quicker', () {
      // Off iOS, which is where `flutter test` runs, the push is still a
      // CustomTransitionPage. The iOS route has its own test below.
      final push =
          sortedPushPage(null, const SizedBox.shrink()) as CustomTransitionPage<void>;
      final tab = sortedTabPage(null, const SizedBox.shrink());
      final sheet = sortedSheetPage(null, const SizedBox.shrink());

      for (final page in [push, tab, sheet]) {
        expect(page.transitionDuration.inMilliseconds, greaterThan(0));
        expect(page.reverseTransitionDuration, lessThanOrEqualTo(page.transitionDuration));
      }
      // Going back should feel like undoing, not like a second journey.
      expect(tab.transitionDuration, lessThan(push.transitionDuration));
    });
  });

  group('driven through a real router', () {
    // The tests above drive the transition functions directly. These check
    // the other half: that a page built by sortedPushPage actually animates
    // when a Navigator pushes it, rather than the builder being wired up
    // somewhere it never runs.
    Widget app(GoRouter router) => MaterialApp.router(routerConfig: router);

    GoRouter routerFor(
      Page<void> Function(GoRouterState?, Widget) second,
    ) =>
        GoRouter(routes: [
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
            pageBuilder: (_, s) => second(
              s,
              const Scaffold(
                body: ColoredBox(
                  key: Key('second'),
                  color: Color(0xFF111111),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ]);

    testWidgets('a push really travels, and arrives', (tester) async {
      await tester.pumpWidget(app(routerFor(sortedPushPage)));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final midway = tester.getTopLeft(find.byKey(const Key('second'))).dx;
      expect(midway, greaterThan(0), reason: 'still on its way in');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const Key('second'))).dx, 0);
    });

    testWidgets('a sheet really rises, and arrives', (tester) async {
      await tester.pumpWidget(app(routerFor(sortedSheetPage)));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final sheet = find.byKey(const Key('second'));
      expect(tester.getTopLeft(sheet).dy, greaterThan(0));
      expect(tester.getTopLeft(sheet).dx, 0, reason: 'a sheet has no sideways');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(sheet), Offset.zero);
    });

    testWidgets('popping takes it back off the way it came', (tester) async {
      await tester.pumpWidget(app(routerFor(sortedPushPage)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(const Key('second')));
      GoRouter.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(find.byKey(const Key('second'))).dx, greaterThan(0));

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('second')), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });
  });

  group('iOS keeps its back-swipe', () {
    // Reset inside each body: flutter_test checks the foundation debug vars
    // when the body returns, before tearDown gets a turn.
    testWidgets('a pushed page is a route that can be swiped back',
        (tester) async {
      // iOS hands you an edge swipe on every pushed screen and people reach
      // for it without thinking. It comes from Cupertino's own route, so a
      // plain CustomTransitionPage takes it away silently.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final page = sortedPushPage(null, const SizedBox.shrink());
      expect(page, isNot(isA<CustomTransitionPage<void>>()));

      late Route<void> route;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          route = page.createRoute(context);
          return const SizedBox.shrink();
        }),
      ));
      // The gesture comes from this mixin; popGestureEnabled itself cannot
      // be asked until the route is installed in a Navigator.
      expect(route, isA<CupertinoRouteTransitionMixin<void>>());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('and still travels our way, not Cupertino\'s', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // Keeping the gesture did not mean accepting the full-width native
      // slide: the page comes in on the shared axis, a fraction of the way.
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => TextButton(
              onPressed: () => context.push('/next'),
              child: const Text('go'),
            ),
          ),
          GoRoute(
            path: '/next',
            pageBuilder: (_, s) => sortedPushPage(
              s,
              const ColoredBox(
                key: Key('pushed'),
                color: Color(0xFF111111),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ]),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final width = tester.getSize(find.byType(MaterialApp)).width;
      final x = tester.getTopLeft(find.byKey(const Key('pushed'))).dx;
      expect(x, greaterThan(0), reason: 'still on its way in');
      expect(x, lessThan(width * 0.5),
          reason: 'our 18% travel, not a full-width native slide');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const Key('pushed'))).dx, 0);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
