import '../core/firestore_time.dart';

/// `order.nudge`: the reminders for an unpaid link. Written only by the API.
///
/// `draftText` is a reminder Sorted has written but the seller has not sent,
/// either from the hourly sweep or from opening the nudge screen. The rest
/// describes the last one actually copied into the chat.
class OrderNudge {
  const OrderNudge({
    this.count = 0,
    this.lastSentAt,
    this.lastText,
    this.snoozedUntil,
    this.draftText,
  });

  final int count;
  final DateTime? lastSentAt;
  final String? lastText;
  final DateTime? snoozedUntil;
  final String? draftText;

  static OrderNudge fromJson(Object? json) {
    if (json is! Map) return const OrderNudge();
    final count = json['count'];
    final draft = json['draftText'];
    return OrderNudge(
      count: count is num ? count.toInt() : 0,
      lastSentAt: dateTimeFromJson(json['lastSentAt']),
      lastText: json['lastText'] as String?,
      snoozedUntil: dateTimeFromJson(json['snoozedUntil']),
      draftText: draft is String && draft.trim().isNotEmpty ? draft : null,
    );
  }

  static Map<String, dynamic> toJson(OrderNudge nudge) => {
    'count': nudge.count,
    'lastSentAt': dateTimeToJson(nudge.lastSentAt),
    'lastText': nudge.lastText,
    'snoozedUntil': dateTimeToJson(nudge.snoozedUntil),
    'draftText': nudge.draftText,
  };

  @override
  bool operator ==(Object other) =>
      other is OrderNudge &&
      other.count == count &&
      other.lastSentAt == lastSentAt &&
      other.lastText == lastText &&
      other.snoozedUntil == snoozedUntil &&
      other.draftText == draftText;

  @override
  int get hashCode =>
      Object.hash(count, lastSentAt, lastText, snoozedUntil, draftText);
}
