import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../service_locator.dart';
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

      state = AppAuthState.authenticated(existing);
    } else {
      state = const AppAuthState.unauthenticated();
    }
  }

  // Future<void> _listen() async {
  //   _streamSubscription = supabase.auth.onAuthStateChange.listen((
  //     supabasestate,
  //   ) {
  //     if (supabasestate.event == AuthChangeEvent.signedOut) {
  //     } else if (supabasestate.event == AuthChangeEvent.signedIn) {}
  //   });
  // }

  void login() async {
    state = AppAuthState.loading();

    final User? user = await _googleSignIn();

    if (user == null) {
      state = AppAuthState.error('Something went wrong, please try again.');
      return;
    }

    // Handle soft-deleted/banned users
    final UserModel existing = UserModel.fromJson(
      await supabase.from('profiles').select().eq('id', user.id).single(),
    );

    // if (postSignInResult.errorMessage != null) {
    //   state = AppAuthState.error(postSignInResult.errorMessage!);
    //   return;
    // }

    // state = AppAuthState.authenticated(postSignInResult.user!);
  }

  Future<User?> _googleSignIn() async {
    /// Web Client ID that you registered with Google Cloud.
    final webClientId = env.googleLoginWebClientId;

    /// iOS Client ID that you registered with Google Cloud.
    final iosClientId = env.googleLoginIosClientId;

    // Google sign in on Android will work without providing the Android
    // Client ID registered on Google Cloud.

    final GoogleSignIn signIn = GoogleSignIn.instance;

    // At the start of your app, initialize the GoogleSignIn instance
    unawaited(
      signIn.initialize(clientId: iosClientId, serverClientId: webClientId),
    );

    try {
      // Perform the sign in
      final googleAccount = await signIn.authenticate();

      final googleAuthorization = await googleAccount.authorizationClient
          .authorizationForScopes(['email']);
      final googleAuthentication = googleAccount.authentication;
      final idToken = googleAuthentication.idToken;
      final accessToken = googleAuthorization?.accessToken;

      if (idToken == null) {
        throw 'No ID Token found.';
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      return supabase.auth.currentUser;
    } catch (e) {
      debugPrint('_googleSignIn error: $e');
      return null;
    }
  }

  void logout() async {
    state = const AppAuthState.loading();

    await supabase.auth.signOut();

    state = const AppAuthState.unauthenticated();
  }
}
