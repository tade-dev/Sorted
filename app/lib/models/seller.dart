import '../core/firestore_time.dart';

/// The seller doc at `sellers/{uid}`. Read straight from Firestore; changes go
/// through `PATCH /v1/session/seller`.
class Seller {
  const Seller({
    required this.id,
    this.displayName = '',
    this.personaTone = '',
    this.sells = const [],
    this.channels = const [],
    this.fulfilmentMode,
    this.paypalMerchant,
    this.paypalEmail,
    this.onboardedAt,
  });

  final String id;
  final String displayName;
  final String personaTone;
  final List<String> sells;
  final List<String> channels;
  final String? fulfilmentMode;
  final String? paypalMerchant;

  /// Where buyers pay. Null pays the shared sandbox merchant.
  final String? paypalEmail;
  final DateTime? onboardedAt;

  bool get onboarded => onboardedAt != null;
  bool get paypalConnected => paypalMerchant != null;

  factory Seller.fromMap(String id, Map<String, dynamic> map) => Seller(
    id: id,
    displayName: (map['displayName'] as String?) ?? '',
    personaTone: (map['personaTone'] as String?) ?? '',
    sells: _strings(map['sells']),
    channels: _strings(map['channels']),
    fulfilmentMode: map['fulfilmentMode'] as String?,
    paypalMerchant: map['paypalMerchant'] as String?,
    paypalEmail: map['paypalEmail'] as String?,
    onboardedAt: dateTimeFromJson(map['onboardedAt']),
  );

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}
