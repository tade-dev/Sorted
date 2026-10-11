import 'package:freezed_annotation/freezed_annotation.dart';

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

  factory Fulfilment.fromJson(Map<String, dynamic> json) => _$FulfilmentFromJson(json);
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
  }) = _Order;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  List<Ambiguity> get blockingAmbiguities =>
      ambiguities.where((a) => a.blocking && !a.resolved).toList();

  /// The seller cannot create a link while the AI is still unsure of
  /// something that changes what the buyer pays.
  bool get isBlocked => blockingAmbiguities.isNotEmpty;

  bool get hasLink => (approvalUrl ?? '').isNotEmpty;

  /// What is still owed after a deposit, which the reply mentions.
  int get balanceMinor =>
      depositMinor == null ? 0 : subtotalMinor - depositMinor!;
}
