// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_candidate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProductCandidate _$ProductCandidateFromJson(Map<String, dynamic> json) =>
    _ProductCandidate(
      tempId: json['tempId'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      basePriceMinor: (json['basePriceMinor'] as num?)?.toInt(),
      variants:
          (json['variants'] as List<dynamic>?)
              ?.map((e) => Variant.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Variant>[],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      ambiguities:
          (json['ambiguities'] as List<dynamic>?)
              ?.map((e) => Ambiguity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Ambiguity>[],
    );

Map<String, dynamic> _$ProductCandidateToJson(_ProductCandidate instance) =>
    <String, dynamic>{
      'tempId': instance.tempId,
      'name': instance.name,
      'description': instance.description,
      'basePriceMinor': instance.basePriceMinor,
      'variants': instance.variants.map((e) => e.toJson()).toList(),
      'confidence': instance.confidence,
      'ambiguities': instance.ambiguities.map((e) => e.toJson()).toList(),
    };
