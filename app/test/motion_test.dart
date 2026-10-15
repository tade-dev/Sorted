import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/sorted_motion.dart';
import 'package:sorted/core/theme/sorted_theme.dart';
import 'package:sorted/features/orders/status_pill.dart';

Widget _wrap(Widget child, {bool reduce = false}) => MaterialApp(
      theme: sortedTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('PaidAnnouncer', () {
    test('announces each newly paid order once, never the ones already paid', () {
      var haptics = 0;
      final said = <String>[];
      final a = PaidAnnouncer(haptic: () => haptics++, announce: said.add);

      a.observe([(id: 'old', status: 'paid', label: 'Paid: Old')]);
      expect(haptics, 0);

      a.observe([
        (id: 'old', status: 'paid', label: 'Paid: Old'),
        (id: 'o1', status: 'link_sent', label: 'Paid: Jess'),
      ]);
      expect(haptics, 0);

      a.observe([(id: 'o1', status: 'paid', label: 'Paid: Jess, £56.00')]);
      a.observe([(id: 'o1', status: 'paid', label: 'Paid: Jess, £56.00')]);
      expect(haptics, 1);
      expect(said, ['Paid: Jess, £56.00']);
    });
  });

  testWidgets('EnterStagger shows rows at once under Reduce Motion', (tester) async {
    await tester.pumpWidget(_wrap(const EnterStagger(index: 0, child: Text('row')), reduce: true));
    expect(find.byType(Animate), findsNothing);
    expect(find.text('row'), findsOneWidget);
  });

  testWidgets('EnterStagger fades the first rows in and settles', (tester) async {
    await tester.pumpWidget(_wrap(const EnterStagger(index: 2, child: Text('row'))));
    expect(find.byType(Animate), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('row'), findsOneWidget);
  });

  testWidgets('StatusPill morphs its label when the status changes', (tester) async {
    await tester.pumpWidget(_wrap(const StatusPill(status: 'link_sent')));
    await tester.pumpWidget(_wrap(const StatusPill(status: 'paid')));
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-morph both labels are on screen, cross-fading.
    expect(find.byType(Text), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets('PressScale shrinks while a finger is down', (tester) async {
    await tester.pumpWidget(_wrap(const PressScale(child: SizedBox(key: Key('btn'), width: 100, height: 40, child: ColoredBox(color: Colors.blue)))));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('btn'))));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, SortedMotion.pressScale);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
