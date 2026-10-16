import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/paid_pop.dart';

Widget _host({required bool paid, bool reduce = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: PaidPop(
            paid: paid,
            child: const ColoredBox(
              key: Key('card'),
              color: Color(0xFF111111),
              child: SizedBox(width: 200, height: 90),
            ),
          ),
        ),
      ),
    );

/// The card's painted width, which tracks the pop.
double _painted(WidgetTester tester) {
  final card = find.byKey(const Key('card'));
  return (tester.getBottomRight(card) - tester.getTopLeft(card)).dx;
}

/// The largest the card gets over the next half second.
Future<double> _peak(WidgetTester tester) async {
  var peak = _painted(tester);
  for (var i = 0; i < 32; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final w = _painted(tester);
    if (w > peak) peak = w;
  }
  return peak;
}

void main() {
  group('PaidPop', () {
    testWidgets('an order that was already paid does not pop on arrival',
        (tester) async {
      // Opening the Orders tab should not set every paid card off.
      await tester.pumpWidget(_host(paid: true));
      final resting = _painted(tester);
      expect(await _peak(tester), moreOrLessEquals(resting, epsilon: 0.01));
    });

    testWidgets('pops when payment lands while the card is on screen',
        (tester) async {
      await tester.pumpWidget(_host(paid: false));
      await tester.pumpAndSettle();
      final resting = _painted(tester);

      await tester.pumpWidget(_host(paid: true));
      await tester.pump(const Duration(milliseconds: 1));
      expect(await _peak(tester), greaterThan(resting));
    });

    testWidgets('and settles back to its own size', (tester) async {
      await tester.pumpWidget(_host(paid: false));
      await tester.pumpAndSettle();
      final resting = _painted(tester);

      await tester.pumpWidget(_host(paid: true));
      await tester.pumpAndSettle();
      expect(_painted(tester), moreOrLessEquals(resting, epsilon: 0.01));
    });

    testWidgets('pops once, not on every later rebuild', (tester) async {
      await tester.pumpWidget(_host(paid: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(paid: true));
      await tester.pumpAndSettle();
      final resting = _painted(tester);

      await tester.pumpWidget(_host(paid: true));
      expect(await _peak(tester), moreOrLessEquals(resting, epsilon: 0.01));
    });

    testWidgets('keeps its child', (tester) async {
      await tester.pumpWidget(_host(paid: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('card')), findsOneWidget);
    });
  });

  group('PaidPop under reduced motion', () {
    testWidgets('does not pop', (tester) async {
      // The haptic and the screen-reader announcement still happen; those are
      // PaidAnnouncer's job and are not motion.
      await tester.pumpWidget(_host(paid: false, reduce: true));
      await tester.pumpAndSettle();
      final resting = _painted(tester);

      await tester.pumpWidget(_host(paid: true, reduce: true));
      await tester.pump(const Duration(milliseconds: 1));
      expect(await _peak(tester), moreOrLessEquals(resting, epsilon: 0.01));
    });
  });
}
