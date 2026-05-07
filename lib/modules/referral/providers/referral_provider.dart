import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../service_locator.dart';
import '../data/models/referral_stats.dart';

final referralStatsProvider = FutureProvider.autoDispose<ReferralStats>((ref) async {
  final userId = supabase.auth.currentUser!.id;
  final results = await Future.wait([
    supabase.rpc('get_referral_stats') as Future<dynamic>,
    supabase
        .from('referrals')
        .select('id')
        .eq('referee_id', userId)
        .maybeSingle(),
  ]);

  final data = results[0] as Map<String, dynamic>;
  final usedRow = results[1];

  return ReferralStats(
    referralCode: data['referral_code'] as String,
    totalReferrals: data['total_referrals'] as int,
    hasUsedReferral: usedRow != null,
    referralsUntilNext: data['referrals_until_next'] as int,
    bonusExpiresAt: data['bonus_expires_at'] != null
        ? DateTime.parse(data['bonus_expires_at'] as String)
        : null,
  );
});

// ── Entry notifier ────────────────────────────────────────────────────────────

class ReferralCodeEntryState {
  const ReferralCodeEntryState({
    this.code = '',
    this.isSubmitting = false,
    this.error,
    this.submitted = false,
  });

  final String code;
  final bool isSubmitting;
  final String? error;
  final bool submitted;

  static final _validPattern = RegExp(r'^[A-Z0-9]{8}$');

  bool get isPartial => code.isNotEmpty && !_validPattern.hasMatch(code);
  bool get isValid => _validPattern.hasMatch(code);

  ReferralCodeEntryState copyWith({
    String? code,
    bool? isSubmitting,
    String? error,
    bool? submitted,
  }) => ReferralCodeEntryState(
    code: code ?? this.code,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: error,
    submitted: submitted ?? this.submitted,
  );
}

class ReferralCodeEntryNotifier extends Notifier<ReferralCodeEntryState> {
  @override
  ReferralCodeEntryState build() => const ReferralCodeEntryState();

  void onCodeChanged(String value) {
    state = state.copyWith(code: value.toUpperCase(), error: null);
  }

  Future<void> submit() async {
    if (!state.isValid || state.isSubmitting) return;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await supabase.rpc('apply_referral_code', params: {'p_code': state.code});
      state = state.copyWith(isSubmitting: false, submitted: true);
      ref.invalidate(referralStatsProvider);
    } on PostgrestException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        error: _errorMessage(e.hint),
      );
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Could not apply referral code. Please try again.',
      );
    }
  }

  String _errorMessage(String? hint) => switch (hint) {
    'invalid_code' => 'Referral code not found',
    'own_code' => 'You cannot use your own referral code',
    'already_used' => 'You have already used a referral code',
    _ => 'Could not apply referral code',
  };
}

final referralCodeEntryProvider =
    NotifierProvider<ReferralCodeEntryNotifier, ReferralCodeEntryState>(
  ReferralCodeEntryNotifier.new,
);
