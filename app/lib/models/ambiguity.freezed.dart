// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ambiguity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Ambiguity {

 String get field; String get kind; String get question; List<String> get options; bool get blocking;
/// Create a copy of Ambiguity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AmbiguityCopyWith<Ambiguity> get copyWith => _$AmbiguityCopyWithImpl<Ambiguity>(this as Ambiguity, _$identity);

  /// Serializes this Ambiguity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Ambiguity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Ambiguity&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.question, _this.question) || other.question == _this.question)&&const DeepCollectionEquality().equals(other.options, _this.options)&&(identical(other.blocking, _this.blocking) || other.blocking == _this.blocking));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Ambiguity;
  return Object.hash(runtimeType,_this.field,_this.kind,_this.question,const DeepCollectionEquality().hash(_this.options),_this.blocking);
}

@override
String toString() {
  final _this = this as Ambiguity;
  return 'Ambiguity(field: ${_this.field}, kind: ${_this.kind}, question: ${_this.question}, options: ${_this.options}, blocking: ${_this.blocking})';
}


}

/// @nodoc
abstract mixin class $AmbiguityCopyWith<$Res>  {
  factory $AmbiguityCopyWith(Ambiguity value, $Res Function(Ambiguity) _then) = _$AmbiguityCopyWithImpl;
@useResult
$Res call({
 String field, String kind, String question, List<String> options, bool blocking
});




}
/// @nodoc
class _$AmbiguityCopyWithImpl<$Res>
    implements $AmbiguityCopyWith<$Res> {
  _$AmbiguityCopyWithImpl(this._self, this._then);

  final Ambiguity _self;
  final $Res Function(Ambiguity) _then;

/// Create a copy of Ambiguity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,Object? kind = null,Object? question = null,Object? options = null,Object? blocking = null,}) {
  return _then(Ambiguity(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<String>,blocking: null == blocking ? _self.blocking : blocking // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Ambiguity].
extension AmbiguityPatterns on Ambiguity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Ambiguity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Ambiguity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Ambiguity value)  $default,){
final _that = this;
switch (_that) {
case _Ambiguity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Ambiguity value)?  $default,){
final _that = this;
switch (_that) {
case _Ambiguity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String field,  String kind,  String question,  List<String> options,  bool blocking)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Ambiguity() when $default != null:
return $default(_that.field,_that.kind,_that.question,_that.options,_that.blocking);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String field,  String kind,  String question,  List<String> options,  bool blocking)  $default,) {final _that = this;
switch (_that) {
case _Ambiguity():
return $default(_that.field,_that.kind,_that.question,_that.options,_that.blocking);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String field,  String kind,  String question,  List<String> options,  bool blocking)?  $default,) {final _that = this;
switch (_that) {
case _Ambiguity() when $default != null:
return $default(_that.field,_that.kind,_that.question,_that.options,_that.blocking);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Ambiguity implements Ambiguity {
  const _Ambiguity({required this.field, required this.kind, required this.question,  List<String> options = const <String>[], this.blocking = true}): _options = options;
  factory _Ambiguity.fromJson(Map<String, dynamic> json) => _$AmbiguityFromJson(json);

@override final  String field;
@override final  String kind;
@override final  String question;
 final  List<String> _options;
@override@JsonKey() List<String> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@override@JsonKey() final  bool blocking;

/// Create a copy of Ambiguity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AmbiguityCopyWith<_Ambiguity> get copyWith => __$AmbiguityCopyWithImpl<_Ambiguity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AmbiguityToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Ambiguity&&(identical(other.field, field) || other.field == field)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.question, question) || other.question == question)&&const DeepCollectionEquality().equals(other.options, _options)&&(identical(other.blocking, blocking) || other.blocking == blocking));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,field,kind,question,const DeepCollectionEquality().hash(_options),blocking);
}

@override
String toString() {
    return 'Ambiguity(field: $field, kind: $kind, question: $question, options: $options, blocking: $blocking)';
}


}

/// @nodoc
abstract mixin class _$AmbiguityCopyWith<$Res> implements $AmbiguityCopyWith<$Res> {
  factory _$AmbiguityCopyWith(_Ambiguity value, $Res Function(_Ambiguity) _then) = __$AmbiguityCopyWithImpl;
@override @useResult
$Res call({
 String field, String kind, String question, List<String> options, bool blocking
});




}
/// @nodoc
class __$AmbiguityCopyWithImpl<$Res>
    implements _$AmbiguityCopyWith<$Res> {
  __$AmbiguityCopyWithImpl(this._self, this._then);

  final _Ambiguity _self;
  final $Res Function(_Ambiguity) _then;

/// Create a copy of Ambiguity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? kind = null,Object? question = null,Object? options = null,Object? blocking = null,}) {
  return _then(_Ambiguity(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<String>,blocking: null == blocking ? _self.blocking : blocking // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
