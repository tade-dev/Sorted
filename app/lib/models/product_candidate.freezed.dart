// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product_candidate.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProductCandidate {

 String get tempId; String get name; String get description;/// Null when no price was readable. Review.dc.html shows this as
/// "Couldn't read a price. Add one to save."
 int? get basePriceMinor; List<Variant> get variants; double get confidence; List<Ambiguity> get ambiguities;
/// Create a copy of ProductCandidate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductCandidateCopyWith<ProductCandidate> get copyWith => _$ProductCandidateCopyWithImpl<ProductCandidate>(this as ProductCandidate, _$identity);

  /// Serializes this ProductCandidate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ProductCandidate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductCandidate&&(identical(other.tempId, _this.tempId) || other.tempId == _this.tempId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.basePriceMinor, _this.basePriceMinor) || other.basePriceMinor == _this.basePriceMinor)&&const DeepCollectionEquality().equals(other.variants, _this.variants)&&(identical(other.confidence, _this.confidence) || other.confidence == _this.confidence)&&const DeepCollectionEquality().equals(other.ambiguities, _this.ambiguities));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ProductCandidate;
  return Object.hash(runtimeType,_this.tempId,_this.name,_this.description,_this.basePriceMinor,const DeepCollectionEquality().hash(_this.variants),_this.confidence,const DeepCollectionEquality().hash(_this.ambiguities));
}

@override
String toString() {
  final _this = this as ProductCandidate;
  return 'ProductCandidate(tempId: ${_this.tempId}, name: ${_this.name}, description: ${_this.description}, basePriceMinor: ${_this.basePriceMinor}, variants: ${_this.variants}, confidence: ${_this.confidence}, ambiguities: ${_this.ambiguities})';
}


}

/// @nodoc
abstract mixin class $ProductCandidateCopyWith<$Res>  {
  factory $ProductCandidateCopyWith(ProductCandidate value, $Res Function(ProductCandidate) _then) = _$ProductCandidateCopyWithImpl;
@useResult
$Res call({
 String tempId, String name, String description, int? basePriceMinor, List<Variant> variants, double confidence, List<Ambiguity> ambiguities
});




}
/// @nodoc
class _$ProductCandidateCopyWithImpl<$Res>
    implements $ProductCandidateCopyWith<$Res> {
  _$ProductCandidateCopyWithImpl(this._self, this._then);

  final ProductCandidate _self;
  final $Res Function(ProductCandidate) _then;

/// Create a copy of ProductCandidate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tempId = null,Object? name = null,Object? description = null,Object? basePriceMinor = freezed,Object? variants = null,Object? confidence = null,Object? ambiguities = null,}) {
  return _then(ProductCandidate(
tempId: null == tempId ? _self.tempId : tempId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,basePriceMinor: freezed == basePriceMinor ? _self.basePriceMinor : basePriceMinor // ignore: cast_nullable_to_non_nullable
as int?,variants: null == variants ? _self.variants : variants // ignore: cast_nullable_to_non_nullable
as List<Variant>,confidence: null == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as double,ambiguities: null == ambiguities ? _self.ambiguities : ambiguities // ignore: cast_nullable_to_non_nullable
as List<Ambiguity>,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductCandidate].
extension ProductCandidatePatterns on ProductCandidate {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductCandidate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductCandidate() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductCandidate value)  $default,){
final _that = this;
switch (_that) {
case _ProductCandidate():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductCandidate value)?  $default,){
final _that = this;
switch (_that) {
case _ProductCandidate() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String tempId,  String name,  String description,  int? basePriceMinor,  List<Variant> variants,  double confidence,  List<Ambiguity> ambiguities)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductCandidate() when $default != null:
return $default(_that.tempId,_that.name,_that.description,_that.basePriceMinor,_that.variants,_that.confidence,_that.ambiguities);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String tempId,  String name,  String description,  int? basePriceMinor,  List<Variant> variants,  double confidence,  List<Ambiguity> ambiguities)  $default,) {final _that = this;
switch (_that) {
case _ProductCandidate():
return $default(_that.tempId,_that.name,_that.description,_that.basePriceMinor,_that.variants,_that.confidence,_that.ambiguities);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String tempId,  String name,  String description,  int? basePriceMinor,  List<Variant> variants,  double confidence,  List<Ambiguity> ambiguities)?  $default,) {final _that = this;
switch (_that) {
case _ProductCandidate() when $default != null:
return $default(_that.tempId,_that.name,_that.description,_that.basePriceMinor,_that.variants,_that.confidence,_that.ambiguities);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProductCandidate extends ProductCandidate {
  const _ProductCandidate({required this.tempId, required this.name, this.description = '', this.basePriceMinor,  List<Variant> variants = const <Variant>[], this.confidence = 0.0,  List<Ambiguity> ambiguities = const <Ambiguity>[]}): _variants = variants,_ambiguities = ambiguities,super._();
  factory _ProductCandidate.fromJson(Map<String, dynamic> json) => _$ProductCandidateFromJson(json);

@override final  String tempId;
@override final  String name;
@override@JsonKey() final  String description;
/// Null when no price was readable. Review.dc.html shows this as
/// "Couldn't read a price. Add one to save."
@override final  int? basePriceMinor;
 final  List<Variant> _variants;
@override@JsonKey() List<Variant> get variants {
  if (_variants is EqualUnmodifiableListView) return _variants;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_variants);
}

@override@JsonKey() final  double confidence;
 final  List<Ambiguity> _ambiguities;
@override@JsonKey() List<Ambiguity> get ambiguities {
  if (_ambiguities is EqualUnmodifiableListView) return _ambiguities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ambiguities);
}


/// Create a copy of ProductCandidate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductCandidateCopyWith<_ProductCandidate> get copyWith => __$ProductCandidateCopyWithImpl<_ProductCandidate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProductCandidateToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductCandidate&&(identical(other.tempId, tempId) || other.tempId == tempId)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.basePriceMinor, basePriceMinor) || other.basePriceMinor == basePriceMinor)&&const DeepCollectionEquality().equals(other.variants, _variants)&&(identical(other.confidence, confidence) || other.confidence == confidence)&&const DeepCollectionEquality().equals(other.ambiguities, _ambiguities));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,tempId,name,description,basePriceMinor,const DeepCollectionEquality().hash(_variants),confidence,const DeepCollectionEquality().hash(_ambiguities));
}

