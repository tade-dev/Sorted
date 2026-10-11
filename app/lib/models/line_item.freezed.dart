// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'line_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LineItem {

 String get id;/// Null when the catalogue had nothing matching, which is a blocking
/// ambiguity rather than a GBP 0 line.
 String? get productId; List<String> get variantIds;/// What the buyer actually wrote, kept so the seller can see it.
 String get nameRaw; String? get nameResolved; int get qty; int get unitPriceMinor; int get lineTotalMinor; double get matchConfidence; String get matchMethod;
/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LineItemCopyWith<LineItem> get copyWith => _$LineItemCopyWithImpl<LineItem>(this as LineItem, _$identity);

  /// Serializes this LineItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LineItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LineItem&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.productId, _this.productId) || other.productId == _this.productId)&&const DeepCollectionEquality().equals(other.variantIds, _this.variantIds)&&(identical(other.nameRaw, _this.nameRaw) || other.nameRaw == _this.nameRaw)&&(identical(other.nameResolved, _this.nameResolved) || other.nameResolved == _this.nameResolved)&&(identical(other.qty, _this.qty) || other.qty == _this.qty)&&(identical(other.unitPriceMinor, _this.unitPriceMinor) || other.unitPriceMinor == _this.unitPriceMinor)&&(identical(other.lineTotalMinor, _this.lineTotalMinor) || other.lineTotalMinor == _this.lineTotalMinor)&&(identical(other.matchConfidence, _this.matchConfidence) || other.matchConfidence == _this.matchConfidence)&&(identical(other.matchMethod, _this.matchMethod) || other.matchMethod == _this.matchMethod));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LineItem;
  return Object.hash(runtimeType,_this.id,_this.productId,const DeepCollectionEquality().hash(_this.variantIds),_this.nameRaw,_this.nameResolved,_this.qty,_this.unitPriceMinor,_this.lineTotalMinor,_this.matchConfidence,_this.matchMethod);
}

@override
String toString() {
  final _this = this as LineItem;
  return 'LineItem(id: ${_this.id}, productId: ${_this.productId}, variantIds: ${_this.variantIds}, nameRaw: ${_this.nameRaw}, nameResolved: ${_this.nameResolved}, qty: ${_this.qty}, unitPriceMinor: ${_this.unitPriceMinor}, lineTotalMinor: ${_this.lineTotalMinor}, matchConfidence: ${_this.matchConfidence}, matchMethod: ${_this.matchMethod})';
}


}

