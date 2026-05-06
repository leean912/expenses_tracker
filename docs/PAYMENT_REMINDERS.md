# Payment Reminders (Premium Feature)

## Overview

Bill creators can send a push notification to participants who haven't settled their share yet. Limited to **once per hour per share** to prevent spam. Premium-only.

---

## User Flow

1. Creator opens a split bill detail screen
2. On a participant's **pending** share row, a bell icon appears (only visible to the creator)
3. Tapping the bell:
   - **Free user** → `UpgradeSheet` shown ("Upgrade to Premium")
   - **Premium, within cooldown** → bell is disabled, row shows "Reminded Xm ago"
   - **Premium, available** → sends reminder, snackbar "Reminder sent to [name]"
4. Participant receives push notification: *"[Creator] is waiting for your payment — you owe MYR X.XX for '[bill note]'"*

---

## Architecture

```
Flutter (bill creator taps bell)
  → supabase.functions.invoke('remind-split-share', { share_id })
      → Edge Function (JWT-authenticated, user context)
          → calls send_split_reminder RPC
              → validates: caller = bill creator, share = pending, cooldown > 1hr
              → updates split_bill_shares.last_reminded_at = now()
              → returns debtor's fcm_token + notification payload data
          → POST to FCM HTTP v1 API
              → debtor's device receives push notification
```

---

## Database Changes

Run this patch on Supabase SQL editor:

```sql
-- 1. FCM token per user (set by Flutter on login)
alter table profiles
  add column if not exists fcm_token text;

-- 2. Cooldown tracking per share
alter table split_bill_shares
  add column if not exists last_reminded_at timestamptz;

-- 3. RPC: validate + update cooldown + return notification payload
-- Called by the Edge Function using the user's JWT (RLS enforced)
create or replace function send_split_reminder(p_share_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_share  split_bill_shares%rowtype;
  v_bill   split_bills%rowtype;
  v_debtor_token  text;
  v_debtor_name   text;
  v_creator_name  text;
begin
  select * into v_share
  from split_bill_shares
  where id = p_share_id and deleted_at is null;

  if not found then
    raise exception 'Share not found' using errcode = 'P0001';
  end if;

  select * into v_bill
  from split_bills
  where id = v_share.split_bill_id and deleted_at is null;

  -- Only the bill creator may send reminders
  if v_bill.created_by != auth.uid() then
    raise exception 'Only the bill creator can send reminders'
      using errcode = 'P0001';
  end if;

  -- Share must still be pending
  if v_share.status != 'pending' then
    raise exception 'Share is not pending'
      using errcode = 'P0001';
  end if;

  -- Cannot remind yourself
  if v_share.user_id = auth.uid() then
    raise exception 'Cannot send reminder to yourself'
      using errcode = 'P0001';
  end if;

  -- 1-hour rate limit (server-side enforcement)
  if v_share.last_reminded_at is not null
     and v_share.last_reminded_at > now() - interval '1 hour' then
    raise exception 'Reminder sent too recently. Please wait before sending again.'
      using errcode = 'P0001', hint = 'rate_limited';
  end if;

  -- Fetch debtor info
  select fcm_token, coalesce(display_name, username)
  into v_debtor_token, v_debtor_name
  from profiles where id = v_share.user_id;

  -- Fetch creator name
  select coalesce(display_name, username)
  into v_creator_name
  from profiles where id = auth.uid();

  -- Stamp the cooldown
  update split_bill_shares
  set last_reminded_at = now()
  where id = p_share_id;

  return jsonb_build_object(
    'fcm_token',    v_debtor_token,
    'debtor_name',  v_debtor_name,
    'creator_name', v_creator_name,
    'amount_cents', v_share.share_cents,
    'currency',     v_bill.currency,
    'bill_note',    v_bill.note
  );
end;
$$;
```

---

## Supabase Edge Function

Deploy at: `supabase/functions/remind-split-share/index.ts`

