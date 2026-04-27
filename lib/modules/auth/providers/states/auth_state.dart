import 'package:freezed_annotation/freezed_annotation.dart';

import '../../data/models/user_model.dart';

part 'auth_state.freezed.dart';
part 'auth_state.g.dart';

@freezed
abstract class AppAuthState with _$AppAuthState {
  const factory AppAuthState.initial() = _Initial;

  const factory AppAuthState.loading() = _Loading;

  const factory AppAuthState.authenticated(UserModel user) = _Authenticated;

  const factory AppAuthState.deleted() = _Deleted;

  const factory AppAuthState.unauthenticated() = _Unauthenticated;

  const factory AppAuthState.error([String? message]) = _Error;

  factory AppAuthState.fromJson(Map<String, dynamic> json) =>
      _$AppAuthStateFromJson(json);
}
