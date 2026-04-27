# settlements

Immutable history of payback events. Each row records "X paid Y for share Z."

## Purpose

Audit trail of all settlement events. Even if a share is later "unsettled," the original settlement row is preserved (soft-deleted via `deleted_at`).

## Schema

```sql
create table settlements (
  id uuid primary key default gen_random_uuid(),
  split_bill_id uuid not null references split_bills(id) on delete cascade,
  split_bill_share_id uuid not null references split_bill_shares(id) on delete cascade,

  from_user_id uuid not null references profiles(id) on delete cascade,  -- the settler
  to_user_id uuid not null references profiles(id) on delete cascade,    -- the bill payer

  amount_cents bigint not null check (amount_cents > 0),
  currency text not null,

  note text,
  settled_on date not null default current_date,

  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `split_bill_id` | uuid | Which bill |
| `split_bill_share_id` | uuid | Which share was settled |
| `from_user_id` | uuid | Who paid (settler — Bob) |
| `to_user_id` | uuid | Who received (payer — Alice) |
| `amount_cents` | bigint | The amount paid (= share's `share_cents`) |
| `currency` | text | Bill's currency |
| `note` | text | Optional ("Paid via Touch'nGo") |
| `settled_on` | date | When settlement happened |

## Constraints

- All FKs cascade
- `amount_cents > 0` — settlements can't be zero or negative

## Settlements vs share status

`split_bill_shares.status = 'settled'` and a corresponding `settlements` row both exist when settled:

```
Before settling:
  share: status='pending', settlement_id=null
  no settlement row

After settling:
  share: status='settled', settlement_id=<UUID>, settled_at=<timestamp>
  settlement row exists with that UUID
```

When unsettled (rare):
```
share: status='pending', settlement_id=null, settled_at=null
settlement row: deleted_at=<timestamp>  (soft-deleted, kept for audit)
```

This dual-tracking lets:
- Quick lookups via `share.status` for filtering UI
- Full historical audit via `settlements` table

## Side effects of settle_split_share

When a share is settled, FOUR things happen atomically:

1. INSERT `settlements` row (this table)
2. INSERT `expenses` row for settler (Bob's expense)
3. INSERT `expenses` row for payer (Alice's income)
4. UPDATE `split_bill_shares` (status, settled_at, settlement_id)

If any step fails, the whole transaction rolls back. No partial states.

## RLS policies

```sql
alter table settlements enable row level security;

create policy set_select on settlements for select using (
  from_user_id = auth.uid()
  or to_user_id = auth.uid()
);

create policy set_update on settlements for update using (
  from_user_id = auth.uid() or to_user_id = auth.uid()
);

-- No INSERT policy — only created by settle_split_share RPC (security definer)
-- No DELETE policy — soft-delete only
```

Both parties (settler and payer) can see + soft-delete (via UPDATE setting `deleted_at`).

## Common queries

```dart
// All my settlement history (paid + received)
final history = await supabase.from('settlements')
  .select('*, bill:split_bills(*), from_user:profiles!from_user_id(*), to_user:profiles!to_user_id(*)')
  .or('from_user_id.eq.$currentUserId,to_user_id.eq.$currentUserId')
  .is_('deleted_at', null)
  .order('settled_on', ascending: false);

// Settlements I received (people paid me back)
final received = await supabase.from('settlements')
  .select('*, from_user:profiles!from_user_id(username, display_name)')
  .eq('to_user_id', currentUserId)
  .is_('deleted_at', null);

// Total received this month
final receivedThisMonth = await supabase.from('settlements')
  .select('amount_cents.sum()')
  .eq('to_user_id', currentUserId)
  .gte('settled_on', '2026-04-01')
  .lte('settled_on', '2026-04-30')
  .is_('deleted_at', null)
  .single();
```

## Why settlements + expenses both?

You might wonder: "If settle_split_share creates expense + income rows, why do we ALSO need a settlements table?"

Reasons:
1. **Audit trail**: Settlements are the source of truth for "who paid whom when." Expenses are derivative.
2. **Unique relationship**: The settlement directly links payer ↔ settler with explicit FK to the share.
3. **Display logic**: Activity feed wants "Bob paid you RM 30," which comes from settlements.from/to, not from expenses (where it's a row in two separate users' books).
4. **Future flexibility**: V2 might add settlement methods, partial payments, etc. — settlements is the natural place.

The expense rows are "downstream" — they exist for analytics. Settlements are upstream truth.

## Common mistakes

1. **Don't insert settlements directly.** Always go through `settle_split_share` RPC — otherwise expense rows won't be created.

2. **Don't expect to "modify" a settlement.** They're effectively immutable. To "fix" one, soft-delete and re-settle.

3. **Don't double-count in analytics.** A settlement creates one income row for Alice and one expense row for Bob. Summing all expenses across users would double-count from the settlement's perspective.

4. **Don't show settlements UI as "pending."** If a settlement row exists, the share IS settled. Pending state lives in `split_bill_shares.status`, not here.
