# pending_split_shares

Holds email-based split share slots for users who haven't signed up yet. Part of the **Split V2** feature. See `docs/split_v2.sql` for the full patch.

## Purpose

When Alice splits a bill with bob@email.com before Bob has an account, a row lands here instead of `split_bill_shares`. When Bob signs up, `handle_new_user()` detects rows matching his email, migrates them to real `split_bill_shares` rows, and auto-creates bidirectional contacts between Alice and Bob.

## Schema

```sql
create table pending_split_shares (
  id            uuid primary key default gen_random_uuid(),
  split_bill_id uuid not null references split_bills(id) on delete cascade,
  invited_by    uuid not null references profiles(id)   on delete cascade,

  invitee_email text not null
    check (invitee_email = lower(trim(invitee_email))),
  share_cents   bigint not null check (share_cents >= 0),
  split_method  text not null default 'equal'
    check (split_method in ('equal', 'percentage', 'exact', 'shares')),

  created_at    timestamptz not null default now(),
  claimed_at    timestamptz,
  claimed_by    uuid references profiles(id) on delete set null,

  unique (split_bill_id, invitee_email)
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `split_bill_id` | uuid | The parent split bill |
| `invited_by` | uuid | The onboarded user who created the split (the payer) |
| `invitee_email` | text | Normalised (lowercase, trimmed) email of the invitee |
| `share_cents` | bigint | Their share in the bill's currency |
| `split_method` | text | Mirrors `split_bill_shares.split_method` |
| `created_at` | timestamptz | When the split was created |
| `claimed_at` | timestamptz | When the invitee signed up and the row was claimed. NULL = still pending |
| `claimed_by` | uuid | Profile ID of the invitee after signup |

## Constraints

- `unique (split_bill_id, invitee_email)` — one slot per email per bill
- `invitee_email` is always stored lowercase and trimmed (enforced by check constraint)
- Email shares and user_id shares are in separate tables — a person cannot have both a `split_bill_shares` row and a `pending_split_shares` row for the same bill

## Lifecycle

```
Alice creates split → bob@email.com not in profiles
      │
      ▼
pending_split_shares row created
  split_bill_id = <bill>
  invited_by    = alice_id
  invitee_email = "bob@email.com"
  share_cents   = 4000
  claimed_at    = NULL

      │  Bob signs up with bob@email.com
      ▼
handle_new_user() trigger fires:
  1. Finds pending row (invitee_email = new.email)
  2. INSERT into split_bill_shares (status='pending')
  3. INSERT contacts: alice→bob, bob→alice
  4. UPDATE pending row: claimed_at=now(), claimed_by=bob_id

      │
      ▼
Bob sees pending split in activity feed.
From here, normal split_bill_shares flow applies.
```

## What happens to the pending row after claim

It stays in the table permanently as an audit record (`claimed_at` and `claimed_by` are set). It is never hard-deleted. The real share is now in `split_bill_shares`.

## RLS policies

```sql
-- Only the inviter can see their pending rows
create policy pss_select on pending_split_shares
  for select using (invited_by = auth.uid());

-- Insert via create_split_bill RPC (security definer) — this is a fallback guard
create policy pss_insert on pending_split_shares
  for insert with check (invited_by = auth.uid());

-- Update for claim only (handle_new_user runs security definer, bypasses RLS)
create policy pss_update on pending_split_shares
  for update using (invited_by = auth.uid());
```

Note: the invitee cannot read their own pending rows (they don't have an account yet). After signup, they read from `split_bill_shares` directly.

## Common queries

```dart
// Pending invites Alice sent that haven't been claimed yet
final unclaimed = await supabase
  .from('pending_split_shares')
  .select('*, bill:split_bills(note, expense_date, total_amount_cents)')
  .eq('invited_by', currentUserId)
  .is_('claimed_at', null)
  .order('created_at', ascending: false);

// How many unclaimed email invites on a specific bill
final count = await supabase
  .from('pending_split_shares')
  .select('*', const FetchOptions(count: CountOption.exact))
  .eq('split_bill_id', billId)
  .is_('claimed_at', null)
  .count();
```

## Edge cases

**Invitee signs up with a different email**
The pending row is never claimed. Alice would need to manually add Bob as a contact and recreate the split. No automatic resolution.

**Bill is deleted before Bob signs up**
`on delete cascade` from `split_bills` removes the pending row. When Bob signs up, nothing is claimed (the bill is gone). This is correct behaviour.

**Bob already has an account under that email**
`create_split_bill` RPC checks `profiles` for the email before creating a pending row and raises an error with `hint = 'use_p_shares'`. The caller should retry with the user's `user_id` in `p_shares`.

**Same email invited to the same bill twice**
`unique (split_bill_id, invitee_email)` silently deduplicates via `on conflict do nothing`.

## UI considerations

- Show a "pending" badge (e.g., clock icon) next to email-invited participants in the bill detail view — they're in `pending_split_shares`, not `split_bill_shares`
- When computing total participants count, query both tables and union
- Don't show "Settle" or "Dispute" for pending email participants — those actions require a real `split_bill_shares` row
- Consider showing "Remind" button to re-send invite email (out of scope for V2 schema, but UX is straightforward)

## Common mistakes

1. **Don't query `split_bill_shares` expecting to find email-invited participants.** They're in `pending_split_shares` until they sign up. Merge both when building the participant list for a bill detail screen.

2. **Don't try to INSERT into `pending_split_shares` directly.** Use `create_split_bill` RPC with `p_email_shares` — it validates the email format and checks whether the user is already onboarded.

3. **Don't hard-delete claimed rows.** They're audit records. Filter by `claimed_at is null` for "still pending" views.
