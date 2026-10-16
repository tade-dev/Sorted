import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/orders/status_pill.dart';

Widget _wrap(String status, {bool reduce = false}) => MaterialApp(
      theme: sortedTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: StatusPill(status: status))),
      ),
    );

Color? _pillColour(WidgetTester tester) {
  final box = tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((w) => w.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.borderRadius != null)
      .firstOrNull;
  return box?.color;
}

/// The painted width of the pill, which changes as the label does.
double _width(WidgetTester tester) {
  final pill = find.byType(StatusPill);
  return tester.getBottomRight(pill).dx - tester.getTopLeft(pill).dx;
}

void main() {
  testWidgets('it is a chip wherever it is put, not a bar in a Column',
      (tester) async {
    // A Row hands its children unbounded width, so the pill shrink-wrapped
    // there and nobody noticed that in a Column — Order detail — the same
    // pill stretched the full width as a green bar.
    await tester.pumpWidget(MaterialApp(
      theme: sortedTheme(),
      home: const Scaffold(
        body: SizedBox(
          width: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [StatusPill(status: 'paid', key: Key('inRow'))]),
              StatusPill(status: 'paid', key: Key('inColumn')),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final inRow = tester.getSize(find.byKey(const Key('inRow')));
    expect(tester.getSize(find.byKey(const Key('inColumn'))), inRow);
    expect(inRow.width, lessThan(200));
  });

  group('StatusPill morph', () {
    testWidgets('both labels are on screen mid-morph, cross-fading', (tester) async {
      await tester.pumpWidget(_wrap('link_sent'));
      await tester.pumpWidget(_wrap('paid'));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(Text), findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('the background tweens rather than cutting', (tester) async {
      await tester.pumpWidget(_wrap('link_sent'));
      final before = _pillColour(tester);
      await tester.pumpWidget(_wrap('paid'));
      await tester.pumpAndSettle();
      final after = _pillColour(tester);
      expect(before, isNotNull);
      expect(after, isNot(before));

      // Half way through, the colour is somewhere between the two.
      await tester.pumpWidget(_wrap('link_sent'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap('paid'));
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _pillColour(tester);
      expect(mid, isNot(before));
      expect(mid, isNot(after));
    });

    testWidgets('the pill resizes to fit the new label', (tester) async {
      await tester.pumpWidget(_wrap('paid'));
      await tester.pumpAndSettle();
      final short = _width(tester);
      await tester.pumpWidget(_wrap('awaiting_deposit'));
      await tester.pumpAndSettle();
      expect(_width(tester), greaterThan(short));
    });
  });

  group('StatusPill under reduced motion', () {
    testWidgets('resizes instantly, because a width has nothing to fade',
        (tester) async {
      // Movement goes and the cross-fade stays. A pill stretching open is
      // movement, and unlike opacity there is no gentler version of it, so it
      // happens at once.
      await tester.pumpWidget(_wrap('paid', reduce: true));
      await tester.pumpAndSettle();
      final short = _width(tester);
      await tester.pumpWidget(_wrap('awaiting_deposit', reduce: true));
      await tester.pump();
      expect(_width(tester), greaterThan(short));
    });

    testWidgets('still cross-fades the label', (tester) async {
      await tester.pumpWidget(_wrap('link_sent', reduce: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap('paid', reduce: true));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(Text), findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('does not scale the arriving label', (tester) async {
      await tester.pumpWidget(_wrap('link_sent', reduce: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_wrap('paid', reduce: true));
      await tester.pump(const Duration(milliseconds: 40));
      // Scoped to the pill: the Scaffold has a ScaleTransition of its own for
      // the floating action button, and it sits at 0 the whole time.
      final inPill = find.descendant(
        of: find.byType(StatusPill),
        matching: find.byType(ScaleTransition),
      );
      expect(inPill, findsWidgets);
      for (final t in tester.widgetList<ScaleTransition>(inPill)) {
        expect(t.scale.value, 1.0);
      }
    });
  });
}
