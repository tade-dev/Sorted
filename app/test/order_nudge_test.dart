import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/orders/nudge_rules.dart';
import 'package:sorted/features/orders/nudge_screen.dart';
import 'package:sorted/features/orders/order_detail_screen.dart';
import 'package:sorted/features/orders/order_presentation.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/models/order_nudge.dart';
import 'package:sorted/models/payment_event.dart';
import 'package:sorted/providers/orders_providers.dart';

const _link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';
final _now = DateTime(2026, 10, 19, 10);

Order priya(
  String status, {
  Duration age = const Duration(hours: 30),
  OrderNudge nudge = const OrderNudge(),
}) => Order(
  id: 'o1',
  status: status,
  buyerName: 'Priya K',
  lineItems: const [
    LineItem(
      id: 'li-1',
      productId: 'p1',
      nameRaw: 'celebration cake',
      nameResolved: 'Celebration cake',
      qty: 1,
      unitPriceMinor: 6000,
      lineTotalMinor: 6000,
    ),
  ],
  subtotalMinor: 6000,
  depositMinor: 2000,
  amountDueMinor: 2000,
  approvalUrl: status == 'draft' ? null : _link,
  createdAt: _now.subtract(age).subtract(const Duration(minutes: 2)),
  linkSentAt: status == 'draft' ? null : _now.subtract(age),
  nudge: nudge,
);

class FakeNudgeApi extends Fake implements OrdersApi {
  final drafts = <String>[];
  final sent = <String>[];
  int snoozes = 0;
  Completer<void>? hold;
  Object? sentError;

  @override
  Future<Map<String, dynamic>> draftNudge(String orderId, String tone) async {
    drafts.add(tone);
    await hold?.future;
    return {
      'nudge': {'text': 'Hi Priya! A $tone reminder. You can pay here: $_link'},
      'source': 'template',
    };
  }

  @override
  Future<Map<String, dynamic>> nudgeSent(String orderId, String text) async {
    sent.add(text);
    if (sentError != null) throw sentError!;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> snoozeNudge(String orderId) async {
    snoozes++;
    return const {};
  }
}

Widget nudgeHost(Order? order, FakeNudgeApi api) {
  final router = GoRouter(
    initialLocation: '/orders/o1/nudge',
    routes: [
      GoRoute(
        path: '/orders/:id/nudge',
        builder: (_, _) => NudgeScreen(orderId: 'o1', now: () => _now),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, _) => const Scaffold(body: Text('order detail')),
      ),
    ],
  );
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ordersRepositoryProvider.overrideWithValue(OrdersRepository(api: api)),
      orderByIdProvider.overrideWith((ref, id) => Stream.value(order)),
    ],
    child: MaterialApp.router(theme: sortedTheme(), routerConfig: router),
  );
}

Widget detailHost(Order order) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    ordersRepositoryProvider.overrideWithValue(
      OrdersRepository(api: FakeNudgeApi()),
    ),
    orderByIdProvider.overrideWith((ref, id) => Stream.value(order)),
    paymentEventsProvider.overrideWith(
      (ref, id) => Stream.value(const <PaymentEvent>[]),
    ),
  ],
  child: MaterialApp(
    theme: sortedTheme(),
    home: const OrderDetailScreen(orderId: 'o1'),
  ),
);

Future<void> scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
  await tester.pumpAndSettle();
}

