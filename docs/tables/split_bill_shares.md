# split_bill_shares

Per-participant shares of a split bill. One row per person per bill. Tracks status (pending/settled/disputed).

## Purpose

When Alice creates a bill split with Bob and Charlie, three share rows are created (Alice's, Bob's, Charlie's). Alice's share is auto-marked settled (she paid). Others start pending.

## Schema

```sql
create table split_bill_shares (
  id uuid primary key default gen_random_uuid(),
  split_bill_id uuid not null references split_bills(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  settlement_id uuid,  -- FK added later (settlements table comes after)

  share_cents bigint not null check (share_cents >= 0),
  split_method text not null default 'equal' check (split_method in ('equal', 'custom')),

  status text not null default 'pending'
    check (status in ('pending', 'settled', 'disputed', 'archived')),
  dispute_reason text,
  acknowledged_at timestamptz,
  settled_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Archive support (used when home currency changes)
  archived_at timestamptz,
  archived_reason text,

  unique (split_bill_id, user_id)
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `split_bill_id` | uuid | Which bill |
| `user_id` | uuid | Whose share this is |
| `settlement_id` | uuid | NULL until settled. Set by `settle_split_share` |
| `share_cents` | bigint | This person's amount (in bill's currency) |
| `split_method` | text | 'equal' (default) or 'custom' (V2) |
| `status` | text | Lifecycle state — see below |
| `dispute_reason` | text | Free text reason if disputed |
| `acknowledged_at` | timestamptz | When user acknowledged the share (V2 feature) |
| `settled_at` | timestamptz | When marked settled |

## Constraints

- `unique (split_bill_id, user_id)` — one share per person per bill
- `share_cents >= 0` — could be zero (rare edge case)
- All FKs cascade

## Status lifecycle

```
        ┌─────────────┐
        │   pending   │  ← initial state for non-payer participants
        └──────┬──────┘
               │ settle_split_share RPC
               ▼
        ┌─────────────┐
        │   settled   │  ← created settlement + expense rows
        └─────────────┘
               │ unsettle_split_share RPC (optional)
               ▼
        ┌─────────────┐
        │   pending   │
        └─────────────┘

OR:
        ┌─────────────┐
        │   pending   │
        └──────┬──────┘
               │ dispute_split_share RPC
               ▼
        ┌─────────────┐
        │  disputed   │  ← user contests the amount
        └──────┬──────┘
               │ resolution can be: re-settle, or bill creator updates
               ▼
        ┌─────────────┐
        │   settled   │ or back to pending
        └─────────────┘
```

For the bill creator's own share: auto-set to `'settled'` immediately (they paid the merchant directly).

## The 'archived' status

Used during currency changes. When a user changes their home currency, all unsettled shares are archived (`status = 'archived'`, `archived_at = now()`). They effectively become read-only history.

## Cents-precision rounding

When splitting equally, you may have rounding leftover:

```
Alice paid RM 100, splitting equally with Bob and Charlie:
  100 / 3 = 33.33...
  
Strategy: 33.33, 33.33, 33.34 (one share gets the extra cent)
```

Flutter handles this — pass exact `share_cents` values. The DB doesn't auto-balance.

For uneven splits: pass arbitrary values. The DB doesn't validate that `sum(shares) = total_amount_cents`. The UI should warn if there's a mismatch.

## RLS policies

```sql
alter table split_bill_shares enable row level security;

create policy sbs_select on split_bill_shares for select using (
  user_id = auth.uid()
  or split_bill_id in (
    select id from split_bills where created_by = auth.uid() or paid_by = auth.uid()
  )
);

create policy sbs_update on split_bill_shares for update using (
  user_id = auth.uid()  -- own share
  or split_bill_id in (select id from split_bills where created_by = auth.uid())  -- creator
);
```

Each user sees their own shares + all shares on bills they created. They can update their own (settle/dispute), or the creator can update any (e.g., adjust amounts pre-settlement).

## RPCs

| RPC | Purpose |
|---|---|
| `settle_split_share(p_share_id, p_category_id, p_account_id)` | Mark settled, create expense + income rows |
| `unsettle_split_share(p_share_id)` | Reverse a settlement |
| `dispute_split_share(p_share_id, p_reason)` | Mark disputed with reason |

All handle the multi-row transaction (settlement + expense + income + status update) atomically.

## Common queries

```dart
// My pending shares (I owe people)
final pending = await supabase.from('split_bill_shares')
  .select('*, bill:split_bills(*, payer:profiles!paid_by(id, username, display_name))')
  .eq('user_id', currentUserId)
  .eq('status', 'pending')
  .order('created_at', ascending: false);

// Shares of a specific bill (for detail view)
final shares = await supabase.from('split_bill_shares')
  .select('*, user:profiles(id, username, display_name, avatar_url)')
  .eq('split_bill_id', billId)
  .order('user_id');

// Counts for badges
final pendingCount = await supabase.from('split_bill_shares')
  .select('*', const FetchOptions(count: CountOption.exact))
  .eq('user_id', currentUserId)
  .eq('status', 'pending')
  .count();
```

## Common mistakes

1. **Don't INSERT shares directly.** Use `create_split_bill` RPC — it inserts the bill + all shares + payer's auto-expense atomically.

2. **Don't UPDATE status manually.** Use `settle_split_share` so settlement rows are created. Manual UPDATEs leave dangling state.

3. **Don't expect `share_cents` to always equal `total_amount_cents / num_participants`.** That's the equal-split case. Custom splits will have arbitrary values.

4. **Don't forget the unique constraint.** Trying to insert the same user twice on a bill will fail. Each user is one share.
