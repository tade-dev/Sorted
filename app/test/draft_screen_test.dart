import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/data/orders_repository.dart';
import 'package:sorted/features/order/draft_screen.dart';
import 'package:sorted/models/ambiguity.dart';
import 'package:sorted/models/line_item.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';

const _cake = LineItem(
  id: 'li-1',
  productId: 'p1',
  variantIds: ['10-inch'],
  nameRaw: 'lemon drizzle cake',
  nameResolved: 'Lemon drizzle cake',
  qty: 1,
  unitPriceMinor: 4200,
  lineTotalMinor: 4200,
  matchConfidence: 1,
  matchMethod: 'exact',
);
const _brownies = LineItem(
  id: 'li-2',
  productId: 'p2',
  variantIds: ['box-of-6'],
  nameRaw: 'brownie box of 6',
  nameResolved: 'Brownie box',
  qty: 1,
  unitPriceMinor: 1400,
  lineTotalMinor: 1400,
  matchConfidence: 1,
  matchMethod: 'exact',
);

Order _order({List<Ambiguity> ambiguities = const []}) => Order(
  id: 'o1',
  status: 'draft',
  buyerName: 'Jess M',
  buyerHandle: 'jess.mcr',
  channel: 'instagram',
  lineItems: const [_cake, _brownies],
  subtotalMinor: 5600,
  amountDueMinor: 5600,
  fulfilment: const Fulfilment(
    mode: 'collection',
    date: '2026-10-10',
    notes: "For her mum's birthday",
  ),
  ambiguities: ambiguities,
);

class _FakeApi implements OrdersApi {
  Object? lastResolveBody;
  bool confirmed = false;
  Order? resolveReturns;
  Object? confirmError;

  @override
  Future<Map<String, dynamic>> draftFromImage(List<int> b, String f) async => {
    'order': null,
  };
  @override
  Future<Map<String, dynamic>> draftFromText(String t) async => {'order': null};
  @override
  Future<Map<String, dynamic>> resolve(String id, Object body) async {
    lastResolveBody = body;
    return {'order': (resolveReturns ?? _order()).toJson()};
  }

  @override
  Future<Map<String, dynamic>> confirm(String id, Object body) async {
    if (confirmError != null) throw confirmError!;
    confirmed = true;
    return {
      'order': _order()
          .copyWith(
            status: 'link_sent',
            approvalUrl: 'https://x/checkoutnow?token=T',
          )
          .toJson(),
    };
  }

  @override
  Future<Map<String, dynamic>> regenerateReply(String id, String tone) async =>
      {'draftedReply': 'hi'};
}

class _StubController extends DraftController {
  _StubController(this._order);
  final Order _order;
  @override
  DraftState build() => DraftReady(_order);
}

class _StateController extends DraftController {
  _StateController(this._state);
  final DraftState _state;
  @override
  DraftState build() => _state;
}

Widget _host(Order order, {_FakeApi? api}) => ProviderScope(
  overrides: [
    draftControllerProvider.overrideWith(() => _StubController(order)),
    if (api != null)
      ordersRepositoryProvider.overrideWithValue(OrdersRepository(api: api)),
  ],
  child: MaterialApp.router(
    theme: sortedTheme(),
    routerConfig: GoRouter(
      initialLocation: '/order/draft',
      routes: [
        GoRoute(path: '/order/draft', builder: (_, _) => const DraftScreen()),
        GoRoute(
          path: '/order/reply',
          builder: (_, _) => const Scaffold(body: Text('reply landed')),
        ),
      ],
    ),
  ),
);

