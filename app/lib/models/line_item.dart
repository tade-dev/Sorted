import 'package:freezed_annotation/freezed_annotation.dart';

part 'line_item.freezed.dart';
part 'line_item.g.dart';

@freezed
abstract class LineItem with _$LineItem {
  const LineItem._();

  const factory LineItem({
    required String id,
    /// Null when the catalogue had nothing matching, which is a blocking
    /// ambiguity rather than a GBP 0 line.
    String? productId,
    @Default(<String>[]) List<String> variantIds,
    /// What the buyer actually wrote, kept so the seller can see it.
    required String nameRaw,
    String? nameResolved,
    @Default(1) int qty,
    @Default(0) int unitPriceMinor,
    @Default(0) int lineTotalMinor,
    @Default(0.0) double matchConfidence,
    @Default('unmatched') String matchMethod,
  }) = _LineItem;

  factory LineItem.fromJson(Map<String, dynamic> json) => _$LineItemFromJson(json);

  bool get isUnmatched => productId == null;

  String get displayName => nameResolved ?? nameRaw;
}
