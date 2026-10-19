import '../../models/order.dart';
import '../orders/nudge_rules.dart';
import '../orders/order_presentation.dart';

/// Today's numbers for the Home card, worked out from the live order list.
class HomeSummary {
  const HomeSummary({
    required this.paidTodayMinor,
    required this.paidTodayCount,
    required this.waitingCount,
    required this.waitingMinor,
    required this.nudge,
    required this.upcoming,
  });

  final int paidTodayMinor;
  final int paidTodayCount;
  final int waitingCount;
  final int waitingMinor;

  /// The longest-unpaid link that is due a reminder, if any. One already
  /// nudged today, snoozed, or chased twice is left alone.
  final Order? nudge;

  /// Live orders with a collection or delivery date from today, soonest first.
  final List<Order> upcoming;
}

const _waiting = {'link_sent', 'processing', 'pending', 'declined'};
const _live = {..._waiting, 'paid'};

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String _isoDay(DateTime d) {
  final l = d.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

HomeSummary summarise(List<Order> orders, DateTime now, {int maxUpcoming = 5}) {
  var paidMinor = 0;
  var paidCount = 0;
  var waitingCount = 0;
  var waitingMinor = 0;
  Order? nudge;

  for (final o in orders) {
    if (o.status == 'paid' && o.paidAt != null && _sameDay(o.paidAt!, now)) {
      paidMinor += o.amountDueMinor;
      paidCount++;
    }
    if (_waiting.contains(o.status)) {
      waitingCount++;
      waitingMinor += o.amountDueMinor;
      if (nudgeDue(o, now) &&
          (nudge == null || o.linkSentAt!.isBefore(nudge.linkSentAt!))) {
        nudge = o;
      }
    }
  }

  final today = _isoDay(now);
  final upcoming = [
    for (final o in orders)
      if (_live.contains(o.status) &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(o.fulfilment.date ?? '') &&
          o.fulfilment.date!.compareTo(today) >= 0)
        o,
  ]..sort((a, b) => a.fulfilment.date!.compareTo(b.fulfilment.date!));

  return HomeSummary(
    paidTodayMinor: paidMinor,
    paidTodayCount: paidCount,
    waitingCount: waitingCount,
    waitingMinor: waitingMinor,
    nudge: nudge,
    upcoming: upcoming.take(maxUpcoming).toList(),
  );
}

const _weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "Saturday 3 October".
String longDate(DateTime now) {
  final l = now.toLocal();
  return '${_weekdays[l.weekday % 7]} ${l.day} ${_months[l.month - 1]}';
}

String greeting(DateTime now, String name) {
  final h = now.toLocal().hour;
  final part = h < 12 ? 'Morning' : (h < 18 ? 'Afternoon' : 'Evening');
  // Shop names read as "Ola's Bakehouse"; greet the person, "Ola".
  final first = name.trim().split(RegExp(r'\s+')).first.replaceAll(RegExp(r"['’]s$"), '');
  return first.isEmpty ? part : '$part, $first';
}

/// "Priya hasn't paid their £20 deposit yet. The link went out on Thursday."
String nudgeLine(Order o, DateTime now, String Function(int) money) {
  final who = buyerLabel(o).split(RegExp(r'\s+')).first;
  final what = o.depositMinor != null
      ? '${money(o.amountDueMinor)} deposit'
      : money(o.amountDueMinor);
  final sent = o.linkSentAt!.toLocal();
  final days = now.difference(sent).inDays;
  final when = days < 7 ? 'on ${_weekdays[sent.weekday % 7]}' : '${sent.day} ${_months[sent.month - 1]}';
  return "$who hasn't paid the $what yet. The link went out $when.";
}
