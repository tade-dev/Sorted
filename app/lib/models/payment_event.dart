import '../core/firestore_time.dart';

/// One PayPal webhook (or the reconcile sweep) stored under the order.
///
/// The timeline is derived from these documents plus `createdAt` and
/// `linkSentAt` on the order. Nothing else is written for history.
class PaymentEvent {
  const PaymentEvent({
    required this.id,
    required this.eventType,
    this.paypalResourceId,
    this.amountMinor,
    this.receivedAt,
    this.processedAt,
    this.processingError,
    this.rawStatus,
  });

  final String id;
  final String eventType;
  final String? paypalResourceId;
  final int? amountMinor;
  final DateTime? receivedAt;
  final DateTime? processedAt;
  final String? processingError;

  /// Set by the reconcile sweep (`raw.status`). Webhook events leave it null.
  final String? rawStatus;

  factory PaymentEvent.fromMap(Map<String, dynamic> json) {
    final raw = json['raw'];
    String? rawStatus;
    if (raw is Map) {
      final status = raw['status'];
      if (status is String && status.isNotEmpty) rawStatus = status;
    }
    final amount = json['amountMinor'];
    return PaymentEvent(
      id: json['id'] as String? ?? '',
      eventType: json['eventType'] as String? ?? '',
      paypalResourceId: json['paypalResourceId'] as String?,
      amountMinor: amount is num ? amount.toInt() : null,
      receivedAt: dateTimeFromJson(json['receivedAt']),
      processedAt: dateTimeFromJson(json['processedAt']),
      processingError: json['processingError'] as String?,
      rawStatus: rawStatus,
    );
  }
}
