import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../service_locator.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../data/models/user_model.dart';
import 'states/auth_state.dart';

final authProvider = NotifierProvider<AuthNotifier, AppAuthState>(
  AuthNotifier.new,
);

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

      unawaited(paymentService.identify(profile.id));
      unawaited(syncSubscriptionTier(profile.id));
      state = AppAuthState.authenticated(profile);
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

  void logout() async {
    state = const AppAuthState.loading();

    await supabase.auth.signOut();
    await GoogleSignIn.instance.disconnect();
    unawaited(paymentService.logout());

    state = const AppAuthState.unauthenticated();
  }
}
