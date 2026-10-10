import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_colors.dart';
import 'package:sorted/core/theme/sorted_shape.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/models/product.dart';
import 'package:sorted/models/variant.dart';
import 'package:sorted/widgets/primary_button.dart';
import 'package:sorted/widgets/product_tile.dart';
import 'package:sorted/widgets/warning_card.dart';

Widget host(Widget child) =>
    MaterialApp(theme: sortedTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('PrimaryButton is at least the design height', (tester) async {
    await tester.pumpWidget(host(PrimaryButton(label: 'Save', onPressed: () {})));
    final size = tester.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(SortedShape.primaryButtonHeight));
  });

  testWidgets('PrimaryButton disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(host(const PrimaryButton(label: 'Save', onPressed: null)));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isFalse);
  });

  testWidgets('WarningCard uses the warning tokens, not arbitrary colours', (tester) async {
    await tester.pumpWidget(host(const WarningCard(message: "Couldn't read a price.")));
    final box = tester.widget<Container>(find.byType(Container).first);
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, SortedColors.light.warningTint);
    expect(find.text("Couldn't read a price."), findsOneWidget);
  });

  testWidgets('ProductTile shows "from" only when there is a choice', (tester) async {
    const twoSizes = Product(
      id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200,
      variants: [
        Variant(id: 'a', axis: 'size', label: '8 inch', priceDeltaMinor: 0),
        Variant(id: 'b', axis: 'size', label: '10 inch', priceDeltaMinor: 1000),
      ],
    );
    await tester.pumpWidget(host(const ProductTile(product: twoSizes)));
    expect(find.text('from £32.00'), findsOneWidget);
    expect(find.textContaining('8 inch'), findsOneWidget);
  });

  testWidgets('ProductTile shows an exact price for a single variant', (tester) async {
    const oneSize = Product(
      id: 'p2', name: 'Red velvet cake', basePriceMinor: 3600,
      variants: [Variant(id: 'a', axis: 'size', label: '8 inch', priceDeltaMinor: 0)],
    );
    await tester.pumpWidget(host(const ProductTile(product: oneSize)));
    expect(find.text('£36.00'), findsOneWidget);
    expect(find.text('from £36.00'), findsNothing);
  });

  testWidgets('ProductTile surfaces a deposit', (tester) async {
    const withDeposit = Product(
      id: 'p3', name: 'Custom celebration cake', basePriceMinor: 5500, depositMinor: 2000,
    );
    await tester.pumpWidget(host(const ProductTile(product: withDeposit)));
    expect(find.textContaining('£20.00 deposit'), findsOneWidget);
  });
}
