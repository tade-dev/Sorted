import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/reveal.dart';

Widget _host({bool reduce = false, String trailing = ''}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            const Reveal(
              child: ColoredBox(
                key: Key('group'),
                color: Color(0xFF111111),
                child: SizedBox(width: 120, height: 48),
              ),
            ),
            Text(trailing),
          ],
        ),
      ),
    );

Future<void> _begin(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 1));

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

double _offsetY(WidgetTester tester) {
  final transforms = find.byType(Transform).evaluate();
  if (transforms.isEmpty) return 0;
  return (transforms.first.widget as Transform).transform.getTranslation().y;
}

void main() {
  group('Reveal', () {
    testWidgets('the group arrives from below, faded', (tester) async {
      await tester.pumpWidget(_host());
      await _begin(tester);
      expect(_opacity(tester), lessThan(1.0));
      expect(_offsetY(tester), greaterThan(0));
    });

    testWidgets('and settles in place', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
      expect(_offsetY(tester), moreOrLessEquals(0, epsilon: 0.01));
    });

    testWidgets('travels further than a list row, being the whole group',
        (tester) async {
      await tester.pumpWidget(_host());
      await _begin(tester);
      expect(_offsetY(tester), greaterThan(10));
    });

    testWidgets('plays once, not on every rebuild', (tester) async {
      // A screen whose provider ticks would otherwise re-reveal its own
      // header every time anything changed.
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      await tester.pumpWidget(_host(trailing: 'something else changed'));
      await _begin(tester);
      expect(_opacity(tester), 1.0);
      expect(_offsetY(tester), moreOrLessEquals(0, epsilon: 0.01));
    });

    testWidgets('keeps its child', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('group')), findsOneWidget);
    });
  });

  group('Reveal under reduced motion', () {
    testWidgets('fades without moving', (tester) async {
      await tester.pumpWidget(_host(reduce: true));
      await _begin(tester);
      expect(_opacity(tester), lessThan(1.0));
      expect(_offsetY(tester), 0);
    });

    testWidgets('still ends up visible', (tester) async {
      await tester.pumpWidget(_host(reduce: true));
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1.0);
    });
  });
}
