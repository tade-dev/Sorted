// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Fulfilment _$FulfilmentFromJson(Map<String, dynamic> json) => _Fulfilment(
  mode: json['mode'] as String? ?? 'unknown',
  date: json['date'] as String?,
  notes: json['notes'] as String?,
);

Map<String, dynamic> _$FulfilmentToJson(_Fulfilment instance) =>
    <String, dynamic>{
      'mode': instance.mode,
      'date': instance.date,
      'notes': instance.notes,
    };

_Order _$OrderFromJson(Map<String, dynamic> json) => _Order(
  id: json['id'] as String,
  status: json['status'] as String? ?? 'draft',
  buyerName: json['buyerName'] as String?,
  buyerHandle: json['buyerHandle'] as String?,
  buyerEmail: json['buyerEmail'] as String?,
  channel: json['channel'] as String? ?? 'unknown',
  lineItems:
      (json['lineItems'] as List<dynamic>?)
          ?.map((e) => LineItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <LineItem>[],
  subtotalMinor: (json['subtotalMinor'] as num?)?.toInt() ?? 0,
  depositMinor: (json['depositMinor'] as num?)?.toInt(),
  amountDueMinor: (json['amountDueMinor'] as num?)?.toInt() ?? 0,
  currency: json['currency'] as String? ?? 'GBP',
  fulfilment: json['fulfilment'] == null
      ? const Fulfilment()
      : Fulfilment.fromJson(json['fulfilment'] as Map<String, dynamic>),
  ambiguities:
      (json['ambiguities'] as List<dynamic>?)
          ?.map((e) => Ambiguity.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Ambiguity>[],
  paypalOrderId: json['paypalOrderId'] as String?,
  approvalUrl: json['approvalUrl'] as String?,
  draftedReply: json['draftedReply'] as String?,
  sourceKind: json['sourceKind'] as String? ?? 'screenshot',
);

Map<String, dynamic> _$OrderToJson(_Order instance) => <String, dynamic>{
  'id': instance.id,
  'status': instance.status,
  'buyerName': instance.buyerName,
  'buyerHandle': instance.buyerHandle,
  'buyerEmail': instance.buyerEmail,
  'channel': instance.channel,
  'lineItems': instance.lineItems.map((e) => e.toJson()).toList(),
  'subtotalMinor': instance.subtotalMinor,
  'depositMinor': instance.depositMinor,
  'amountDueMinor': instance.amountDueMinor,
  'currency': instance.currency,
  'fulfilment': instance.fulfilment.toJson(),
  'ambiguities': instance.ambiguities.map((e) => e.toJson()).toList(),
  'paypalOrderId': instance.paypalOrderId,
  'approvalUrl': instance.approvalUrl,
  'draftedReply': instance.draftedReply,
  'sourceKind': instance.sourceKind,
};
