// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'order.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Fulfilment {

 String get mode; String? get date; String? get notes;
/// Create a copy of Fulfilment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FulfilmentCopyWith<Fulfilment> get copyWith => _$FulfilmentCopyWithImpl<Fulfilment>(this as Fulfilment, _$identity);

  /// Serializes this Fulfilment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Fulfilment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Fulfilment&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.date, _this.date) || other.date == _this.date)&&(identical(other.notes, _this.notes) || other.notes == _this.notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Fulfilment;
  return Object.hash(runtimeType,_this.mode,_this.date,_this.notes);
}

@override
String toString() {
  final _this = this as Fulfilment;
  return 'Fulfilment(mode: ${_this.mode}, date: ${_this.date}, notes: ${_this.notes})';
}


}

/// @nodoc
abstract mixin class $FulfilmentCopyWith<$Res>  {
  factory $FulfilmentCopyWith(Fulfilment value, $Res Function(Fulfilment) _then) = _$FulfilmentCopyWithImpl;
@useResult
$Res call({
 String mode, String? date, String? notes
});




}
/// @nodoc
class _$FulfilmentCopyWithImpl<$Res>
    implements $FulfilmentCopyWith<$Res> {
  _$FulfilmentCopyWithImpl(this._self, this._then);

  final Fulfilment _self;
  final $Res Function(Fulfilment) _then;

/// Create a copy of Fulfilment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? date = freezed,Object? notes = freezed,}) {
  return _then(Fulfilment(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,date: freezed == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Fulfilment].
extension FulfilmentPatterns on Fulfilment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Fulfilment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Fulfilment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Fulfilment value)  $default,){
final _that = this;
switch (_that) {
case _Fulfilment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Fulfilment value)?  $default,){
final _that = this;
switch (_that) {
case _Fulfilment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String mode,  String? date,  String? notes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Fulfilment() when $default != null:
return $default(_that.mode,_that.date,_that.notes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String mode,  String? date,  String? notes)  $default,) {final _that = this;
switch (_that) {
case _Fulfilment():
return $default(_that.mode,_that.date,_that.notes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String mode,  String? date,  String? notes)?  $default,) {final _that = this;
switch (_that) {
case _Fulfilment() when $default != null:
return $default(_that.mode,_that.date,_that.notes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Fulfilment implements Fulfilment {
  const _Fulfilment({this.mode = 'unknown', this.date, this.notes});
  factory _Fulfilment.fromJson(Map<String, dynamic> json) => _$FulfilmentFromJson(json);

@override@JsonKey() final  String mode;
@override final  String? date;
@override final  String? notes;

/// Create a copy of Fulfilment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FulfilmentCopyWith<_Fulfilment> get copyWith => __$FulfilmentCopyWithImpl<_Fulfilment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FulfilmentToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Fulfilment&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.date, date) || other.date == date)&&(identical(other.notes, notes) || other.notes == notes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,mode,date,notes);
}

@override
String toString() {
    return 'Fulfilment(mode: $mode, date: $date, notes: $notes)';
}


}

/// @nodoc
abstract mixin class _$FulfilmentCopyWith<$Res> implements $FulfilmentCopyWith<$Res> {
  factory _$FulfilmentCopyWith(_Fulfilment value, $Res Function(_Fulfilment) _then) = __$FulfilmentCopyWithImpl;
@override @useResult
$Res call({
 String mode, String? date, String? notes
});




}
/// @nodoc
class __$FulfilmentCopyWithImpl<$Res>
    implements _$FulfilmentCopyWith<$Res> {
  __$FulfilmentCopyWithImpl(this._self, this._then);

  final _Fulfilment _self;
  final $Res Function(_Fulfilment) _then;

/// Create a copy of Fulfilment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? date = freezed,Object? notes = freezed,}) {
  return _then(_Fulfilment(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,date: freezed == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$Order {

 String get id; String get status; String? get buyerName; String? get buyerHandle; String? get buyerEmail; String get channel; List<LineItem> get lineItems; int get subtotalMinor; int? get depositMinor; int get amountDueMinor; String get currency; Fulfilment get fulfilment; List<Ambiguity> get ambiguities; String? get paypalOrderId; String? get approvalUrl; String? get draftedReply; String get sourceKind;/// When the draft was written. The timeline's first entry.
@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? get createdAt;@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? get updatedAt;/// When the checkout link was created. Null until confirm.
@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? get linkSentAt;/// Set only when a capture completes. Null on every earlier status.
@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? get paidAt;
/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OrderCopyWith<Order> get copyWith => _$OrderCopyWithImpl<Order>(this as Order, _$identity);

  /// Serializes this Order to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Order;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Order&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.buyerName, _this.buyerName) || other.buyerName == _this.buyerName)&&(identical(other.buyerHandle, _this.buyerHandle) || other.buyerHandle == _this.buyerHandle)&&(identical(other.buyerEmail, _this.buyerEmail) || other.buyerEmail == _this.buyerEmail)&&(identical(other.channel, _this.channel) || other.channel == _this.channel)&&const DeepCollectionEquality().equals(other.lineItems, _this.lineItems)&&(identical(other.subtotalMinor, _this.subtotalMinor) || other.subtotalMinor == _this.subtotalMinor)&&(identical(other.depositMinor, _this.depositMinor) || other.depositMinor == _this.depositMinor)&&(identical(other.amountDueMinor, _this.amountDueMinor) || other.amountDueMinor == _this.amountDueMinor)&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.fulfilment, _this.fulfilment) || other.fulfilment == _this.fulfilment)&&const DeepCollectionEquality().equals(other.ambiguities, _this.ambiguities)&&(identical(other.paypalOrderId, _this.paypalOrderId) || other.paypalOrderId == _this.paypalOrderId)&&(identical(other.approvalUrl, _this.approvalUrl) || other.approvalUrl == _this.approvalUrl)&&(identical(other.draftedReply, _this.draftedReply) || other.draftedReply == _this.draftedReply)&&(identical(other.sourceKind, _this.sourceKind) || other.sourceKind == _this.sourceKind)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.linkSentAt, _this.linkSentAt) || other.linkSentAt == _this.linkSentAt)&&(identical(other.paidAt, _this.paidAt) || other.paidAt == _this.paidAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Order;
  return Object.hashAll([runtimeType,_this.id,_this.status,_this.buyerName,_this.buyerHandle,_this.buyerEmail,_this.channel,const DeepCollectionEquality().hash(_this.lineItems),_this.subtotalMinor,_this.depositMinor,_this.amountDueMinor,_this.currency,_this.fulfilment,const DeepCollectionEquality().hash(_this.ambiguities),_this.paypalOrderId,_this.approvalUrl,_this.draftedReply,_this.sourceKind,_this.createdAt,_this.updatedAt,_this.linkSentAt,_this.paidAt]);
}

@override
String toString() {
  final _this = this as Order;
  return 'Order(id: ${_this.id}, status: ${_this.status}, buyerName: ${_this.buyerName}, buyerHandle: ${_this.buyerHandle}, buyerEmail: ${_this.buyerEmail}, channel: ${_this.channel}, lineItems: ${_this.lineItems}, subtotalMinor: ${_this.subtotalMinor}, depositMinor: ${_this.depositMinor}, amountDueMinor: ${_this.amountDueMinor}, currency: ${_this.currency}, fulfilment: ${_this.fulfilment}, ambiguities: ${_this.ambiguities}, paypalOrderId: ${_this.paypalOrderId}, approvalUrl: ${_this.approvalUrl}, draftedReply: ${_this.draftedReply}, sourceKind: ${_this.sourceKind}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt}, linkSentAt: ${_this.linkSentAt}, paidAt: ${_this.paidAt})';
}


}

/// @nodoc
abstract mixin class $OrderCopyWith<$Res>  {
  factory $OrderCopyWith(Order value, $Res Function(Order) _then) = _$OrderCopyWithImpl;
@useResult
$Res call({
 String id, String status, String? buyerName, String? buyerHandle, String? buyerEmail, String channel, List<LineItem> lineItems, int subtotalMinor, int? depositMinor, int amountDueMinor, String currency, Fulfilment fulfilment, List<Ambiguity> ambiguities, String? paypalOrderId, String? approvalUrl, String? draftedReply, String sourceKind,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? createdAt,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? updatedAt,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? linkSentAt,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? paidAt
});


$FulfilmentCopyWith<$Res> get fulfilment;

}
/// @nodoc
class _$OrderCopyWithImpl<$Res>
    implements $OrderCopyWith<$Res> {
  _$OrderCopyWithImpl(this._self, this._then);

  final Order _self;
  final $Res Function(Order) _then;

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? status = null,Object? buyerName = freezed,Object? buyerHandle = freezed,Object? buyerEmail = freezed,Object? channel = null,Object? lineItems = null,Object? subtotalMinor = null,Object? depositMinor = freezed,Object? amountDueMinor = null,Object? currency = null,Object? fulfilment = null,Object? ambiguities = null,Object? paypalOrderId = freezed,Object? approvalUrl = freezed,Object? draftedReply = freezed,Object? sourceKind = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? linkSentAt = freezed,Object? paidAt = freezed,}) {
  return _then(Order(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,buyerName: freezed == buyerName ? _self.buyerName : buyerName // ignore: cast_nullable_to_non_nullable
as String?,buyerHandle: freezed == buyerHandle ? _self.buyerHandle : buyerHandle // ignore: cast_nullable_to_non_nullable
as String?,buyerEmail: freezed == buyerEmail ? _self.buyerEmail : buyerEmail // ignore: cast_nullable_to_non_nullable
as String?,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,lineItems: null == lineItems ? _self.lineItems : lineItems // ignore: cast_nullable_to_non_nullable
as List<LineItem>,subtotalMinor: null == subtotalMinor ? _self.subtotalMinor : subtotalMinor // ignore: cast_nullable_to_non_nullable
as int,depositMinor: freezed == depositMinor ? _self.depositMinor : depositMinor // ignore: cast_nullable_to_non_nullable
as int?,amountDueMinor: null == amountDueMinor ? _self.amountDueMinor : amountDueMinor // ignore: cast_nullable_to_non_nullable
as int,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,fulfilment: null == fulfilment ? _self.fulfilment : fulfilment // ignore: cast_nullable_to_non_nullable
as Fulfilment,ambiguities: null == ambiguities ? _self.ambiguities : ambiguities // ignore: cast_nullable_to_non_nullable
as List<Ambiguity>,paypalOrderId: freezed == paypalOrderId ? _self.paypalOrderId : paypalOrderId // ignore: cast_nullable_to_non_nullable
as String?,approvalUrl: freezed == approvalUrl ? _self.approvalUrl : approvalUrl // ignore: cast_nullable_to_non_nullable
as String?,draftedReply: freezed == draftedReply ? _self.draftedReply : draftedReply // ignore: cast_nullable_to_non_nullable
as String?,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,linkSentAt: freezed == linkSentAt ? _self.linkSentAt : linkSentAt // ignore: cast_nullable_to_non_nullable
as DateTime?,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FulfilmentCopyWith<$Res> get fulfilment {
  
  return $FulfilmentCopyWith<$Res>(_self.fulfilment, (value) {
    return _then(_self.copyWith(fulfilment: value));
  });
}
}


/// Adds pattern-matching-related methods to [Order].
extension OrderPatterns on Order {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Order value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Order() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Order value)  $default,){
final _that = this;
switch (_that) {
case _Order():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Order value)?  $default,){
final _that = this;
switch (_that) {
case _Order() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String status,  String? buyerName,  String? buyerHandle,  String? buyerEmail,  String channel,  List<LineItem> lineItems,  int subtotalMinor,  int? depositMinor,  int amountDueMinor,  String currency,  Fulfilment fulfilment,  List<Ambiguity> ambiguities,  String? paypalOrderId,  String? approvalUrl,  String? draftedReply,  String sourceKind, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? createdAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? updatedAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? linkSentAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? paidAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Order() when $default != null:
return $default(_that.id,_that.status,_that.buyerName,_that.buyerHandle,_that.buyerEmail,_that.channel,_that.lineItems,_that.subtotalMinor,_that.depositMinor,_that.amountDueMinor,_that.currency,_that.fulfilment,_that.ambiguities,_that.paypalOrderId,_that.approvalUrl,_that.draftedReply,_that.sourceKind,_that.createdAt,_that.updatedAt,_that.linkSentAt,_that.paidAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String status,  String? buyerName,  String? buyerHandle,  String? buyerEmail,  String channel,  List<LineItem> lineItems,  int subtotalMinor,  int? depositMinor,  int amountDueMinor,  String currency,  Fulfilment fulfilment,  List<Ambiguity> ambiguities,  String? paypalOrderId,  String? approvalUrl,  String? draftedReply,  String sourceKind, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? createdAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? updatedAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? linkSentAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? paidAt)  $default,) {final _that = this;
switch (_that) {
case _Order():
return $default(_that.id,_that.status,_that.buyerName,_that.buyerHandle,_that.buyerEmail,_that.channel,_that.lineItems,_that.subtotalMinor,_that.depositMinor,_that.amountDueMinor,_that.currency,_that.fulfilment,_that.ambiguities,_that.paypalOrderId,_that.approvalUrl,_that.draftedReply,_that.sourceKind,_that.createdAt,_that.updatedAt,_that.linkSentAt,_that.paidAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String status,  String? buyerName,  String? buyerHandle,  String? buyerEmail,  String channel,  List<LineItem> lineItems,  int subtotalMinor,  int? depositMinor,  int amountDueMinor,  String currency,  Fulfilment fulfilment,  List<Ambiguity> ambiguities,  String? paypalOrderId,  String? approvalUrl,  String? draftedReply,  String sourceKind, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? createdAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? updatedAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? linkSentAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson)  DateTime? paidAt)?  $default,) {final _that = this;
switch (_that) {
case _Order() when $default != null:
return $default(_that.id,_that.status,_that.buyerName,_that.buyerHandle,_that.buyerEmail,_that.channel,_that.lineItems,_that.subtotalMinor,_that.depositMinor,_that.amountDueMinor,_that.currency,_that.fulfilment,_that.ambiguities,_that.paypalOrderId,_that.approvalUrl,_that.draftedReply,_that.sourceKind,_that.createdAt,_that.updatedAt,_that.linkSentAt,_that.paidAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Order extends Order {
  const _Order({required this.id, this.status = 'draft', this.buyerName, this.buyerHandle, this.buyerEmail, this.channel = 'unknown',  List<LineItem> lineItems = const <LineItem>[], this.subtotalMinor = 0, this.depositMinor, this.amountDueMinor = 0, this.currency = 'GBP', this.fulfilment = const Fulfilment(),  List<Ambiguity> ambiguities = const <Ambiguity>[], this.paypalOrderId, this.approvalUrl, this.draftedReply, this.sourceKind = 'screenshot', @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) this.createdAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) this.updatedAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) this.linkSentAt, @JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) this.paidAt}): _lineItems = lineItems,_ambiguities = ambiguities,super._();
  factory _Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

@override final  String id;
@override@JsonKey() final  String status;
@override final  String? buyerName;
@override final  String? buyerHandle;
@override final  String? buyerEmail;
@override@JsonKey() final  String channel;
 final  List<LineItem> _lineItems;
@override@JsonKey() List<LineItem> get lineItems {
  if (_lineItems is EqualUnmodifiableListView) return _lineItems;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lineItems);
}

@override@JsonKey() final  int subtotalMinor;
@override final  int? depositMinor;
@override@JsonKey() final  int amountDueMinor;
@override@JsonKey() final  String currency;
@override@JsonKey() final  Fulfilment fulfilment;
 final  List<Ambiguity> _ambiguities;
@override@JsonKey() List<Ambiguity> get ambiguities {
  if (_ambiguities is EqualUnmodifiableListView) return _ambiguities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_ambiguities);
}

@override final  String? paypalOrderId;
@override final  String? approvalUrl;
@override final  String? draftedReply;
@override@JsonKey() final  String sourceKind;
/// When the draft was written. The timeline's first entry.
@override@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) final  DateTime? createdAt;
@override@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) final  DateTime? updatedAt;
/// When the checkout link was created. Null until confirm.
@override@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) final  DateTime? linkSentAt;
/// Set only when a capture completes. Null on every earlier status.
@override@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) final  DateTime? paidAt;

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OrderCopyWith<_Order> get copyWith => __$OrderCopyWithImpl<_Order>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OrderToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Order&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.buyerName, buyerName) || other.buyerName == buyerName)&&(identical(other.buyerHandle, buyerHandle) || other.buyerHandle == buyerHandle)&&(identical(other.buyerEmail, buyerEmail) || other.buyerEmail == buyerEmail)&&(identical(other.channel, channel) || other.channel == channel)&&const DeepCollectionEquality().equals(other.lineItems, _lineItems)&&(identical(other.subtotalMinor, subtotalMinor) || other.subtotalMinor == subtotalMinor)&&(identical(other.depositMinor, depositMinor) || other.depositMinor == depositMinor)&&(identical(other.amountDueMinor, amountDueMinor) || other.amountDueMinor == amountDueMinor)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.fulfilment, fulfilment) || other.fulfilment == fulfilment)&&const DeepCollectionEquality().equals(other.ambiguities, _ambiguities)&&(identical(other.paypalOrderId, paypalOrderId) || other.paypalOrderId == paypalOrderId)&&(identical(other.approvalUrl, approvalUrl) || other.approvalUrl == approvalUrl)&&(identical(other.draftedReply, draftedReply) || other.draftedReply == draftedReply)&&(identical(other.sourceKind, sourceKind) || other.sourceKind == sourceKind)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.linkSentAt, linkSentAt) || other.linkSentAt == linkSentAt)&&(identical(other.paidAt, paidAt) || other.paidAt == paidAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,status,buyerName,buyerHandle,buyerEmail,channel,const DeepCollectionEquality().hash(_lineItems),subtotalMinor,depositMinor,amountDueMinor,currency,fulfilment,const DeepCollectionEquality().hash(_ambiguities),paypalOrderId,approvalUrl,draftedReply,sourceKind,createdAt,updatedAt,linkSentAt,paidAt]);
}

