import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/data/catalogue_repository.dart';
import 'package:sorted/data/photo_store.dart';
import 'package:sorted/models/ambiguity.dart';
import 'package:sorted/models/product_candidate.dart';
import 'package:sorted/models/variant.dart';

class _FakeApi implements CatalogueApi {
  @override
  Future<Map<String, dynamic>> patchProduct(
    String productId,
    Object body,
  ) async {
    patched = (productId, body);
    return {'product': body};
  }

  (String, Object)? patched;

  Object? lastBody;
  Map<String, dynamic> extractResponse = {'candidates': []};
  Map<String, dynamic> saveResponse = {
    'created': <String>[],
    'skippedDuplicates': <String>[],
  };

  @override
  Future<Map<String, dynamic>> extract(
    List<({List<int> bytes, String filename})> f,
  ) async => extractResponse;

  @override
  Future<Map<String, dynamic>> saveProducts(Object body) async {
    lastBody = body;
    return saveResponse;
  }
}

class _FakeStore implements PhotoStore {
  String? path;
  @override
  Future<String> uploadProductPhoto({
    required String sellerId,
    required String productId,
    required List<int> bytes,
  }) async {
    path = 'sellers/$sellerId/products/$productId';
    return 'https://firebasestorage.googleapis.com/v0/b/b/o/x.jpg?alt=media';
  }
}

void main() {
  test('uploads a product photo then saves its URL on the product', () async {
    final api = _FakeApi();
    final store = _FakeStore();
    final url = await CatalogueRepository(
      api: api,
      photos: store,
    ).setPhoto(sellerId: 's1', productId: 'p1', bytes: [1, 2, 3]);
    expect(store.path, 'sellers/s1/products/p1');
    expect(api.patched?.$1, 'p1');
    expect(api.patched?.$2, {'photoUrl': url});
  });

  late _FakeApi api;
  late CatalogueRepository repo;

  setUp(() {
    api = _FakeApi();
    repo = CatalogueRepository(api: api);
  });

  test('parses candidates from the extract response', () async {
    // EXACTLY what POST /v1/catalogue/extract returns. Variants carry no `id`:
    // ids are assigned by the backend at save time via uniqueSlugs. An earlier
    // version of this fixture invented one, so the model could require `id`
    // and every real extraction with a variant threw while tests stayed green.
    api.extractResponse = {
      'candidates': [
        {
          'tempId': 't1',
          'name': 'Lemon drizzle cake',
          'description': 'Zesty.',
          'basePriceMinor': 3200,
          'variants': [
            {'axis': 'size', 'label': '8 inch', 'priceDeltaMinor': 0},
            {'axis': 'size', 'label': '10 inch', 'priceDeltaMinor': 1000},
          ],
          'confidence': 0.9,
          'ambiguities': <Map<String, dynamic>>[],
        },
      ],
    };
    final out = await repo.extract([]);
    expect(out.single.name, 'Lemon drizzle cake');
    expect(out.single.needsPrice, isFalse);
    expect(out.single.variants.map((v) => v.label), ['8 inch', '10 inch']);
  });

  test('a candidate with a null price reports needsPrice', () async {
    api.extractResponse = {
      'candidates': [
        {
          'tempId': 't2',
          'name': 'Cinnamon buns',
          'description': '',
          'basePriceMinor': null,
          'variants': <Map<String, dynamic>>[],
          'confidence': 0.4,
          'ambiguities': [
            {
              'field': 'basePriceMinor',
              'kind': 'missing',
              'question': 'Price?',
            },
          ],
        },
      ],
    };
    final out = await repo.extract([]);
    expect(out.single.needsPrice, isTrue);
    expect(out.single.ambiguities.single.question, 'Price?');
  });

  test('refuses to save a candidate that still has no price', () async {
    final candidate = ProductCandidate(
      tempId: 't',
      name: 'Buns',
      basePriceMinor: null,
    );
    expect(() => repo.save([candidate]), throwsA(isA<ArgumentError>()));
  });

  test('sends only the fields the API accepts', () async {
    await repo.save([
      const ProductCandidate(
        tempId: 't',
        name: 'Buns',
        description: 'Soft.',
        basePriceMinor: 1200,
        variants: [
          Variant(
            id: 'box-of-4',
            axis: 'size',
            label: 'Box of 4',
            priceDeltaMinor: 0,
          ),
        ],
        confidence: 0.9,
        ambiguities: <Ambiguity>[],
      ),
    ]);
    final body = api.lastBody! as Map<String, dynamic>;
    final product = (body['products'] as List).single as Map<String, dynamic>;
    expect(product.keys, containsAll(['name', 'basePriceMinor', 'variants']));
    // tempId, confidence and ambiguities are app-side only.
    expect(product.containsKey('tempId'), isFalse);
    expect(product.containsKey('confidence'), isFalse);
    expect(product.containsKey('ambiguities'), isFalse);
  });

  test('reports duplicates the API skipped', () async {
    api.saveResponse = {
      'created': <String>[],
      'skippedDuplicates': ['Buns'],
    };
    final result = await repo.save([
      const ProductCandidate(tempId: 't', name: 'Buns', basePriceMinor: 1200),
    ]);
    expect(result.skippedDuplicates, ['Buns']);
  });

  test('updateProduct sends only the edited fields', () async {
    final api = _FakeApi();
    final repo = CatalogueRepository(api: api);
    await repo.updateProduct(
      'p1',
      name: 'Lemon cake',
      basePriceMinor: 3500,
      variants: [(axis: 'size', label: '10 inch', priceDeltaMinor: 1000)],
      inStock: false,
    );
    expect(api.patched!.$1, 'p1');
    expect(api.patched!.$2, {
      'name': 'Lemon cake',
      'basePriceMinor': 3500,
      'variants': [
        {'axis': 'size', 'label': '10 inch', 'priceDeltaMinor': 1000},
      ],
      'inStock': false,
    });

    await repo.updateProduct('p1', inStock: true);
    expect(api.patched!.$2, {'inStock': true});
  });
}
