# collabs

A shared expense workspace. Multiple users can log expenses together; at close, each member imports to their personal books.

## Purpose

Solve the "we shared expenses together, who paid for what?" problem — whether it's a travel trip, a group dinner, a shared project, or any other collaborative spending scenario. Collab expenses are stored separately during the collab and only flow into personal expense books when each member explicitly imports.

## Schema

```sql
create table collabs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  description text,
  cover_photo_url text,
  start_date date,
  end_date date,
  currency text not null default 'MYR',
  home_currency text not null default 'MYR',
  exchange_rate numeric(20, 10),
  budget_cents bigint,
  status text not null default 'active'
    check (status in ('active', 'closed')),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (end_date is null or start_date is null or end_date >= start_date),
  check (
    (currency = home_currency and exchange_rate is null)
    or (currency <> home_currency and exchange_rate is not null and exchange_rate > 0)
  )
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `owner_id` | uuid | Who created the collab |
| `name` | text | "Japan 2026", "Team Lunch April", "Chalet Weekend" |
| `description` | text | Optional |
| `cover_photo_url` | text | NULL in MVP (V2 feature) |
| `start_date` / `end_date` | date | Both nullable. If both set, end >= start |
| `currency` | text | Collab's primary currency (e.g., 'JPY' for a Japan trip; defaults to home currency) |
| `home_currency` | text | Owner's home currency at creation (frozen for historical accuracy) |
| `exchange_rate` | numeric | 1 home_currency = X collab_currency. NULL if same currency |
| `budget_cents` | bigint | Optional shared total budget in home_currency. NULL = no budget set |
| `status` | text | 'active' or 'closed' |
| `closed_at` | timestamptz | When closed |

## Lifecycle

```
        ┌─────────────┐
        │   active    │  ← created here, members log expenses freely
        └──────┬──────┘
               │ close_collab RPC (owner only)
               ▼
        ┌─────────────┐
        │   closed    │  ← read-only, no new expenses
        └─────────────┘
```

While **active**:
- Members can add/edit/delete their own expenses tagged with this `collab_id`
- Members can be added by owner
- Members can leave

When **closed**:
- No new expenses can be tagged to this collab
- Existing expenses remain in members' personal books (they were never separate)
- Owner can re-open by reverting status (manual SQL, not exposed in UI)

## Budget

`budget_cents` is the **shared total budget** for the collab in `home_currency`. It's optional — NULL means no budget is set.

UI shows remaining budget as: `budget_cents - SUM(expenses.home_amount_cents WHERE collab_id = this.id AND deleted_at IS NULL)`.

This is computed client-side or via a query; there is no server-side budget enforcement. The budget is informational only — members are not blocked from logging expenses that exceed it.

## Currency model

Collabs can be in foreign currency (e.g., JPY for a Japan trip). The owner's home currency and a conversion rate are stored on the collab:

```
Example: Alice (Malaysian) goes to Japan
  collabs:
    currency       = 'JPY'
    home_currency  = 'MYR'
    exchange_rate  = 30   (meaning: 1 MYR = 30 JPY)
```

The convention is **1 home_currency = X collab_currency**. So `exchange_rate = 30` means RM 1 buys ¥30. To convert ¥3000 to MYR: `3000 / 30 = 100`.

For same-currency collabs (domestic trips, group dinners), set `currency = home_currency` and leave `exchange_rate` as NULL.

## Auto-add owner as member

When a collab is created, the `handle_new_collab()` trigger fires and inserts a row in `collab_members` with `role = 'owner'`. The owner doesn't need to be added manually.

## RLS policies

```sql
alter table collabs enable row level security;

create policy collabs_select on collabs for select using (
  owner_id = auth.uid()
  or id in (
    select collab_id from collab_members
    where user_id = auth.uid() and left_at is null
  )
);

create policy collabs_insert on collabs for insert with check (owner_id = auth.uid());
create policy collabs_update on collabs for update using (owner_id = auth.uid());
create policy collabs_delete on collabs for delete using (owner_id = auth.uid());
```

Only the owner can modify the collab. Active members can read it.

## RPCs

| RPC | Purpose |
|---|---|
| `add_collab_member(p_collab_id, p_user_id)` | Owner adds a contact to the collab |
| `leave_collab(p_collab_id)` | Member self-removes (owner can't leave — must delete collab) |
| `close_collab(p_collab_id)` | Mark collab closed (read-only). Warns about unsettled splits but doesn't block |

## Common queries

```dart
// My collabs (active and closed)
final collabs = await supabase.from('collabs')
  .select('*, member_count:collab_members(count)')
  .is_('deleted_at', null)
  .order('created_at', ascending: false);

// Collab detail with members
final collab = await supabase.from('collabs')
  .select('*, members:collab_members(user:profiles(id, username, display_name))')
  .eq('id', collabId)
  .single();

// Budget remaining (sum from expenses table)
final summary = await supabase.from('expenses')
  .select('home_amount_cents.sum()')
  .eq('collab_id', collabId)
  .is_('deleted_at', null)
  .single();
// remaining = collab.budget_cents - summary['sum']
```

## Common mistakes

1. **Don't try to add non-contacts to a collab.** `add_collab_member` validates the user is in your contacts.

2. **Don't expect closing a collab to settle outstanding splits.** Closure just marks the collab read-only. Splits can be settled before or after.

3. **Don't change `home_currency` or `currency` after creation.** They're snapshots. If the user is moving across currencies, create a new collab.

4. **Don't enforce budget at the DB layer.** The budget is informational. Show a warning in the UI when spending approaches or exceeds it, but don't block inserts.
