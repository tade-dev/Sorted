// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Product _$ProductFromJson(Map<String, dynamic> json) => _Product(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String? ?? '',
  basePriceMinor: (json['basePriceMinor'] as num).toInt(),
  depositMinor: (json['depositMinor'] as num?)?.toInt(),
  currency: json['currency'] as String? ?? 'GBP',
  photoUrl: json['photoUrl'] as String?,
  variants:
      (json['variants'] as List<dynamic>?)
          ?.map((e) => Variant.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Variant>[],
  active: json['active'] as bool? ?? true,
  source: json['source'] as String? ?? 'manual',
);

Map<String, dynamic> _$ProductToJson(_Product instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'basePriceMinor': instance.basePriceMinor,
  'depositMinor': instance.depositMinor,
  'currency': instance.currency,
  'photoUrl': instance.photoUrl,
  'variants': instance.variants.map((e) => e.toJson()).toList(),
  'active': instance.active,
  'source': instance.source,
};
