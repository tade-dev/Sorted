import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/catalogue_repository.dart';
import 'package:sorted/data/photo_store.dart';
import 'package:sorted/features/catalogue/review_screen.dart';
import 'package:sorted/providers/catalogue_providers.dart';
import 'package:sorted/providers/seller_provider.dart';

/// Mirrors the real API: extract hands back a photoIndex, and saving hands
/// back one id per product sent. The other review-screen tests use a fake
/// that omits `ids`, which is exactly why the photo path was never exercised.
class _Api implements CatalogueApi {
  List<({List<int> bytes, String filename})> extracted = const [];
  final patched = <(String, Object)>[];
  bool returnIds = true;

  @override
  Future<Map<String, dynamic>> extract(
      List<({List<int> bytes, String filename})> files) async {
    extracted = files;
    return {
      'candidates': [
        {
          'tempId': 't1',
          'name': 'Lemon drizzle cake',
          'basePriceMinor': 4200,
          'variants': <dynamic>[],
          'confidence': 0.9,
          'photoIndex': 0,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> saveProducts(Object body) async => {
        'created': ['p1'],
        'skippedDuplicates': <String>[],
        if (returnIds) 'ids': ['p1'],
      };

  @override
  Future<Map<String, dynamic>> patchProduct(String productId, Object body) async {
    patched.add((productId, body));
    return {'product': body};
  }
}

class _Store implements PhotoStore {
  final uploads = <({String productId, List<int> bytes})>[];

  @override
  Future<String> uploadProductPhoto({
    required String sellerId,
    required String productId,
    required List<int> bytes,
  }) async {
    uploads.add((productId: productId, bytes: bytes));
    return 'https://example.test/$productId.jpg';
  }
}

Widget _host(_Api api, _Store store, {Duration sellerDelay = Duration.zero}) =>
    ProviderScope(
      overrides: [
        // The real ExtractionController, not a stub: the photos it keeps are
        // the thing under test.
        catalogueRepositoryProvider
            .overrideWithValue(CatalogueRepository(api: api, photos: store)),
        sellerIdProvider.overrideWith((ref) async {
          // Only a real timer when a test asks for one: in testWidgets a timer
          // fires on a pump, so a zero Future.delayed awaited before pumping
          // would deadlock.
          if (sellerDelay > Duration.zero) {
            await Future<void>.delayed(sellerDelay);
          }
          return 's1';
        }),
      ],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/catalogue/review',
          routes: [
            GoRoute(path: '/catalogue/review', builder: (_, _) => const ReviewScreen()),
            GoRoute(path: '/catalogue', builder: (_, _) => const Text('catalogue landed')),
          ],
        ),
      ),
    );

void main() {
  testWidgets('a snapped photo reaches Storage when the products are saved',
      (tester) async {
    final api = _Api();
    final store = _Store();
    await tester.pumpWidget(_host(api, store));
    // Not pumpAndSettle: with no candidates yet the screen shows the loading
    // skeleton, whose shimmer repeats forever and never settles.
    await tester.pump();

    // Snap: the controller keeps the bytes behind the candidates.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReviewScreen)),
    );
    await container.read(extractionControllerProvider.notifier).extract([
      (bytes: const [1, 2, 3], filename: 'shelf.jpg'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Lemon drizzle cake'), findsOneWidget);

    await container.read(sellerIdProvider.future);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(store.uploads, hasLength(1), reason: 'the photo should have uploaded');
    expect(store.uploads.single.productId, 'p1');
    expect(store.uploads.single.bytes, const [1, 2, 3]);
    expect(
      api.patched.map((p) => p.$1),
      contains('p1'),
      reason: 'and its URL recorded on the product',
    );
  });

  testWidgets('and still reaches Storage when the seller id is slow to resolve',
      (tester) async {
    // The real bug. sellerIdProvider is a FutureProvider, and reading .value
    // off it is a synchronous peek that answers null while it is still
    // loading — or has failed. save() then sees a null sellerId, skips every
    // upload, and reports photosFailed: 0, so the seller is told nothing. The
    // products save, the photos quietly do not, and the only way to get one
    // on is to open the product and snap it again.
    //
    // product_edit_screen does the same job with `await ref.read(
    // sellerIdProvider.future)` and has always worked, which is the
    // difference this pins down.
    final api = _Api();
    final store = _Store();
    await tester.pumpWidget(
      _host(api, store, sellerDelay: const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReviewScreen)),
    );
    await container.read(extractionControllerProvider.notifier).extract([
      (bytes: const [9, 9, 9], filename: 'shelf.jpg'),
    ]);
    await tester.pumpAndSettle();

    // Deliberately not awaiting the seller first: this is a seller who got to
    // Review quickly, which is the whole point.
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(store.uploads, hasLength(1),
        reason: 'the photo should upload once the seller id arrives');
    expect(store.uploads.single.bytes, const [9, 9, 9]);
  });
}
