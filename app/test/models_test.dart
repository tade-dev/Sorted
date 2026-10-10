import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/models/product.dart';
import 'package:sorted/models/variant.dart';

Product cake({List<Variant>? variants, int base = 3200, int? deposit}) => Product(
      id: 'p1',
      name: 'Lemon drizzle cake',
      description: 'Zesty.',
      basePriceMinor: base,
      depositMinor: deposit,
      currency: 'GBP',
      photoUrl: null,
      variants: variants ??
          const [
            Variant(id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0),
            Variant(id: '10-inch', axis: 'size', label: '10 inch', priceDeltaMinor: 1000),
          ],
      active: true,
      source: 'ai_extracted',
    );

void main() {
  group('Product', () {
    test('round-trips through JSON', () {
      final p = cake();
      expect(Product.fromJson(p.toJson()), p);
    });

    test('fromPriceMinor is the cheapest variant, which is what the list shows', () {
      // Catalogue.dc.html renders "from £32" for the lemon drizzle.
      expect(cake().fromPriceMinor, 3200);
    });

    test('fromPriceMinor accounts for a negative delta', () {
      final p = cake(variants: const [
        Variant(id: '6-inch', axis: 'size', label: '6 inch', priceDeltaMinor: -800),
        Variant(id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0),
      ]);
      expect(p.fromPriceMinor, 2400);
    });

    test('fromPriceMinor falls back to the base price with no variants', () {
      expect(cake(variants: const []).fromPriceMinor, 3200);
    });

    test('ignores inactive variants when pricing', () {
      final p = cake(variants: const [
        Variant(id: 'a', axis: 'size', label: 'cheap', priceDeltaMinor: -1000, active: false),
        Variant(id: 'b', axis: 'size', label: 'normal', priceDeltaMinor: 0),
      ]);
      expect(p.fromPriceMinor, 3200);
    });

    test('hasVariants is false for a single-variant product', () {
      // Catalogue.dc.html shows "Red velvet cake · 8 inch · £36", an exact
      // price rather than "from", when there is nothing to choose between.
      final p = cake(variants: const [
        Variant(id: '8-inch', axis: 'size', label: '8 inch', priceDeltaMinor: 0),
      ]);
      expect(p.hasVariants, isFalse);
    });

    test('hasVariants is true with a real choice', () {
      expect(cake().hasVariants, isTrue);
    });

    test('keeps a product-level deposit', () {
      expect(cake(deposit: 2000).depositMinor, 2000);
    });

    test('tolerates a missing depositMinor in stored JSON', () {
      final json = cake().toJson()..remove('depositMinor');
      expect(Product.fromJson(json).depositMinor, isNull);
    });
  });
}
