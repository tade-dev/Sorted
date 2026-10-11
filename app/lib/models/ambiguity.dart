// app/lib/models/ambiguity.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'ambiguity.freezed.dart';
part 'ambiguity.g.dart';

@freezed
abstract class Ambiguity with _$Ambiguity {
  const factory Ambiguity({
    required String field,
    required String kind,
    required String question,
    @Default(<String>[]) List<String> options,
    @Default(true) bool blocking,
    @Default(false) bool resolved,
  }) = _Ambiguity;

  factory Ambiguity.fromJson(Map<String, dynamic> json) => _$AmbiguityFromJson(json);
}
