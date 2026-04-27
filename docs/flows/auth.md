# Authentication Flow

How a user goes from "tapped the app icon for the first time" to "logged in and using the app."

## Overview

```
Cold start → Splash → Onboarding (3-4 screens) → Sign in → Username pick → Main app
                                                    │
                                                    ▼
                                           [If returning user]
                                           Auto-login → Main app
```

## Sign-up flow (first-time user)

### Step 1: Splash + onboarding screens

User opens the app. Brief splash (logo, ~1s). Then 3-4 onboarding screens:

```
Screen 1: "Track what you spend"
  Visual: phone showing expense list with categories
  Text: "Log purchases, see where your money goes."

Screen 2: "Don't track conversions or transfers"
  Visual: ATM with X mark
  Text: "We focus on real spending — not money moving form."

Screen 3: "Split bills with friends"
  Visual: 3 people sharing a meal
  Text: "Easily split with the people you eat, travel, and live with."

Screen 4: "Your data stays private"
  Visual: lock icon
  Text: "We don't share your data. Ever."

[Get Started] button → goes to sign-in
```

User can skip via "Skip" button. Onboarding is shown only on first launch (track via SharedPreferences flag).

### Step 2: Sign in

```
Sign in screen:
  ┌─────────────────────────────────┐
  │   App Logo                       │
  │                                  │
  │   [ Sign in with Google ]        │
  │   [ Sign in with Apple ]         │
  │                                  │
  │   By signing in, you agree to    │
  │   our Terms and Privacy Policy.  │
  └─────────────────────────────────┘
```

User taps a provider button. OAuth flow begins.

```dart
// Google
await supabase.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: 'io.supabase.expensetracker://login-callback',
);

// Apple (iOS only)
await supabase.auth.signInWithApple();
```

OAuth completes. Supabase creates an `auth.users` row.

### Step 3: Trigger auto-creates profile

The `handle_new_user()` trigger fires when a new auth.users row is inserted:

```
trg_on_auth_user_created → handle_new_user():
  1. INSERT INTO profiles (id, email, display_name, avatar_url, default_currency)
       VALUES (
         <auth user id>,
         <email from OAuth>,
         <name from OAuth, fallback to email prefix>,
         <avatar from OAuth>,
         'MYR'  ← default
       );
       (username remains NULL initially)
  
  2. INSERT 11 default categories
  
  3. INSERT 2 default accounts (Cash, Bank) in MYR
```

### Step 4: Flutter checks username

After OAuth completes, Flutter fetches the profile:

```dart
final profile = await supabase
  .from('profiles')
  .select('username, display_name')
  .eq('id', supabase.auth.currentUser!.id)
  .single();

if (profile['username'] == null) {
  // First-time user — show username pick screen
  context.go('/onboarding/username');
} else {
  // Returning user — go to main app
  context.go('/home');
}
```

### Step 5: Username pick screen (first-time only)

```
┌──────────────────────────────────┐
│  Pick a username                  │
│                                  │
│  This is how friends will find   │
│  and add you to splits.          │
│                                  │
│  @ [          alice          ]   │
│       ✓ available                 │
│                                  │
│  3-20 characters                 │
│  Lowercase letters, digits, _    │
│                                  │
│  [ Continue ]                    │
└──────────────────────────────────┘
```

As the user types, debounced live validation:

```dart
String _username = '';
bool? _isAvailable;

void _onUsernameChanged(String value) async {
  setState(() => _username = value);
  
  // Debounce by 400ms
  await Future.delayed(Duration(milliseconds: 400));
  if (_username != value) return; // user kept typing
  
  if (value.length < 3) {
    setState(() => _isAvailable = null);
    return;
  }
  
  final available = await supabase.rpc(
    'check_username_available',
    params: {'p_username': value},
  ) as bool;
  
  setState(() => _isAvailable = available);
}
```

UI shows green check, red X, or hint text based on `_isAvailable`.

### Step 6: Save username

User taps Continue:

```dart
try {
  await supabase.rpc('set_username', params: {
    'p_username': _username,
  });
  // Navigate to main app
  context.go('/home');
} on PostgrestException catch (e) {
  if (e.hint == 'username_taken') {
    showError('That username is already taken');
  } else if (e.hint == 'invalid_format') {
    showError('Use 3-20 lowercase letters, digits, or underscores');
  }
}
```

