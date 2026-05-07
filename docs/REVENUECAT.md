# RevenueCat Integration

## Overview

RevenueCat (RC) is the source of truth for subscription status **on the client**. The `isPremiumProvider` reads directly from RC's `CustomerInfo` — no Supabase round-trip needed for feature gating.

Supabase (`profiles.subscription_tier`) is kept in sync via a webhook for **server-side enforcement** (RPCs that check the tier before allowing actions like creating a 3rd group).

---

## Architecture

```
User purchases → RevenueCat → isPremiumProvider (Flutter)

profiles.subscription_tier is kept in sync via pg_cron (process_subscription_expirations),
NOT via RC webhook. The webhook approach is documented below but is not implemented.
```

---

## Module Structure

```
lib/modules/subscription/
├── domain/
│   └── payment_service.dart              # Abstract PaymentService + AppPurchaseResult enum
├── data/
│   ├── models/subscription_info.dart     # isPremium, expiresAt
│   └── services/revenue_cat_payment_service.dart  # RC implementation
├── providers/
│   └── subscription_provider.dart       # subscriptionProvider, isPremiumProvider
└── presentation/
    └── screens/paywall_screen.dart       # PaywallView wrapper screen
```

### Abstraction

`PaymentService` is an abstract interface. To swap RevenueCat for another provider:

1. Create a new class implementing `PaymentService`
2. Change one line in `service_locator.dart`:
   ```dart
   final PaymentService paymentService = NewPaymentService(); // was RevenueCatPaymentService
   ```

---

## Entitlement Key

The RC entitlement that grants premium access is:

```
spendz Pro
```

This must match exactly what is configured in the RevenueCat dashboard under **Entitlements**.

---

## API Keys

Configured as constants in `lib/modules/subscription/data/services/revenue_cat_payment_service.dart`:

```dart
static const _iOSApiKey = 'xxx';
static const _androidApiKey = 'xxx';
```

Replace with production keys before release. Consider moving to `env.dart` / `.env` files for environment separation.

---

## Initialization Flow

```
main() → paymentService.initialize()     ← configures Purchases SDK
       ↓
auth login/bootstrap → paymentService.identify(userId)   ← links RC identity to Supabase user
       ↓
auth logout → paymentService.logout()    ← resets RC to anonymous
```

`identify()` is called both on fresh login and on app bootstrap (existing session), so RC always has the correct user linked.

---

## Checking Premium Status (Flutter)

```dart
// In any ConsumerWidget
final isPremium = ref.watch(isPremiumProvider);
```

`isPremiumProvider` is a `Provider<bool>` derived from `subscriptionProvider` (an `AsyncNotifierProvider<SubscriptionNotifier, SubscriptionInfo>`). Returns `false` while loading or on error — safe to use anywhere.

Do **not** use `user?.subscriptionTier != 'free'` for in-app gating. That field is for server-side RPCs only.

---

## Presenting the Paywall

### From UpgradeSheet (modal → full screen)

The `UpgradeSheet` "Upgrade to Premium" button pops the sheet and pushes `paywallRoute`:

```dart
context.pop();
context.push(paywallRoute); // '/paywall'
```

### From anywhere via navigation

```dart
context.push(paywallRoute);
```

### PaywallScreen

`PaywallScreen` wraps `PaywallView` from `purchases_ui_flutter`. On purchase or restore, it invalidates `subscriptionProvider` (RC re-fetches `CustomerInfo`) and pops.

---

## Supabase Sync

**Current implementation:** `profiles.subscription_tier` is kept in sync by the `process_subscription_expirations()` pg_cron job (runs daily at 16:00 UTC / 00:00 MYT). It downgrades expired premium users to free and deactivates premium-only recurring items. See `docs/recurring_migration.sql`.

**RC webhook is NOT implemented.** The scaffold below is kept for reference in case a webhook is added later.

### Edge Function scaffold (not deployed)

```typescript
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('REVENUECAT_WEBHOOK_SECRET')!

const PREMIUM_EVENTS = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'PRODUCT_CHANGE',
])

const FREE_EVENTS = new Set([
  'CANCELLATION',
  'EXPIRATION',
  'BILLING_ISSUE',
  'SUBSCRIBER_ALIAS',
])

Deno.serve(async (req) => {
  // Verify shared secret
  const auth = req.headers.get('Authorization')
  if (auth !== WEBHOOK_SECRET) {
    return new Response('Unauthorized', { status: 401 })
  }

  const { event } = await req.json()
  const userId = event.app_user_id  // matches the userId passed to Purchases.logIn()

  if (PREMIUM_EVENTS.has(event.type)) {
    const expiresAt = event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null

    await supabase
      .from('profiles')
      .update({
        subscription_tier: expiresAt ? 'premium' : 'lifetime',
        subscription_expires_at: expiresAt,
      })
      .eq('id', userId)

  } else if (FREE_EVENTS.has(event.type)) {
    await supabase
      .from('profiles')
      .update({
        subscription_tier: 'free',
        subscription_expires_at: null,
      })
      .eq('id', userId)
  }

  return new Response('ok', { status: 200 })
})
```

### RC Event Types Reference

| Event | Meaning | Action |
|-------|---------|--------|
| `INITIAL_PURCHASE` | First subscription | → `premium` |
| `RENEWAL` | Subscription renewed | → `premium` |
| `UNCANCELLATION` | Cancelled user re-enabled | → `premium` |
| `PRODUCT_CHANGE` | Plan change | → `premium` |
| `CANCELLATION` | User cancelled (still active until period end) | → `free` |
| `EXPIRATION` | Subscription period ended | → `free` |
| `BILLING_ISSUE` | Payment failed | → `free` |

---

## More Screen

The More tab shows subscription status and links to the paywall:

- **Free user**: "Upgrade to Pro" with subtitle "Unlock all features"
- **Premium user**: "Spendz Pro" with subtitle "Active"

Tapping either navigates to `PaywallScreen`.

---

## RC Dashboard Checklist

Before going to production:

- [ ] Create **Entitlement** named `spendz Pro`
- [ ] Create **Products** (monthly, annual, lifetime) and attach to the entitlement
- [ ] Create an **Offering** with the products as packages
- [ ] Replace test API keys with production keys
- [ ] Configure **Webhook** URL pointing to the Supabase Edge Function *(optional — not currently used; sync is via pg_cron)*
- [ ] Set and store the **Webhook shared secret** in Supabase secrets (`REVENUECAT_WEBHOOK_SECRET`) *(only if webhook is enabled)*
- [ ] Test the full purchase → webhook → profile update flow in sandbox
