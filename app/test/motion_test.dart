import 'package:flutter/material.dart';
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


  testWidgets('StatusPill morphs its label when the status changes', (tester) async {
    await tester.pumpWidget(_wrap(const StatusPill(status: 'link_sent')));
    await tester.pumpWidget(_wrap(const StatusPill(status: 'paid')));
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-morph both labels are on screen, cross-fading.
    expect(find.byType(Text), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text('Paid'), findsOneWidget);
  });

}
