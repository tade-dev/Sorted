import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/widgets/money_roll.dart';

Widget _wrap(int minor, {bool reduce = false}) => MaterialApp(
      theme: sortedTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: MoneyRoll(amountMinor: minor))),
      ),
    );

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('MoneyRoll', () {
    testWidgets('shows the amount in pounds', (tester) async {
      await tester.pumpWidget(_wrap(4600));
      await tester.pumpAndSettle();
      expect(find.text('£46.00'), findsOneWidget);
    });

    testWidgets('does not roll in from nowhere on the first build', (tester) async {
      // A total appearing for the first time has not changed, so it should
      // just be the total.
      await tester.pumpWidget(_wrap(4600));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('a total going up brings the new figure from below', (tester) async {
      // Answering an ambiguity on the Draft screen takes £46 to £56. Which
      // way it rolls is the whole message: something was added.
      await tester.pumpWidget(_wrap(4600));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(5600));
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('£46.00'), findsOneWidget);
      expect(find.text('£56.00'), findsOneWidget);
      expect(_y(tester, '£56.00'), greaterThan(_y(tester, '£46.00')));
    });

    testWidgets('a total coming down brings it from above', (tester) async {
      await tester.pumpWidget(_wrap(5600));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(4600));
      await tester.pump(const Duration(milliseconds: 60));

      expect(_y(tester, '£46.00'), lessThan(_y(tester, '£56.00')));
    });

    testWidgets('settles on the new figure alone', (tester) async {
      await tester.pumpWidget(_wrap(4600));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(5600));
      await tester.pumpAndSettle();
      expect(find.text('£56.00'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('an unchanged amount does not roll', (tester) async {
      await tester.pumpWidget(_wrap(4600));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(4600));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('MoneyRoll under reduced motion', () {
    testWidgets('cross-fades in place instead of rolling', (tester) async {
      await tester.pumpWidget(_wrap(4600, reduce: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(5600, reduce: true));
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('£46.00'), findsOneWidget);
      expect(find.text('£56.00'), findsOneWidget);
      expect(_y(tester, '£56.00'), _y(tester, '£46.00'));
    });

    testWidgets('still arrives at the new figure', (tester) async {
      await tester.pumpWidget(_wrap(4600, reduce: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap(5600, reduce: true));
      await tester.pumpAndSettle();
      expect(find.text('£56.00'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });
  });
}
