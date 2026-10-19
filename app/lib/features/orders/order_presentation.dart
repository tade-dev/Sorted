import '../../core/uk_date.dart';
import '../../models/order.dart';
import '../../models/payment_event.dart';

/// How a backend status is drawn. Wording is specific so Link sent, Pending
/// and Declined stay distinct; Paid is the one success colour.
enum StatusTone { paid, waiting, progress, pending, declined, draft, closed }

class StatusPresentation {
  const StatusPresentation(this.label, this.tone);
  final String label;
  final StatusTone tone;
}

StatusPresentation statusPresentation(String status) => switch (status) {
  'paid' => const StatusPresentation('Paid', StatusTone.paid),
  'link_sent' => const StatusPresentation('Link sent', StatusTone.waiting),
  'processing' => const StatusPresentation('Confirming', StatusTone.progress),
  'pending' => const StatusPresentation('Pending', StatusTone.pending),
  'declined' => const StatusPresentation('Declined', StatusTone.declined),
  'draft' => const StatusPresentation('Draft', StatusTone.draft),
  'cancelled' => const StatusPresentation('Cancelled', StatusTone.closed),
  'expired' => const StatusPresentation('Expired', StatusTone.closed),
  _ => const StatusPresentation('Unknown', StatusTone.closed),
};

enum OrderFilter { all, waiting, paid, drafts }

bool orderMatchesFilter(String status, OrderFilter filter) => switch (filter) {
  OrderFilter.all => true,
  OrderFilter.waiting =>
    status == 'link_sent' ||
        status == 'processing' ||
        status == 'pending' ||
        status == 'declined',
  OrderFilter.paid => status == 'paid',
  OrderFilter.drafts => status == 'draft',
};

String orderFilterLabel(OrderFilter filter, int count) => switch (filter) {
  OrderFilter.all => 'All $count',
  OrderFilter.waiting => 'Waiting $count',
  OrderFilter.paid => 'Paid $count',
  OrderFilter.drafts => 'Drafts $count',
};

/// Name, then handle, then a neutral word. Never a blank row.
String buyerLabel(Order order) {
  final name = order.buyerName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final handle = order.buyerHandle?.trim();
  if (handle != null && handle.isNotEmpty) {
    return handle.startsWith('@') ? handle : '@$handle';
  }
  return 'Buyer';
}

String _firstName(Order order) {
  final name = order.buyerName?.trim();
  if (name == null || name.isEmpty) return '';
  return name.split(RegExp(r'\s+')).first;
}

String itemsSummary(Order order) {
  if (order.lineItems.isEmpty) return 'No items yet';
  return order.lineItems
      .map((line) {
        final name = line.displayName;
        if (line.qty > 1) return '$name × ${line.qty}';
        return name;
      })
      .join(', ');
}

/// The large total on the order slip.
String totalLabel(Order order) {
  if (order.status == 'paid') return 'Paid';
  if (order.depositMinor != null) return 'Deposit now';
  if (order.status == 'draft') return 'Total';
  return 'To pay';
}

String balanceCaption(Order order) {
  final later = order.fulfilment.mode == 'delivery'
      ? 'on delivery'
      : 'on collection';
  return later;
}

const _fullWeekdays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

