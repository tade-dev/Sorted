import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/motion/sorted_motion.dart';

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

}
