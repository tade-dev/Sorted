import 'package:freezed_annotation/freezed_annotation.dart';

part 'variant.freezed.dart';
part 'variant.g.dart';

@freezed
abstract class Variant with _$Variant {
  const factory Variant({
    required String id,
    required String axis,
    required String label,
    required int priceDeltaMinor,
    @Default(true) bool active,
  }) = _Variant;

  factory Variant.fromJson(Map<String, dynamic> json) => _$VariantFromJson(json);
}
