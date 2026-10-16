import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/catalogue_repository.dart';
import 'package:sorted/features/catalogue/review_screen.dart';
import 'package:sorted/models/ambiguity.dart';
import 'package:sorted/models/product_candidate.dart';
import 'package:sorted/models/variant.dart';
import 'package:sorted/providers/catalogue_providers.dart';
import 'package:sorted/providers/seller_provider.dart';

const _priced = ProductCandidate(
  tempId: 't1', name: 'Lemon drizzle cake', description: 'Zesty.',
  basePriceMinor: 3200,
  variants: [
    Variant(id: 'a', axis: 'size', label: '8 inch', priceDeltaMinor: 0),
    Variant(id: 'b', axis: 'size', label: '10 inch', priceDeltaMinor: 1000),
  ],
  confidence: 0.9,
);

const _unpriced = ProductCandidate(
  tempId: 't2', name: 'Cinnamon buns', basePriceMinor: null,
  variants: [Variant(id: 'c', axis: 'size', label: 'Box of 4', priceDeltaMinor: 0)],
  confidence: 0.4,
  ambiguities: [
    Ambiguity(field: 'basePriceMinor', kind: 'missing', question: "Couldn't read a price. Add one to save."),
  ],
);

class _FakeApi implements CatalogueApi {
  @override
  Future<Map<String, dynamic>> patchProduct(String productId, Object body) async =>
      {'product': body};

  Object? saved;
  List<String> skipped = <String>[];
  Object? throwOnSave;
  @override
  Future<Map<String, dynamic>> extract(List<({List<int> bytes, String filename})> f) async =>
      {'candidates': []};
  @override
  Future<Map<String, dynamic>> saveProducts(Object body) async {
    saved = body;
    if (throwOnSave != null) throw throwOnSave!;
    return {'created': ['p1'], 'skippedDuplicates': skipped};
  }
}

/// A real router, because ReviewScreen navigates to /catalogue after saving
/// and `context.go` throws without one. The destination screens are stubs whose
/// text the navigation tests assert on.
Widget _host(List<ProductCandidate>? candidates, {_FakeApi? api}) => ProviderScope(
      overrides: [
        extractionControllerProvider.overrideWith(() => _StubController(candidates)),
        // Saving awaits the seller id now, so these need one. Reading
        // .value instead of awaiting the future was the bug that stopped
        // snapped photos ever reaching Storage.
        sellerIdProvider.overrideWith((ref) async => 's1'),
        if (api != null)
          catalogueRepositoryProvider.overrideWithValue(CatalogueRepository(api: api)),
      ],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/catalogue/review',
          routes: [
            GoRoute(
              path: '/catalogue/review',
              builder: (_, _) => const ReviewScreen(),
            ),
            GoRoute(
              path: '/catalogue',
              builder: (_, _) => const Scaffold(body: Text('catalogue landed')),
            ),
            GoRoute(
              path: '/catalogue/snap',
              builder: (_, _) => const Scaffold(body: Text('snap landed')),
            ),
          ],
        ),
      ),
    );

class _StubController extends ExtractionController {
  _StubController(this._initial);
  final List<ProductCandidate>? _initial;
  @override
  List<ProductCandidate>? build() => _initial;
}

void main() {
  testWidgets('shows how many products were found', (tester) async {
    await tester.pumpWidget(_host(const [_priced, _unpriced]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sorted found 2 products'), findsOneWidget);
  });

  testWidgets('flags the product with no price', (tester) async {
    await tester.pumpWidget(_host(const [_unpriced]));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't read a price"), findsOneWidget);
  });

  testWidgets('save is disabled while any product still lacks a price', (tester) async {
    // Saving here would write a £0 product a buyer could order.
    await tester.pumpWidget(_host(const [_priced, _unpriced]));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isFalse);
  });

  testWidgets('save becomes available once every price is filled in', (tester) async {
    await tester.pumpWidget(_host(const [_priced]));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isTrue);
    expect(find.text('Add 1 product'), findsOneWidget);
  });

  testWidgets('typing a price clears the block', (tester) async {
    await tester.pumpWidget(_host(const [_unpriced]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12.00');
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isTrue);
  });

  testWidgets('the price field survives typing it one character at a time', (tester) async {
    // A seller typing "45.00" sends five change events. The field used to be
    // rendered only while needsPrice was true, and the first character cleared
    // that flag, so the field vanished and GBP 4.00 was locked in. The old
    // test passed only because enterText delivers the whole string at once.
    await tester.pumpWidget(_host(const [_unpriced]));
    await tester.pumpAndSettle();

    for (final soFar in ['4', '45', '45.', '45.0', '45.00']) {
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'price field disappeared after typing "$soFar"',
      );
      await tester.enterText(find.byType(TextField), soFar);
      await tester.pump();
    }

    expect(find.textContaining('45.00'), findsWidgets);
  });

  testWidgets('says so plainly when the photo had nothing in it', (tester) async {
    // A selfie or an empty worktop must not show a blank confirm screen.
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't find any products"), findsOneWidget);
  });

  testWidgets('saving sends the candidates to the API', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(const [_priced], api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(api.saved, isNotNull);
    // And it leaves the review screen rather than stranding the seller on it.
    expect(find.text('catalogue landed'), findsOneWidget);
  });

  testWidgets('discarding a candidate removes it from the list', (tester) async {
    // The plan promised "discard what is wrong"; nothing called discard(), so
    // a misread product could only be saved, not removed.
    await tester.pumpWidget(_host(const [_priced, _unpriced]));
    await tester.pumpAndSettle();
    expect(find.text('Cinnamon buns'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Cinnamon buns'));
    await tester.pumpAndSettle();

    expect(find.text('Cinnamon buns'), findsNothing);
    expect(find.text('Lemon drizzle cake'), findsOneWidget);
  });

  testWidgets('tells the seller which products were already in the catalogue',
      (tester) async {
    // skippedDuplicates was returned by the API and dropped by the UI, so a
    // seller re-snapping a shelf saw fewer rows and no explanation.
    final api = _FakeApi()..skipped = ['Lemon drizzle cake'];
    await tester.pumpWidget(_host(const [_priced], api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.textContaining('Lemon drizzle cake'), findsWidgets);
    expect(find.textContaining('not added again'), findsOneWidget);
    // Let the toast auto-dismiss so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('shows the API message when saving fails, and stays put',
      (tester) async {
    final api = _FakeApi()
      ..throwOnSave = ArgumentError('Those products could not be saved.');
    await tester.pumpWidget(_host(const [_priced], api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.textContaining('could not be saved'), findsOneWidget);
    // Still on Review, not stranded on a half-finished navigation.
    expect(find.text('catalogue landed'), findsNothing);
    // Let the toast auto-dismiss so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));
  });
}
