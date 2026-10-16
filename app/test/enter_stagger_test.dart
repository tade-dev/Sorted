import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/enter_stagger.dart';
import 'package:sorted/core/motion/motion_access.dart';

Widget _host({required int index, bool reduce = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: EnterStagger(
          index: index,
          child: const ColoredBox(
            key: Key('row'),
            color: Color(0xFF111111),
            child: SizedBox(width: 120, height: 48),
          ),
        ),
      ),
    );

/// Starts the animation without finishing it.
///
/// flutter_animate kicks every Animate off with `Future.delayed`, even when
/// the delay is zero, so a test that only pumps one frame leaves that timer
/// pending and fails teardown. One millisecond fires it and leaves the
/// animation barely begun, which is what these tests want to look at.
Future<void> _begin(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 1));

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

/// How far the row is currently offset from its resting place.
double _offsetY(WidgetTester tester) {
  final transforms = find.byType(Transform).evaluate();
  if (transforms.isEmpty) return 0;
  return (transforms.first.widget as Transform).transform.getTranslation().y;
}

void main() {
  group('EnterStagger scheduling', () {
    test('the first row does not wait', () {
      expect(EnterStagger.delayFor(0), Duration.zero);
    });

    test('each row follows the one above it', () {
      expect(EnterStagger.delayFor(1), SortedDurations.stagger);
      expect(EnterStagger.delayFor(3), SortedDurations.stagger * 3);
      expect(EnterStagger.delayFor(1), lessThan(EnterStagger.delayFor(2)));
    });

    test('the delay saturates, so a long list never queues behind itself', () {
      // Without a ceiling, row 60 of an order list would wait 2.7 seconds for
      // its turn. The delay stops growing; the animation still happens.
      final capped = EnterStagger.delayFor(EnterStagger.maxSteps);
      expect(EnterStagger.delayFor(60), capped);
      expect(EnterStagger.delayFor(500), capped);
      expect(capped.inMilliseconds, lessThan(700));
    });
  });

  group('EnterStagger entrance', () {
    testWidgets('a row starts invisible and below its place', (tester) async {
      await tester.pumpWidget(_host(index: 0));
      await _begin(tester);
      expect(_opacity(tester), lessThan(1.0));
      expect(_offsetY(tester), greaterThan(0));
    });

    testWidgets('it settles fully visible and in place', (tester) async {
      await tester.pumpWidget(_host(index: 0));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
      expect(_offsetY(tester), moreOrLessEquals(0, epsilon: 0.01));
    });

    testWidgets('rows far down the list still animate', (tester) async {
      // The previous version bailed out at index >= 6 and returned the child
      // untouched, so row 7 of a list snapped in at full opacity while rows
      // 1-6 faded. A seven-order seller saw one row pop.
      await tester.pumpWidget(_host(index: 40));
      await _begin(tester);
      expect(find.byType(FadeTransition), findsOneWidget);
      expect(_opacity(tester), lessThan(1.0));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
    });
  });

  group('EnterStagger under reduced motion', () {
    testWidgets('fades without moving', (tester) async {
      await tester.pumpWidget(_host(index: 2, reduce: true));
      await _begin(tester);
      expect(_opacity(tester), lessThan(1.0));
      expect(_offsetY(tester), 0);
    });

    testWidgets('still ends up visible', (tester) async {
      await tester.pumpWidget(_host(index: 2, reduce: true));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
    });
  });
}
