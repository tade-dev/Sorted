import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/catalogue/catalogue_screen.dart';
import 'package:sorted/models/product.dart';
import 'package:sorted/models/variant.dart';
import 'package:sorted/providers/catalogue_providers.dart';

const _cake = Product(
  id: 'p1', name: 'Lemon drizzle cake', basePriceMinor: 3200,
  variants: [
    Variant(id: 'a', axis: 'size', label: '8 inch', priceDeltaMinor: 0),
    Variant(id: 'b', axis: 'size', label: '10 inch', priceDeltaMinor: 1000),
  ],
);

Widget host(AsyncValue<List<Product>> value) => ProviderScope(
      overrides: [productsProvider.overrideWith((ref) => Stream.value(value.value ?? []))],
      // CatalogueScreen has no Scaffold of its own: in the app it mounts as a
      // ShellRoute child inside _NavShell's Scaffold. Without one here its
      // Expanded has unbounded height and the list cannot lay out.
      child: MaterialApp(
        theme: sortedTheme(),
        home: const Scaffold(body: CatalogueScreen()),
      ),
    );

void main() {
  testWidgets('lists products and counts them', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.data([_cake])));
    await tester.pumpAndSettle();
    expect(find.text('Lemon drizzle cake'), findsOneWidget);
    expect(find.text('1 product'), findsOneWidget);
  });

  testWidgets('pluralises the count', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.data([
      _cake,
      Product(id: 'p2', name: 'Brownie box', basePriceMinor: 1400),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('2 products'), findsOneWidget);
  });

  testWidgets('offers a way in when the catalogue is empty', (tester) async {
    // A judge opening a fresh account must not meet a blank screen.
    await tester.pumpWidget(host(const AsyncValue.data([])));
    await tester.pumpAndSettle();
    expect(find.textContaining('Snap'), findsWidgets);
    expect(find.textContaining('nothing here yet'), findsOneWidget);
  });
}
