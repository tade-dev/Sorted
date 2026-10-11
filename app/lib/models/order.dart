import 'package:freezed_annotation/freezed_annotation.dart';

import '../core/firestore_time.dart';
import 'ambiguity.dart';
import 'line_item.dart';

part 'order.freezed.dart';
part 'order.g.dart';

@freezed
abstract class Fulfilment with _$Fulfilment {
  const factory Fulfilment({
    @Default('unknown') String mode,
    String? date,
    String? notes,
  }) = _Fulfilment;

  factory Fulfilment.fromJson(Map<String, dynamic> json) =>
      _$FulfilmentFromJson(json);
}

@freezed
abstract class Order with _$Order {
  const Order._();

  const factory Order({
    required String id,
    @Default('draft') String status,
    String? buyerName,
    String? buyerHandle,
    String? buyerEmail,
    @Default('unknown') String channel,
    @Default(<LineItem>[]) List<LineItem> lineItems,
    @Default(0) int subtotalMinor,
    int? depositMinor,
    @Default(0) int amountDueMinor,
    @Default('GBP') String currency,
    @Default(Fulfilment()) Fulfilment fulfilment,
    @Default(<Ambiguity>[]) List<Ambiguity> ambiguities,
    String? paypalOrderId,
    String? approvalUrl,
    String? draftedReply,
    @Default('screenshot') String sourceKind,

    /// When the draft was written. The timeline's first entry.
    @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
    DateTime? createdAt,
    @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
    DateTime? updatedAt,

    /// When the checkout link was created. Null until confirm.
    @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
    DateTime? linkSentAt,

    /// Set only when a capture completes. Null on every earlier status.
    @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)
    DateTime? paidAt,
  }) = _Order;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  /// A missing name, handle, or note does not change the price. The spec
  /// leaves those nullable, so they must not disable the payment link.
  static const _optionalIdentity = {
    'buyerName',
    'buyerHandle',
    'buyerEmail',
    'buyer',
    'customerName',
    'channel',
    'fulfilment.notes',
    'fulfillment.notes',
  };

  List<Ambiguity> get blockingAmbiguities => ambiguities
      .where(
        (a) =>
            a.blocking && !a.resolved && !_optionalIdentity.contains(a.field),
      )
      .toList();

  /// The seller cannot create a link while the AI is still unsure of
  /// something that changes what the buyer pays, or of the collection date.
  bool get isBlocked => blockingAmbiguities.isNotEmpty;

  bool get hasLink => (approvalUrl ?? '').isNotEmpty;

  /// What is still owed after a deposit, which the reply mentions.
  int get balanceMinor =>
      depositMinor == null ? 0 : subtotalMinor - depositMinor!;
}
