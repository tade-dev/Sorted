import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/spring_curve.dart';

void main() {
  group('SpringCurve as a Curve', () {
    test('starts at exactly 0', () {
      for (final s in [SortedSprings.gentle, SortedSprings.snappy, SortedSprings.bouncy]) {
        expect(s.transform(0), 0.0);
      }
    });

    test('ends at exactly 1', () {
      // A spring that settles at 0.9998 leaves every animation a hair short of
      // its target, forever. transform(1) must be pinned.
      for (final s in [SortedSprings.gentle, SortedSprings.snappy, SortedSprings.bouncy]) {
        expect(s.transform(1), 1.0);
      }
    });

    test('is a Curve, so flutter_animate effects accept it', () {
      expect(SortedSprings.snappy, isA<Curve>());
    });

    test('bouncy genuinely overshoots past its target', () {
      // This is what makes it a spring rather than an ease. If this fails the
      // curve is damped too hard and the Sorted stamp will land flat.
      var peak = 0.0;
      for (var i = 0; i <= 100; i++) {
        peak = peak > SortedSprings.bouncy.transform(i / 100)
            ? peak
            : SortedSprings.bouncy.transform(i / 100);
      }
      expect(peak, greaterThan(1.0));
    });

    test('gentle settles without a visible bounce', () {
      var peak = 0.0;
      for (var i = 0; i <= 100; i++) {
        final v = SortedSprings.gentle.transform(i / 100);
        if (v > peak) peak = v;
      }
      // Nearly critically damped: a touch of overshoot is fine, a bounce is not.
      expect(peak, lessThan(1.02));
    });

    test('snappy overshoots, but less than bouncy', () {
      double peakOf(Curve c) {
        var peak = 0.0;
        for (var i = 0; i <= 100; i++) {
          final v = c.transform(i / 100);
          if (v > peak) peak = v;
        }
        return peak;
      }

      expect(peakOf(SortedSprings.snappy), greaterThan(1.0));
      expect(peakOf(SortedSprings.snappy), lessThan(peakOf(SortedSprings.bouncy)));
    });

    test('reaches most of the way before it finishes', () {
      // A curve that does nothing until t=0.9 reads as a delay, not motion.
      expect(SortedSprings.snappy.transform(0.5), greaterThan(0.6));
    });

    test('never returns NaN or infinity across its range', () {
      for (final s in [SortedSprings.gentle, SortedSprings.snappy, SortedSprings.bouncy]) {
        for (var i = 0; i <= 200; i++) {
          final v = s.transform(i / 200);
          expect(v.isFinite, isTrue, reason: 'non-finite at t=${i / 200}');
        }
      }
    });
  });

  group('duration honesty', () {
    /// The last t at which the curve is still perceptibly away from its target.
    double lastMovingPoint(Curve c) {
      var last = 0.0;
      for (var i = 0; i <= 500; i++) {
        final t = i / 500;
        if ((c.transform(t) - 1.0).abs() > 0.005) last = t;
      }
      return last;
    }

    test('motion fills most of the duration it is given', () {
      // SpringSimulation.isDone uses a tolerance far tighter than the eye, so
      // normalising against it leaves a long flat tail: a 240ms animation that
      // visually finishes in 145ms makes every duration in the app a lie.
      for (final e in {
        'gentle': SortedSprings.gentle,
        'snappy': SortedSprings.snappy,
        'bouncy': SortedSprings.bouncy,
      }.entries) {
        expect(
          lastMovingPoint(e.value),
          greaterThan(0.6),
          reason: '${e.key} is visually finished before 60% of its duration',
        );
      }
    });

    test('and still arrives, rather than being cut off mid-flight', () {
      for (final s in [SortedSprings.gentle, SortedSprings.snappy, SortedSprings.bouncy]) {
        expect((s.transform(0.95) - 1.0).abs(), lessThan(0.02));
      }
    });
  });
}