@override
String toString() {
    return 'ProductCandidate(tempId: $tempId, name: $name, description: $description, basePriceMinor: $basePriceMinor, variants: $variants, confidence: $confidence, ambiguities: $ambiguities)';
}


}

/// @nodoc
abstract mixin class _$ProductCandidateCopyWith<$Res> implements $ProductCandidateCopyWith<$Res> {
  factory _$ProductCandidateCopyWith(_ProductCandidate value, $Res Function(_ProductCandidate) _then) = __$ProductCandidateCopyWithImpl;
@override @useResult
$Res call({
 String tempId, String name, String description, int? basePriceMinor, List<Variant> variants, double confidence, List<Ambiguity> ambiguities
});




}
/// @nodoc
class __$ProductCandidateCopyWithImpl<$Res>
    implements _$ProductCandidateCopyWith<$Res> {
  __$ProductCandidateCopyWithImpl(this._self, this._then);

  final _ProductCandidate _self;
  final $Res Function(_ProductCandidate) _then;

/// Create a copy of ProductCandidate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tempId = null,Object? name = null,Object? description = null,Object? basePriceMinor = freezed,Object? variants = null,Object? confidence = null,Object? ambiguities = null,}) {
  return _then(_ProductCandidate(
tempId: null == tempId ? _self.tempId : tempId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,basePriceMinor: freezed == basePriceMinor ? _self.basePriceMinor : basePriceMinor // ignore: cast_nullable_to_non_nullable
as int?,variants: null == variants ? _self._variants : variants // ignore: cast_nullable_to_non_nullable
as List<Variant>,confidence: null == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as double,ambiguities: null == ambiguities ? _self._ambiguities : ambiguities // ignore: cast_nullable_to_non_nullable
as List<Ambiguity>,
  ));
}


}

// dart format on
