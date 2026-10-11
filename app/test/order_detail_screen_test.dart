import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/orders/order_detail_screen.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/payment_event.dart';
import 'package:sorted/providers/orders_providers.dart';

const _link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';

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

Order jess({
  String status = 'paid',
  int? depositMinor,
  String? reply = "Hi Jess! That's sorted. Pay here: $_link",
  String? approvalUrl = _link,
  DateTime? createdAt,
  DateTime? linkSentAt,
  DateTime? paidAt,
  String? notes = '2pm',
}) {
  final subtotal = 5600;
  return Order(
    id: 'o1',
    status: status,
    buyerName: 'Jess M',
    lineItems: const [_cake, _brownie],
    subtotalMinor: subtotal,
    depositMinor: depositMinor,
    amountDueMinor: depositMinor ?? subtotal,
    fulfilment: Fulfilment(
      mode: 'collection',
      date: '2026-10-10',
      notes: notes,
    ),
    approvalUrl: approvalUrl,
    draftedReply: reply,
    createdAt: createdAt,
    linkSentAt: linkSentAt,
    paidAt: paidAt,
  );
}

Widget host({Stream<Order?>? order, Stream<List<PaymentEvent>>? events}) =>
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        orderByIdProvider.overrideWith(
          (ref, id) => order ?? Stream.value(jess()),
        ),
        paymentEventsProvider.overrideWith(
          (ref, id) => events ?? Stream.value(const <PaymentEvent>[]),
        ),
      ],
      child: MaterialApp(
        theme: sortedTheme(),
        home: const OrderDetailScreen(orderId: 'o1'),
      ),
    );

void main() {
  testWidgets('shows the slip, the link, the reply and the timeline', (
    tester,
  ) async {
    final created = DateTime(2026, 10, 10, 11, 2);
    final sent = DateTime(2026, 10, 10, 11, 4);
    final paid = DateTime(2026, 10, 10, 11, 31);
    await tester.pumpWidget(
      host(
        order: Stream.value(
          jess(createdAt: created, linkSentAt: sent, paidAt: paid),
        ),
        events: Stream.value([
          PaymentEvent(
            id: 'WH-OK',
            eventType: 'CHECKOUT.ORDER.APPROVED',
            receivedAt: paid,
          ),
          PaymentEvent(
            id: 'WH-PAID',
            eventType: 'PAYMENT.CAPTURE.COMPLETED',
            receivedAt: paid,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Order for Jess M'), findsOneWidget);
    expect(find.text('Sat 10 Oct, 2pm'), findsOneWidget);
    expect(find.text('Lemon drizzle cake'), findsOneWidget);
    expect(find.text('Brownie box'), findsOneWidget);
    expect(find.text('£42'), findsOneWidget);
    expect(find.text('£14'), findsOneWidget);
    expect(find.text('£56.00'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Sorted'), findsOneWidget);
    expect(find.text("Read from Jess's screenshot"), findsOneWidget);
    expect(find.text('Checkout link sent'), findsOneWidget);
    expect(find.text('Jess paid with PayPal'), findsOneWidget);
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('11:02'), findsOneWidget);
    expect(find.text('11:31'), findsWidgets);
    expect(
      find.textContaining('money is in your PayPal account'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkoutnow'), findsWidgets);
    expect(find.textContaining('Hi Jess!'), findsOneWidget);
    expect(find.text('No reminder has been sent yet.'), findsNothing);
  });

  testWidgets('shows the deposit and what is left on collection', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        order: Stream.value(
          jess(status: 'link_sent', depositMinor: 2000, paidAt: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deposit now'), findsOneWidget);
    expect(find.text('£20.00'), findsOneWidget);
    expect(find.text('£56.00'), findsOneWidget);
    expect(find.textContaining('£36.00 on collection'), findsOneWidget);
    expect(find.text('Link sent'), findsOneWidget);
    expect(find.text('Sorted'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('No reminder has been sent yet.'),
      200,
    );
    expect(find.text('No reminder has been sent yet.'), findsOneWidget);
  });

  testWidgets('copies the checkout link and the reply', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    await tester.tap(find.text('Copy reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(copied, contains(_link));
    expect(copied.any((text) => text.contains('Hi Jess!')), isTrue);
    expect(find.textContaining('Copied'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('says when the order is not on this shop', (tester) async {
    await tester.pumpWidget(host(order: Stream.value(null)));
    await tester.pumpAndSettle();
    expect(find.text('That order is not here'), findsOneWidget);
  });

  testWidgets('says when the order cannot be loaded', (tester) async {
    await tester.pumpWidget(
      host(order: Stream<Order?>.error(Exception('offline'))),
    );
    await tester.pump();
    expect(find.text('Could not load this order'), findsOneWidget);
  });

  testWidgets('says when the link and the reply were not kept', (tester) async {
    await tester.pumpWidget(
      host(
        order: Stream.value(
          jess(status: 'link_sent', reply: null, approvalUrl: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No checkout link on this order.'), findsOneWidget);
    expect(find.text('No reply was drafted for this order.'), findsOneWidget);
  });

  testWidgets('the stamp appears when the live order turns paid', (
    tester,
  ) async {
    final controller = StreamController<Order?>();
    addTearDown(controller.close);
    await tester.pumpWidget(host(order: controller.stream));
    controller.add(jess(status: 'link_sent', paidAt: null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Sorted'), findsNothing);
    expect(find.text('To pay'), findsOneWidget);

    controller.add(
      jess(status: 'paid', paidAt: DateTime(2026, 10, 10, 11, 31)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Sorted'), findsOneWidget);
    expect(find.text('Payment received'), findsOneWidget);
  });
}
