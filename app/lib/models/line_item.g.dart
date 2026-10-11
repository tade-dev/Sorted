// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'line_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LineItem _$LineItemFromJson(Map<String, dynamic> json) => _LineItem(
  id: json['id'] as String,
  productId: json['productId'] as String?,
  variantIds:
      (json['variantIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  nameRaw: json['nameRaw'] as String,
  nameResolved: json['nameResolved'] as String?,
  qty: (json['qty'] as num?)?.toInt() ?? 1,
  unitPriceMinor: (json['unitPriceMinor'] as num?)?.toInt() ?? 0,
  lineTotalMinor: (json['lineTotalMinor'] as num?)?.toInt() ?? 0,
  matchConfidence: (json['matchConfidence'] as num?)?.toDouble() ?? 0.0,
  matchMethod: json['matchMethod'] as String? ?? 'unmatched',
);

Map<String, dynamic> _$LineItemToJson(_LineItem instance) => <String, dynamic>{
  'id': instance.id,
  'productId': instance.productId,
  'variantIds': instance.variantIds,
  'nameRaw': instance.nameRaw,
  'nameResolved': instance.nameResolved,
  'qty': instance.qty,
  'unitPriceMinor': instance.unitPriceMinor,
  'lineTotalMinor': instance.lineTotalMinor,
  'matchConfidence': instance.matchConfidence,
  'matchMethod': instance.matchMethod,
};
