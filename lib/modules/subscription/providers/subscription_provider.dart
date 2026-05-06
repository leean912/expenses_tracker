import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/subscription_info.dart';

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, SubscriptionInfo>(
  SubscriptionNotifier.new,
);

final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).valueOrNull?.isPremium ?? false;
});

class SubscriptionNotifier extends AsyncNotifier<SubscriptionInfo> {
  @override
  Future<SubscriptionInfo> build() => paymentService.getSubscriptionInfo();

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

Future<void> syncSubscriptionTier(String userId) async {
  try {
    final info = await paymentService.getSubscriptionInfo();
    final tier = info.isPremium
        ? (info.expiresAt == null ? 'lifetime' : 'premium')
        : 'free';
    await supabase.from('profiles').update({
      'subscription_tier': tier,
      'subscription_expires_at': info.expiresAt?.toIso8601String(),
    }).eq('id', userId);
  } catch (e) {
    debugPrint('syncSubscriptionTier error: $e');
  }
}
