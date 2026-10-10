// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'variant.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Variant _$VariantFromJson(Map<String, dynamic> json) => _Variant(
  id: json['id'] as String? ?? '',
  axis: json['axis'] as String,
  label: json['label'] as String,
  priceDeltaMinor: (json['priceDeltaMinor'] as num).toInt(),
  active: json['active'] as bool? ?? true,
);

Map<String, dynamic> _$VariantToJson(_Variant instance) => <String, dynamic>{
  'id': instance.id,
  'axis': instance.axis,
  'label': instance.label,
  'priceDeltaMinor': instance.priceDeltaMinor,
  'active': instance.active,
};
