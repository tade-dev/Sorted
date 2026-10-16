import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/motion_access.dart';
import 'package:sorted/core/motion/press_scale.dart';

Widget _host({bool reduce = false, bool enabled = true, VoidCallback? onTap}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: PressScale(
            enabled: enabled,
            onTap: onTap,
            // Opaque, because PressScale defers hit testing to its child:
          // a decorator should only feel presses where its child paints.
          child: const ColoredBox(
            key: Key('target'),
            color: Color(0xFF111111),
            child: SizedBox(width: 120, height: 48),
          ),
          ),
        ),
      ),
    );

/// The scale PressScale is currently applying to its child.
double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

Curve _curve(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).curve;

void main() {
  group('PressScale press feedback', () {
    testWidgets('rests at full size', (tester) async {
      await tester.pumpWidget(_host());
      expect(_scale(tester), 1.0);
    });

    testWidgets('shrinks under a finger', (tester) async {
      await tester.pumpWidget(_host());
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump();
      expect(_scale(tester), lessThan(1.0));
      await gesture.up();
    });

    testWidgets('shrinks under a mouse too, so web and desktop get feedback', (tester) async {
      // The old implementation gated on PointerDeviceKind.touch, which meant
      // every click in the web build — the one judges will use — felt dead.
      await tester.pumpWidget(_host());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('target'))),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(_scale(tester), lessThan(1.0));
      await gesture.up();
    });

    testWidgets('springs back on release', (tester) async {
      await tester.pumpWidget(_host());
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(_scale(tester), 1.0);
      expect(_curve(tester), same(SortedSprings.snappy));
    });

    testWidgets('releases when a scroll steals the gesture', (tester) async {
      // Press a row, then drag to scroll: the pointer never comes up here, it
      // is cancelled. Without this the row stays visibly squashed.
      await tester.pumpWidget(_host());
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump();
      expect(_scale(tester), lessThan(1.0));
      await gesture.cancel();
      await tester.pump();
      expect(_scale(tester), 1.0);
    });

    testWidgets('presses in faster than it releases', (tester) async {
      // Going down should feel like direct manipulation; coming back up is
      // where the spring gets to show off.
      await tester.pumpWidget(_host());
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump();
      final down = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration;
      await gesture.up();
      await tester.pump();
      final up = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration;
      expect(down, lessThan(up));
    });
  });

  group('PressScale restraint', () {
    testWidgets('stays still when disabled', (tester) async {
      await tester.pumpWidget(_host(enabled: false));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump();
      expect(_scale(tester), 1.0);
      await gesture.up();
    });

    testWidgets('stays still under reduced motion', (tester) async {
      // Scale is movement, and movement is exactly what the setting removes.
      await tester.pumpWidget(_host(reduce: true));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump();
      expect(_scale(tester), 1.0);
      await gesture.up();
    });
  });

  group('PressScale as a tappable', () {
    testWidgets('fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(onTap: () => taps++));
      await tester.tap(find.byKey(const Key('target')));
      expect(taps, 1);
    });

    testWidgets('is a button to a screen reader when it has an onTap', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(onTap: () {}));
      expect(
        tester.getSemantics(find.byKey(const Key('target'))),
        matchesSemantics(isButton: true, hasTapAction: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('adds no semantics when it only decorates an existing tappable', (tester) async {
      // Wrapping a ListTile must not announce "button" twice.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host());
      expect(find.byType(Semantics), findsNothing);
      handle.dispose();
    });

    testWidgets('does not fire onTap when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(enabled: false, onTap: () => taps++));
      await tester.tap(find.byKey(const Key('target')), warnIfMissed: false);
      expect(taps, 0);
    });
  });
}
