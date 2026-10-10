// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'variant.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Variant {

/// Empty on a candidate: ids are assigned by the backend at save time via
/// uniqueSlugs, so `/catalogue/extract` sends variants without one.
 String get id; String get axis; String get label; int get priceDeltaMinor; bool get active;
/// Create a copy of Variant
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VariantCopyWith<Variant> get copyWith => _$VariantCopyWithImpl<Variant>(this as Variant, _$identity);

  /// Serializes this Variant to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Variant;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Variant&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.axis, _this.axis) || other.axis == _this.axis)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.priceDeltaMinor, _this.priceDeltaMinor) || other.priceDeltaMinor == _this.priceDeltaMinor)&&(identical(other.active, _this.active) || other.active == _this.active));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Variant;
  return Object.hash(runtimeType,_this.id,_this.axis,_this.label,_this.priceDeltaMinor,_this.active);
}

@override
String toString() {
  final _this = this as Variant;
  return 'Variant(id: ${_this.id}, axis: ${_this.axis}, label: ${_this.label}, priceDeltaMinor: ${_this.priceDeltaMinor}, active: ${_this.active})';
}


}

/// @nodoc
abstract mixin class $VariantCopyWith<$Res>  {
  factory $VariantCopyWith(Variant value, $Res Function(Variant) _then) = _$VariantCopyWithImpl;
@useResult
$Res call({
 String id, String axis, String label, int priceDeltaMinor, bool active
});




}
/// @nodoc
class _$VariantCopyWithImpl<$Res>
    implements $VariantCopyWith<$Res> {
  _$VariantCopyWithImpl(this._self, this._then);

  final Variant _self;
  final $Res Function(Variant) _then;

/// Create a copy of Variant
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? axis = null,Object? label = null,Object? priceDeltaMinor = null,Object? active = null,}) {
  return _then(Variant(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,axis: null == axis ? _self.axis : axis // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,priceDeltaMinor: null == priceDeltaMinor ? _self.priceDeltaMinor : priceDeltaMinor // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Variant].
extension VariantPatterns on Variant {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Variant value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Variant() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Variant value)  $default,){
final _that = this;
switch (_that) {
case _Variant():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Variant value)?  $default,){
final _that = this;
switch (_that) {
case _Variant() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String axis,  String label,  int priceDeltaMinor,  bool active)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Variant() when $default != null:
return $default(_that.id,_that.axis,_that.label,_that.priceDeltaMinor,_that.active);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String axis,  String label,  int priceDeltaMinor,  bool active)  $default,) {final _that = this;
switch (_that) {
case _Variant():
return $default(_that.id,_that.axis,_that.label,_that.priceDeltaMinor,_that.active);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String axis,  String label,  int priceDeltaMinor,  bool active)?  $default,) {final _that = this;
switch (_that) {
case _Variant() when $default != null:
return $default(_that.id,_that.axis,_that.label,_that.priceDeltaMinor,_that.active);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Variant implements Variant {
  const _Variant({this.id = '', required this.axis, required this.label, required this.priceDeltaMinor, this.active = true});
  factory _Variant.fromJson(Map<String, dynamic> json) => _$VariantFromJson(json);

/// Empty on a candidate: ids are assigned by the backend at save time via
/// uniqueSlugs, so `/catalogue/extract` sends variants without one.
@override@JsonKey() final  String id;
@override final  String axis;
@override final  String label;
@override final  int priceDeltaMinor;
@override@JsonKey() final  bool active;

/// Create a copy of Variant
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VariantCopyWith<_Variant> get copyWith => __$VariantCopyWithImpl<_Variant>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VariantToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Variant&&(identical(other.id, id) || other.id == id)&&(identical(other.axis, axis) || other.axis == axis)&&(identical(other.label, label) || other.label == label)&&(identical(other.priceDeltaMinor, priceDeltaMinor) || other.priceDeltaMinor == priceDeltaMinor)&&(identical(other.active, active) || other.active == active));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,axis,label,priceDeltaMinor,active);
}

@override
String toString() {
    return 'Variant(id: $id, axis: $axis, label: $label, priceDeltaMinor: $priceDeltaMinor, active: $active)';
}


}

/// @nodoc
abstract mixin class _$VariantCopyWith<$Res> implements $VariantCopyWith<$Res> {
  factory _$VariantCopyWith(_Variant value, $Res Function(_Variant) _then) = __$VariantCopyWithImpl;
@override @useResult
$Res call({
 String id, String axis, String label, int priceDeltaMinor, bool active
});




}
/// @nodoc
class __$VariantCopyWithImpl<$Res>
    implements _$VariantCopyWith<$Res> {
  __$VariantCopyWithImpl(this._self, this._then);

  final _Variant _self;
  final $Res Function(_Variant) _then;

/// Create a copy of Variant
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? axis = null,Object? label = null,Object? priceDeltaMinor = null,Object? active = null,}) {
  return _then(_Variant(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,axis: null == axis ? _self.axis : axis // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,priceDeltaMinor: null == priceDeltaMinor ? _self.priceDeltaMinor : priceDeltaMinor // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
