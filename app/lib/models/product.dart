import 'package:freezed_annotation/freezed_annotation.dart';

import 'variant.dart';

part 'product.freezed.dart';
part 'product.g.dart';

@freezed
abstract class Product with _$Product {
  const Product._();

  const factory Product({
    required String id,
    required String name,
    @Default('') String description,
    required int basePriceMinor,
    int? depositMinor,
    @Default('GBP') String currency,
    String? photoUrl,
    @Default(<Variant>[]) List<Variant> variants,
    @Default(true) bool active,
    @Default('manual') String source,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) => _$ProductFromJson(json);

  List<Variant> get _live => variants.where((v) => v.active).toList();

  /// The cheapest price a buyer could pay. Catalogue.dc.html shows this as
  /// "from £32" when there is a choice, and as an exact price when there is not.
  int get fromPriceMinor {
    if (_live.isEmpty) return basePriceMinor;
    final deltas = _live.map((v) => v.priceDeltaMinor).reduce((a, b) => a < b ? a : b);
    final lowest = basePriceMinor + deltas;
    return lowest < 0 ? 0 : lowest;
  }

  /// True only when the buyer has something to choose between.
  bool get hasVariants => _live.length > 1;
}
