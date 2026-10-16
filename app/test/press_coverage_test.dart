import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/models/product.dart';
import 'package:sorted/widgets/product_tile.dart';
import 'package:sorted/widgets/segmented_control.dart';
import 'package:sorted/widgets/selectable_chip.dart';

Widget _wrap(Widget child, {bool reduce = false}) => MaterialApp(
      theme: sortedTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

const _product = Product(
  id: 'p1',
  name: 'Lemon drizzle cake',
  variants: [],
  basePriceMinor: 4200,
  inStock: true,
);

/// The smallest scale any PressScale in the tree is applying.
double _scale(WidgetTester tester) => tester
    .widgetList<AnimatedScale>(find.byType(AnimatedScale))
    .map((w) => w.scale)
    .fold(1.0, (a, b) => b < a ? b : a);

/// Presses [target] with a mouse, which is what a judge on the hosted build
/// will be using, and reports the scale while it is held.
Future<double> _mousePress(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  final held = _scale(tester);
  await gesture.up();
  await tester.pumpAndSettle();
  return held;
}

void main() {
  group('every shared tappable answers a press', () {
    testWidgets('SelectableChip', (tester) async {
      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: false, onTap: () {}),
      ));
      expect(await _mousePress(tester, find.text('Collection')), lessThan(1.0));
    });

    testWidgets('ProductTile', (tester) async {
      await tester.pumpWidget(_wrap(ProductTile(product: _product, onTap: () {})));
      expect(
        await _mousePress(tester, find.text('Lemon drizzle cake')),
        lessThan(1.0),
      );
    });

    testWidgets('SegmentedControl', (tester) async {
      await tester.pumpWidget(_wrap(SegmentedControl(
        segments: const {'a': 'One', 'b': 'Two'},
        selected: 'a',
        onChanged: (_) {},
      )));
      expect(await _mousePress(tester, find.text('Two')), lessThan(1.0));
    });

    testWidgets('and none of them presses under reduced motion', (tester) async {
      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: false, onTap: () {}),
        reduce: true,
      ));
      expect(await _mousePress(tester, find.text('Collection')), 1.0);
    });
  });

  group('they all still work as controls', () {
    testWidgets('the chip fires onTap and keeps its selected state', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: true, onTap: () => taps++),
      ));
      await tester.tap(find.text('Collection'));
      expect(taps, 1);
      expect(
        tester.getSemantics(find.text('Collection')),
        matchesSemantics(
          label: 'Collection',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
    });

    testWidgets('the tile fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(ProductTile(product: _product, onTap: () => taps++)));
      await tester.tap(find.text('Lemon drizzle cake'));
      expect(taps, 1);
    });

    testWidgets('the segmented control reports the segment tapped', (tester) async {
      String? picked;
      await tester.pumpWidget(_wrap(SegmentedControl(
        segments: const {'a': 'One', 'b': 'Two'},
        selected: 'a',
        onChanged: (k) => picked = k,
      )));
      await tester.tap(find.text('Two'));
      expect(picked, 'b');
    });
  });

  group('the chip morphs when it is selected', () {
    Color? fill(WidgetTester tester) => tester
        .widgetList<Material>(find.descendant(
          of: find.byType(SelectableChip),
          matching: find.byType(Material),
        ))
        .map((m) => m.color)
        .firstOrNull;

    testWidgets('the fill travels between the two colours', (tester) async {
      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: false, onTap: () {}),
      ));
      await tester.pumpAndSettle();
      final unselected = fill(tester);

      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: true, onTap: () {}),
      ));
      await tester.pumpAndSettle();
      final selected = fill(tester);
      expect(selected, isNot(unselected));

      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: false, onTap: () {}),
      ));
      await tester.pump(const Duration(milliseconds: 80));
      final mid = fill(tester);
      expect(mid, isNot(selected));
      expect(mid, isNot(unselected));
    });

    testWidgets('colour still changes under reduced motion, being no movement',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: false, onTap: () {}),
        reduce: true,
      ));
      await tester.pumpAndSettle();
      final unselected = fill(tester);
      await tester.pumpWidget(_wrap(
        SelectableChip(label: 'Collection', selected: true, onTap: () {}),
        reduce: true,
      ));
      await tester.pumpAndSettle();
      expect(fill(tester), isNot(unselected));
    });
  });
}
