# expenses

The heart of the app. Every personal expense + income row lives here. Auto-populated by split bill settlements and collab imports.

## Purpose

Track all personal financial events: manual purchases, settlement-related expenses, collab imports, etc. This table powers all spending analytics.

## Schema

```sql
create table expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,

  -- Classification
  type text not null default 'expense' check (type in ('expense', 'income')),
  source text not null default 'manual'
    check (source in ('manual', 'settlement', 'split_payer')),
  source_split_bill_id uuid,
  source_settlement_id uuid,

  category_id uuid references categories(id) on delete set null,
  collab_id uuid references collabs(id) on delete set null,
  account_id uuid references accounts(id) on delete set null,

  -- Amount — always positive; type column determines +/- in UI
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null,

  -- Home currency conversion, frozen at time of entry
  home_amount_cents bigint,
  home_currency text,
  conversion_rate numeric(20, 10),  -- 1 home_currency = X this.currency

  note text,
  expense_date date not null default current_date,

  google_place_id text,
  place_name text,
  latitude double precision,
  longitude double precision,
  receipt_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  -- Archive support (used when home currency changes)
  archived_at timestamptz,
  archived_reason text
);
```

## Columns by purpose

### Identity
- `id`, `user_id`

### Classification
- `type` — 'expense' (money out) or 'income' (money in)
- `source` — where this row came from (manual entry vs auto-created)

### Source links (auditability)
- `source_split_bill_id` — set when this row was auto-created from a split bill
- `source_settlement_id` — set for settlement-related expenses/incomes

### Tags
- `category_id` — what was bought
- `collab_id` — optional collab context
- `account_id` — how it was paid

### Amount
- `amount_cents` — always positive, in the row's currency
- `currency` — ISO code (e.g., 'MYR', 'JPY')

### Home conversion (snapshot)
- `home_amount_cents` — equivalent in user's home currency
- `home_currency` — user's home currency at entry time
- `conversion_rate` — the rate used (1 home = X this.currency)

### Location
- `google_place_id`, `place_name`, `latitude`, `longitude` — optional venue info

### Soft delete + archive
- `deleted_at` — soft delete
- `archived_at`, `archived_reason` — archive (used when user changes home currency)

## The `source` column

This tracks where each row came from:

| Source | Meaning | Created by |
|---|---|---|
| `manual` | User typed it in | Direct INSERT from Flutter |
| `split_payer` | Auto-expense for the bill creator (full amount) | `create_split_bill` RPC |
| `settlement` | Auto-expense (settler) or auto-income (payer) | `settle_split_share` RPC |

For analytics, you can filter:
- "My actual spending" = `where source = 'manual'`
- "My out-of-pocket spending" = `where type = 'expense'`
- "My net spending" = sum(expense) - sum(income), regardless of source

## Type: 'expense' vs 'income'

The `type` field distinguishes:

- `'expense'`: money out (taxi, food, rent, settlement payment to friend)
- `'income'`: money in (salary, refund, friend paying you back)

Both are POSITIVE in `amount_cents`. The UI applies the sign for display.

Examples of income rows:
- Receipt from settlement: friend paid you back → income
- Manual income entry: salary, freelance payment, refund

## Source links explained

When auto-created by RPCs, the source column AND a source_*_id column are both set:

```
Bob settles his RM 30 share to Alice for "Lunch":

Bob's expense row:
  type = 'expense'
  source = 'settlement'
  source_split_bill_id = <lunch bill UUID>
  source_settlement_id = <settlement UUID>
  amount_cents = 3000
  category_id = <Bob's "Food" category>
  account_id = <Bob's "Touch'nGo" account>
  
Alice's income row:
  type = 'income'
  source = 'settlement'
  source_split_bill_id = <lunch bill UUID>
  source_settlement_id = <settlement UUID>  
  amount_cents = 3000
  category_id = <Alice's "Food" category>  (the bill's category, which is hers)
  account_id = NULL
```

The source_* columns are NOT enforced as FKs at table-creation time (because the target tables come later in the schema). They're added as ALTER TABLE constraints after all tables exist.

