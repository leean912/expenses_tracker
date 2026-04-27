# accounts

Per-user payment method tags. Track WHERE money was spent from (Maybank, Cash, Touch'nGo, credit card, etc.).

**Important**: These are NOT balance-tracking accounts. There is no `current_balance` column — accounts are pure metadata tags for analytics.

## Purpose

Tag each expense with a payment method so users can see "I spent RM 500 from Maybank this month, RM 200 from cash." Complements categories (which track WHAT was bought) with a HOW-PAID dimension.

## Pattern: mirrors categories

Accounts and categories are conceptually the same kind of thing — user-managed tags with sensible defaults. They share the same shape:

| | categories | accounts |
|---|---|---|
| Auto-seeded on signup | 11 defaults | 2 defaults (Cash + Bank) |
| `is_default` flag | Yes | Yes |
| User can edit defaults | Yes | Yes |
| User can soft-delete | Yes | Yes |
| Freemium limit | 5 custom (free) | 10 custom (free) |
| Defaults count toward limit | No | No |
| Usage tag on expenses | `category_id` | `account_id` |

If you understand categories, you understand accounts.

## Schema

```sql
create table accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  icon text not null default 'account_balance_wallet',
  color text not null default '#378ADD',
  currency text not null default 'MYR',
  is_default boolean not null default false,
  is_archived boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `user_id` | uuid | Owner |
| `name` | text | "Maybank Savings", "Cash", "Touch'nGo" |
| `icon` | text | Material icon name |
| `color` | text | Hex color |
| `currency` | text | ISO code (default 'MYR') |
| `is_default` | boolean | True for auto-seeded; false for user-created |
| `is_archived` | boolean | Hide from picker but keep history |
| `sort_order` | integer | Display order |
| `deleted_at` | timestamptz | Soft delete |

## Default seeded accounts

Auto-created via `handle_new_user()` on signup:

| Name | Icon | Color | is_default |
|---|---|---|---|
| Cash | payments | #4CAF50 | true |
| Bank | account_balance | #378ADD | true |

The user can rename, recolor, or delete these. They're sensible starting points and don't count toward the freemium limit.

## Why no balance column

We deliberately don't store `current_balance` because:

1. **Sync bugs are catastrophic.** Updating balances on every expense change is fragile. One missed update = corrupted balance forever.
2. **Different product positioning.** This is an expense tracker, not a personal finance / net-worth app.

Spending totals are computed via the `my_account_spending` RPC. Real balances are derivable from `sum(income) - sum(expense)` if ever needed in V2.

## Why no `account_type` column

Earlier designs included an `account_type` enum ('cash', 'bank', 'credit_card', 'investment', 'wallet', 'loan', 'other'). This was removed because:

- It didn't drive any behavior (just visual hints)
- Users distinguish accounts by name + icon, not by type
- Categories don't have types and that's fine
- Removing it makes accounts truly mirror categories

If V2 wants type-based analytics ("spending by credit card"), the icon string can be used as a soft proxy, or a `type` column can be added back via migration.

## Freemium limits

- **Free tier**: 10 custom accounts (defaults don't count) = 12 total active accounts
- **Premium tier**: unlimited

Enforced in `create_account` RPC (counts only `is_default = false` rows).

## RLS policies

```sql
alter table accounts enable row level security;
create policy acc_select on accounts for select using (user_id = auth.uid());
create policy acc_insert on accounts for insert with check (user_id = auth.uid());
create policy acc_update on accounts for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
```

Per-user isolation only. No sharing.

## Used by

- `expenses.account_id` (nullable, ON DELETE SET NULL)

When an account is soft-deleted, `expenses.account_id` references remain (account_id stays valid even if the row's `deleted_at` is set, since the FK target still exists). Hard delete sets account_id to NULL on expenses.

## Calling the RPC

```dart
await supabase.rpc('create_account', params: {
  'p_name': 'Touch\'nGo eWallet',
  'p_icon': 'account_balance_wallet',
  'p_color': '#0099cc',
  'p_currency': 'MYR',  // optional, defaults to user's home currency
});
// Returns: { account_id, custom_count, tier }
```

If the user is at the limit, the RPC raises with `hint = 'upgrade_required'`.

## Common queries

```dart
// My active accounts (non-archived, non-deleted) — for picker
final accounts = await supabase.from('accounts')
  .select()
  .eq('is_archived', false)
  .is_('deleted_at', null)
  .order('is_default', ascending: false)  // defaults first
  .order('sort_order');

// All accounts including archived (for settings screen)
final allAccounts = await supabase.from('accounts')
  .select()
  .is_('deleted_at', null)
  .order('is_archived')
  .order('sort_order');

// My custom accounts count (for limit UI)
final customCount = await supabase.from('accounts')
  .select('*', const FetchOptions(count: CountOption.exact))
  .eq('is_default', false)
  .is_('deleted_at', null)
  .count();

// Spending per account this month (analytics)
final spending = await supabase.rpc('my_account_spending', params: {
  'p_start_date': '2026-04-01',
  'p_end_date': '2026-04-30',
});
```

## Editing rules

**Defaults can be edited** but their `is_default` stays true (so they don't count toward the limit).

**Defaults can be soft-deleted** but it's user-friendly to warn first ("This is a default account. Delete anyway?").

**Custom accounts** behave like defaults for everything except they count toward the 10-custom limit.

## Archive vs soft delete

| Action | When | Behavior |
|---|---|---|
| **Archive** (`is_archived = true`) | "I closed this Maybank account but want to keep history" | Hidden from picker; data + analytics preserved |
| **Soft delete** (`deleted_at = now()`) | "I never want to see this again" | Hidden everywhere; expenses still linked |

Archive is the typical user action. Hard delete is rare.

## Common mistakes

1. **Don't try to "transfer money" between accounts.** That's a balance-tracking concern. In this app, currency conversions and ATM withdrawals are NOT logged.

2. **Don't assume `account_id` is required on expenses.** It's nullable. Many users will skip it for quick logging.

3. **Don't INSERT directly to accounts table.** Use `create_account` RPC so the freemium limit is enforced.

4. **Don't seed accounts manually for new users.** The trigger does it. Manual seeding causes duplicate-key errors.

5. **Don't hardcode account IDs in Flutter.** They're user-specific UUIDs. Always fetch by user.
