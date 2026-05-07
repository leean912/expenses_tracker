import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../service_locator.dart';

class ReferralOnboardingState {
  const ReferralOnboardingState({
    this.code = '',
    this.isSubmitting = false,
    this.error,
  });

  final String code;
  final bool isSubmitting;
  final String? error;

  static final _validPattern = RegExp(r'^[A-Z0-9]{8}$');

  bool get hasCode => code.isNotEmpty;
  bool get isValidFormat => _validPattern.hasMatch(code);
  bool get isPartial => code.isNotEmpty && !isValidFormat;

  bool get canContinue {
    if (isSubmitting) return false;
    if (isPartial) return false;
    return true;
  }

  ReferralOnboardingState copyWith({
    String? code,
    bool? isSubmitting,
    String? error,
  }) => ReferralOnboardingState(
    code: code ?? this.code,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: error,
  );
}

class ReferralOnboardingNotifier
    extends Notifier<ReferralOnboardingState> {
  @override
  ReferralOnboardingState build() => const ReferralOnboardingState();

  void onCodeChanged(String value) {
    state = state.copyWith(code: value.toUpperCase(), error: null);
  }

  /// Returns true if navigation to home should proceed.
  Future<bool> submit() async {
    if (!state.canContinue) return false;

    // Empty code = skip
    if (!state.hasCode) return true;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await supabase.rpc(
        'apply_referral_code',
        params: {'p_code': state.code},
      );
      state = state.copyWith(isSubmitting: false);
      return true;
    } on PostgrestException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: _errorMessage(e.hint),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Could not apply referral code. Please try again.',
      );
      return false;
    }
  }

  String _errorMessage(String? hint) => switch (hint) {
    'invalid_code' => 'Referral code not found',
    'own_code' => 'You cannot use your own referral code',
    'already_used' => 'You have already used a referral code',
    _ => 'Could not apply referral code',
  };
}

final referralOnboardingProvider =
    NotifierProvider<ReferralOnboardingNotifier, ReferralOnboardingState>(
  ReferralOnboardingNotifier.new,
);
