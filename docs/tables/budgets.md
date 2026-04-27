# budgets

Spending targets per category (or overall) per period.

## Purpose

Let users set "I want to spend at most RM 500 on Food this month" and see progress bars. Pure UX feature — doesn't enforce or block spending.

## Schema

```sql
create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  category_id uuid references categories(id) on delete cascade,
  limit_cents bigint not null check (limit_cents > 0),
  period text not null default 'monthly'
    check (period in ('weekly', 'monthly', 'yearly')),
  currency text not null default 'MYR',
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
| `category_id` | uuid | Which category this budget targets. NULL = overall budget |
| `limit_cents` | bigint | Spending limit in user's home currency |
| `period` | text | 'weekly', 'monthly', or 'yearly' |
| `currency` | text | Should match user's home currency |
| `deleted_at` | timestamptz | Soft delete |

## Period meanings

- `weekly`: Resets every Monday (or whichever start of week the UI defines)
- `monthly`: Resets on the 1st of each month
- `yearly`: Resets on January 1st

The DB doesn't enforce period boundaries — Flutter computes "spent this period" by summing expenses within the appropriate date range.

## NULL category_id = overall budget

A budget with `category_id IS NULL` represents an overall spending cap:

```
Budget A: category_id = null, limit = RM 2000, period = 'monthly'
  → "I want to spend at most RM 2000 total per month"

Budget B: category_id = food_id, limit = RM 500, period = 'monthly'
  → "I want to spend at most RM 500 on Food per month"
```

A user can have both at the same time. Flutter renders progress bars for each.

## Computing progress

```dart
// Monthly food budget progress
final budget = await supabase.from('budgets').select().eq('id', budgetId).single();

final spent = await supabase.from('expenses')
  .select('home_amount_cents.sum()')
  .eq('user_id', currentUserId)
  .eq('type', 'expense')
  .eq('category_id', budget['category_id'])
  .gte('expense_date', monthStart)
  .lte('expense_date', monthEnd)
  .is_('deleted_at', null)
  .single();

final pct = (spent['sum'] / budget['limit_cents']).clamp(0.0, 1.5);
```

## Visual states

UI typically shows:

- **0-79%**: green progress bar, "On track"
- **80-99%**: yellow, "Approaching limit"
- **100-119%**: orange, "Over budget"
- **120%+**: red, "Significantly over"

Optionally trigger an in-app banner at 80% and 100%, but **don't push notify** for MVP.

## RLS policies

```sql
alter table budgets enable row level security;
create policy bud_select on budgets for select using (user_id = auth.uid());
create policy bud_insert on budgets for insert with check (user_id = auth.uid());
create policy bud_update on budgets for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
```

Per-user isolation.

## Common queries

```dart
// All my active budgets
final budgets = await supabase.from('budgets')
  .select('*, category:categories(name, icon, color)')
  .is_('deleted_at', null)
  .order('created_at');

// Just monthly budgets
final monthly = await supabase.from('budgets')
  .select()
  .eq('period', 'monthly')
  .is_('deleted_at', null);

// Overall budget (no category)
final overall = await supabase.from('budgets')
  .select()
  .is_('category_id', null)
  .is_('deleted_at', null)
  .maybeSingle();
```

## Common mistakes

1. **Don't enforce budgets at the DB level.** They're informational, not constraints. Users can always exceed.

2. **Don't store "amount spent" on the budget row.** Always compute from expenses. Otherwise it'll get out of sync.

3. **Don't allow currency mismatch.** Budget should be in user's home currency. If user changes home currency, archive old budgets.

4. **Don't auto-create budgets.** Let users set them up explicitly. Defaults feel restrictive.
