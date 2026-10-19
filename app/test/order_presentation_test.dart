import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/features/orders/order_presentation.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/payment_event.dart';

const _cake = LineItem(
  id: 'li-1',
  productId: 'p1',
  nameRaw: 'lemon drizzle',
  nameResolved: 'Lemon drizzle cake',
  qty: 1,
  unitPriceMinor: 4200,
  lineTotalMinor: 4200,
);

const _brownie = LineItem(
  id: 'li-2',
  productId: 'p2',
  nameRaw: 'brownie box',
  nameResolved: 'Brownie box',
  qty: 1,
  unitPriceMinor: 1400,
  lineTotalMinor: 1400,
);

Order _order({
  String status = 'link_sent',
  String? buyerName = 'Jess M',
  String? buyerHandle,
  DateTime? createdAt,
  DateTime? linkSentAt,
  DateTime? paidAt,
  String sourceKind = 'screenshot',
  int? depositMinor,
  List<LineItem> lines = const [_cake, _brownie],
}) => Order(
  id: 'o1',
  status: status,
  buyerName: buyerName,
  buyerHandle: buyerHandle,
  lineItems: lines,
  subtotalMinor: 5600,
  depositMinor: depositMinor,
  amountDueMinor: depositMinor ?? 5600,
  fulfilment: const Fulfilment(
    mode: 'collection',
    date: '2026-10-10',
    notes: '2pm',
  ),
  sourceKind: sourceKind,
  createdAt: createdAt,
  linkSentAt: linkSentAt,
  paidAt: paidAt,
);

