import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/uk_date.dart';

void main() {
  test('formats an ISO date the way the screens write it', () {
    expect(formatUkDate('2026-10-13'), 'Tue 13 Oct');
    expect(formatUkDate('2026-10-10'), 'Sat 10 Oct');
  });

  test('leaves a size label alone', () {
    expect(displayDate('10 inch'), '10 inch');
  });

  test('leaves a nonsense date alone', () {
    expect(formatUkDate('2026-13-40'), '2026-13-40');
  });
}
