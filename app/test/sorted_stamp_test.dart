import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/widgets/sorted_stamp.dart';

Widget _wrap({bool reduce = false, double degrees = -10}) => MaterialApp(
      theme: sortedTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: SortedStamp(degrees: degrees))),
      ),
    );

/// The stamp's painted width. It is tilted, so this is not its layout width —
/// but it tracks the scale, which is what these tests are watching.
double _painted(WidgetTester tester) {
  final stamp = find.descendant(
    of: find.byType(SortedStamp),
    matching: find.byType(DecoratedBox),
  );
  return (tester.getBottomRight(stamp.first) - tester.getTopLeft(stamp.first)).dx;
}

void main() {
  group('SortedStamp', () {
    testWidgets('lands rather than appears: small, over-full, then settled',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump(const Duration(milliseconds: 1));
      final start = _painted(tester);

      var peak = start;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final w = _painted(tester);
        if (w > peak) peak = w;
      }
      await tester.pumpAndSettle();
      final settled = _painted(tester);

      expect(start, lessThan(settled), reason: 'it should grow into place');
      // The whole point of spending one of the two bouncy springs here.
      expect(peak, greaterThan(settled), reason: 'it should overshoot');
      expect(peak / settled, greaterThan(1.02));
    });

    testWidgets('keeps the design tilt', (tester) async {
      await tester.pumpWidget(_wrap(degrees: -12));
      await tester.pumpAndSettle();
      // Some transform in there rotates. Which one, and whether the scale
      // sits inside or outside it, is the implementation's business.
      final rotated = tester
          .widgetList<Transform>(find.descendant(
            of: find.byType(SortedStamp),
            matching: find.byType(Transform),
          ))
          .any((t) => t.transform.getRotation().storage[1] != 0);
      expect(rotated, isTrue);
    });

    testWidgets('reads "Sorted"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Sorted'), findsOneWidget);
    });
  });

  group('SortedStamp under reduced motion', () {
    testWidgets('is simply there, at full size, from the first frame',
        (tester) async {
      // The tilt stays: it is the design of the mark, not an animation.
      await tester.pumpWidget(_wrap(reduce: true));
      await tester.pump(const Duration(milliseconds: 1));
      final first = _painted(tester);
      await tester.pumpAndSettle();
      expect(_painted(tester), moreOrLessEquals(first, epsilon: 0.01));
    });

    testWidgets('never overshoots', (tester) async {
      await tester.pumpWidget(_wrap(reduce: true));
      await tester.pumpAndSettle();
      final settled = _painted(tester);
      await tester.pumpWidget(_wrap(reduce: true));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_painted(tester), lessThanOrEqualTo(settled + 0.01));
      }
    });
  });
}