```typescript
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return new Response('Unauthorized', { status: 401 })

  // User-scoped client — RLS enforces caller = bill creator inside the RPC
  const userSupabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )

  const { share_id } = await req.json()

  const { data, error } = await userSupabase.rpc('send_split_reminder', {
    p_share_id: share_id,
  })

  if (error) {
    const status = error.hint === 'rate_limited' ? 429 : 400
    return new Response(
      JSON.stringify({ error: error.message, hint: error.hint }),
      { status, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const { fcm_token, creator_name, amount_cents, currency, bill_note } = data

  // Debtor hasn't granted notification permission — not an error
  if (!fcm_token) {
    return new Response(
      JSON.stringify({ sent: false, reason: 'no_fcm_token' }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  }

  // Get Firebase access token from service account
  const accessToken = await getFirebaseAccessToken()
  const projectId = JSON.parse(Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON')!).project_id

  const amount = (amount_cents / 100).toFixed(2)
  const title = `${creator_name} is waiting for your payment`
  const body = `You owe ${currency} ${amount} for "${bill_note || 'Split bill'}"`

  const fcmRes = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: fcm_token,
          notification: { title, body },
          data: { type: 'split_bill_reminder', share_id },
        },
      }),
    },
  )

  if (!fcmRes.ok) {
    const err = await fcmRes.text()
    return new Response(JSON.stringify({ error: err }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  return new Response(JSON.stringify({ sent: true }), {
    headers: { 'Content-Type': 'application/json' },
  })
})

// Minimal OAuth2 JWT flow for Firebase service account
async function getFirebaseAccessToken(): Promise<string> {
  const sa = JSON.parse(Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON')!)
  const now = Math.floor(Date.now() / 1000)

  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = btoa(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  )

  const jwt = `${header}.${payload}.${btoa(String.fromCharCode(...new Uint8Array(sig)))}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const { access_token } = await res.json()
  return access_token
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')
  const bin = atob(b64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return buf.buffer
}
```

### Required Supabase secrets

Set these in Supabase Dashboard → Settings → Edge Functions → Secrets:

| Secret | Value |
|---|---|
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Full JSON content of the Firebase service account key |

To get the service account key: Firebase Console → Project Settings → Service Accounts → Generate new private key.

---

## Flutter Implementation

### New dependency

```yaml
# pubspec.yaml
firebase_messaging: ^15.2.5
```

### New file: `lib/modules/notifications/notification_service.dart`

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _supabase = Supabase.instance.client;

  Future<void> initialize(String userId) async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(userId, token);

    FirebaseMessaging.instance.onTokenRefresh.listen(
      (newToken) => _saveToken(userId, newToken),
    );
  }

  Future<void> _saveToken(String userId, String token) async {
    await _supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }

  // Returns error string or null on success.
  Future<String?> sendReminder(String shareId) async {
    try {
      await _supabase.functions.invoke(
        'remind-split-share',
        body: {'share_id': shareId},
      );
      return null;
    } on FunctionsException catch (e) {
      if ((e.details as Map?)?['hint'] == 'rate_limited') {
        return 'Already reminded recently. Try again in 1 hour.';
      }
      return 'Failed to send reminder';
    } catch (_) {
      return 'Failed to send reminder';
    }
  }
}
```

### Edit: `lib/service_locator.dart`

Add:
```dart
import 'package:expenses_tracker_new/modules/notifications/notification_service.dart';

final NotificationService notificationService = NotificationService();
```

### Edit: `lib/modules/auth/providers/auth_provider.dart`

In both `_bootstrap()` and `login()`, after `paymentService.identify(userId)`, add:
```dart
unawaited(notificationService.initialize(userId));
```

In `logout()`, clear the FCM token:
```dart
await _supabase.from('profiles').update({'fcm_token': null}).eq('id', currentUserId);
```

### Edit: `lib/modules/split_bills/data/models/split_share_model.dart`

Add field:
```dart
final DateTime? lastRemindedAt;
```

In `fromJson`:
```dart
lastRemindedAt: json['last_reminded_at'] != null
    ? DateTime.parse(json['last_reminded_at'] as String)
    : null,
```

### Edit: `lib/modules/split_bills/providers/split_bill_detail_provider.dart`

Update select string to include `last_reminded_at`:
```dart
'*, shares:split_bill_shares(*, last_reminded_at, user:profiles(...)), ...'
```

### Edit: `lib/modules/split_bills/presentation/screens/split_bill_detail_screen.dart`

**In `_BillDetail`**, pass `isCreator` to each `_ShareRow`:
```dart
_ShareRow(
  share: bill.shares[i],
  currency: bill.currency,
  isCurrentUser: bill.shares[i].userId == currentUserId,
  isCreator: bill.createdBy == currentUserId,   // new
  billId: billId,
)
```

**Convert `_ShareRow` to `ConsumerStatefulWidget`** and add remind button logic:

- Add `isCreator` parameter
- Add `bool _reminding` state
- Computed getters:
  - `_canRemind` → `isCreator && !isCurrentUser && share.isPending`
  - `_onCooldown` → `lastRemindedAt != null && DateTime.now().difference(lastRemindedAt!) < Duration(hours: 1)`
  - `_cooldownLabel` → `"Xm ago"` or `"Xh ago"`
- In the name column: if `_canRemind && _onCooldown`, show `"Reminded $_cooldownLabel"` as a small subtitle
- In the trailing widget slot:
  - `isCurrentUser && isPending` → existing `_SettleButton`
  - `_canRemind && _reminding` → small `CircularProgressIndicator`
  - `_canRemind` → `IconButton` with `Icons.notifications_outlined` (active) or `Icons.notifications_off_outlined` (cooldown, disabled)
  - otherwise → existing `_StatusChip`
- `_remind()` method:
  1. Check `ref.read(isPremiumProvider)` → show `UpgradeSheet` if false
  2. `setState(() => _reminding = true)`
  3. `await notificationService.sendReminder(share.id)`
  4. On error: show snackbar with error message
  5. On success: `ref.invalidate(splitBillDetailProvider(billId))`, snackbar "Reminder sent to [name]"

**Imports to add:**
```dart
import '../../../../core/widgets/upgrade_sheet.dart';
import '../../../subscription/providers/subscription_provider.dart';
```

---

## Platform Setup (one-time, manual)

### iOS (Xcode)
1. Enable **Push Notifications** capability in Xcode → Signing & Capabilities
2. Enable **Background Modes → Remote notifications**
3. In Firebase Console → Project Settings → Cloud Messaging → upload APNs Authentication Key

### Android
- Already works if `google-services.json` is in `android/app/`
- No extra config needed for FCM

### `ios/Runner/AppDelegate.swift`
```swift
import UIKit
import Flutter
import FirebaseCore

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

## Paywall Screen Update

Add to `_features` list in `paywall_screen.dart`:
```dart
(Icons.notifications_active_rounded, 'Payment reminders'),
```

---

## FREEMIUM.md Update

Add to V2 Premium Features:
```
- **Payment reminders** — notify people who owe you with one tap (1-hour cooldown per share)
```