@override
String toString() {
    return 'Order(id: $id, status: $status, buyerName: $buyerName, buyerHandle: $buyerHandle, buyerEmail: $buyerEmail, channel: $channel, lineItems: $lineItems, subtotalMinor: $subtotalMinor, depositMinor: $depositMinor, amountDueMinor: $amountDueMinor, currency: $currency, fulfilment: $fulfilment, ambiguities: $ambiguities, paypalOrderId: $paypalOrderId, approvalUrl: $approvalUrl, draftedReply: $draftedReply, sourceKind: $sourceKind, createdAt: $createdAt, updatedAt: $updatedAt, linkSentAt: $linkSentAt, paidAt: $paidAt)';
}


}

/// @nodoc
abstract mixin class _$OrderCopyWith<$Res> implements $OrderCopyWith<$Res> {
  factory _$OrderCopyWith(_Order value, $Res Function(_Order) _then) = __$OrderCopyWithImpl;
@override @useResult
$Res call({
 String id, String status, String? buyerName, String? buyerHandle, String? buyerEmail, String channel, List<LineItem> lineItems, int subtotalMinor, int? depositMinor, int amountDueMinor, String currency, Fulfilment fulfilment, List<Ambiguity> ambiguities, String? paypalOrderId, String? approvalUrl, String? draftedReply, String sourceKind,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? createdAt,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? updatedAt,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? linkSentAt,@JsonKey(fromJson: dateTimeFromJson, toJson: dateTimeToJson) DateTime? paidAt
});


@override $FulfilmentCopyWith<$Res> get fulfilment;

}
/// @nodoc
class __$OrderCopyWithImpl<$Res>
    implements _$OrderCopyWith<$Res> {
  __$OrderCopyWithImpl(this._self, this._then);

  final _Order _self;
  final $Res Function(_Order) _then;

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? status = null,Object? buyerName = freezed,Object? buyerHandle = freezed,Object? buyerEmail = freezed,Object? channel = null,Object? lineItems = null,Object? subtotalMinor = null,Object? depositMinor = freezed,Object? amountDueMinor = null,Object? currency = null,Object? fulfilment = null,Object? ambiguities = null,Object? paypalOrderId = freezed,Object? approvalUrl = freezed,Object? draftedReply = freezed,Object? sourceKind = null,Object? createdAt = freezed,Object? updatedAt = freezed,Object? linkSentAt = freezed,Object? paidAt = freezed,}) {
  return _then(_Order(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,buyerName: freezed == buyerName ? _self.buyerName : buyerName // ignore: cast_nullable_to_non_nullable
as String?,buyerHandle: freezed == buyerHandle ? _self.buyerHandle : buyerHandle // ignore: cast_nullable_to_non_nullable
as String?,buyerEmail: freezed == buyerEmail ? _self.buyerEmail : buyerEmail // ignore: cast_nullable_to_non_nullable
as String?,channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as String,lineItems: null == lineItems ? _self._lineItems : lineItems // ignore: cast_nullable_to_non_nullable
as List<LineItem>,subtotalMinor: null == subtotalMinor ? _self.subtotalMinor : subtotalMinor // ignore: cast_nullable_to_non_nullable
as int,depositMinor: freezed == depositMinor ? _self.depositMinor : depositMinor // ignore: cast_nullable_to_non_nullable
as int?,amountDueMinor: null == amountDueMinor ? _self.amountDueMinor : amountDueMinor // ignore: cast_nullable_to_non_nullable
as int,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,fulfilment: null == fulfilment ? _self.fulfilment : fulfilment // ignore: cast_nullable_to_non_nullable
as Fulfilment,ambiguities: null == ambiguities ? _self._ambiguities : ambiguities // ignore: cast_nullable_to_non_nullable
as List<Ambiguity>,paypalOrderId: freezed == paypalOrderId ? _self.paypalOrderId : paypalOrderId // ignore: cast_nullable_to_non_nullable
as String?,approvalUrl: freezed == approvalUrl ? _self.approvalUrl : approvalUrl // ignore: cast_nullable_to_non_nullable
as String?,draftedReply: freezed == draftedReply ? _self.draftedReply : draftedReply // ignore: cast_nullable_to_non_nullable
as String?,sourceKind: null == sourceKind ? _self.sourceKind : sourceKind // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,linkSentAt: freezed == linkSentAt ? _self.linkSentAt : linkSentAt // ignore: cast_nullable_to_non_nullable
as DateTime?,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of Order
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FulfilmentCopyWith<$Res> get fulfilment {
  
  return $FulfilmentCopyWith<$Res>(_self.fulfilment, (value) {
    return _then(_self.copyWith(fulfilment: value));
  });
}
}

// dart format on