/// @nodoc
abstract mixin class $LineItemCopyWith<$Res>  {
  factory $LineItemCopyWith(LineItem value, $Res Function(LineItem) _then) = _$LineItemCopyWithImpl;
@useResult
$Res call({
 String id, String? productId, List<String> variantIds, String nameRaw, String? nameResolved, int qty, int unitPriceMinor, int lineTotalMinor, double matchConfidence, String matchMethod
});




}
/// @nodoc
class _$LineItemCopyWithImpl<$Res>
    implements $LineItemCopyWith<$Res> {
  _$LineItemCopyWithImpl(this._self, this._then);

  final LineItem _self;
  final $Res Function(LineItem) _then;

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? productId = freezed,Object? variantIds = null,Object? nameRaw = null,Object? nameResolved = freezed,Object? qty = null,Object? unitPriceMinor = null,Object? lineTotalMinor = null,Object? matchConfidence = null,Object? matchMethod = null,}) {
  return _then(LineItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,productId: freezed == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String?,variantIds: null == variantIds ? _self.variantIds : variantIds // ignore: cast_nullable_to_non_nullable
as List<String>,nameRaw: null == nameRaw ? _self.nameRaw : nameRaw // ignore: cast_nullable_to_non_nullable
as String,nameResolved: freezed == nameResolved ? _self.nameResolved : nameResolved // ignore: cast_nullable_to_non_nullable
as String?,qty: null == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as int,unitPriceMinor: null == unitPriceMinor ? _self.unitPriceMinor : unitPriceMinor // ignore: cast_nullable_to_non_nullable
as int,lineTotalMinor: null == lineTotalMinor ? _self.lineTotalMinor : lineTotalMinor // ignore: cast_nullable_to_non_nullable
as int,matchConfidence: null == matchConfidence ? _self.matchConfidence : matchConfidence // ignore: cast_nullable_to_non_nullable
as double,matchMethod: null == matchMethod ? _self.matchMethod : matchMethod // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LineItem].
extension LineItemPatterns on LineItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LineItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LineItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LineItem value)  $default,){
final _that = this;
switch (_that) {
case _LineItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LineItem value)?  $default,){
final _that = this;
switch (_that) {
case _LineItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? productId,  List<String> variantIds,  String nameRaw,  String? nameResolved,  int qty,  int unitPriceMinor,  int lineTotalMinor,  double matchConfidence,  String matchMethod)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LineItem() when $default != null:
return $default(_that.id,_that.productId,_that.variantIds,_that.nameRaw,_that.nameResolved,_that.qty,_that.unitPriceMinor,_that.lineTotalMinor,_that.matchConfidence,_that.matchMethod);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? productId,  List<String> variantIds,  String nameRaw,  String? nameResolved,  int qty,  int unitPriceMinor,  int lineTotalMinor,  double matchConfidence,  String matchMethod)  $default,) {final _that = this;
switch (_that) {
case _LineItem():
return $default(_that.id,_that.productId,_that.variantIds,_that.nameRaw,_that.nameResolved,_that.qty,_that.unitPriceMinor,_that.lineTotalMinor,_that.matchConfidence,_that.matchMethod);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? productId,  List<String> variantIds,  String nameRaw,  String? nameResolved,  int qty,  int unitPriceMinor,  int lineTotalMinor,  double matchConfidence,  String matchMethod)?  $default,) {final _that = this;
switch (_that) {
case _LineItem() when $default != null:
return $default(_that.id,_that.productId,_that.variantIds,_that.nameRaw,_that.nameResolved,_that.qty,_that.unitPriceMinor,_that.lineTotalMinor,_that.matchConfidence,_that.matchMethod);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LineItem extends LineItem {
  const _LineItem({required this.id, this.productId,  List<String> variantIds = const <String>[], required this.nameRaw, this.nameResolved, this.qty = 1, this.unitPriceMinor = 0, this.lineTotalMinor = 0, this.matchConfidence = 0.0, this.matchMethod = 'unmatched'}): _variantIds = variantIds,super._();
  factory _LineItem.fromJson(Map<String, dynamic> json) => _$LineItemFromJson(json);

@override final  String id;
/// Null when the catalogue had nothing matching, which is a blocking
/// ambiguity rather than a GBP 0 line.
@override final  String? productId;
 final  List<String> _variantIds;
@override@JsonKey() List<String> get variantIds {
  if (_variantIds is EqualUnmodifiableListView) return _variantIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_variantIds);
}

/// What the buyer actually wrote, kept so the seller can see it.
@override final  String nameRaw;
@override final  String? nameResolved;
@override@JsonKey() final  int qty;
@override@JsonKey() final  int unitPriceMinor;
@override@JsonKey() final  int lineTotalMinor;
@override@JsonKey() final  double matchConfidence;
@override@JsonKey() final  String matchMethod;

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LineItemCopyWith<_LineItem> get copyWith => __$LineItemCopyWithImpl<_LineItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LineItemToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LineItem&&(identical(other.id, id) || other.id == id)&&(identical(other.productId, productId) || other.productId == productId)&&const DeepCollectionEquality().equals(other.variantIds, _variantIds)&&(identical(other.nameRaw, nameRaw) || other.nameRaw == nameRaw)&&(identical(other.nameResolved, nameResolved) || other.nameResolved == nameResolved)&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.unitPriceMinor, unitPriceMinor) || other.unitPriceMinor == unitPriceMinor)&&(identical(other.lineTotalMinor, lineTotalMinor) || other.lineTotalMinor == lineTotalMinor)&&(identical(other.matchConfidence, matchConfidence) || other.matchConfidence == matchConfidence)&&(identical(other.matchMethod, matchMethod) || other.matchMethod == matchMethod));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,productId,const DeepCollectionEquality().hash(_variantIds),nameRaw,nameResolved,qty,unitPriceMinor,lineTotalMinor,matchConfidence,matchMethod);
}

@override
String toString() {
    return 'LineItem(id: $id, productId: $productId, variantIds: $variantIds, nameRaw: $nameRaw, nameResolved: $nameResolved, qty: $qty, unitPriceMinor: $unitPriceMinor, lineTotalMinor: $lineTotalMinor, matchConfidence: $matchConfidence, matchMethod: $matchMethod)';
}


}

/// @nodoc
abstract mixin class _$LineItemCopyWith<$Res> implements $LineItemCopyWith<$Res> {
  factory _$LineItemCopyWith(_LineItem value, $Res Function(_LineItem) _then) = __$LineItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String? productId, List<String> variantIds, String nameRaw, String? nameResolved, int qty, int unitPriceMinor, int lineTotalMinor, double matchConfidence, String matchMethod
});




}
/// @nodoc
class __$LineItemCopyWithImpl<$Res>
    implements _$LineItemCopyWith<$Res> {
  __$LineItemCopyWithImpl(this._self, this._then);

  final _LineItem _self;
  final $Res Function(_LineItem) _then;

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? productId = freezed,Object? variantIds = null,Object? nameRaw = null,Object? nameResolved = freezed,Object? qty = null,Object? unitPriceMinor = null,Object? lineTotalMinor = null,Object? matchConfidence = null,Object? matchMethod = null,}) {
  return _then(_LineItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,productId: freezed == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as String?,variantIds: null == variantIds ? _self._variantIds : variantIds // ignore: cast_nullable_to_non_nullable
as List<String>,nameRaw: null == nameRaw ? _self.nameRaw : nameRaw // ignore: cast_nullable_to_non_nullable
as String,nameResolved: freezed == nameResolved ? _self.nameResolved : nameResolved // ignore: cast_nullable_to_non_nullable
as String?,qty: null == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as int,unitPriceMinor: null == unitPriceMinor ? _self.unitPriceMinor : unitPriceMinor // ignore: cast_nullable_to_non_nullable
as int,lineTotalMinor: null == lineTotalMinor ? _self.lineTotalMinor : lineTotalMinor // ignore: cast_nullable_to_non_nullable
as int,matchConfidence: null == matchConfidence ? _self.matchConfidence : matchConfidence // ignore: cast_nullable_to_non_nullable
as double,matchMethod: null == matchMethod ? _self.matchMethod : matchMethod // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
