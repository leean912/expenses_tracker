import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../service_locator.dart';
import '../../home/providers/home/home_provider.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../data/models/user_model.dart';
import 'app_config_provider.dart';
import 'states/auth_state.dart';

final authProvider = NotifierProvider<AuthNotifier, AppAuthState>(
  AuthNotifier.new,
);

/// Derived provider that exposes only the current user's ID.
/// All data providers that are user-scoped should watch this so they
/// automatically rebuild when the account changes.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref
      .watch(authProvider)
      .maybeWhen(authenticated: (user) => user.id, orElse: () => null);
});

class AuthNotifier extends Notifier<AppAuthState> {
  StreamSubscription? _streamSubscription;

  @override
  AppAuthState build() {
    Future(() => {_bootstrap()});

    ref.onDispose(() {
      _streamSubscription?.cancel();
    });

    return AppAuthState.initial();
  }

  Future<void> _bootstrap() async {
    // Fetch all app config keys in one query before routing.
    try {
      final configRows = await supabase
          .from('app_config')
          .select('key, value')
          .inFilter('key', ['privacy_policy_version', 'min_app_version']);

      final config = {
        for (final r in configRows as List)
          r['key'] as String: r['value'] as String,
      };

      if (config.containsKey('privacy_policy_version')) {
        ref.read(currentPolicyVersionProvider.notifier).state = int.parse(
          config['privacy_policy_version']!,
        );
      }
      if (config.containsKey('min_app_version')) {
        ref.read(minAppVersionProvider.notifier).state =
            config['min_app_version']!;
      }
    } catch (_) {
      // Falls back to defaults.
    }

    final currentSession = supabase.auth.currentSession;

    if (currentSession != null) {
      final UserModel existing = UserModel.fromJson(
        await supabase
            .from('profiles')
            .select()
            .eq('id', currentSession.user.id)
            .single(),
      );

      unawaited(paymentService.identify(currentSession.user.id));
      unawaited(syncSubscriptionTier(currentSession.user.id));
      state = AppAuthState.authenticated(existing);
    } else {
      state = const AppAuthState.unauthenticated();
    }
  }

  void login() async {
    state = AppAuthState.loading();

    final User? user = await _googleSignIn();

    if (user == null) {
      state = AppAuthState.error('Something went wrong, please try again.');
      return;
    }

    try {
      final profile = await _fetchOrAwaitProfile(user.id);

      if (profile == null) {
        state = AppAuthState.error('Failed to load profile. Please try again.');
        return;
      }

      if (profile.deletedAt != null) {
        state = const AppAuthState.deleted();
        return;
      }

      // New user — write agreement since they had to tick the checkbox.
      UserModel finalProfile = profile;
      if (profile.privacyPolicyVersion == null) {
        finalProfile = await _writePrivacyAgreement(profile);
      }

      unawaited(paymentService.identify(finalProfile.id));
      unawaited(syncSubscriptionTier(finalProfile.id));
      ref.invalidate(homeAnalyticsProvider);
      ref.invalidate(homeExpensesProvider);
      state = AppAuthState.authenticated(finalProfile);
    } catch (e) {
      debugPrint('login error: $e');
      state = AppAuthState.error('Something went wrong, please try again.');
    }
  }

  // Returns the profile, waiting briefly for the handle_new_user() DB trigger
  // to complete if this is a first-time sign-in.
  Future<UserModel?> _fetchOrAwaitProfile(String userId) async {
    final rows = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .limit(1);

    if (rows.isNotEmpty) {
      return UserModel.fromJson(rows.first);
    }

    // New user — handle_new_user() trigger fires async on Supabase; retry once.
    await Future.delayed(const Duration(milliseconds: 800));
    final row = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    return row != null ? UserModel.fromJson(row) : null;
  }

  Future<User?> _googleSignIn() async {
    /// Web Client ID that you registered with Google Cloud.
    final webClientId = env.googleLoginWebClientId;

    /// iOS Client ID that you registered with Google Cloud.
    final iosClientId = env.googleLoginIosClientId;

    final scopes = ['email', 'profile'];

    // Google sign in on Android will work without providing the Android
    // Client ID registered on Google Cloud.

    final GoogleSignIn googleSignIn = GoogleSignIn.instance;

    // At the start of your app, initialize the GoogleSignIn instance
    await googleSignIn.initialize(
      clientId: iosClientId,
      serverClientId: webClientId,
    );

    final googleUser = await googleSignIn.authenticate();

    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
        await googleUser.authorizationClient.authorizeScopes(scopes);

    final idToken = googleUser.authentication.idToken;
    final accessToken = authorization.accessToken;

    if (idToken == null) {
      throw 'No ID Token found.';
    }

    await supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    return supabase.auth.currentUser;
  }

  /// Called from ConsentScreen when an existing user agrees to an updated policy.
  Future<void> agreeToPrivacyPolicy() async {
    final current = state.maybeWhen(
      authenticated: (user) => user,
      orElse: () => null,
    );
    if (current == null) return;
    final updated = await _writePrivacyAgreement(current);
    state = AppAuthState.authenticated(updated);
  }

  Future<UserModel> _writePrivacyAgreement(UserModel profile) async {
    final version = ref.read(currentPolicyVersionProvider);
    final now = DateTime.now();
    await supabase
        .from('profiles')
        .update({
          'privacy_policy_agreed_at': now.toIso8601String(),
          'privacy_policy_version': version,
        })
        .eq('id', profile.id);
    return profile.copyWith(
      privacyPolicyAgreedAt: now,
      privacyPolicyVersion: version,
    );
  }

  Future<void> updateDisplayName(String displayName) async {
    final current = state.maybeWhen(
      authenticated: (user) => user,
      orElse: () => null,
    );
    if (current == null) return;

    await supabase
        .from('profiles')
        .update({'display_name': displayName})
        .eq('id', current.id);

    state = AppAuthState.authenticated(
      current.copyWith(displayName: displayName),
    );
  }

  void logout() async {
    state = const AppAuthState.loading();

    await supabase.auth.signOut();
    // await GoogleSignIn.instance.disconnect();
    unawaited(paymentService.logout());

    state = const AppAuthState.unauthenticated();
  }
}
