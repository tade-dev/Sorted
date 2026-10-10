// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ambiguity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Ambiguity _$AmbiguityFromJson(Map<String, dynamic> json) => _Ambiguity(
  field: json['field'] as String,
  kind: json['kind'] as String,
  question: json['question'] as String,
  options:
      (json['options'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  blocking: json['blocking'] as bool? ?? true,
);

Map<String, dynamic> _$AmbiguityToJson(_Ambiguity instance) =>
    <String, dynamic>{
      'field': instance.field,
      'kind': instance.kind,
      'question': instance.question,
      'options': instance.options,
      'blocking': instance.blocking,
    };