void main() {
  test('names every status the backend can set', () {
    expect(statusPresentation('draft').label, 'Draft');
    expect(statusPresentation('link_sent').label, 'Link sent');
    expect(statusPresentation('processing').label, 'Confirming');
    expect(statusPresentation('pending').label, 'Pending');
    expect(statusPresentation('declined').label, 'Declined');
    expect(statusPresentation('paid').label, 'Paid');
    expect(statusPresentation('cancelled').label, 'Cancelled');
    expect(statusPresentation('expired').label, 'Expired');
    expect(statusPresentation('paid').tone, StatusTone.paid);
    expect(statusPresentation('link_sent').tone, isNot(StatusTone.paid));
  });

  test('waiting filter keeps the unpaid states together', () {
    for (final status in ['link_sent', 'processing', 'pending', 'declined']) {
      expect(orderMatchesFilter(status, OrderFilter.waiting), isTrue);
    }
    expect(orderMatchesFilter('paid', OrderFilter.waiting), isFalse);
    expect(orderMatchesFilter('draft', OrderFilter.drafts), isTrue);
    expect(orderMatchesFilter('cancelled', OrderFilter.all), isTrue);
    expect(orderMatchesFilter('cancelled', OrderFilter.paid), isFalse);
  });

  test('cancelled and expired are closed: not waiting, not cancellable', () {
    for (final status in ['cancelled', 'expired']) {
      expect(orderMatchesFilter(status, OrderFilter.waiting), isFalse);
      expect(orderMatchesFilter(status, OrderFilter.drafts), isFalse);
      expect(isClosedStatus(status), isTrue);
      expect(cancellableOrderStatuses.contains(status), isFalse);
      expect(statusPresentation(status).tone, StatusTone.closed);
    }
    expect(cancellableOrderStatuses, {'draft', 'link_sent', 'declined'});
    expect(isClosedStatus('paid'), isFalse);
  });

  test('the cancel warning names the buyer only when a link is out', () {
    expect(
      cancelOrderWarning(_order(status: 'draft')),
      "The draft is closed and can't be sent. You can't undo this.",
    );
    expect(
      cancelOrderWarning(
        _order().copyWith(approvalUrl: 'https://paypal.test/x'),
      ),
      "The checkout link stops working, so Jess can't pay on it. You can't undo this.",
    );
    expect(
      cancelOrderWarning(
        _order(buyerName: null).copyWith(approvalUrl: 'https://paypal.test/x'),
      ),
      "The checkout link stops working, so The buyer can't pay on it. You can't undo this.",
    );
  });

  test('a closed order says why its link is gone', () {
    expect(closedOrderNote(_order(status: 'cancelled')), contains('You cancelled'));
    expect(closedOrderNote(_order(status: 'expired')), contains('expired unpaid'));
  });

  test('cancel and expiry read as the last thing on the timeline', () {
    final at = DateTime(2026, 10, 10, 12);
    final timeline = buildTimeline(_order(status: 'cancelled'), [
      PaymentEvent(id: 'cancel-o1', eventType: 'cancelled', receivedAt: at),
      PaymentEvent(id: 'WH-1', eventType: 'CHECKOUT.ORDER.APPROVED', receivedAt: at),
    ]);
    expect(timeline.map((e) => e.label), [
      'Jess paid with PayPal',
      'You cancelled the order',
    ]);
    expect(
      paymentEventLabel(const PaymentEvent(id: 'e', eventType: 'expired'), 'Jess'),
      'The link expired unpaid',
    );
  });

  test('a capture on a closed link is a refund to make, never Payment received', () {
    const late = PaymentEvent(
      id: 'WH-LATE',
      eventType: 'PAYMENT.CAPTURE.COMPLETED',
      refundDue: true,
    );
    expect(paymentEventLabel(late, 'Jess'), 'Paid on a closed link. Refund it in PayPal');
    expect(
      PaymentEvent.fromMap({'id': 'x', 'eventType': 'PAYMENT.CAPTURE.COMPLETED', 'refundDue': true}).refundDue,
      isTrue,
    );
    expect(PaymentEvent.fromMap({'id': 'x', 'eventType': 'reconcile'}).refundDue, isFalse);
  });

  test('buyer falls back to a handle, then a neutral word', () {
    expect(buyerLabel(_order()), 'Jess M');
    expect(
      buyerLabel(_order(buyerName: '  ', buyerHandle: 'jess.mcr')),
      '@jess.mcr',
    );
    expect(buyerLabel(_order(buyerName: null, buyerHandle: null)), 'Buyer');
  });

  test('summarises the lines the way the card reads them', () {
    expect(itemsSummary(_order()), 'Lemon drizzle cake, Brownie box');
    expect(itemsSummary(_order(lines: const [])), 'No items yet');
  });

  test('captions follow the order list', () {
    final now = DateTime(2026, 10, 11, 15);
    expect(
      activityCaption(
        _order(
          paidAt: now.subtract(const Duration(seconds: 30)),
          status: 'paid',
        ),
        now,
      ),
      'Just now',
    );
    expect(
      activityCaption(
        _order(status: 'paid', paidAt: DateTime(2026, 10, 11, 9, 30)),
        now,
      ),
      'This morning',
    );
    expect(
      activityCaption(
        _order(linkSentAt: now.subtract(const Duration(hours: 3))),
        now,
      ),
      'Link sent 3h ago',
    );
    expect(
      activityCaption(_order(linkSentAt: DateTime(2026, 10, 8, 11)), now),
      'Sent Thursday',
    );
    expect(
      activityCaption(_order(status: 'declined'), now),
      'Ask them to try again',
    );
    expect(
      activityCaption(_order(status: 'processing'), now),
      'Confirming with PayPal',
    );
    expect(
      activityCaption(_order(status: 'pending'), now),
      'Pending with PayPal',
    );
  });

  test('a payment just landing is the highlighted card', () {
    final now = DateTime(2026, 10, 11, 15);
    expect(
      isFreshPaid(
        _order(
          status: 'paid',
          paidAt: now.subtract(const Duration(seconds: 20)),
        ),
        now,
      ),
      isTrue,
    );
    expect(
      isFreshPaid(
        _order(status: 'paid', paidAt: now.subtract(const Duration(hours: 5))),
        now,
      ),
      isFalse,
    );
    expect(isFreshPaid(_order(), now), isFalse);
  });

  test('timeline is created, link sent, then the stored events', () {
    final created = DateTime(2026, 10, 10, 11, 2);
    final sent = DateTime(2026, 10, 10, 11, 4);
    final paid = DateTime(2026, 10, 10, 11, 31);
    final entries = buildTimeline(
      _order(
        status: 'paid',
        createdAt: created,
        linkSentAt: sent,
        paidAt: paid,
      ),
      [
        PaymentEvent(
          id: 'WH-PAID',
          eventType: 'PAYMENT.CAPTURE.COMPLETED',
          receivedAt: paid,
        ),
        PaymentEvent(
          id: 'WH-OK',
          eventType: 'CHECKOUT.ORDER.APPROVED',
          receivedAt: paid,
        ),
      ],
    );
    expect(entries.map((e) => e.label).toList(), [
      "Read from Jess's screenshot",
      'Checkout link sent',
      'Jess paid with PayPal',
      'Payment received',
    ]);
    expect(entries.last.emphasis, isTrue);
    expect(formatClock(created), '11:02');
    expect(fulfilmentLabel(_order()), 'Sat 10 Oct, 2pm');
  });

  test('a text order and a reconcile sweep still read honestly', () {
    final at = DateTime(2026, 10, 10, 12);
    final entries = buildTimeline(
      _order(
        status: 'paid',
        buyerName: null,
        sourceKind: 'text',
        createdAt: at,
        paidAt: at,
      ),
      [
        const PaymentEvent(
          id: 'reconcile-o1',
          eventType: 'reconcile',
          rawStatus: 'paid',
        ),
      ],
    );
    expect(entries.first.label, 'Read from a message');
    expect(entries.last.label, 'Payment received');
  });

  test('paidAt still says the money arrived when no event was stored', () {
    final at = DateTime(2026, 10, 10, 11, 31);
    final entries = buildTimeline(
      _order(status: 'paid', createdAt: at, paidAt: at),
      const [],
    );
    expect(entries.map((e) => e.label), contains('Payment received'));
  });

  test('deposit total is labelled as the amount due now', () {
    expect(totalLabel(_order(depositMinor: 2000)), 'Deposit now');
    expect(totalLabel(_order(status: 'paid', depositMinor: 2000)), 'Paid');
    expect(balanceCaption(_order()), 'on collection');
  });
}
