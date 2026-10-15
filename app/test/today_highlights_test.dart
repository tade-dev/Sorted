import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/home/home_screen.dart';
import 'package:sorted/features/home/today_highlights.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';
import 'package:sorted/providers/seller_provider.dart';

void main() {
  test('parseHighlights reads the summary body and skips junk', () {
    expect(
      parseHighlights({
        'summary': {
          'highlights': ['Two paid today ', '', 3, 'One link still open'],
        },
      }),
      ['Two paid today', 'One link still open'],
    );
    expect(parseHighlights({}), isEmpty);
    expect(
      parseHighlights({
        'summary': {'highlights': null},
      }),
      isEmpty,
    );
  });

  final now = DateTime(2026, 10, 15, 9);
  final orders = [
    Order(id: 'a', status: 'paid', amountDueMinor: 4800, paidAt: now),
    Order(id: 'b', status: 'link_sent', amountDueMinor: 2000, linkSentAt: now),
  ];

  Widget host(List<String> highlights) => ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ordersProvider.overrideWith((ref) => Stream.value(orders)),
      sellerProvider.overrideWith((ref) => Stream.value(null)),
      todayHighlightsProvider.overrideWith((ref) async => highlights),
    ],
    child: MaterialApp(
      theme: sortedTheme(),
      home: Scaffold(body: HomeScreen(now: () => now)),
    ),
  );

  testWidgets('shows the highlights under the card figures', (tester) async {
    await tester.pumpWidget(host(['Two orders paid', 'One link still open']));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 paid'), findsOneWidget);
    expect(find.text('Two orders paid · One link still open'), findsOneWidget);
  });

  testWidgets('shows no highlight line when there are none', (tester) async {
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('today-highlights')), findsNothing);
    expect(find.text('1 paid'), findsOneWidget);
  });
}
