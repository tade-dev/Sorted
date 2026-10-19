import 'package:flutter_test/flutter_test.dart';
import 'package:sorted/core/money.dart';
import 'package:sorted/features/home/home_summary.dart';
import 'package:sorted/models/order.dart';

void main() {
  final now = DateTime(2026, 10, 10, 9);

  Order o(String id, String status, {int amount = 1000, DateTime? paidAt, DateTime? linkSentAt, String? date, int? deposit}) =>
      Order(
        id: id,
        status: status,
        buyerName: 'Priya K',
        amountDueMinor: amount,
        depositMinor: deposit,
        paidAt: paidAt,
        linkSentAt: linkSentAt,
        fulfilment: Fulfilment(mode: 'collection', date: date),
      );

  test('cancelled and expired orders count as nothing on Home', () {
    final old = now.subtract(const Duration(days: 3));
    final s = summarise([
      o('c', 'cancelled', amount: 2000, linkSentAt: old, date: '2026-10-12'),
      o('x', 'expired', amount: 3000, linkSentAt: old, date: '2026-10-12'),
      o('w', 'link_sent', amount: 1500, linkSentAt: now.subtract(const Duration(hours: 2))),
    ], now);

    expect(s.waitingCount, 1);
    expect(s.waitingMinor, 1500);
    expect(s.paidTodayCount, 0);
    expect(s.nudge, isNull);
    expect(s.upcoming, isEmpty);
  });

  test('counts today, waiting, the oldest day-old link and upcoming dates', () {
    final s = summarise([
      o('a', 'paid', amount: 5600, paidAt: now.subtract(const Duration(hours: 1)), date: '2026-10-17'),
      o('b', 'paid', amount: 999, paidAt: now.subtract(const Duration(days: 2))),
      o('c', 'link_sent', amount: 2000, linkSentAt: now.subtract(const Duration(hours: 50)), date: '2026-10-10', deposit: 2000),
      o('d', 'link_sent', amount: 3000, linkSentAt: now.subtract(const Duration(hours: 3))),
      o('e', 'draft', date: '2026-10-11'),
      o('f', 'paid', paidAt: now, date: '2026-10-01'),
    ], now);

    expect(s.paidTodayMinor, 6600);
    expect(s.paidTodayCount, 2);
    expect(s.waitingCount, 2);
    expect(s.waitingMinor, 5000);
    expect(s.nudge?.id, 'c');
    expect(s.upcoming.map((x) => x.id), ['c', 'a']);
    expect(nudgeLine(s.nudge!, now, formatGbpCompact),
        "Priya hasn't paid the £20 deposit yet. The link went out on Thursday.");
  });

  test('no nudge before 24 hours', () {
    final s = summarise([o('d', 'link_sent', linkSentAt: now.subtract(const Duration(hours: 23)))], now);
    expect(s.nudge, isNull);
  });

  test('greeting and date', () {
    expect(greeting(now, 'Mia Bakes'), 'Morning, Mia');
    expect(greeting(now, "Ola's Bakehouse"), 'Morning, Ola');
    expect(greeting(DateTime(2026, 10, 10, 19), ''), 'Evening');
    expect(longDate(now), 'Saturday 10 October');
  });
}
