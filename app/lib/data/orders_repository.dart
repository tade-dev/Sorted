// cloud_firestore exports its own Order (an index-definition type).
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../core/api_client.dart';
import '../models/order.dart';

/// Named so tests can fake it without Dio or a live token.
abstract class OrdersApi {
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename);
  Future<Map<String, dynamic>> draftFromText(String text);
  Future<Map<String, dynamic>> resolve(String orderId, Object body);
  Future<Map<String, dynamic>> confirm(String orderId, Object body);
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone);
}

class HttpOrdersApi implements OrdersApi {
  HttpOrdersApi(this._client);
  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename) =>
      _client.postImages('/v1/orders/draft', [(bytes: bytes, filename: filename)],
          field: 'image');

  @override
  Future<Map<String, dynamic>> draftFromText(String text) =>
      _client.postForm('/v1/orders/draft', {'text': text});

  @override
  Future<Map<String, dynamic>> resolve(String orderId, Object body) =>
      _client.postJson('/v1/orders/$orderId/resolve', body);

  @override
  Future<Map<String, dynamic>> confirm(String orderId, Object body) =>
      _client.postJson('/v1/orders/$orderId/confirm', body);

  @override
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone) =>
      _client.postJson('/v1/orders/$orderId/reply/regenerate', {'tone': tone});
}

class OrdersRepository {
  OrdersRepository({required this.api});
  final OrdersApi api;

  /// Set when a draft came back empty, so the screen can say why.
  String? lastDraftReason;

  Stream<List<Order>> watchOrders(String sellerId) => FirebaseFirestore.instance
      .collection('sellers/$sellerId/orders')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => Order.fromJson({...d.data(), 'id': d.id}))
          .toList());

  Order? _readOrder(Map<String, dynamic> json) {
    final raw = json['order'];
    if (raw == null) {
      lastDraftReason = json['reason'] as String?;
      return null;
    }
    lastDraftReason = null;
    return Order.fromJson(raw as Map<String, dynamic>);
  }

  Future<Order?> draftFromText(String text) async =>
      _readOrder(await api.draftFromText(text));

  Future<Order?> draftFromImage(List<int> bytes, String filename) async =>
      _readOrder(await api.draftFromImage(bytes, filename));

  Future<Order> resolve(
    String orderId, {
    (String, List<String>)? variantFor,
    int? qtyFor,
    String? qtyLineId,
    int? depositMinor,
    String? buyerName,
    String? fulfilmentDate,
  }) async {
    // Built as one list: two collection-ifs both writing 'lineItems' would
    // silently drop the first, so a call changing a variant AND a quantity
    // would lose the variant.
    final edits = <Map<String, dynamic>>[
      if (variantFor != null) {'id': variantFor.$1, 'variantIds': variantFor.$2},
      if (qtyFor != null && qtyLineId != null) {'id': qtyLineId, 'qty': qtyFor},
    ];

    final body = <String, dynamic>{
      if (edits.isNotEmpty) 'lineItems': edits,
      'depositMinor': ?depositMinor,
      'buyerName': ?buyerName,
      if (fulfilmentDate != null) 'fulfilment': {'date': fulfilmentDate},
    };
    final json = await api.resolve(orderId, body);
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  Future<Order> confirm(Order order, {int? depositMinor}) async {
    if (order.isBlocked) {
      throw ArgumentError(order.blockingAmbiguities.first.question);
    }
    final json = await api.confirm(order.id, {
      'depositMinor': ?depositMinor,
    });
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  Future<String> regenerateReply(String orderId, String tone) async {
    final json = await api.regenerateReply(orderId, tone);
    return json['draftedReply'] as String;
  }
}
