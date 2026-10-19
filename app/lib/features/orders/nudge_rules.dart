import '../../models/order.dart';

/// The same timings as the API's domain/nudge.ts, so Home and the server
/// agree on what is due: first at a day, second at three days and a day
/// after the first, never a third, never while snoozed.
const nudgeDueHours = [24, 72];
const _gapHours = 24;

/// Whether the seller may draft a nudge at all: an unpaid link a day old.
bool canNudge(Order order, DateTime now) {
  if (order.status != 'link_sent' || !order.hasLink) return false;
  final sent = order.linkSentAt;
  if (sent == null) return false;
  return now.difference(sent).inHours >= nudgeDueHours.first;
}

/// Whether Sorted should bring it up unasked, as Home's nudge card does.
bool nudgeDue(Order order, DateTime now) {
  if (!canNudge(order, now)) return false;
  final nudge = order.nudge;
  if (nudge.count >= nudgeDueHours.length) return false;
  if (now.difference(order.linkSentAt!).inHours < nudgeDueHours[nudge.count]) {
    return false;
  }
  final last = nudge.lastSentAt;
  if (last != null && now.difference(last).inHours < _gapHours) return false;
  final snoozed = nudge.snoozedUntil;
  if (snoozed != null && now.isBefore(snoozed)) return false;
  return true;
}

const _days = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _firstName(Order order) {
  final name = order.buyerName?.trim() ?? '';
  return name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
}

/// "Nudge Priya", the nudge sheet's headline.
String nudgeTitle(Order order) {
  final who = _firstName(order);
  return who.isEmpty ? 'Nudge the buyer' : 'Nudge $who';
}

/// "Link sent Thursday 1 Oct", under the order on the nudge sheet.
String linkSentOn(Order order) {
  final sent = order.linkSentAt?.toLocal();
  if (sent == null) return 'Link not sent yet';
  return 'Link sent ${_days[sent.weekday % 7]} ${sent.day} ${_months[sent.month - 1]}';
}

/// Why there is nothing to nudge, in the API's words, or null when there is.
String? nudgeRefusal(Order order, DateTime now) {
  final who = _firstName(order).isEmpty ? 'The buyer' : _firstName(order);
  switch (order.status) {
    case 'paid':
      return '$who has already paid. Nothing to chase.';
    case 'cancelled':
      return 'This order was cancelled, so there is nothing to chase.';
    case 'expired':
      return 'This link expired, so there is nothing to chase.';
    case 'processing':
    case 'pending':
      return '$who is paying for this right now.';
    case 'draft':
      return 'There is no payment link to chase yet.';
    case 'declined':
      return "$who's payment was declined. Ask them to try the link again.";
  }
  if (!order.hasLink || order.linkSentAt == null) {
    return 'There is no payment link to chase yet.';
  }
  if (!canNudge(order, now)) {
    return 'The link went out less than a day ago. Give $who a little longer.';
  }
  return null;
}

/// The line on Order detail where "No reminder has been sent yet." sat.
String reminderHistory(Order order, DateTime now) {
  final nudge = order.nudge;
  final snoozed = nudge.snoozedUntil;
  final snoozeNote = snoozed != null && now.isBefore(snoozed)
      ? ' Sorted will remind you tomorrow.'
      : '';
  if (nudge.count == 0) return 'No reminder has been sent yet.$snoozeNote';
  final last = nudge.lastSentAt?.toLocal();
  final when = last == null
      ? ''
      : ', last on ${_days[last.weekday % 7]} ${last.day} ${_months[last.month - 1]}';
  final count = nudge.count == 1
      ? 'One reminder sent'
      : '${nudge.count} reminders sent';
  return '$count$when.$snoozeNote';
}
