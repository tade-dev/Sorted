import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/order/reply_screen.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';

const _link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';

Order _sent({String? reply}) => Order(
  id: 'o1',
  status: 'link_sent',
  buyerName: 'Jess M',
  subtotalMinor: 5600,
  amountDueMinor: 5600,
  approvalUrl: _link,
  draftedReply: reply ?? "Hi Jess! That's sorted, £56 total. Pay here: $_link",
);

class _FakeApi implements OrdersApi {
  @override
  Future<Map<String, dynamic>> invoice(String orderId) async =>
      {'url': 'https://api.example.com/v1/invoice/s/$orderId/sig'};

  @override
  Future<Map<String, dynamic>> refresh(String orderId) async => const {};

  @override
  Future<Map<String, dynamic>> cancel(String orderId) async => const {};

  @override
  Future<Map<String, dynamic>> thankYou(String orderId) async => {'message': 'Thanks!'};

  String? lastTone;
  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> b, String f) async => {
    'order': null,
  };
  @override
  Future<Map<String, dynamic>> draftFromText(String t) async => {'order': null};
  @override
  Future<Map<String, dynamic>> resolve(String id, Object body) async => {
    'order': _sent().toJson(),
  };
  @override
  Future<Map<String, dynamic>> edit(String orderId, Object body) async => {'order': {}};

  @override
  Future<Map<String, dynamic>> confirm(String id, Object body) async => {
    'order': _sent().toJson(),
  };
  @override
  Future<Map<String, dynamic>> regenerateReply(String id, String tone) async {
    lastTone = tone;
    return {'draftedReply': 'Dear Jess, your order is confirmed. $_link'};
  }
}

class _StubController extends DraftController {
  _StubController(this._order);
  final Order _order;
  @override
  DraftState build() => DraftReady(_order);
}

Widget _host(
  Order order, {
  _FakeApi? api,
  Stream<List<Order>>? orders,
}) => ProviderScope(
  overrides: [
    draftControllerProvider.overrideWith(() => _StubController(order)),
    ordersProvider.overrideWith(
      (ref) => orders ?? Stream.value(const <Order>[]),
    ),
    if (api != null)
      ordersRepositoryProvider.overrideWithValue(OrdersRepository(api: api)),
  ],
  child: MaterialApp.router(
    theme: sortedTheme(),
    routerConfig: GoRouter(
      initialLocation: '/order/reply',
      routes: [
        GoRoute(path: '/order/reply', builder: (_, _) => const ReplyScreen()),
        GoRoute(
          path: '/orders',
          builder: (_, _) => const Scaffold(body: Text('orders landed')),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('shows the amount and the drafted reply', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    expect(find.textContaining('£56'), findsWidgets);
    expect(find.textContaining('Hi Jess!'), findsOneWidget);
  });

  testWidgets('shows the link so the seller can see what they are sending', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkoutnow'), findsWidgets);
  });

  testWidgets('copy puts the whole reply on the clipboard', (tester) async {
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

    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(copied, hasLength(1));
    expect(copied.single, contains(_link));
    expect(find.textContaining('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('changing the tone asks the API to rewrite it', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(_sent(), api: api));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Formal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formal'));
    await tester.pumpAndSettle();
    expect(api.lastTone, 'formal');
    expect(find.textContaining('Dear Jess'), findsOneWidget);
  });

  testWidgets('says it is waiting to be paid', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Waiting'), findsWidgets);
  });

  testWidgets('flips to paid when the live order does', (tester) async {
    await tester.pumpWidget(
      _host(
        _sent(),
        orders: Stream<List<Order>>.multi((controller) {
          controller.add([_sent()]);
          Future<void>.delayed(const Duration(milliseconds: 30), () {
            controller.add([_sent().copyWith(status: 'paid')]);
          });
        }),
      ),
    );
    await tester.pump();
    expect(find.text('Waiting for Jess M to pay'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    // The banner's words cross over rather than cut, so let the old ones out.
    await tester.pumpAndSettle();

    expect(find.text('Jess M paid'), findsOneWidget);
    expect(find.text('Waiting for Jess M to pay'), findsNothing);
  });

  testWidgets('offers the link alone when the draft failed', (tester) async {
    // draftReply can refuse to return a reply that lost the link. The seller
    // must still be able to get paid.
    final order = _sent().copyWith(draftedReply: null);
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining('checkoutnow'), findsWidgets);
    expect(find.textContaining('Copy'), findsWidgets);
    expect(find.textContaining('could not write the message'), findsOneWidget);
  });

  testWidgets('goes to orders', (tester) async {
    await tester.pumpWidget(_host(_sent()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to orders'));
    await tester.pumpAndSettle();
    expect(find.text('orders landed'), findsOneWidget);
  });
}
