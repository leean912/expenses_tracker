import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/states/auth_state.dart';
import '../data/models/subscription_info.dart';

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, SubscriptionInfo>(
  SubscriptionNotifier.new,
);

// Debug-only override: null = use real subscription, true = force premium, false = force free.
final devPremiumOverrideProvider = StateProvider<bool?>((ref) => null);

// Premium if RC subscription is active OR referral_premium_expires_at is in the future.
final isPremiumProvider = Provider<bool>((ref) {
  if (kDebugMode) {
    final override = ref.watch(devPremiumOverrideProvider);
    if (override != null) return override;
  }

  if (ref.watch(subscriptionProvider).valueOrNull?.isPremium ?? false) return true;

  return ref.watch(authProvider).maybeWhen(
    authenticated: (user) {
      final expiry = user.referralPremiumExpiresAt;
      return expiry != null && expiry.isAfter(DateTime.now());
    },
    orElse: () => false,
  );
});

class SubscriptionNotifier extends AsyncNotifier<SubscriptionInfo> {
  @override
  Future<SubscriptionInfo> build() {
    final sub = paymentService.customerInfoStream.listen((info) {
      state = AsyncData(info);
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) syncSubscriptionTier(userId);
    });
    ref.onDispose(sub.cancel);
    return paymentService.getSubscriptionInfo();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

Future<void> syncSubscriptionTier(String userId) async {
  try {
    final info = await paymentService.getSubscriptionInfo();

    if (!info.isPremium) {
      // Check if referral premium is still active before downgrading
      final profile = await supabase
          .from('profiles')
          .select('referral_premium_expires_at')
          .eq('id', userId)
          .single();

      final referralExpiry = profile['referral_premium_expires_at'] != null
          ? DateTime.parse(profile['referral_premium_expires_at'] as String)
          : null;

      if (referralExpiry != null && referralExpiry.isAfter(DateTime.now())) {
        await supabase.from('profiles').update({
          'subscription_tier': 'premium',
          'subscription_expires_at': referralExpiry.toIso8601String(),
        }).eq('id', userId);
        return;
      }
    }

    final tier = info.isPremium
        ? (info.expiresAt == null ? 'lifetime' : 'premium')
        : 'free';

    DateTime? newReferralExpiry;
    if (info.isPremium && info.expiresAt != null) {
      // If existing referral days would be eclipsed by the paid sub, push them
      // to start after the paid sub ends so they aren't silently discarded.
      final profile = await supabase
          .from('profiles')
          .select('referral_premium_expires_at')
          .eq('id', userId)
          .single();

      final referralExpiry = profile['referral_premium_expires_at'] != null
          ? DateTime.parse(profile['referral_premium_expires_at'] as String)
          : null;

      if (referralExpiry != null && referralExpiry.isBefore(info.expiresAt!)) {
        final daysRemaining = referralExpiry.difference(DateTime.now()).inDays;
        if (daysRemaining > 0) {
          newReferralExpiry = info.expiresAt!.add(Duration(days: daysRemaining));
        }
      }
    }

    await supabase.from('profiles').update({
      'subscription_tier': tier,
      'subscription_expires_at': info.expiresAt?.toIso8601String(),
      if (newReferralExpiry != null)
        'referral_premium_expires_at': newReferralExpiry.toIso8601String(),
    }).eq('id', userId);
  } catch (e) {
    debugPrint('syncSubscriptionTier error: $e');
  }
}
