# split_bills

A shared bill record. The "header" of a split — pointed to by `split_bill_shares` (one per participant).

## Purpose

When Alice paid for a meal and wants to split with Bob and Charlie, the bill goes here. Records who paid, total amount, and links to the shares.

## Schema

```sql
create table split_bills (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references profiles(id) on delete cascade,
  paid_by uuid not null references profiles(id) on delete cascade,

  total_amount_cents bigint not null check (total_amount_cents > 0),
  currency text not null default 'MYR',

  -- Home currency conversion snapshot (from creator's perspective, frozen at creation)
  home_amount_cents bigint,
  home_currency text,
  conversion_rate numeric(20, 10),

  note text,
  expense_date date not null default current_date,

  category_id uuid references categories(id) on delete set null,
  collab_id uuid references collabs(id) on delete set null,
  group_id uuid references groups(id) on delete set null,

  google_place_id text,
  place_name text,
  latitude double precision,
  longitude double precision,
  receipt_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `created_by` | uuid | Who set up the split (in MVP, must equal paid_by) |
| `paid_by` | uuid | Who actually paid the merchant |
| `total_amount_cents` | bigint | Full bill amount |
| `currency` | text | Bill's currency (e.g., 'JPY' for Japan) |
| `home_amount_cents` | bigint | Bill total in creator's home currency |
| `home_currency` | text | Creator's home currency |
| `conversion_rate` | numeric | 1 home_currency = X bill_currency (frozen at creation) |
| `note` | text | "Dinner at Sushi King" |
| `expense_date` | date | Day of the spend |
| `category_id` | uuid | Creator's category (per-user) |
| `collab_id` | uuid | Optional: link to a collab |
| `group_id` | uuid | Optional: link to a group (just a tag for filtering) |

## MVP restriction: creator = payer

In MVP, `created_by` MUST equal `paid_by`. This is enforced in `create_split_bill` RPC:

```sql
if p_paid_by <> v_user_id then
  raise exception 'MVP: only the payer can create a split bill. Have the actual payer create it.';
end if;
```

**Why?** The auto-created `expenses` row uses the creator's category. If the creator weren't the payer, the bill creator's category would land on someone else's expense — cross-user pollution.

V2 may lift this with a separate categorization flow.

## Conversion snapshot

For foreign-currency bills, the conversion is stored on the bill:

```
Alice (Malaysian) creates "Dinner ¥12,000" in Japan with rate 30:
  total_amount_cents = 1200000
  currency = 'JPY'
  home_amount_cents = 40000  (RM 400)
  home_currency = 'MYR'
  conversion_rate = 30
```

When Bob views the bill in his app, he sees:
```
"Dinner ¥12,000 (≈ RM 400)"
"Your share: ¥4,000 (≈ RM 133.33)"
```

Bob uses Alice's rate (no separate conversion). This is the MVP simplification: cross-currency settlement isn't optimized for MVP.

When Bob settles, his auto-expense row reads the bill's rate and computes his share's home amount: `4000 / 30 = 133.33`. Bob's own analytics show RM 133.33.

## Auto-created payer expense

When `create_split_bill` runs, it inserts a row into `expenses` for the payer:

```
Alice's expense (auto-created):
  user_id = alice_id
  type = 'expense'
  source = 'split_payer'
  source_split_bill_id = <bill UUID>
  amount_cents = 1200000  (¥12000, the FULL amount)
  currency = 'JPY'
  home_amount_cents = 40000  (RM 400)
  home_currency = 'MYR'
  conversion_rate = 30
  category_id = <Alice's Food category>
  collab_id = <Japan collab>
  note = 'Dinner at Sushi King'
```

This way, Alice's personal analytics immediately reflect the spend. As Bob and others settle, INCOME rows get added to Alice's books to balance.

## RLS policies

```sql
alter table split_bills enable row level security;

create policy sb_select on split_bills for select using (
  created_by = auth.uid()
  or paid_by = auth.uid()
  or id in (
    select split_bill_id from split_bill_shares
    where user_id = auth.uid()
  )
);

create policy sb_insert on split_bills for insert with check (
  created_by = auth.uid()
);

create policy sb_update on split_bills for update using (
  created_by = auth.uid()
);

-- No DELETE policy — soft-delete via UPDATE
```

Anyone involved in the bill (creator, payer, or share holder) can SEE it. Only the creator can modify it.

## Common queries

```dart
// Bills I created
final myBills = await supabase.from('split_bills')
  .select('*, shares:split_bill_shares(*, user:profiles(id, username, display_name))')
  .eq('created_by', currentUserId)
  .is_('deleted_at', null)
  .order('expense_date', ascending: false);

// Bills involving me (created or share)
final involvedBills = await supabase.from('split_bills')
  .select('*')
  .or('created_by.eq.$currentUserId,id.in.(select split_bill_id from split_bill_shares where user_id = $currentUserId)')
  .is_('deleted_at', null);

// Bills filtered by group
final groupBills = await supabase.from('split_bills')
  .select()
  .eq('group_id', groupId)
  .is_('deleted_at', null);

// Bills for a specific collab
final collabBills = await supabase.from('split_bills')
  .select()
  .eq('collab_id', collabId)
  .is_('deleted_at', null);
```

## Editing bills

Once a bill has at least one settled share, editing should be RESTRICTED. Reasoning:

- Bob already paid based on the original amount
- Changing total_amount_cents retroactively would invalidate his settlement

Flutter UX: Show "Cannot edit — Bob has settled" when any share is settled. Allow note edits but not amount.

The DB doesn't enforce this — just the UI. Power users with SQL access could still edit, but that's their problem.

## Deletion rules

- Soft-delete only (set `deleted_at`)
- Allowed if all shares are still pending
- Blocked if any share is settled (UI-level rule)

## Common mistakes

1. **Don't insert split_bills directly.** Use `create_split_bill` RPC so shares + payer expense are created atomically.

2. **Don't change `category_id` after creation.** It's a snapshot of the creator's choice at creation time. Changing it doesn't propagate to existing settler/payer rows.

3. **Don't expect `paid_by` to be different from `created_by`.** MVP enforces equality.
