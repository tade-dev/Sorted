import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/order/reading_screen.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';

class _StubController extends DraftController {
  _StubController(this._initial);
  final DraftState _initial;
  @override
  DraftState build() => _initial;
}

Widget _host(DraftState state) => ProviderScope(
      overrides: [draftControllerProvider.overrideWith(() => _StubController(state))],
      child: MaterialApp.router(
        theme: sortedTheme(),
        routerConfig: GoRouter(
          initialLocation: '/order/reading',
          routes: [
            GoRoute(path: '/order/reading', builder: (_, _) => const ReadingScreen()),
            GoRoute(path: '/order/draft', builder: (_, _) => const Scaffold(body: Text('draft landed'))),
            GoRoute(path: '/order/new', builder: (_, _) => const Scaffold(body: Text('intake landed'))),
          ],
        ),
      ),
    );

const _order = Order(id: 'o1', buyerName: 'Jess M');

void main() {
  testWidgets('shows the checklist while the model works', (tester) async {
    await tester.pumpWidget(_host(const DraftReading(0)));
    await tester.pump();
    expect(find.textContaining('Reading'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    // flutter_animate schedules a zero-length start timer; let it fire.
    await tester.pump(Duration.zero);
  });

  testWidgets('moves to the draft once it is ready', (tester) async {
    await tester.pumpWidget(_host(const DraftReady(_order)));
    await tester.pumpAndSettle();
    expect(find.text('draft landed'), findsOneWidget);
  });

  testWidgets('says plainly when the photo had no order in it', (tester) async {
    // Photographing a receipt or a menu is a normal mistake and deserves an
    // explanation, not an error screen.
    await tester.pumpWidget(_host(const DraftEmpty('Sorted could not find an order in that.')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not find an order'), findsOneWidget);
    expect(find.textContaining('Try again'), findsWidgets);
  });

  testWidgets('offers another go after an empty read', (tester) async {
    await tester.pumpWidget(_host(const DraftEmpty('nothing there')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('intake landed'), findsOneWidget);
  });

  testWidgets('shows the message when the request failed', (tester) async {
    await tester.pumpWidget(_host(const DraftFailed('Sorted could not reach the server.')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not reach the server'), findsOneWidget);
  });
}
