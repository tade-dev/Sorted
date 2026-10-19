// cloud_firestore exports its own Order (an index-definition type).
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../core/api_client.dart';
import '../models/order.dart';
import '../models/payment_event.dart';

/// Named so tests can fake it without Dio or a live token.
abstract class OrdersApi {
  Future<Map<String, dynamic>> draftFromImage(List<int> bytes, String filename);
  Future<Map<String, dynamic>> draftFromText(String text);
  Future<Map<String, dynamic>> resolve(String orderId, Object body);
  Future<Map<String, dynamic>> confirm(String orderId, Object body);
  Future<Map<String, dynamic>> edit(String orderId, Object body);
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone);
  Future<Map<String, dynamic>> thankYou(String orderId);
  Future<Map<String, dynamic>> refresh(String orderId);
  Future<Map<String, dynamic>> invoice(String orderId);
  Future<Map<String, dynamic>> cancel(String orderId);
}

class HttpOrdersApi implements OrdersApi {
  HttpOrdersApi(this._client);
  final ApiClient _client;

  @override
  Future<Map<String, dynamic>> draftFromImage(
    List<int> bytes,
    String filename,
  ) => _client.postImages('/v1/orders/draft', [
    (bytes: bytes, filename: filename),
  ], field: 'image');

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
  Future<Map<String, dynamic>> edit(String orderId, Object body) =>
      _client.postJson('/v1/orders/$orderId/edit', body);

  @override
  Future<Map<String, dynamic>> regenerateReply(String orderId, String tone) =>
      _client.postJson('/v1/orders/$orderId/reply/regenerate', {'tone': tone});

  @override
  Future<Map<String, dynamic>> thankYou(String orderId) =>
      _client.postJson('/v1/orders/$orderId/thank-you', const {});

  @override
  Future<Map<String, dynamic>> refresh(String orderId) =>
      _client.postJson('/v1/orders/$orderId/refresh', const {});

  @override
  Future<Map<String, dynamic>> invoice(String orderId) =>
      _client.getJson('/v1/orders/$orderId/invoice');

  @override
  Future<Map<String, dynamic>> cancel(String orderId) =>
      _client.postJson('/v1/orders/$orderId/cancel', const {});
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
      .map(
        (snap) => snap.docs
            .map((d) => Order.fromJson({...d.data(), 'id': d.id}))
            .toList(),
      );

  /// One order, live. Missing documents emit null rather than an error so the
  /// detail screen can say the order is not here.
  Stream<Order?> watchOrder(String sellerId, String orderId) =>
      FirebaseFirestore.instance
          .doc('sellers/$sellerId/orders/$orderId')
          .snapshots()
          .map((snap) {
            final data = snap.data();
            if (!snap.exists || data == null) return null;
            return Order.fromJson({...data, 'id': snap.id});
          });

  /// Webhook and reconcile rows. Sorted here so a missing `receivedAt` does
  /// not drop the event the way an `orderBy` query would.
  Stream<List<PaymentEvent>> watchPaymentEvents(
    String sellerId,
    String orderId,
  ) => FirebaseFirestore.instance
      .collection('sellers/$sellerId/orders/$orderId/paymentEvents')
      .snapshots()
      .map((snap) {
        final events = snap.docs
            .map((d) => PaymentEvent.fromMap({...d.data(), 'id': d.id}))
            .toList();
        events.sort((a, b) {
          final at = a.receivedAt ?? a.processedAt;
          final bt = b.receivedAt ?? b.processedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return at.compareTo(bt);
        });
        return events;
      });

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
    String? fulfilmentMode,
    List<String>? resolvedFields,
  }) async {
    // Built as one list: two collection-ifs both writing 'lineItems' would
    // silently drop the first, so a call changing a variant AND a quantity
    // would lose the variant.
    final edits = <Map<String, dynamic>>[
      if (variantFor != null)
        {'id': variantFor.$1, 'variantIds': variantFor.$2},
      if (qtyFor != null && qtyLineId != null) {'id': qtyLineId, 'qty': qtyFor},
    ];
    final fulfilment = <String, dynamic>{
      'date': ?fulfilmentDate,
      'mode': ?fulfilmentMode,
    };

    final body = <String, dynamic>{
      if (edits.isNotEmpty) 'lineItems': edits,
      'depositMinor': ?depositMinor,
      'buyerName': ?buyerName,
      if (fulfilment.isNotEmpty) 'fulfilment': fulfilment,
      if (resolvedFields != null && resolvedFields.isNotEmpty)
        'resolvedAmbiguities': resolvedFields,
    };
    final json = await api.resolve(orderId, body);
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  Future<Order> confirm(Order order, {int? depositMinor}) async {
    if (order.isBlocked) {
      throw ArgumentError(order.blockingAmbiguities.first.question);
    }
    final json = await api.confirm(order.id, {'depositMinor': ?depositMinor});
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  /// Replaces the order's lines and note. The server reprices every line and
  /// refuses paid orders; a sent order whose total changed comes back as a
  /// draft with no link, so the seller makes a fresh one.
  Future<Order> edit(
    String orderId, {
    required List<
      ({String? id, String productId, List<String> variantIds, int qty})
    >
    lines,
    String? note,
  }) async {
    final json = await api.edit(orderId, {
      'lineItems': [
        for (final l in lines)
          {
            'id': ?l.id,
            'productId': l.productId,
            'variantIds': l.variantIds,
            'qty': l.qty,
          },
      ],
      'note': note,
    });
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  Future<String> regenerateReply(String orderId, String tone) async {
    final json = await api.regenerateReply(orderId, tone);
    return json['draftedReply'] as String;
  }

  /// A fresh thank-you for a paid order, written in the seller's voice.
  Future<String> thankYou(String orderId) async {
    final json = await api.thankYou(orderId);
    return json['message'] as String;
  }

  /// The buyer-facing invoice link for a paid order.
  Future<String> invoiceUrl(String orderId) async {
    final json = await api.invoice(orderId);
    return json['url'] as String;
  }

  /// Cancels an unpaid order. The server checks PayPal first and refuses if
  /// the buyer has already paid, so a failure here carries a reason worth
  /// showing. Asking for an order that is already cancelled is fine.
  Future<Order> cancel(String orderId) async {
    final json = await api.cancel(orderId);
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  /// Asks the API to check PayPal for this order. A payment to the seller's
  /// own PayPal may not webhook Sorted, so opening the order is the fallback.
  /// The order stream picks up any change; failures are ignored.
  Future<void> refreshFromPayPal(String orderId) async {
    try {
      await api.refresh(orderId);
    } catch (_) {}
  }
}