The RPC enforces:
- Format constraint
- Uniqueness
- Immutability (once set, can't change in MVP)

## Sign-in flow (returning user)

```
App launch
  │
  ▼
Supabase SDK auto-restores session from secure storage
  │
  ├─ Session valid? ──Yes──► Fetch profile → Go to /home
  │
  └─ Session expired ──► Try refresh token
      │
      ├─ Success ──► Fetch profile → Go to /home
      │
      └─ Fail ──► Sign in screen
```

Supabase Flutter SDK handles this automatically. Just check `supabase.auth.currentSession`:

```dart
final session = supabase.auth.currentSession;
if (session != null) {
  // Logged in
  return MainApp();
} else {
  // Show sign-in screen
  return SignInScreen();
}
```

## Edge cases

### User cancels OAuth mid-flow

OAuth provider returns null/error. Flutter shows a friendly message and stays on sign-in screen.

```dart
try {
  await supabase.auth.signInWithOAuth(...);
} on AuthException catch (e) {
  if (e.message.contains('cancelled')) {
    // User cancelled — no error message needed
    return;
  }
  showError('Sign-in failed. Please try again.');
}
```

### Apple Private Relay email

Apple users may sign in with a private relay email like `xyz123@privaterelay.appleid.com`. The schema accepts this — `email` is just a unique text field. The user can still set a username and use the app normally.

### Trigger fails to fire

If `handle_new_user()` fails (extremely rare), the user has an `auth.users` row but no `profiles` row. Flutter detects this:

```dart
final profile = await supabase
  .from('profiles')
  .select()
  .eq('id', userId)
  .maybeSingle();

if (profile == null) {
  // Trigger didn't fire — manually create
  await supabase.from('profiles').insert({
    'id': userId,
    'email': user.email,
    'display_name': user.userMetadata?['full_name'] ?? 'User',
  });
  // Also seed categories + accounts manually
}
```

This shouldn't happen in production, but it's a safety net.

### User signs in on a new device

Same OAuth provider → same `auth.users` ID → same `profiles` row. All their data follows them.

If they sign in with a different provider (e.g., Google on phone, Apple on tablet) using the same email... this creates TWO separate accounts in Supabase. There's no email-based account linking in MVP. Document this in your Help / FAQ:

> "Make sure you sign in with the same provider (Google or Apple) on every device, otherwise you'll have separate accounts."

V2 can add account linking via Supabase's `linkIdentity` API.

### User signs out

```dart
await supabase.auth.signOut();
// Clear local SharedPreferences (last-used FX rates, settings, etc.)
await prefs.clear();
context.go('/sign-in');
```

Their data persists in Supabase. They can sign back in anytime.

### User deletes account

```dart
// Step 1: Confirm with user (multiple confirmations recommended)
final confirmed = await showDeleteAccountDialog(context);
if (!confirmed) return;

// Step 2: Call Supabase admin API to delete the auth user
// (Cascade delete will wipe profiles + all related data)
await supabase.auth.admin.deleteUser(userId);
// Note: This requires admin role. Typically you'd call an Edge Function
// that has admin privileges, not the client SDK directly.

// Step 3: Sign out locally + clear storage
await supabase.auth.signOut();
await prefs.clear();
context.go('/sign-in');
```

The cascade behavior of `profiles.id REFERENCES auth.users(id) ON DELETE CASCADE` ensures all user data is wiped.

## Flutter routing setup

Using `go_router`:

```dart
final router = GoRouter(
  redirect: (context, state) {
    final loggedIn = supabase.auth.currentUser != null;
    final atSignIn = state.matchedLocation == '/sign-in';
    
    if (!loggedIn && !atSignIn) return '/sign-in';
    if (loggedIn && atSignIn) return '/home';
    
    return null; // No redirect
  },
  routes: [
    GoRoute(path: '/sign-in', builder: (_, __) => SignInScreen()),
    GoRoute(path: '/onboarding/username', builder: (_, __) => UsernameScreen()),
    GoRoute(path: '/home', builder: (_, __) => MainApp()),
    // ...
  ],
);
```

Add a Riverpod provider that watches the auth state:

```dart
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});
```

When auth state changes, the router re-evaluates redirects.

## Common mistakes

1. **Don't show the username screen every launch.** Check `profile.username` once at app start; if set, go straight to main app.

2. **Don't fetch the profile inside individual screens.** Cache it in a Riverpod provider so it's available everywhere without N database hits.

3. **Don't trust `auth.currentUser.email` for display.** Use `profiles.display_name` and `profiles.username`.

4. **Don't forget Apple sign-in capability config.** iOS apps need "Sign in with Apple" capability enabled in Xcode + Apple Developer.

5. **Don't try to create profile rows manually if the trigger usually does it.** This causes duplicate-key errors. Only fall back to manual creation if the trigger demonstrably failed.
