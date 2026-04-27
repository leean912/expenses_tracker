// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_UserModel _$UserModelFromJson(Map<String, dynamic> json) => _UserModel(
  id: json['id'] as String,
  email: json['email'] as String,
  username: json['username'] as String?,
  displayName: json['displayName'] as String,
  avatarUrl: json['avatarUrl'] as String?,
  defaultCurrency: json['defaultCurrency'] as String? ?? 'MYR',
  subscriptionTier: json['subscriptionTier'] as String? ?? 'free',
  subscriptionExpiresAt: json['subscriptionExpiresAt'] == null
      ? null
      : DateTime.parse(json['subscriptionExpiresAt'] as String),
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$UserModelToJson(
  _UserModel instance,
) => <String, dynamic>{
  'id': instance.id,
  'email': instance.email,
  'username': instance.username,
  'displayName': instance.displayName,
  'avatarUrl': instance.avatarUrl,
  'defaultCurrency': instance.defaultCurrency,
  'subscriptionTier': instance.subscriptionTier,
  'subscriptionExpiresAt': instance.subscriptionExpiresAt?.toIso8601String(),
  'createdAt': instance.createdAt?.toIso8601String(),
  'updatedAt': instance.updatedAt?.toIso8601String(),
};