void main() {
  group('OrderNudge', () {
    test('reads what the API writes, and treats a missing map as none', () {
      final n = OrderNudge.fromJson({
        'count': 1,
        'lastSentAt': '2026-10-18T09:00:00.000Z',
        'lastText': 'Hi',
        'snoozedUntil': null,
        'draftText': '  ',
      });
      expect(n.count, 1);
      expect(n.lastSentAt, DateTime.utc(2026, 10, 18, 9));
      expect(n.draftText, isNull);
      expect(OrderNudge.fromJson(null), const OrderNudge());
      expect(Order.fromJson({'id': 'x', 'status': 'link_sent'}).nudge.count, 0);
    });

    test('survives a round trip through the order', () {
      final order = priya(
        'link_sent',
        nudge: OrderNudge(count: 2, lastSentAt: _now),
      );
      final back = Order.fromJson(order.toJson());
      expect(back.nudge.count, 2);
      expect(back.nudge.lastSentAt!.isAtSameMomentAs(_now), isTrue);
    });
  });

  group('nudge rules', () {
    test('only an unpaid link a day old can be nudged', () {
      expect(canNudge(priya('link_sent'), _now), isTrue);
      expect(
        canNudge(priya('link_sent', age: const Duration(hours: 23)), _now),
        isFalse,
      );
      for (final status in [
        'paid',
        'cancelled',
        'expired',
        'processing',
        'pending',
        'declined',
        'draft',
      ]) {
        expect(canNudge(priya(status), _now), isFalse, reason: status);
        expect(nudgeRefusal(priya(status), _now), isNotNull, reason: status);
      }
      expect(
        nudgeRefusal(priya('paid'), _now),
        'Priya has already paid. Nothing to chase.',
      );
    });

    test(
      'the second reminder waits for three days and a day after the first',
      () {
        final once = OrderNudge(
          count: 1,
          lastSentAt: _now.subtract(const Duration(hours: 30)),
        );
        expect(
          nudgeDue(
            priya('link_sent', age: const Duration(hours: 60), nudge: once),
            _now,
          ),
          isFalse,
        );
        expect(
          nudgeDue(
            priya('link_sent', age: const Duration(hours: 80), nudge: once),
            _now,
          ),
          isTrue,
        );
        final twice = OrderNudge(
          count: 2,
          lastSentAt: _now.subtract(const Duration(days: 3)),
        );
        expect(
          nudgeDue(
            priya('link_sent', age: const Duration(days: 6), nudge: twice),
            _now,
          ),
          isFalse,
        );
      },
    );

    test('Order detail says how many reminders went out', () {
      expect(
        reminderHistory(priya('link_sent'), _now),
        'No reminder has been sent yet.',
      );
      final once = OrderNudge(count: 1, lastSentAt: DateTime(2026, 10, 18, 9));
      expect(
        reminderHistory(priya('link_sent', nudge: once), _now),
        'One reminder sent, last on Sunday 18 Oct.',
      );
      final snoozed = OrderNudge(
        snoozedUntil: _now.add(const Duration(hours: 4)),
      );
      expect(
        reminderHistory(priya('link_sent', nudge: snoozed), _now),
        'No reminder has been sent yet. Sorted will remind you tomorrow.',
      );
    });

    test('the timeline shows the reminder after the link went out', () {
      final at = _now.subtract(const Duration(hours: 2));
      final order = priya(
        'link_sent',
        nudge: OrderNudge(count: 1, lastSentAt: at),
      );
      final labels = buildTimeline(
        order,
        const [],
      ).map((e) => e.label).toList();
      expect(labels.last, 'Reminder sent');
      expect(
        labels.indexOf('Checkout link sent'),
        lessThan(labels.indexOf('Reminder sent')),
      );
    });
  });

  group('NudgeScreen', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
    });

    testWidgets('drafts a reminder and lays it out like Nudge.dc.html', (
      tester,
    ) async {
      final api = FakeNudgeApi()..hold = Completer<void>();
      await tester.pumpWidget(nudgeHost(priya('link_sent'), api));
      await tester.pump();
      await tester.pump();

      expect(find.text('Payment nudge'), findsOneWidget);
      expect(find.text('Nudge Priya'), findsOneWidget);
      expect(find.text('Celebration cake deposit'), findsOneWidget);
      expect(find.text('£20'), findsOneWidget);
      expect(find.text('Sorted drafted this for you'), findsOneWidget);
      // Nothing to copy while it is still writing.
      final copy = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: find.byKey(const Key('copy-nudge')),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(copy.onPressed, isNull);

      api.hold!.complete();
      await tester.pumpAndSettle();
      expect(api.drafts, ['friendly']);
      expect(
        find.text('Hi Priya! A friendly reminder. You can pay here:'),
        findsOneWidget,
      );
      expect(find.text(_link), findsOneWidget);
    });

    testWidgets('a reminder the sweep already wrote is shown, not redrafted', (
      tester,
    ) async {
      final api = FakeNudgeApi();
      final order = priya(
        'link_sent',
        nudge: const OrderNudge(draftText: 'Hi Priya! Waiting one.'),
      );
      await tester.pumpWidget(nudgeHost(order, api));
      await tester.pumpAndSettle();
      expect(api.drafts, isEmpty);
      expect(find.text('Hi Priya! Waiting one.'), findsOneWidget);
    });

    testWidgets('a tone chip writes it again in that tone', (tester) async {
      final api = FakeNudgeApi();
      await tester.pumpWidget(nudgeHost(priya('link_sent'), api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nudge-tone-firm')));
      await tester.pumpAndSettle();
      expect(api.drafts, ['friendly', 'firm']);
      expect(
        find.text('Hi Priya! A firm reminder. You can pay here:'),
        findsOneWidget,
      );
    });

    testWidgets('Copy nudge copies the whole text, records it and closes', (
      tester,
    ) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      final api = FakeNudgeApi();
      await tester.pumpWidget(nudgeHost(priya('link_sent'), api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy nudge'));
      await tester.pumpAndSettle();

      const full = 'Hi Priya! A friendly reminder. You can pay here: $_link';
      expect(copied, full);
      expect(api.sent, [full]);
      expect(find.text('Copied. Paste it into the chat.'), findsOneWidget);
      expect(find.text('order detail'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Remind me tomorrow snoozes and closes', (tester) async {
      final api = FakeNudgeApi();
      await tester.pumpWidget(nudgeHost(priya('link_sent'), api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remind me tomorrow'));
      await tester.pumpAndSettle();
      expect(api.snoozes, 1);
      expect(api.sent, isEmpty);
      expect(find.text('Sorted will remind you tomorrow.'), findsOneWidget);
      expect(find.text('order detail'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    for (final status in ['paid', 'cancelled', 'expired']) {
      testWidgets('a $status order is never nudged', (tester) async {
        final api = FakeNudgeApi();
        await tester.pumpWidget(nudgeHost(priya(status), api));
        await tester.pumpAndSettle();
        expect(find.text('Nothing to nudge'), findsOneWidget);
        expect(find.text('Copy nudge'), findsNothing);
        expect(api.drafts, isEmpty);
      });
    }
  });

  group('Order detail', () {
    testWidgets('offers Draft a nudge on a day-old unpaid link', (
      tester,
    ) async {
      await tester.pumpWidget(
        detailHost(priya('link_sent', age: const Duration(days: 2))),
      );
      await tester.pumpAndSettle();
      await scrollToEnd(tester);
      expect(find.byKey(const Key('draft-nudge')), findsOneWidget);
      expect(find.text('No reminder has been sent yet.'), findsOneWidget);
    });

    testWidgets('not on a link sent this morning', (tester) async {
      final fresh = priya('link_sent').copyWith(linkSentAt: DateTime.now());
      await tester.pumpWidget(detailHost(fresh));
      await tester.pumpAndSettle();
      await scrollToEnd(tester);
      expect(find.byKey(const Key('draft-nudge')), findsNothing);
    });

    for (final status in ['paid', 'cancelled', 'expired', 'processing']) {
      testWidgets('not on a $status order', (tester) async {
        await tester.pumpWidget(
          detailHost(priya(status, age: const Duration(days: 2))),
        );
        await tester.pumpAndSettle();
        await scrollToEnd(tester);
        expect(find.byKey(const Key('draft-nudge')), findsNothing);
      });
    }
  });
}
