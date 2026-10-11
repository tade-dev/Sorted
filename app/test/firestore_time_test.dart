import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/firestore_time.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/payment_event.dart';

class _Stamp {
  _Stamp(this.value);
  final DateTime value;
  DateTime toDate() => value;
}

void main() {
  test('reads ISO strings, epoch maps and Timestamp-like values', () {
    expect(
      dateTimeFromJson('2026-10-10T11:02:00.000Z'),
      DateTime.utc(2026, 10, 10, 11, 2),
    );
    expect(
      dateTimeFromJson({'_seconds': 1760090520, '_nanoseconds': 0}),
      DateTime.fromMillisecondsSinceEpoch(1760090520 * 1000, isUtc: true),
    );
    final stamp = DateTime.utc(2026, 10, 10, 11, 31);
    expect(dateTimeFromJson(_Stamp(stamp)), stamp);
    expect(dateTimeFromJson(null), isNull);
    expect(dateTimeFromJson('not-a-date'), isNull);
  });

  test('an order keeps the times Firestore stores', () {
    final order = Order.fromJson({
      'id': 'o1',
      'status': 'paid',
      'createdAt': '2026-10-10T11:02:00.000Z',
      'linkSentAt': '2026-10-10T11:04:00.000Z',
      'paidAt': {'_seconds': 1760092260, '_nanoseconds': 0},
      'lineItems': <Map<String, dynamic>>[],
    });
    expect(order.createdAt, DateTime.utc(2026, 10, 10, 11, 2));
    expect(order.linkSentAt, DateTime.utc(2026, 10, 10, 11, 4));
    expect(order.paidAt, isNotNull);
    expect(Order.fromJson(order.toJson()).createdAt, order.createdAt);
  });

  test('a reconcile event keeps the status it moved the order to', () {
    final event = PaymentEvent.fromMap({
      'id': 'reconcile-o1',
      'eventType': 'reconcile',
      'raw': {'source': 'reconcile', 'status': 'paid'},
      'receivedAt': '2026-10-10T11:31:00.000Z',
      'amountMinor': null,
    });
    expect(event.rawStatus, 'paid');
    expect(event.receivedAt, DateTime.utc(2026, 10, 10, 11, 31));
  });
}
