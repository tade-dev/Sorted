import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/models/order.dart';

Map<String, dynamic> orderJson({
  String id = 'o1',
  String status = 'draft',
  List<Map<String, dynamic>>? ambiguities,
  String? approvalUrl,
}) => {
  'id': id,
  'status': status,
  'buyerName': 'Jess M',
  'buyerHandle': 'jess.mcr',
  'channel': 'instagram',
  'lineItems': [
    {
      'id': 'li-1',
      'productId': 'p1',
      'variantIds': ['10-inch'],
      'nameRaw': 'lemon drizzle',
      'nameResolved': 'Lemon drizzle cake',
      'qty': 1,
      'unitPriceMinor': 4200,
      'lineTotalMinor': 4200,
      'matchConfidence': 1.0,
      'matchMethod': 'exact',
    },
  ],
  'subtotalMinor': 4200,
  'amountDueMinor': 4200,
  'currency': 'GBP',
  'fulfilment': {'mode': 'collection', 'date': '2026-10-10'},
  'ambiguities': ambiguities ?? <Map<String, dynamic>>[],
  'approvalUrl': ?approvalUrl,
};

class _FakeApi implements OrdersApi {
  @override
  Future<Map<String, dynamic>> invoice(String orderId) async =>
      {'url': 'https://api.example.com/v1/invoice/s/$orderId/sig'};

  @override
  Future<Map<String, dynamic>> refresh(String orderId) async => const {};

  @override
  Future<Map<String, dynamic>> thankYou(String orderId) async {
    lastPath = 'thank-you/$orderId';
    if (throwOn != null) throw throwOn!;
    return {'message': 'Thanks Jess!'};
  }

  Map<String, dynamic> draftResponse = {
    'order': null,
    'reason': 'nothing here',
  };
  Map<String, dynamic> orderResponse = {'order': {}};
  String replyResponse = 'hi';
  Object? throwOn;
  Object? lastBody;
  String? lastPath;

  @override
  Future<Map<String, dynamic>> draftFromImage(
    List<int> bytes,
    String filename,
  ) async {
    lastPath = 'image';
    if (throwOn != null) throw throwOn!;
    return draftResponse;
  }

  @override
  Future<Map<String, dynamic>> draftFromText(String text) async {
    lastPath = 'text';
    lastBody = text;
    if (throwOn != null) throw throwOn!;
    return draftResponse;
  }

  @override
  Future<Map<String, dynamic>> resolve(String orderId, Object body) async {
    lastBody = body;
    return orderResponse;
  }

  @override
  Future<Map<String, dynamic>> edit(String orderId, Object body) async {
    lastPath = 'edit/$orderId';
    lastBody = body;
    return orderResponse;
  }

  @override
  Future<Map<String, dynamic>> confirm(String orderId, Object body) async {
    lastBody = body;
    if (throwOn != null) throw throwOn!;
    return orderResponse;
  }

  @override
  Future<Map<String, dynamic>> regenerateReply(
    String orderId,
    String tone,
  ) async {
    lastBody = tone;
    return {'draftedReply': replyResponse};
  }
}

void main() {
  late _FakeApi api;
  late OrdersRepository repo;

  setUp(() {
    api = _FakeApi();
    repo = OrdersRepository(api: api);
  });

  test('returns a parsed order from a text draft', () async {
    api.draftResponse = {'order': orderJson()};
    final out = await repo.draftFromText('a lemon drizzle please');
    expect(out!.buyerName, 'Jess M');
    expect(out.subtotalMinor, 4200);
  });

  test('returns null when the API found no order', () async {
    api.draftResponse = {
      'order': null,
      'reason': 'Sorted could not find an order in that.',
    };
    expect(await repo.draftFromText('a cat photo'), isNull);
    expect(repo.lastDraftReason, contains('could not find'));
  });

  test('sends a variant choice as a line edit', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.resolve('o1', variantFor: ('li-1', ['8-inch']));
    final body = api.lastBody! as Map<String, dynamic>;
    final line = (body['lineItems'] as List).single as Map<String, dynamic>;
    expect(line['id'], 'li-1');
    expect(line['variantIds'], ['8-inch']);
  });

  test('sends a deposit on its own', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.resolve('o1', depositMinor: 2000);
    expect((api.lastBody! as Map<String, dynamic>)['depositMinor'], 2000);
  });

  test('refuses to confirm an order that is still blocked', () async {
    // The API refuses too; failing here saves a round trip and a confusing
    // error, and keeps the button and the rule in agreement.
    final blocked = Order.fromJson(
      orderJson(
        ambiguities: [
          {
            'field': 'lineItems[0].variantIds',
            'kind': 'missing',
            'question': 'Which size?',
          },
        ],
      ),
    );
    expect(() => repo.confirm(blocked), throwsA(isA<ArgumentError>()));
  });

  test('confirms an unblocked order', () async {
    api.orderResponse = {
      'order': orderJson(
        status: 'link_sent',
        approvalUrl: 'https://x/checkoutnow?token=T',
      ),
    };
    final out = await repo.confirm(Order.fromJson(orderJson()));
    expect(out.status, 'link_sent');
    expect(out.hasLink, isTrue);
  });

  test('passes a deposit through on confirm', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.confirm(Order.fromJson(orderJson()), depositMinor: 1500);
    expect((api.lastBody! as Map<String, dynamic>)['depositMinor'], 1500);
  });

  test('regenerates the reply in a given tone', () async {
    api.replyResponse = 'Dear Jess, ...';
    final out = await repo.regenerateReply('o1', 'formal');
    expect(out, 'Dear Jess, ...');
    expect(api.lastBody, 'formal');
  });

  test('fetches a thank-you for the order', () async {
    final out = await repo.thankYou('o1');
    expect(out, 'Thanks Jess!');
    expect(api.lastPath, 'thank-you/o1');
  });

  test('edit sends every line and the note to the edit route', () async {
    api.orderResponse = {'order': orderJson()};
    await repo.edit(
      'o1',
      lines: [
        (id: 'l1', productId: 'p1', variantIds: ['8-inch'], qty: 2),
        (id: null, productId: 'p2', variantIds: <String>[], qty: 1),
      ],
      note: 'Happy birthday',
    );
    expect(api.lastPath, 'edit/o1');
    expect(api.lastBody, {
      'lineItems': [
        {
          'id': 'l1',
          'productId': 'p1',
          'variantIds': ['8-inch'],
          'qty': 2,
        },
        {'productId': 'p2', 'variantIds': <String>[], 'qty': 1},
      ],
      'note': 'Happy birthday',
    });
  });
}