const _shortMonths = [
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

/// The grey caption under a status pill. Paid and link-sent follow the
/// order-list design ("Just now", "Link sent 3h ago", "Sent Thursday",
/// "This morning"). Interim PayPal states say what is happening.
String activityCaption(Order order, DateTime now) {
  switch (order.status) {
    case 'processing':
      return 'Confirming with PayPal';
    case 'pending':
      return 'Pending with PayPal';
    case 'declined':
      return 'Ask them to try again';
    case 'cancelled':
      return 'Cancelled';
    case 'expired':
      return 'Link expired';
    default:
      return _relativeCaption(order, now);
  }
}

DateTime? _anchor(Order order) => switch (order.status) {
  'paid' => order.paidAt ?? order.updatedAt ?? order.createdAt,
  'link_sent' => order.linkSentAt ?? order.updatedAt ?? order.createdAt,
  _ => order.createdAt ?? order.updatedAt,
};

String _relativeCaption(Order order, DateTime now) {
  final at = _anchor(order);
  if (at == null) return '';
  final localNow = now.toLocal();
  final localAt = at.toLocal();
  final diff = localNow.difference(localAt);
  final link = order.status == 'link_sent';

  if (!diff.isNegative && diff.inMinutes < 2) {
    return link ? 'Link sent just now' : 'Just now';
  }
  if (diff.isNegative && diff.inMinutes > -2) {
    return link ? 'Link sent just now' : 'Just now';
  }

  final sameDay =
      localNow.year == localAt.year &&
      localNow.month == localAt.month &&
      localNow.day == localAt.day;
  if (order.status == 'paid' &&
      sameDay &&
      localAt.hour < 12 &&
      localNow.hour >= 12) {
    return 'This morning';
  }

  if (!diff.isNegative && diff.inHours < 1) {
    final mins = diff.inMinutes;
    return link ? 'Link sent ${mins}m ago' : '${mins}m ago';
  }
  if (!diff.isNegative && diff.inHours < 24) {
    final hours = diff.inHours;
    return link ? 'Link sent ${hours}h ago' : '${hours}h ago';
  }

  final weekday = _fullWeekdays[localAt.weekday % 7];
  if (!diff.isNegative && diff.inDays < 7) {
    return link ? 'Sent $weekday' : weekday;
  }
  final dayMonth = '${localAt.day} ${_shortMonths[localAt.month - 1]}';
  return link ? 'Sent $dayMonth' : dayMonth;
}

/// The blue card is the order that just flipped to Paid.
bool isFreshPaid(Order order, DateTime now) {
  if (order.status != 'paid' || order.paidAt == null) return false;
  final minutes = now.difference(order.paidAt!).inMinutes;
  return minutes < 2 && minutes > -2;
}

class TimelineEntry {
  const TimelineEntry({
    required this.label,
    required this.at,
    this.emphasis = false,
  });

  final String label;
  final DateTime? at;
  final bool emphasis;
}

/// "11:02". Uses the device zone so a Firestore UTC timestamp reads locally.
String formatClock(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String fulfilmentLabel(Order order) {
  final date = order.fulfilment.date;
  if (date == null || date.isEmpty) return '';
  final formatted = formatUkDate(date);
  final notes = order.fulfilment.notes?.trim();
  if (notes == null || notes.isEmpty) return formatted;
  return '$formatted, $notes';
}

/// Derived timeline. The first two lines come from the order document; the
/// rest from `paymentEvents`. A paid order with no capture event still shows
/// "Payment received" from `paidAt`, which reconcile writes alongside an event
/// but a partial write might not.
List<TimelineEntry> buildTimeline(Order order, List<PaymentEvent> events) {
  final who = _firstName(order);
  final entries = <TimelineEntry>[];

  if (order.createdAt != null) {
    final source = order.sourceKind == 'text' ? 'message' : 'screenshot';
    final label = who.isEmpty
        ? 'Read from a $source'
        : "Read from $who's $source";
    entries.add(TimelineEntry(label: label, at: order.createdAt));
  }
  if (order.linkSentAt != null) {
    entries.add(
      TimelineEntry(label: 'Checkout link sent', at: order.linkSentAt),
    );
  }

  var sawReceived = false;
  final sorted = events.indexed.toList()
    ..sort((a, b) {
      final at = a.$2.receivedAt ?? a.$2.processedAt;
      final bt = b.$2.receivedAt ?? b.$2.processedAt;
      final byTime = switch ((at, bt)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        _ => at!.compareTo(bt!),
      };
      if (byTime != 0) return byTime;
      // Same instant: approval is the buyer's step, capture is the money landing.
      final byKind = _eventOrder(a.$2.eventType)
          .compareTo(_eventOrder(b.$2.eventType));
      return byKind != 0 ? byKind : a.$1.compareTo(b.$1);
    });
  for (final (_, event) in sorted) {
    final label = paymentEventLabel(event, who);
    if (label == 'Payment received') sawReceived = true;
    entries.add(
      TimelineEntry(
        label: label,
        at: event.receivedAt ?? event.processedAt,
        emphasis: _emphasise(label),
      ),
    );
  }

  if (order.status == 'paid' && order.paidAt != null && !sawReceived) {
    entries.add(
      TimelineEntry(
        label: 'Payment received',
        at: order.paidAt,
        emphasis: true,
      ),
    );
  }

  return entries;
}

int _eventOrder(String eventType) => switch (eventType) {
  'CHECKOUT.ORDER.APPROVED' => 0,
  'PAYMENT.CAPTURE.COMPLETED' || 'reconcile' => 2,
  'cancelled' || 'expired' => 3,
  _ => 1,
};

bool _emphasise(String label) =>
    label == 'Payment received' || label.endsWith('paid with PayPal');

String paymentEventLabel(PaymentEvent event, String firstName) {
  final buyer = firstName.isEmpty ? 'The buyer' : firstName;
  // Checked first: it is a capture, but calling it "Payment received" on a
  // closed order would tell the seller to fulfil something they cancelled.
  if (event.refundDue) return 'Paid on a closed link. Refund it in PayPal';
  switch (event.eventType) {
    case 'CHECKOUT.ORDER.APPROVED':
      return '$buyer paid with PayPal';
    case 'PAYMENT.CAPTURE.COMPLETED':
      return 'Payment received';
    case 'PAYMENT.CAPTURE.PENDING':
      return 'Payment is pending';
    case 'PAYMENT.CAPTURE.DENIED':
      return 'Payment declined';
    case 'PAYMENT.CAPTURE.REFUNDED':
      return 'Payment refunded';
    case 'CHECKOUT.PAYMENT-APPROVAL.REVERSED':
      return 'Checkout was reversed';
    case 'cancelled':
      return 'You cancelled the order';
    case 'expired':
      return 'The link expired unpaid';
    case 'reconcile':
      return switch (event.rawStatus) {
        'paid' => 'Payment received',
        'pending' => 'Payment is pending',
        'declined' => 'Payment declined',
        'processing' => 'Confirming the payment',
        _ => 'Checked with PayPal',
      };
    default:
      return 'PayPal update';
  }
}

/// Statuses the seller can cancel from. The API refuses the rest: paid is a
/// refund, and processing or pending means the buyer is paying right now.
const cancellableOrderStatuses = {'draft', 'link_sent', 'declined'};

bool isClosedStatus(String status) =>
    status == 'cancelled' || status == 'expired';

/// What Order detail says in place of the link and reply once it is closed.
String closedOrderNote(Order order) => order.status == 'expired'
    ? 'This link expired unpaid, so it no longer takes payment. Start a new order if they still want it.'
    : 'You cancelled this order. Its checkout link no longer takes payment.';

/// The confirm sheet's body. A sent link is the part worth warning about.
String cancelOrderWarning(Order order) {
  if (order.status == 'draft' || !order.hasLink) {
    return "The draft is closed and can't be sent. You can't undo this.";
  }
  final who = _firstName(order);
  final buyer = who.isEmpty ? 'The buyer' : who;
  return "The checkout link stops working, so $buyer can't pay on it. You can't undo this.";
}

String paidProtectionNote(Order order) {
  final who = _firstName(order);
  if (who.isEmpty) {
    return 'This was paid through PayPal checkout, so the money is in your PayPal account. No transfer to check.';
  }
  return '$who paid through PayPal checkout, so the money is in your PayPal account. No transfer to check.';
}
