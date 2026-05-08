# Push Notifications — "Ping" Feature Plan (V2)

**Status**: Planned, not started  
**Target**: V2  
**Scope**: Firebase Cloud Messaging (FCM) integration + premium "Ping" for split bill debtors

---

## What It Does

Premium users can tap **Ping** on a pending split bill share to send a push notification reminder to the person who owes them money. Rate limit: **once per share per hour**. Premium only.

---

## Architecture

```
Flutter (Ping button)
  │
  ▼
Supabase RPC: ping_split_share(p_share_id)
  │  validates: premium tier, bill ownership, share is pending, rate limit
  │  updates: split_bill_shares.last_pinged_at = now()
  │  returns: { fcm_token, debtor_display_name, bill_description, share_cents, currency }
  │
  ▼
Flutter calls Edge Function: send-push-notification
  │  re-validates share_id against calling user
  │  fetches: profiles.fcm_token of target user
  │  calls: Firebase FCM v1 API (service account key stored as Edge Function secret)
  │
  ▼
Firebase FCM → Target Device
  │
  ▼
Flutter (notification tap) → deep-links to split bill detail screen
```

**Why RPC → Flutter → Edge Function (not RPC → Edge Function directly):**
- Avoids `pg_net` extension dependency (requires Supabase Pro, adds complexity)
- FCM server key stays in Edge Function secrets — never in Flutter bundle
- FCM token of target user is returned by RPC (security definer context), not fetched by Flutter directly

---

## Database Changes Required

Two additive patches — no RLS rewrites, no data loss.

### Patch file: `docs/patches/add_fcm_ping.sql` (create when implementing)

**1. `profiles` table — store FCM token per device:**
```sql
alter table profiles
  add column fcm_token text,
  add column fcm_token_updated_at timestamptz;
```

**2. `split_bill_shares` table — rate limit tracking:**
```sql
alter table split_bill_shares
  add column last_pinged_at timestamptz;
```

`last_pinged_at` is NULL when never pinged. The RPC rejects a new ping if `now() - last_pinged_at < interval '1 hour'`.

---

## New Supabase RPC: `ping_split_share(p_share_id uuid)`

Security definer. Logic:

1. Get caller's profile — must be `premium` or `lifetime`, else raise `upgrade_required`
2. Get the share — must exist, status `pending`, not archived
3. Validate caller is `created_by` or `paid_by` on the parent `split_bills` row (they are owed money)
4. Caller cannot ping their own share
5. Rate limit check — if `now() - last_pinged_at < '1 hour'`, raise error with time remaining
6. Fetch `profiles.fcm_token` of the share's `user_id`
7. Update `split_bill_shares.last_pinged_at = now()`
8. Return `{ fcm_token, debtor_display_name, bill_description, share_cents, currency }`

---

## New Supabase Edge Function: `send-push-notification`

- Accepts: Supabase JWT (caller must be authenticated) + `{ share_id, fcm_token, payload }`
- Re-validates `share_id` belongs to the calling user's bill (belt-and-suspenders)
- Calls Firebase FCM v1 API using service account credentials (stored as Edge Function secret, not in code)
- Returns `{ success: true }` or descriptive error

**FCM notification shape:**
```json
{
  "title": "Hey, you owe @alice 💸",
  "body": "RM 45.00 from Dinner at Fatty Crab — settle up when you can!",
  "data": {
    "screen": "split_bill_detail",
    "bill_id": "<uuid>"
  }
}
```

---

## Flutter Changes

### New packages
```
firebase_core
firebase_messaging
flutter_local_notifications  (for foreground in-app banners)
```

Use `fvm flutter pub add <pkg>` — do NOT edit pubspec.yaml manually.

### Platform config (one-time manual setup)
- `android/app/google-services.json` — from Firebase Console
- `ios/Runner/GoogleService-Info.plist` — from Firebase Console
- iOS: enable **Push Notifications** capability in Xcode
- iOS: enable **Background Modes → Remote notifications** in Xcode
- `android/build.gradle`: add `classpath 'com.google.gms:google-services:...'`
- `android/app/build.gradle`: add `apply plugin: 'com.google.gms.google-services'`

### Code changes (5 areas)

| Area | What changes |
|---|---|
| App startup (`main.dart` or `app.dart`) | Init Firebase, request permission, get token, upsert `profiles.fcm_token` |
| Token refresh | `FirebaseMessaging.instance.onTokenRefresh` → upsert new token to `profiles` |
| Foreground messages | `FirebaseMessaging.onMessage` → show local notification banner |
| Background/terminated handler | Top-level `firebaseMessagingBackgroundHandler` function (Flutter requirement — must be top-level, not a class method) |
| Notification tap routing | `onMessageOpenedApp` + `getInitialMessage` → `go_router` push to split bill detail |
| Split bill detail screen | Ping button (hidden or greyed for free tier) → RPC → Edge Function |

### Token upsert on startup
```dart
final token = await FirebaseMessaging.instance.getToken();
if (token != null) {
  await supabase.from('profiles').update({
    'fcm_token': token,
    'fcm_token_updated_at': DateTime.now().toIso8601String(),
  }).eq('id', supabase.auth.currentUser!.id);
}
```

### Notification tap → deep link
```dart
// On app resume from notification
FirebaseMessaging.onMessageOpenedApp.listen((message) {
  final screen = message.data['screen'];
  final billId = message.data['bill_id'];
  if (screen == 'split_bill_detail' && billId != null) {
    context.push('/split-bills/$billId');
  }
});
```

---

## Freemium Gate

The RPC enforces this server-side. Flutter adds a client-side check for UX (same upgrade sheet used elsewhere):

```dart
if (profile.subscriptionTier == 'free') {
  showUpgradeSheet(context); // existing upgrade flow
  return;
}
// proceed with ping
```

Freemium pitch copy suggestion: *"Ping your friends to settle up — Premium feature."*

---

## Impact Summary

| Area | Impact | Reversible? |
|---|---|---|
| DB schema | 3 new nullable columns (additive) | Yes — `alter table ... drop column` |
| Supabase RPCs | 1 new RPC | Yes |
| Supabase Edge Functions | 1 new function | Yes |
| Flutter packages | `firebase_messaging`, `firebase_core`, `flutter_local_notifications` | Yes |
| iOS/Android config | Platform files + entitlements | Yes |
| Existing features | None affected | — |

No RLS rewrites. No table restructures. No impact on existing queries.

The `profiles` RLS `profile_self` policy already allows self-update for token upsert. The `ping_split_share` RPC is `security definer` so it can safely read another user's `fcm_token` without exposing it to Flutter.

---

## Implementation Order (when ready)

1. Firebase project setup in Firebase Console (manual, ~15 min)
2. Add `docs/patches/add_fcm_ping.sql` and run on Supabase
3. Flutter: add packages + platform config files
4. Flutter: FCM token registration on app startup + refresh listener
5. Supabase Edge Function: `send-push-notification`
6. Supabase RPC: `ping_split_share`
7. Flutter: notification tap routing via `go_router`
8. Flutter: "Ping" button in split bill detail screen (with premium guard)

---

## Firebase Console Setup Notes (when starting)

- Create project at https://console.firebase.google.com
- Add Android app: package name from `android/app/build.gradle` (`applicationId`)
- Add iOS app: bundle ID from Xcode → Runner → General → Bundle Identifier
- Enable Cloud Messaging in the Firebase Console
- Generate a service account key (Project Settings → Service Accounts → Generate new private key) — store as Supabase Edge Function secret, never commit to repo
