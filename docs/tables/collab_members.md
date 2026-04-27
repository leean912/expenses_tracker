# collab_members

Membership rows for collabs. Tracks who's in the collab, their role, and their optional personal spending budget.

## Purpose

Manage collab participation. Each row represents one user's involvement in one collab.

## Schema

```sql
create table collab_members (
  id uuid primary key default gen_random_uuid(),
  collab_id uuid not null references collabs(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  personal_budget_cents bigint,
  unique (collab_id, user_id)
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `collab_id` | uuid | Which collab |
| `user_id` | uuid | Which user |
| `role` | text | `'owner'` (creator) or `'member'` (regular participant) |
| `joined_at` | timestamptz | When added |
| `left_at` | timestamptz | Soft-leave timestamp |
| `personal_budget_cents` | bigint | Optional personal spending cap in collab's `home_currency`. NULL = no personal budget set |

## Personal budget

`personal_budget_cents` is each member's optional individual spending cap, stored in the collab's `home_currency` (same unit as `collabs.budget_cents`).

Remaining personal budget:
```
personal_budget_cents - SUM(expenses.home_amount_cents
  WHERE collab_id = this.collab_id
  AND user_id = this.user_id
  AND deleted_at IS NULL)
```

Two budget levels coexist:
- **Shared** (`collabs.budget_cents`) — total cap for the whole collab
- **Personal** (`collab_members.personal_budget_cents`) — each member's individual cap

Both are informational only. No DB enforcement — show a warning in UI when spending approaches or exceeds the cap.

Members set their own `personal_budget_cents` via a direct UPDATE on their own row (RLS `cm_update` allows `user_id = auth.uid()`).

## Constraints

- `unique (collab_id, user_id)` — a user can only be in a collab once
- Both FKs cascade
- `role` enum (owner/member)

## Auto-creation: owner as member

When a collab is created, the `handle_new_collab()` trigger fires:

```sql
create or replace function handle_new_collab()
returns trigger language plpgsql security definer as $$
begin
  insert into collab_members (collab_id, user_id, role, joined_at)
  values (new.id, new.owner_id, 'owner', now());
  return new;
end;
$$;
```

So `collab_members` always has at least one row per collab (the owner).

## RLS policies

```sql
alter table collab_members enable row level security;

create policy cm_select on collab_members for select using (
  user_id = auth.uid()
  or collab_id in (select id from collabs where owner_id = auth.uid())
  or collab_id in (
    select collab_id from collab_members
    where user_id = auth.uid() and left_at is null
  )
);

create policy cm_insert on collab_members for insert with check (
  collab_id in (select id from collabs where owner_id = auth.uid())
);

create policy cm_update on collab_members for update using (
  user_id = auth.uid()  -- members can update their own row (e.g., leave, import)
  or collab_id in (select id from collabs where owner_id = auth.uid())  -- owner can manage
);
```

- Members and owner can SELECT
- Only owner can INSERT (via `add_collab_member` RPC)
- Members can UPDATE their own row (leave, import)
- Owner can UPDATE any row (manage members)

## RPCs

| RPC | Purpose |
|---|---|
| `add_collab_member(p_collab_id, p_user_id)` | Owner adds a contact to the collab |
| `leave_collab(p_collab_id)` | Set `left_at = now()` for current user |

## Common queries

```dart
// Members of a specific collab (active only)
final members = await supabase.from('collab_members')
  .select('*, user:profiles(id, username, display_name, avatar_url)')
  .eq('collab_id', collabId)
  .is_('left_at', null)
  .order('role')
  .order('joined_at');

// Am I still an active member?
final myMembership = await supabase.from('collab_members')
  .select('role, joined_at')
  .eq('collab_id', collabId)
  .eq('user_id', currentUserId)
  .is_('left_at', null)
  .maybeSingle();
final isMember = myMembership != null;
```

## Common mistakes

1. **Don't let the owner leave their own collab.** `leave_collab` RPC blocks owners — they must delete the collab instead.

2. **Don't validate role too strictly in RLS.** The owner is just a special collab_member with `role='owner'`. Most logic doesn't need to distinguish.
