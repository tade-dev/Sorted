// app/lib/models/product_candidate.dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'ambiguity.dart';
import 'variant.dart';

part 'product_candidate.freezed.dart';
part 'product_candidate.g.dart';

@freezed
abstract class ProductCandidate with _$ProductCandidate {
  const ProductCandidate._();

  const factory ProductCandidate({
    required String tempId,
    required String name,
    @Default('') String description,
    /// Null when no price was readable. Review.dc.html shows this as
    /// "Couldn't read a price. Add one to save."
    int? basePriceMinor,
    @Default(<Variant>[]) List<Variant> variants,
    @Default(0.0) double confidence,
    @Default(<Ambiguity>[]) List<Ambiguity> ambiguities,
    /// Which snapped photo (0-based) this product came from, so saving can
    /// attach it. Null when the API could not tell.
    int? photoIndex,
  }) = _ProductCandidate;

  factory ProductCandidate.fromJson(Map<String, dynamic> json) =>
      _$ProductCandidateFromJson(json);

  /// A candidate cannot be saved until it has a price.
  bool get needsPrice => basePriceMinor == null;
}
