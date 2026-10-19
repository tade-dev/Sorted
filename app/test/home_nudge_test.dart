import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/home/home_screen.dart';
import 'package:sorted/features/home/today_highlights.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/order_nudge.dart';
import 'package:sorted/providers/orders_providers.dart';
import 'package:sorted/providers/seller_provider.dart';

void main() {
  final now = DateTime(2026, 10, 15, 9);

  Order waiting({OrderNudge nudge = const OrderNudge()}) => Order(
    id: 'w1',
    status: 'link_sent',
    buyerName: 'Priya K',
    amountDueMinor: 2000,
    approvalUrl: 'https://paypal.test/pay',
    linkSentAt: now.subtract(const Duration(hours: 30)),
    nudge: nudge,
  );

  Widget host(List<Order> orders) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: HomeScreen(now: () => now)),
        ),
        GoRoute(
          path: '/orders/:id/nudge',
          builder: (_, s) => Text('nudge ${s.pathParameters['id']}'),
        ),
      ],
    );
    return ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ordersProvider.overrideWith((ref) => Stream.value(orders)),
        sellerProvider.overrideWith((ref) => Stream.value(null)),
        todayHighlightsProvider.overrideWith((ref) async => const <String>[]),
      ],
      child: MaterialApp.router(theme: sortedTheme(), routerConfig: router),
    );
  }

  testWidgets('Draft a nudge opens the nudge sheet for that order', (
    tester,
  ) async {
    await tester.pumpWidget(host([waiting()]));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    final button = find.byKey(const Key('draft-nudge'));
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Draft a nudge'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('nudge w1'), findsOneWidget);
  });

  testWidgets('a snoozed order drops off the card', (tester) async {
    final snoozed = waiting(
      nudge: OrderNudge(snoozedUntil: now.add(const Duration(hours: 12))),
    );
    await tester.pumpWidget(host([snoozed]));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('draft-nudge')), findsNothing);
  });
}
