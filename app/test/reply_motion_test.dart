import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sorted/core/motion/sorted_motion.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/order/reply_screen.dart';
import 'package:sorted/models/order.dart';
import 'package:sorted/providers/orders_providers.dart';
import 'package:sorted/widgets/primary_button.dart';
import 'package:sorted/widgets/sorted_icon.dart';

const _link = 'https://www.sandbox.paypal.com/checkoutnow?token=PP1';

Order _sent() => const Order(
  id: 'o1',
  status: 'link_sent',
  buyerName: 'Jess M',
  subtotalMinor: 5600,
  amountDueMinor: 5600,
  approvalUrl: _link,
  draftedReply: "Hi Jess! That's sorted, £56 total. Pay here: $_link",
);

class _StubController extends DraftController {
  @override
  DraftState build() => DraftReady(_sent());
}

/// Reply ready, pushed from a page before it the way Draft pushes it, so the
/// push is real and there is something to arrive from.
Widget _host({bool reduce = false, Stream<List<Order>>? orders}) =>
    ProviderScope(
      overrides: [
        draftControllerProvider.overrideWith(_StubController.new),
        ordersProvider.overrideWith(
          (ref) => orders ?? Stream.value(const <Order>[]),
        ),
      ],
      child: MaterialApp.router(
        theme: sortedTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: child!,
        ),
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => context.push('/order/reply'),
                    child: const Text('get link'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/order/reply',
              pageBuilder: (_, s) => sortedPushPage(s, const ReplyScreen()),
            ),
          ],
        ),
      ),
    );

/// Everything above [target] that is changing its opacity, combined.
double _opacity(WidgetTester tester, Finder target) => find
    .ancestor(of: target, matching: find.byType(FadeTransition))
    .evaluate()
    .map((e) => (e.widget as FadeTransition).opacity.value)
    .fold(1.0, (a, b) => a * b);

/// The painted size of [target], which getSize cannot see through a scale.
Size _painted(WidgetTester tester, Finder target) => Rect.fromPoints(
  tester.getTopLeft(target),
  tester.getBottomRight(target),
).size;

final _tick = find.byKey(const Key('reply-tick'));
final _bubble = find.textContaining('Hi Jess!');
final _linkRow = find.text(_link);

Future<void> _open(
  WidgetTester tester, {
  bool reduce = false,
  Stream<List<Order>>? orders,
}) async {
  await tester.pumpWidget(_host(reduce: reduce, orders: orders));
  await tester.tap(find.text('get link'));
  await tester.pump();
}

/// Runs real frames until the push has landed and the moment is under way.
/// Frame by frame rather than one long pump: the push and the moment each
/// start their clocks on a frame of their own.
Future<void> _land(WidgetTester tester) async {
  final frames = (SortedDurations.medium.inMilliseconds + 40) ~/ 16;
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

bool _showsCheck(WidgetTester tester) => find
    .descendant(
      of: find.byType(PrimaryButton),
      matching: find.byWidgetPredicate(
        (w) => w is SortedIcon && w.icon == SortedIcons.check,
      ),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  group('the link arrives after the page does', () {
    testWidgets('nothing in it moves while the page is still travelling', (
      tester,
    ) async {
      await _open(tester);
      await tester.pump(const Duration(milliseconds: 80));
      // Held at its starting frame: two moves at once would fight.
      expect(_opacity(tester, _tick), 0);
      expect(_opacity(tester, _bubble), 0);
      expect(_opacity(tester, _linkRow), 0);
    });

    testWidgets('then the tick lands first, small and springing to size', (
      tester,
    ) async {
      await _open(tester);
      await _land(tester);
      expect(_opacity(tester, _tick), greaterThan(0));
      expect(_painted(tester, _tick).width, lessThan(44));
      // The reply waits its beat.
      expect(_opacity(tester, _bubble), 0);
    });

    testWidgets('the reply follows a beat later, rising like a sent message', (
      tester,
    ) async {
      await _open(tester);
      await _land(tester);
      final before = tester.getTopLeft(_bubble).dy;
      await tester.pump(
        SortedDurations.beat + const Duration(milliseconds: 60),
      );
      expect(_opacity(tester, _bubble), greaterThan(0));
      expect(_opacity(tester, _linkRow), 0, reason: 'the link is last');

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_bubble).dy, lessThan(before));
    });

    testWidgets('and everything settles exactly in place', (tester) async {
      await _open(tester);
      await tester.pumpAndSettle();
      expect(_opacity(tester, _tick), 1);
      expect(_opacity(tester, _bubble), 1);
      expect(_opacity(tester, _linkRow), 1);
      expect(_painted(tester, _tick), const Size(44, 44));
    });

    testWidgets('under reduced motion it fades in where it sits', (
      tester,
    ) async {
      await _open(tester, reduce: true);
      await tester.pumpAndSettle();
      final rest = tester.getTopLeft(_bubble);

      await _open(tester, reduce: true);
      await tester.pump(SortedDurations.medium);
      await tester.pump(
        SortedDurations.beat + const Duration(milliseconds: 20),
      );
      expect(_opacity(tester, _bubble), lessThan(1));
      expect(tester.getTopLeft(_bubble), rest, reason: 'no travel');
      expect(_painted(tester, _tick), const Size(44, 44), reason: 'no scale');
      await tester.pumpAndSettle();
    });
  });

  group('copy answers on the button', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('the copy icon turns into a tick, then back', (tester) async {
      await _open(tester);
      await tester.pumpAndSettle();
      expect(_showsCheck(tester), isFalse);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump(SortedDurations.short);
      expect(_showsCheck(tester), isTrue);

      await tester.pump(SortedDurations.confirmHold);
      await tester.pumpAndSettle();
      expect(
        _showsCheck(tester),
        isFalse,
        reason: 'a second copy finds the button it expects',
      );
      // The toast's own timer.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('payment landing while the seller is still here', () {
    final banner = find.descendant(
      of: find.byType(PaidPop),
      matching: find.byType(AnimatedContainer),
    );
    double width(WidgetTester tester) =>
        tester.getBottomRight(banner.first).dx -
        tester.getTopLeft(banner.first).dx;

    testWidgets('the banner gets the paid celebration', (tester) async {
      final live = StreamController<List<Order>>();
      addTearDown(live.close);
      await _open(tester, orders: live.stream);
      live.add([_sent()]);
      await tester.pumpAndSettle();
      final resting = width(tester);

      live.add([_sent().copyWith(status: 'paid')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      var peak = resting;
      for (var i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (width(tester) > peak) peak = width(tester);
      }
      expect(peak, greaterThan(resting));

      await tester.pumpAndSettle();
      expect(width(tester), moreOrLessEquals(resting, epsilon: 0.01));
      expect(find.text('Jess M paid'), findsOneWidget);
    });
  });
}
