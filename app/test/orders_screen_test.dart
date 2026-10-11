import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_colors.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/orders/order_detail_screen.dart';
import 'package:sorted/features/orders/orders_screen.dart';
import 'package:sorted/features/orders/status_pill.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/payment_event.dart';
import 'package:sorted/providers/orders_providers.dart';
import 'package:sorted/router.dart';

const _cake = LineItem(
  id: 'li-1',
  productId: 'p1',
  nameRaw: 'lemon drizzle',
  nameResolved: 'Lemon drizzle cake',
  qty: 1,
  unitPriceMinor: 4200,
  lineTotalMinor: 4200,
);

Order sample({
  String id = 'o1',
  String status = 'link_sent',
  String? buyerName = 'Jess M',
  String? buyerHandle,
  int amountDueMinor = 5600,
  List<LineItem> lines = const [_cake],
  DateTime? paidAt,
  DateTime? linkSentAt,
}) => Order(
  id: id,
  status: status,
  buyerName: buyerName,
  buyerHandle: buyerHandle,
  lineItems: lines,
  subtotalMinor: amountDueMinor,
  amountDueMinor: amountDueMinor,
  paidAt: paidAt,
  linkSentAt: linkSentAt,
);

Widget host(Stream<List<Order>> orders) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    ordersProvider.overrideWith((ref) => orders),
    orderByIdProvider.overrideWith((ref, id) => Stream.value(sample(id: id))),
    paymentEventsProvider.overrideWith(
      (ref, id) => Stream.value(const <PaymentEvent>[]),
    ),
  ],
  child: MaterialApp.router(
    theme: sortedTheme(),
    routerConfig: GoRouter(
      initialLocation: '/orders',
      routes: [
        GoRoute(
          path: '/orders',
          builder: (_, _) => const Scaffold(body: OrdersScreen()),
        ),
        GoRoute(
          path: '/orders/:orderId',
          builder: (_, state) =>
              OrderDetailScreen(orderId: state.pathParameters['orderId']!),
        ),
        GoRoute(
          path: '/order/new',
          builder: (_, _) => const Scaffold(body: Text('intake')),
        ),
      ],
    ),
  ),
);

void main() {
  test('the orders routes are on the app router', () {
    final paths = <String>[];
    void walk(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute) {
          paths.add(route.path);
          walk(route.routes);
        } else if (route is ShellRoute) {
          walk(route.routes);
        }
      }
    }

    walk(appRouter.configuration.routes);
    expect(paths, contains('/orders'));
    expect(paths, contains('/orders/:orderId'));
  });

  testWidgets('shows every status, the buyer and the amount', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final orders = [
      sample(
        id: 'a',
        status: 'draft',
        buyerName: 'Draft buyer',
        amountDueMinor: 1000,
      ),
      sample(
        id: 'b',
        status: 'link_sent',
        buyerName: 'Ade O',
        amountDueMinor: 3600,
      ),
      sample(
        id: 'c',
        status: 'processing',
        buyerName: 'Processing buyer',
        amountDueMinor: 1100,
      ),
      sample(
        id: 'd',
        status: 'pending',
        buyerName: 'Pending buyer',
        amountDueMinor: 1200,
      ),
      sample(
        id: 'e',
        status: 'declined',
        buyerName: 'Declined buyer',
        amountDueMinor: 1300,
      ),
      sample(
        id: 'f',
        status: 'paid',
        buyerName: 'Jess M',
        amountDueMinor: 5600,
        paidAt: DateTime.now(),
      ),
      sample(
        id: 'g',
        status: 'cancelled',
        buyerName: 'Cancelled buyer',
        amountDueMinor: 1400,
      ),
      sample(
        id: 'h',
        status: 'expired',
        buyerName: 'Expired buyer',
        amountDueMinor: 1500,
      ),
      sample(
        id: 'i',
        buyerName: null,
        buyerHandle: null,
        status: 'draft',
        amountDueMinor: 900,
      ),
    ];

    await tester.pumpWidget(host(Stream.value(orders)));
    await tester.pumpAndSettle();

    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Live from PayPal'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Link sent'), findsOneWidget);
    expect(find.text('Confirming'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Cancelled'), findsWidgets);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Buyer'), findsOneWidget);
    expect(find.text('£56'), findsOneWidget);
    expect(find.text('£36'), findsOneWidget);
    expect(find.text('Lemon drizzle cake'), findsWidgets);
    expect(find.text('Just now'), findsOneWidget);

    final paidPill = tester.widget<Container>(
      find
          .descendant(
            of: find
                .byType(StatusPill)
                .at(orders.indexWhere((order) => order.status == 'paid')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (paidPill.decoration! as BoxDecoration).color,
      SortedColors.light.successTint,
    );
  });

  testWidgets('empty shop offers a way to start an order', (tester) async {
    await tester.pumpWidget(host(Stream.value(const [])));
    await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);
    await tester.tap(find.text('New order'));
    await tester.pumpAndSettle();
    expect(find.text('intake'), findsOneWidget);
  });

  testWidgets('a failed stream says so, instead of a blank list', (
    tester,
  ) async {
    await tester.pumpWidget(host(Stream.error(Exception('offline'))));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your orders'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('filters down to the waiting orders', (tester) async {
    await tester.pumpWidget(
      host(
        Stream.value([
          sample(id: 'a', status: 'paid', buyerName: 'Jess M'),
          sample(id: 'b', status: 'link_sent', buyerName: 'Ade O'),
          sample(id: 'c', status: 'draft', buyerName: 'Tom H'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waiting 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ade O'), findsOneWidget);
    expect(find.text('Jess M'), findsNothing);
    expect(find.text('Tom H'), findsNothing);
    expect(find.text('Nothing in this view.'), findsNothing);
  });

  testWidgets('flips Link sent to Paid when the stream emits', (tester) async {
    final controller = StreamController<List<Order>>();
    addTearDown(controller.close);
    await tester.pumpWidget(host(controller.stream));
    controller.add([sample(status: 'link_sent', buyerName: 'Jess M')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Link sent'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);

    controller.add([
      sample(status: 'paid', buyerName: 'Jess M', paidAt: DateTime.now()),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Link sent'), findsNothing);
    expect(find.text('Just now'), findsOneWidget);
  });

  testWidgets('a row opens that order', (tester) async {
    await tester.pumpWidget(host(Stream.value([sample(buyerName: 'Jess M')])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jess M'));
    await tester.pumpAndSettle();
    expect(find.text('Order for Jess M'), findsOneWidget);
  });
}
