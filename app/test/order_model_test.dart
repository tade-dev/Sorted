import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/models/ambiguity.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';

const _line = LineItem(
  id: 'li-1',
  productId: 'p1',
  variantIds: ['10-inch'],
  nameRaw: 'lemon drizzle',
  nameResolved: 'Lemon drizzle cake',
  qty: 1,
  unitPriceMinor: 4200,
  lineTotalMinor: 4200,
  matchConfidence: 1,
  matchMethod: 'exact',
);

Order order({
  List<Ambiguity> ambiguities = const [],
  String? approvalUrl,
  int? depositMinor,
}) => Order(
  id: 'o1',
  status: 'draft',
  buyerName: 'Jess M',
  buyerHandle: 'jess.mcr',
  channel: 'instagram',
  lineItems: const [_line],
  subtotalMinor: 5600,
  depositMinor: depositMinor,
  amountDueMinor: depositMinor ?? 5600,
  fulfilment: const Fulfilment(mode: 'collection', date: '2026-10-10'),
  ambiguities: ambiguities,
  approvalUrl: approvalUrl,
);

void main() {
  test('round-trips through JSON', () {
    final o = order();
    expect(Order.fromJson(o.toJson()), o);
  });

  test('tolerates the nulls the API sends on a fresh draft', () {
    final json = order().toJson()
      ..remove('approvalUrl')
      ..remove('paypalOrderId')
      ..remove('draftedReply')
      ..remove('depositMinor');
    final o = Order.fromJson(json);
    expect(o.approvalUrl, isNull);
    expect(o.hasLink, isFalse);
  });

  test('isBlocked while a blocking ambiguity is unanswered', () {
    final o = order(
      ambiguities: const [
        Ambiguity(
          field: 'lineItems[0].variantIds',
          kind: 'missing',
          question: 'Which size?',
        ),
      ],
    );
    expect(o.isBlocked, isTrue);
    expect(o.blockingAmbiguities, hasLength(1));
  });

  test('a missing buyer name does not block the link', () {
    // The spec leaves the name nullable. It does not change the price.
    final o = order(
      ambiguities: const [
        Ambiguity(
          field: 'buyerName',
          kind: 'missing',
          question: 'Who is this for?',
        ),
      ],
    );
    expect(o.isBlocked, isFalse);
  });

  test('a missing collection date does block the link', () {
    final o = order(
      ambiguities: const [
        Ambiguity(
          field: 'fulfilment.date',
          kind: 'missing',
          question: 'Which day?',
        ),
      ],
    );
    expect(o.isBlocked, isTrue);
  });

  test('a non-blocking ambiguity does not block', () {
    final o = order(
      ambiguities: const [
        Ambiguity(
          field: 'x',
          kind: 'unclear',
          question: 'eh?',
          blocking: false,
        ),
      ],
    );
    expect(o.isBlocked, isFalse);
  });

  test('isBlocked is false with no ambiguities', () {
    expect(order().isBlocked, isFalse);
  });

  test('hasLink once PayPal has given one', () {
    expect(order(approvalUrl: 'https://x/checkoutnow?token=T').hasLink, isTrue);
  });

  test('balanceMinor is what is left after a deposit', () {
    // The Draft screen tells the buyer what is still owed on collection.
    expect(order(depositMinor: 2000).balanceMinor, 3600);
  });

  test('balanceMinor is zero when the whole order is paid up front', () {
    expect(order().balanceMinor, 0);
  });

  test('a line keeps the buyer\'s own words alongside the resolved name', () {
    expect(_line.nameRaw, 'lemon drizzle');
    expect(_line.nameResolved, 'Lemon drizzle cake');
  });

  test('an unmatched line has no product and no price', () {
    const unmatched = LineItem(
      id: 'li-2',
      productId: null,
      variantIds: [],
      nameRaw: 'carrot cake',
      nameResolved: null,
      qty: 1,
      unitPriceMinor: 0,
      lineTotalMinor: 0,
      matchConfidence: 0,
      matchMethod: 'unmatched',
    );
    expect(unmatched.isUnmatched, isTrue);
  });
}
