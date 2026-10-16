import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final push = sortedPushPage(null, const SizedBox.shrink());
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
}
