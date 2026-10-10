import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/env.dart';
import '../data/catalogue_repository.dart';
import '../models/product.dart';
import '../models/product_candidate.dart';
import 'seller_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: apiBaseUrl));

final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => CatalogueRepository(api: HttpCatalogueApi(ref.watch(apiClientProvider))),
);

/// The live product list. A Firestore listener, so a product saved through the
/// API appears here without the app asking again.
final productsProvider = StreamProvider<List<Product>>((ref) {
  final sellerId = ref.watch(sellerIdProvider).value;
  if (sellerId == null) return const Stream<List<Product>>.empty();
  return ref.watch(catalogueRepositoryProvider).watchProducts(sellerId);
});

/// Candidates awaiting the seller's confirmation. Null until a snap happens.
class ExtractionController extends Notifier<List<ProductCandidate>?> {
  @override
  List<ProductCandidate>? build() => null;

  Future<void> extract(List<({List<int> bytes, String filename})> files) async {
    state = null;
    state = await ref.read(catalogueRepositoryProvider).extract(files);
  }

  void setPrice(String tempId, int priceMinor) {
    state = [
      for (final c in state ?? <ProductCandidate>[])
        if (c.tempId == tempId) c.copyWith(basePriceMinor: priceMinor) else c,
    ];
  }

  void discard(String tempId) {
    state = [for (final c in state ?? <ProductCandidate>[]) if (c.tempId != tempId) c];
  }

  void clear() => state = null;
}

final extractionControllerProvider =
    NotifierProvider<ExtractionController, List<ProductCandidate>?>(
  ExtractionController.new,
);
