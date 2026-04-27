// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Initial _$InitialFromJson(Map<String, dynamic> json) =>
    _Initial($type: json['runtimeType'] as String?);

Map<String, dynamic> _$InitialToJson(_Initial instance) => <String, dynamic>{
  'runtimeType': instance.$type,
};

_Loading _$LoadingFromJson(Map<String, dynamic> json) =>
    _Loading($type: json['runtimeType'] as String?);

Map<String, dynamic> _$LoadingToJson(_Loading instance) => <String, dynamic>{
  'runtimeType': instance.$type,
};

_Authenticated _$AuthenticatedFromJson(Map<String, dynamic> json) =>
    _Authenticated(
      UserModel.fromJson(json['user'] as Map<String, dynamic>),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$AuthenticatedToJson(_Authenticated instance) =>
    <String, dynamic>{'user': instance.user, 'runtimeType': instance.$type};

_Deleted _$DeletedFromJson(Map<String, dynamic> json) =>
    _Deleted($type: json['runtimeType'] as String?);

Map<String, dynamic> _$DeletedToJson(_Deleted instance) => <String, dynamic>{
  'runtimeType': instance.$type,
};

_Unauthenticated _$UnauthenticatedFromJson(Map<String, dynamic> json) =>
    _Unauthenticated($type: json['runtimeType'] as String?);

Map<String, dynamic> _$UnauthenticatedToJson(_Unauthenticated instance) =>
    <String, dynamic>{'runtimeType': instance.$type};

_Error _$ErrorFromJson(Map<String, dynamic> json) =>
    _Error(json['message'] as String?, json['runtimeType'] as String?);

Map<String, dynamic> _$ErrorToJson(_Error instance) => <String, dynamic>{
  'message': instance.message,
  'runtimeType': instance.$type,
};
