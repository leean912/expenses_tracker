# Freemium Model

## Pricing Tiers

| Tier | Price | What You Get |
|---|---|---|
| **Free** | RM 0 | All core features, with usage limits |
| **Premium Monthly** | RM 12 / $2.99 | Everything unlimited |
| **Premium Annual** | RM 99 / $24.99 | Everything unlimited (~30% savings) |
| **Premium Lifetime** | RM 199 / $49 (one-time) | Everything unlimited, forever |

## Free Tier Limits

| Resource | Free Limit | Premium |
|---|---|---|
| Categories | 11 default + 5 custom = **16 total** | Unlimited |
| Accounts | 2 default + **5 custom** = 7 total | Unlimited |
| Groups | **2** | Unlimited |
| Collabs | Unlimited | Unlimited |
| Contacts | Unlimited | Unlimited |
| Expenses | Unlimited | Unlimited |
| Split bills | Unlimited | Unlimited |
| Budgets | Unlimited | Unlimited |

The principle: **core functionality is free**. Premium unlocks "more of the same" for power users with complex setups.

## Why These Specific Limits

### Categories — 11 default + 5 custom

The 11 defaults cover most spending: Food, Transport, Shopping, Bills, Entertainment, Health, Travel, Education, Gifts, Other, Trip.

5 custom slots let users add personal touches:
- "Coffee" (separate from Food)
- "Subscriptions"
- "Pets"
- "Gym"
- "Boba"

Power users who categorize obsessively (10+ custom) hit the limit and consider upgrading. Casual users never feel restricted.

### Accounts — 5 custom (7 total active)

A typical Malaysian payment-method setup:
- Cash (default — auto-seeded)
- Bank (default — auto-seeded)
- Touch'nGo eWallet (custom)
- Maybank Savings (custom)
- GrabPay or Boost (custom)
- 1 credit card (custom)
- Investment account (custom)

The 2 defaults plus 5 custom slots cover the vast majority of users. Power users with multiple banks and cards exceed 5 customs and upgrade.

Mirrors the categories pattern: defaults don't count toward the limit.

### Groups — 2 total

Most users have 1-2 distinct social circles for split bills:
- "Roommates" (recurring household expenses)
- "Office Lunch" or "Friends" (social splits)

Anyone with 3+ groups (gym crew + family + work + brunch friends) is a power user and the upgrade decision is easy.

## Schema Implementation

Limits are enforced at the RPC layer, not via constraints on the table. This:
- Lets free users see clear error messages (`hint = 'upgrade_required'`)
- Lets premium upgrades take effect immediately (just flip `subscription_tier`)
- Allows backward-compatible relaxation (lift a limit later without migration)

```sql
-- Pattern in every freemium RPC
if v_tier = 'free' and v_custom_count >= 10 then
  raise exception 'Free tier limit reached (10 custom accounts). Upgrade to Premium for unlimited.'
    using errcode = 'P0001', hint = 'upgrade_required';
end if;
```

Flutter catches this and shows an upgrade screen:

```dart
try {
  await supabase.rpc('create_account', params: {...});
} on PostgrestException catch (e) {
  if (e.hint == 'upgrade_required') {
    await showUpgradeSheet(context);
  } else {
    showError(e.message);
  }
}
```

## Subscription State

The `profiles` table tracks subscription via two columns:

```sql
subscription_tier text not null default 'free'
  check (subscription_tier in ('free', 'premium', 'lifetime'));
subscription_expires_at timestamptz;
```

- `free`: default state. All limits apply.
- `premium`: monthly or annual subscriber. `subscription_expires_at` is non-null. App should periodically check this and revert to `free` if expired.
- `lifetime`: one-time purchase. `subscription_expires_at` is NULL (never expires).

Periodic check via cron job (V2) or on app launch (Flutter side):

```dart
final profile = await supabase.from('profiles').select().single();
final expiresAt = profile['subscription_expires_at'];
final tier = profile['subscription_tier'];

if (tier == 'premium' && expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.now())) {
  // Subscription lapsed — degrade to free
  await supabase.from('profiles')
    .update({'subscription_tier': 'free'})
    .eq('id', currentUserId);
}
```

## Upgrade Triggers (UX)

When users hit a limit, show a compelling upgrade screen, not an error.

### Trigger: Try to create 6th custom account

```
┌───────────────────────────────────┐
│  You've added 5 custom accounts!  │
│                                   │
│  Power user? Premium gives you:   │
│  • Unlimited accounts             │
│  • Unlimited categories           │
│  • Unlimited groups               │
│                                   │
│  RM 12/month  or  RM 99/year      │
│                                   │
│  [ Upgrade ]    [ Maybe later ]   │
└───────────────────────────────────┘
```

### Trigger: Try to add 6th custom category

Same pattern — show value, let them dismiss.

### Trigger: Try to create 3rd group

Same pattern.

## Launch Strategy (Recommended)

Don't paywall on day 1. Launch with **all features free** for the first 3-6 months. Goals:

1. Validate product-market fit
2. Build user base
3. Gather feedback
4. Identify which features users actually love

Then introduce paywall:
- Existing users get a "thank you" period (e.g., 1 month free Premium)
- New users immediately face the freemium gates
- Lifetime tier as a launch promo for early supporters

## Conversion Math (Realistic)

```
At 1,000 active users with 5% conversion:
  50 paid users × RM 12/month × 12 months = RM 7,200/year
  
With Annual upgrade preference (60% choose annual):
  30 monthly × RM 12 × 12 = RM 4,320
  20 annual × RM 99 = RM 1,980
  Total: RM 6,300/year
  
With Lifetime sales (5% of paid users):
  Initial: 3 lifetime × RM 199 = RM 597 (one-time)
  Recurring: above ARR

Supabase Pro tier: $25/month = RM ~120/month = RM 1,440/year
Net at 1,000 users: ~RM 4,800-6,000/year profit
```

This is "side-project money," not "full-time income money." Plan accordingly.

## V2 Premium Features

To strengthen the upgrade pitch, V2 should add features that ONLY exist in Premium:

- **Receipt OCR** — scan and auto-extract amount + date
- **Live FX rates** — auto-fill exchange rates from API
- **Data export** — CSV / PDF / Excel export of all expenses
- **Cloud backup** — automatic backup of expense data
- **Recurring expenses** — auto-create monthly subscriptions
- **Custom split methods** — percentages, exact amounts, shares
- **Receipt photo storage** — attach photos to expenses

Each of these moves Premium from "just unlimited usage" to "qualitatively better app." That's where conversion really jumps.
