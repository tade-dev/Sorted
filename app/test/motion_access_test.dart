import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/motion_access.dart';

Widget _host({required bool reduce, required Widget child}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  group('Motion.reduced', () {
    testWidgets('is false by default', (tester) async {
      late bool seen;
      await tester.pumpWidget(_host(
        reduce: false,
        child: Builder(builder: (c) {
          seen = Motion.reduced(c);
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, isFalse);
    });

    testWidgets('follows the platform accessibility setting', (tester) async {
      late bool seen;
      await tester.pumpWidget(_host(
        reduce: true,
        child: Builder(builder: (c) {
          seen = Motion.reduced(c);
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, isTrue);
    });
  });

  group('Motion.move', () {
    testWidgets('passes the distance through normally', (tester) async {
      late double d;
      await tester.pumpWidget(_host(
        reduce: false,
        child: Builder(builder: (c) {
          d = Motion.move(c, 12);
          return const SizedBox.shrink();
        }),
      ));
      expect(d, 12);
    });

    testWidgets('drops movement to zero under reduce, keeping the fade', (tester) async {
      // The accessibility intent is no vestibular motion, not fast motion.
      // Translation, scale and rotation go; opacity stays.
      late double d;
      await tester.pumpWidget(_host(
        reduce: true,
        child: Builder(builder: (c) {
          d = Motion.move(c, 12);
          return const SizedBox.shrink();
        }),
      ));
      expect(d, 0);
    });
  });

  group('Motion.duration', () {
    testWidgets('passes the duration through normally', (tester) async {
      late Duration out;
      await tester.pumpWidget(_host(
        reduce: false,
        child: Builder(builder: (c) {
          out = Motion.duration(c, const Duration(milliseconds: 300));
          return const SizedBox.shrink();
        }),
      ));
      expect(out.inMilliseconds, 300);
    });

    testWidgets('shortens rather than removes it, so fades still read', (tester) async {
      // Zero duration makes everything snap, which is the lazy reading of the
      // setting. A short cross-fade is both calmer and clearer.
      late Duration out;
      await tester.pumpWidget(_host(
        reduce: true,
        child: Builder(builder: (c) {
          out = Motion.duration(c, const Duration(milliseconds: 300));
          return const SizedBox.shrink();
        }),
      ));
      expect(out, Motion.reducedDuration);
      expect(out.inMilliseconds, greaterThan(0));
      expect(out.inMilliseconds, lessThan(300));
    });
  });

  group('Motion.curve', () {
    testWidgets('gives a spring normally and a plain ease under reduce', (tester) async {
      late Curve normal;
      late Curve reduced;
      await tester.pumpWidget(_host(
        reduce: false,
        child: Builder(builder: (c) {
          normal = Motion.curve(c, SortedSprings.bouncy);
          return const SizedBox.shrink();
        }),
      ));
      await tester.pumpWidget(_host(
        reduce: true,
        child: Builder(builder: (c) {
          reduced = Motion.curve(c, SortedSprings.bouncy);
          return const SizedBox.shrink();
        }),
      ));

      expect(normal, same(SortedSprings.bouncy));
      // A bouncing opacity is still vestibularly calm, but overshoot past 1.0
      // on a fade clamps and looks like a stutter.
      expect(reduced, isNot(same(SortedSprings.bouncy)));
      expect(reduced.transform(0.5), lessThanOrEqualTo(1.0));
    });
  });
}