## Indexes

The most important indexes:

```sql
-- For "show my recent expenses" (most common query)
create index idx_expenses_user_date
  on expenses(user_id, expense_date desc)
  where deleted_at is null and archived_at is null;

-- For account analytics
create index idx_expenses_account
  on expenses(account_id, expense_date desc)
  where account_id is not null and deleted_at is null and archived_at is null;

-- For category analytics
create index idx_expenses_category
  on expenses(category_id, expense_date desc)
  where category_id is not null and deleted_at is null and archived_at is null;

-- For "where did this row come from" lookups
create index idx_expenses_source_split on expenses(source_split_bill_id)
  where source_split_bill_id is not null;
```

All include `where deleted_at is null` for efficiency.

## RLS policies

```sql
alter table expenses enable row level security;

-- Own expenses + any expense tagged to a collab you're an active member of
create policy exp_select on expenses for select using (
  user_id = auth.uid()
  or (
    collab_id is not null
    and collab_id in (
      select collab_id from collab_members
      where user_id = auth.uid() and left_at is null
    )
  )
);

-- Write operations are always owner-only
create policy exp_insert on expenses for insert with check (user_id = auth.uid());
create policy exp_update on expenses for update using (user_id = auth.uid());
create policy exp_delete on expenses for delete using (user_id = auth.uid());
```

You can read your own expenses plus expenses from anyone in a shared collab. You can only write your own.

## Common queries

```dart
// Recent expenses (timeline)
final expenses = await supabase.from('expenses')
  .select('*, category:categories(name, icon, color), account:accounts(name, icon)')
  .eq('type', 'expense')
  .is_('deleted_at', null)
  .is_('archived_at', null)
  .order('expense_date', ascending: false)
  .limit(50);

// Spending by category this month
final byCategory = await supabase.from('expenses')
  .select('category_id, home_amount_cents.sum()')
  .eq('type', 'expense')
  .gte('expense_date', '2026-04-01')
  .lte('expense_date', '2026-04-30')
  .is_('deleted_at', null);

// Manual entries only (excludes auto-generated)
final manualOnly = await supabase.from('expenses')
  .select()
  .eq('source', 'manual')
  .is_('deleted_at', null);

// Collab-related expenses
final collabImports = await supabase.from('expenses')
  .select()
  .eq('collab_id', collabId)
  .is_('deleted_at', null);
```

## Logging an expense from Flutter

```dart
final response = await supabase.from('expenses').insert({
  'user_id': currentUserId,
  'type': 'expense',
  'source': 'manual',
  'amount_cents': 5000,  // RM 50
  'currency': 'MYR',
  'home_amount_cents': 5000,
  'home_currency': 'MYR',
  'conversion_rate': null,  // same currency
  'category_id': foodCategoryId,
  'account_id': maybankAccountId,
  'note': 'Lunch at Sushi King',
  'expense_date': '2026-04-25',
});
```

For foreign currency:

```dart
final response = await supabase.from('expenses').insert({
  'user_id': currentUserId,
  'type': 'expense',
  'source': 'manual',
  'amount_cents': 300000,  // ¥3000
  'currency': 'JPY',
  'home_amount_cents': 10000,  // RM 100
  'home_currency': 'MYR',
  'conversion_rate': 30.0,
  'category_id': travelCategoryId,
  'note': 'Taxi from airport',
  'expense_date': '2026-04-25',
});
```

## Common mistakes

1. **Don't store negative `amount_cents`.** Always positive. Use `type` for direction.

2. **Don't forget `home_amount_cents` for foreign expenses.** Without it, analytics queries summing home amount will skip the row.

3. **Don't directly INSERT settlement-related expenses.** Use `settle_split_share` RPC so source links and bill state are correct.

4. **Don't rely on `category_id IS NOT NULL`.** Users can delete categories; the FK becomes NULL but the expense remains.

5. **Don't forget that collab expenses are visible to all collab members.** The RLS `exp_select` policy exposes any expense with a `collab_id` to all active members of that collab. Only tag `collab_id` on expenses that should be shared.
