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
  final uploads = <String, List<int>>{};
  Set<String> failFor = {};
  @override
  Future<String> uploadProductPhoto({
    required String sellerId,
    required String productId,
    required List<int> bytes,
  }) async {
    path = 'sellers/$sellerId/products/$productId';
    if (failFor.contains(productId)) throw Exception('offline');
    uploads[productId] = bytes;
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

  group('attaching snapped photos on save', () {
    ProductCandidate c(String name, int? index) => ProductCandidate(
          tempId: name, name: name, basePriceMinor: 100, photoIndex: index);

    test('uploads each product\'s own photo and patches its URL', () async {
      final store = _FakeStore();
      final api = _FakeApi()
        ..saveResponse = {
          'created': ['p1', 'p2'],
          'skippedDuplicates': ['Dupe'],
          'ids': ['p1', null, 'p2'],
        };
      final result = await CatalogueRepository(api: api, photos: store).save(
        [c('Cake', 1), c('Dupe', 0), c('Buns', 0)],
        photos: [[10], [20]],
        sellerId: 's1',
      );
      expect(store.uploads, {'p1': [20], 'p2': [10]});
      expect(result.photosFailed, 0);
    });

    test('skips candidates with no photoIndex and older APIs without ids', () async {
      final store = _FakeStore();
      final api = _FakeApi()
        ..saveResponse = {'created': ['p1'], 'skippedDuplicates': <String>[]};
      await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', 0)], photos: [[1]], sellerId: 's1');
      expect(store.uploads, isEmpty);

      api.saveResponse = {'created': ['p1'], 'skippedDuplicates': <String>[], 'ids': ['p1']};
      await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', null)], photos: [[1]], sellerId: 's1');
      expect(store.uploads, isEmpty);
    });

    test('a photo that could not be attached is reported, not dropped', () async {
      // The silence is what hid the real bug for a week: when save() cannot
      // attach a photo at all — no ids from the API, or no sellerId — it
      // skipped the upload and reported photosFailed: 0, so the screen said
      // nothing and the seller found out by noticing the gap in their
      // catalogue. A photo the seller took and did not get is a failure.
      final store = _FakeStore();
      final api = _FakeApi()
        ..saveResponse = {'created': ['p1'], 'skippedDuplicates': <String>[]};

      final noIds = await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', 0)], photos: [[1]], sellerId: 's1');
      expect(store.uploads, isEmpty);
      expect(noIds.photosFailed, 1);

      api.saveResponse = {'created': ['p1'], 'skippedDuplicates': <String>[], 'ids': ['p1']};
      final noSeller = await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', 0)], photos: [[1]]);
      expect(store.uploads, isEmpty);
      expect(noSeller.photosFailed, 1);
    });

    test('a duplicate that was never created is not a failed photo', () async {
      // Nothing went wrong for a product that already existed: there is no
      // new product to put a photo on, and the seller is told about the
      // duplicate separately.
      final store = _FakeStore();
      final api = _FakeApi()
        ..saveResponse = {
          'created': <String>[],
          'skippedDuplicates': ['Cake'],
          'ids': [null],
        };
      final result = await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', 0)], photos: [[1]], sellerId: 's1');
      expect(result.photosFailed, 0);
    });

    test('a candidate with no photo of its own is not a failed photo', () async {
      final store = _FakeStore();
      final api = _FakeApi()
        ..saveResponse = {'created': ['p1'], 'skippedDuplicates': <String>[], 'ids': ['p1']};
      final result = await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', null)], photos: [[1]], sellerId: 's1');
      expect(store.uploads, isEmpty);
      expect(result.photosFailed, 0);
    });

    test('a failed upload is counted, not thrown', () async {
      final store = _FakeStore()..failFor = {'p1'};
      final api = _FakeApi()
        ..saveResponse = {'created': ['p1'], 'skippedDuplicates': <String>[], 'ids': ['p1']};
      final result = await CatalogueRepository(api: api, photos: store)
          .save([c('Cake', 0)], photos: [[1]], sellerId: 's1');
      expect(result.photosFailed, 1);
      expect(result.created, ['p1']);
    });
  });
}
