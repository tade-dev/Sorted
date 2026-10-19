import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/orders/order_detail_screen.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/payment_event.dart';
import 'package:sorted/providers/orders_providers.dart';

const _link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';

Order jess(String status, {String? approvalUrl = _link}) => Order(
  id: 'o1',
  status: status,
  buyerName: 'Jess M',
  lineItems: const [
    LineItem(
      id: 'li-1',
      productId: 'p1',
      nameRaw: 'lemon drizzle',
      nameResolved: 'Lemon drizzle cake',
      qty: 1,
      unitPriceMinor: 4200,
      lineTotalMinor: 4200,
    ),
  ],
  subtotalMinor: 4200,
  amountDueMinor: 4200,
  approvalUrl: status == 'draft' ? null : approvalUrl,
  draftedReply: status == 'draft' ? null : "Hi Jess! Pay here: $_link",
  createdAt: DateTime(2026, 10, 10, 11, 2),
  linkSentAt: status == 'draft' ? null : DateTime(2026, 10, 10, 11, 4),
);

class _CancelApi extends Fake implements OrdersApi {
  _CancelApi({this.onCancel, this.error});

  final void Function()? onCancel;
  final Object? error;
  int cancels = 0;

  @override
  Future<Map<String, dynamic>> cancel(String orderId) async {
    cancels++;
    if (error != null) throw error!;
    onCancel?.call();
    return {'order': jess('cancelled').toJson()};
  }

  @override
  Future<Map<String, dynamic>> refresh(String orderId) async => const {};
}

Widget host({
  required Stream<Order?> order,
  Stream<List<PaymentEvent>>? events,
  OrdersApi? api,
}) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    ordersRepositoryProvider.overrideWithValue(
      OrdersRepository(api: api ?? _CancelApi()),
    ),
    orderByIdProvider.overrideWith((ref, id) => order),
    paymentEventsProvider.overrideWith(
      (ref, id) => events ?? Stream.value(const <PaymentEvent>[]),
    ),
  ],
  child: MaterialApp(
    theme: sortedTheme(),
    home: const OrderDetailScreen(orderId: 'o1'),
  ),
);

/// The action sits at the foot of a lazily built list, so scroll to it.
Future<Finder> scrollToCancel(WidgetTester tester) async {
  final button = find.byKey(const Key('cancel-order'));
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return button;
}

/// Scrolls the whole list through, so "not there" means not built at all.
Future<void> scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
  await tester.pumpAndSettle();
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(await scrollToCancel(tester));
  await tester.pumpAndSettle();
}

void main() {
  for (final status in ['draft', 'link_sent', 'declined']) {
    testWidgets('a $status order offers Cancel order', (tester) async {
      await tester.pumpWidget(host(order: Stream.value(jess(status))));
      await tester.pumpAndSettle();
      expect(await scrollToCancel(tester), findsOneWidget);
    });
  }

  for (final status in [
    'paid',
    'processing',
    'pending',
    'cancelled',
    'expired',
  ]) {
    testWidgets('a $status order has no Cancel order', (tester) async {
      await tester.pumpWidget(host(order: Stream.value(jess(status))));
      await tester.pumpAndSettle();
      await scrollToEnd(tester);
      expect(find.byKey(const Key('cancel-order')), findsNothing);
    });
  }

  testWidgets('asks first, and Keep order leaves it alone', (tester) async {
    final api = _CancelApi();
    await tester.pumpWidget(
      host(order: Stream.value(jess('link_sent')), api: api),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    expect(find.text('Cancel this order?'), findsOneWidget);
    expect(
      find.text(
        "The checkout link stops working, so Jess can't pay on it. You can't undo this.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('keep-order')));
    await tester.pumpAndSettle();

    expect(api.cancels, 0);
    expect(find.text('Cancel this order?'), findsNothing);
  });

  testWidgets('confirming cancels, and the live order turns Cancelled', (
    tester,
  ) async {
    final orders = StreamController<Order?>();
    addTearDown(orders.close);
    final api = _CancelApi(onCancel: () => orders.add(jess('cancelled')));
    await tester.pumpWidget(host(order: orders.stream, api: api));
    orders.add(jess('link_sent'));
    await tester.pumpAndSettle();
    expect(find.text('Copy reply'), findsOneWidget);

    await openSheet(tester);
    await tester.tap(find.byKey(const Key('confirm-cancel-order')));
    await tester.pumpAndSettle();

    expect(api.cancels, 1);
    expect(find.text('Order cancelled'), findsOneWidget);
    expect(find.text('Cancelled'), findsWidgets);
    expect(find.byKey(const Key('closed-note')), findsOneWidget);
    expect(find.text('Copy reply'), findsNothing);
    expect(find.text('Copy link'), findsNothing);
    expect(find.byKey(const Key('cancel-order')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('shows why the API refused, in its words', (tester) async {
    final refusal = DioException(
      requestOptions: RequestOptions(path: '/v1/orders/o1/cancel'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/v1/orders/o1/cancel'),
        statusCode: 409,
        data: {
          'error': {
            'code': 'ORDER_STATE_INVALID',
            'message': 'That order is already paid, so Sorted cannot cancel it. Refund it in PayPal instead.',
          },
        },
      ),
    );
    await tester.pumpWidget(
      host(
        order: Stream.value(jess('link_sent')),
        api: _CancelApi(error: refusal),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('confirm-cancel-order')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'That order is already paid, so Sorted cannot cancel it. Refund it in PayPal instead.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
    'a cancelled order shows the pill and the closed note, not the link',
    (tester) async {
      await tester.pumpWidget(
        host(
          order: Stream.value(jess('cancelled')),
          events: Stream.value([
            PaymentEvent(
              id: 'cancel-o1',
              eventType: 'cancelled',
              receivedAt: DateTime(2026, 10, 11, 9),
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      expect(
        find.text(
          'You cancelled this order. Its checkout link no longer takes payment.',
        ),
        findsOneWidget,
      );
      expect(find.text('You cancelled the order'), findsOneWidget);
      expect(find.text('Checkout link'), findsNothing);
      expect(find.text('Copy reply'), findsNothing);
      expect(find.text('Edit order'), findsNothing);
    },
  );

  testWidgets('an expired order says the link expired', (tester) async {
    await tester.pumpWidget(host(order: Stream.value(jess('expired'))));
    await tester.pumpAndSettle();
    expect(find.text('Expired'), findsOneWidget);
    expect(find.textContaining('This link expired unpaid'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
  });

  testWidgets('money taken on a closed link is shown as a refund, not a sale', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        order: Stream.value(jess('cancelled')),
        events: Stream.value([
          PaymentEvent(
            id: 'WH-LATE',
            eventType: 'PAYMENT.CAPTURE.COMPLETED',
            receivedAt: DateTime(2026, 10, 11, 9),
            refundDue: true,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Paid on a closed link. Refund it in PayPal'),
      findsOneWidget,
    );
    expect(find.text('Payment received'), findsNothing);
  });

  testWidgets('under reduced motion the closed note is simply there', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(order: Stream.value(jess('cancelled'))),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('closed-note')), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