Widget _hostState(DraftState state) => ProviderScope(
  overrides: [
    draftControllerProvider.overrideWith(() => _StateController(state)),
  ],
  child: MaterialApp.router(
    theme: sortedTheme(),
    routerConfig: GoRouter(
      initialLocation: '/order/draft',
      routes: [
        GoRoute(path: '/order/draft', builder: (_, _) => const DraftScreen()),
        GoRoute(
          path: '/order/new',
          builder: (_, _) => const Scaffold(body: Text('intake landed')),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('shows the buyer, the items and the total', (tester) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Jess M'), findsWidgets);
    expect(find.text('Lemon drizzle cake'), findsOneWidget);
    expect(find.text('Brownie box'), findsOneWidget);
    expect(find.textContaining('£56.00'), findsWidgets);
    expect(find.textContaining('Instagram'), findsOneWidget);
  });

  testWidgets('shows the collection date and note from the conversation', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sat 10 Oct'), findsWidgets);
    expect(find.textContaining('2026-10-10'), findsNothing);
    expect(find.textContaining("mum's birthday"), findsWidgets);
  });

  testWidgets('asks which size when the AI could not tell', (tester) async {
    // The beat the demo holds on: it asked instead of guessing.
    await tester.pumpWidget(
      _host(
        _order(
          ambiguities: const [
            Ambiguity(
              field: 'lineItems[0].variantIds',
              kind: 'missing',
              question: "Jess didn't say which size. Pick one.",
              options: ['8 inch', '10 inch'],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("didn't say which size"), findsWidgets);
    expect(find.text('8 inch'), findsOneWidget);
    expect(find.text('10 inch'), findsOneWidget);
    expect(find.text('Size needed'), findsOneWidget);
  });

  testWidgets('the create button is disabled while a question is unanswered', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _order(
          ambiguities: const [
            Ambiguity(
              field: 'lineItems[0].variantIds',
              kind: 'missing',
              question: 'Which size?',
              options: ['8 inch'],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
  });

  testWidgets('the create button is enabled with nothing outstanding', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('answering a question sends the variant to the API', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      _host(
        _order(
          ambiguities: const [
            Ambiguity(
              field: 'lineItems[0].variantIds',
              kind: 'missing',
              question: 'Which size?',
              options: ['8 inch', '10 inch'],
            ),
          ],
        ),
        api: api,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 inch'));
    await tester.pumpAndSettle();

    final body = api.lastResolveBody! as Map<String, dynamic>;
    final line = (body['lineItems'] as List).single as Map<String, dynamic>;
    expect(line['id'], 'li-1');
    expect(line['variantIds'], ['8-inch']);
    expect(body['resolvedAmbiguities'], ['lineItems[0].variantIds']);
  });

  testWidgets('tapping the only size clears the question and enables Create', (
    tester,
  ) async {
    const redVelvet = LineItem(
      id: 'li-1',
      productId: 'p-red',
      variantIds: ['8-inch'],
      nameRaw: 'red velvet cake',
      nameResolved: 'Red velvet cake',
      qty: 5,
      unitPriceMinor: 3600,
      lineTotalMinor: 18000,
      matchConfidence: 1,
      matchMethod: 'exact',
    );
    final asking = _order().copyWith(
      buyerName: 'Sarah',
      lineItems: const [redVelvet],
      subtotalMinor: 18000,
      amountDueMinor: 18000,
      ambiguities: const [
        Ambiguity(
          field: 'lineItems[0].size',
          kind: 'missing',
          question: 'What size should the red velvet cakes be?',
          options: ['8 inch'],
        ),
      ],
    );
    final api = _FakeApi()
      ..resolveReturns = asking.copyWith(ambiguities: const []);
    await tester.pumpWidget(_host(asking, api: api));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await tester.tap(find.text('8 inch'));
    await tester.pumpAndSettle();

    final body = api.lastResolveBody! as Map<String, dynamic>;
    final line = (body['lineItems'] as List).single as Map<String, dynamic>;
    expect(line['variantIds'], ['8-inch']);
    expect(body['resolvedAmbiguities'], ['lineItems[0].size']);
    expect(
      find.text('What size should the red velvet cakes be?'),
      findsNothing,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('says so when an answer does not clear the question', (
    tester,
  ) async {
    final asking = _order().copyWith(
      ambiguities: const [
        Ambiguity(
          field: 'lineItems[0].size',
          kind: 'missing',
          question: 'What size should the red velvet cakes be?',
          options: ['8 inch'],
        ),
      ],
    );
    final api = _FakeApi()..resolveReturns = asking;
    await tester.pumpWidget(_host(asking, api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 inch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('That did not clear the question. Try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('says so when the answer does not match a line', (tester) async {
    final api = _FakeApi();
    final asking = _order().copyWith(
      ambiguities: const [
        Ambiguity(
          field: 'lineItems[4].size',
          kind: 'missing',
          question: 'What size should that cake be?',
          options: ['8 inch'],
        ),
      ],
    );
    await tester.pumpWidget(_host(asking, api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 inch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('That answer did not match a line on this order.'),
      findsOneWidget,
    );
    expect(api.lastResolveBody, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('changing a quantity sends the new count to the API', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(_order(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty-more-li-1')));
    await tester.pumpAndSettle();

    final body = api.lastResolveBody! as Map<String, dynamic>;
    final line = (body['lineItems'] as List).single as Map<String, dynamic>;
    expect(line['id'], 'li-1');
    expect(line['qty'], 2);
  });

  testWidgets('quantity cannot drop below one', (tester) async {
    await tester.pumpWidget(_host(_order()));
    await tester.pumpAndSettle();
    final less = tester.widget<IconButton>(
      find.byKey(const Key('qty-less-li-1')),
    );
    expect(less.onPressed, isNull);
  });

  testWidgets('flags a line the catalogue did not have', (tester) async {
    const unmatched = LineItem(
      id: 'li-3',
      productId: null,
      variantIds: [],
      nameRaw: 'gluten free carrot cake',
      nameResolved: null,
      qty: 1,
      unitPriceMinor: 0,
      lineTotalMinor: 0,
      matchConfidence: 0,
      matchMethod: 'unmatched',
    );
    final order = _order().copyWith(lineItems: const [unmatched]);
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining('gluten free carrot cake'), findsWidgets);
    expect(find.textContaining('not in your catalogue'), findsWidgets);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
  });

  testWidgets('creating the link goes to the reply', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_host(_order(), api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(api.confirmed, isTrue);
    expect(find.text('reply landed'), findsOneWidget);
  });

  testWidgets(
    'stays on the draft and says why when the link cannot be created',
    (tester) async {
      final api = _FakeApi()
        ..confirmError = ArgumentError(
          'PayPal rejected that request. Nothing was charged.',
        );
      await tester.pumpWidget(_host(_order(), api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Nothing was charged'), findsOneWidget);
      expect(find.text('Order draft'), findsOneWidget);
      expect(api.confirmed, isFalse);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('shows the deposit split when one is set', (tester) async {
    final order = _order().copyWith(depositMinor: 2000, amountDueMinor: 2000);
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining('£20.00'), findsWidgets);
    expect(find.textContaining('£36.00'), findsWidgets);
    expect(find.text('Deposit now'), findsOneWidget);
  });

  testWidgets('shows a missing date and says why the link is off', (
    tester,
  ) async {
    final order = _order().copyWith(
      fulfilment: const Fulfilment(mode: 'collection'),
      ambiguities: const [
        Ambiguity(
          field: 'fulfilment.date',
          kind: 'missing',
          question: "They didn't say which day.",
          options: ['2026-10-18'],
        ),
      ],
    );
    await tester.pumpWidget(_host(order));
    await tester.pumpAndSettle();
    expect(find.textContaining("didn't say which day"), findsWidgets);
    expect(find.text('Choose a date'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
  });

  testWidgets('picking a date sends it to the API', (tester) async {
    final api = _FakeApi();
    final order = _order().copyWith(
      fulfilment: const Fulfilment(mode: 'collection'),
      ambiguities: const [
        Ambiguity(
          field: 'fulfilment.date',
          kind: 'missing',
          question: "They didn't say which day.",
          options: ['2026-10-18'],
        ),
      ],
    );
    await tester.pumpWidget(_host(order, api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sun 18 Oct'));
    await tester.pumpAndSettle();

    final body = api.lastResolveBody! as Map<String, dynamic>;
    expect(body['fulfilment'], {'date': '2026-10-18'});
    expect(body['resolvedAmbiguities'], ['fulfilment.date']);
  });

  testWidgets('a missing buyer name does not disable the link', (tester) async {
    final api = _FakeApi();
    final order = _order().copyWith(
      buyerName: null,
      ambiguities: const [
        Ambiguity(
          field: 'buyerName',
          kind: 'missing',
          question: 'Who is the cake for?',
        ),
      ],
    );
    await tester.pumpWidget(_host(order, api: api));
    await tester.pumpAndSettle();
    expect(find.text('Who is the cake for?'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const Key('ambiguity-text-buyerName')),
      'Jess M',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final body = api.lastResolveBody! as Map<String, dynamic>;
    expect(body['buyerName'], 'Jess M');
    expect(body['resolvedAmbiguities'], ['buyerName']);
  });

  testWidgets('shows a loader until the draft is ready', (tester) async {
    await tester.pumpWidget(_hostState(const DraftIdle()));
    await tester.pump();
    expect(find.text('Loading the order'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('says plainly when there is no order to show', (tester) async {
    await tester.pumpWidget(
      _hostState(const DraftEmpty('Sorted could not find an order in that.')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not find an order'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('intake landed'), findsOneWidget);
  });

  testWidgets('shows the message when reading the message failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _hostState(const DraftFailed('Sorted could not reach the server.')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not reach the server'), findsOneWidget);
  });
}
