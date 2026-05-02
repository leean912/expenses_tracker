import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import 'auth_provider.dart';

enum UsernameAvailability { idle, checking, available, taken, invalid }

class UserNameState {
  const UserNameState({
    this.availability = UsernameAvailability.idle,
    this.isSubmitting = false,
    this.error,
  });

  final UsernameAvailability availability;
  final bool isSubmitting;
  final String? error;

  UserNameState copyWith({
    UsernameAvailability? availability,
    bool? isSubmitting,
    String? error,
  }) => UserNameState(
    availability: availability ?? this.availability,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: error,
  );
}

class UserNameNotifier extends Notifier<UserNameState> {
  Timer? _debounce;

  @override
  UserNameState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const UserNameState();
  }

  // Supabase username format: 3–20 chars, lowercase alphanumeric + underscore.
  static final _validPattern = RegExp(r'^[a-z0-9_]{3,20}$');

  void onUsernameChanged(String value) {
    _debounce?.cancel();

    if (value.isEmpty) {
      state = const UserNameState();
      return;
    }

    if (!_validPattern.hasMatch(value)) {
      state = state.copyWith(availability: UsernameAvailability.invalid);
      return;
    }

    state = state.copyWith(availability: UsernameAvailability.checking);

    _debounce = Timer(const Duration(milliseconds: 500), () => _check(value));
  }

  Future<void> _check(String username) async {
    try {
      final available =
          await supabase.rpc(
                'check_username_available',
                params: {'p_username': username},
              )
              as bool;

      state = state.copyWith(
        availability: available
            ? UsernameAvailability.available
            : UsernameAvailability.taken,
      );
    } catch (_) {
      state = state.copyWith(availability: UsernameAvailability.idle);
    }
  }

  Future<bool> submit(String username) async {
    if (state.availability != UsernameAvailability.available) return false;

    state = state.copyWith(isSubmitting: true, error: null);

    try {
      await supabase.rpc('set_username', params: {'p_username': username});
      ref.invalidate(authProvider);
      return true;
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Failed to set username. Please try again.',
      );
      return false;
    }
  }
}

final userNameProvider = NotifierProvider<UserNameNotifier, UserNameState>(
  UserNameNotifier.new,
);
