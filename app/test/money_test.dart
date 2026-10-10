import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/money.dart';

void main() {
  group('formatGbp', () {
    test('formats pence as the design writes it', () {
      expect(formatGbp(4500), '£45.00');
      expect(formatGbp(99), '£0.99');
      expect(formatGbp(0), '£0.00');
      expect(formatGbp(123456), '£1,234.56');
    });
  });

  group('parseGbpInput', () {
    test('accepts what a seller plausibly types', () {
      expect(parseGbpInput('45.00'), 4500);
      expect(parseGbpInput('45'), 4500);
      expect(parseGbpInput('45.5'), 4550);
      expect(parseGbpInput('0.99'), 99);
      expect(parseGbpInput('£45.00'), 4500);
      expect(parseGbpInput('  45.00 '), 4500);
      expect(parseGbpInput('1,234.56'), 123456);
    });

    test('rejects a decimal comma instead of reading it as thousands', () {
      // "32,50" is how much of Europe writes £32.50. Stripping the comma and
      // parsing gave 3250.00 — a 100x overcharge sent to a real buyer.
      expect(parseGbpInput('32,50'), isNull);
    });

    test('rejects more than two decimal places rather than rounding silently', () {
      expect(parseGbpInput('32.456'), isNull);
    });

    test('rejects a malformed thousands group', () {
      expect(parseGbpInput('1,2.3'), isNull);
    });

    test('rejects a negative amount', () {
      expect(parseGbpInput('-5'), isNull);
    });

    test('rejects empty and non-numeric input', () {
      for (final bad in ['', '   ', 'abc', '45p', '£', 'NaN', '1e2']) {
        expect(parseGbpInput(bad), isNull, reason: 'should reject "$bad"');
      }
    });

    test('round-trips with formatGbp', () {
      for (final pence in [0, 1, 99, 4500, 123456]) {
        expect(parseGbpInput(formatGbp(pence)), pence);
      }
    });
  });
}
