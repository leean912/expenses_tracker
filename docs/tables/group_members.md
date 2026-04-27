# group_members

The membership rows for groups. Each row says "this user is in this group."

## Purpose

Track which contacts are part of each group, so Alice can pre-fill split bill participants by selecting a group.

## Schema

```sql
create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  removed_at timestamptz,
  unique (group_id, user_id)
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `group_id` | uuid | Which group |
| `user_id` | uuid | Which user (the member) |
| `added_at` | timestamptz | When they were added |
| `removed_at` | timestamptz | Soft remove timestamp |

## Constraints

- `unique (group_id, user_id)` — a user can only be in a group once
- Both FKs cascade on delete

## Soft removal model

When a member is removed, `removed_at` is set rather than deleting the row:

```sql
-- Remove
update group_members
  set removed_at = now()
  where group_id = ? and user_id = ?;

-- Re-add (re-activates)
insert into group_members (group_id, user_id) values (?, ?)
  on conflict (group_id, user_id)
  do update set removed_at = null, added_at = now();
```

This preserves history (you can see "Bob was in Roommates from Jan-March 2026") while allowing re-additions.

## RLS policies

```sql
alter table group_members enable row level security;
create policy gm_all on group_members
  for all using (
    group_id in (select id from groups where created_by = auth.uid())
  ) with check (
    group_id in (select id from groups where created_by = auth.uid())
  );
```

Only the group creator can see or modify members. Members themselves don't see this table.

## RPCs

All operations go through RPCs that check creator ownership and contact validation:

```dart
// Add member (must be a contact of creator)
await supabase.rpc('add_group_member', params: {
  'p_group_id': groupId,
  'p_user_id': bobId,
});

// Remove member (creator only)
await supabase.rpc('remove_group_member', params: {
  'p_group_id': groupId,
  'p_user_id': bobId,
});
```

## Common queries

```dart
// Get active members of a group (with their profile info)
final members = await supabase.from('group_members')
  .select('id, added_at, user:profiles(id, username, display_name, avatar_url)')
  .eq('group_id', groupId)
  .is_('removed_at', null)
  .order('added_at');

// Pre-fill participants for a split bill from a group
final memberIds = (await supabase.from('group_members')
  .select('user_id')
  .eq('group_id', groupId)
  .is_('removed_at', null))
  .map((row) => row['user_id'] as String).toList();
```

## Validation

When adding a member:

1. RPC checks: `auth.uid() = groups.created_by` (only creator can add)
2. RPC checks: `p_user_id` is in `contacts` of the creator (must be a contact)
3. RPC checks: `p_user_id != auth.uid()` (can't add yourself)
4. ON CONFLICT clause re-activates a previously removed member

## Common mistakes

1. **Don't directly INSERT to group_members.** Use the RPC so contact validation happens.

2. **Don't show members of someone else's group.** RLS prevents this anyway, but Flutter UI shouldn't try.

3. **Don't think of group_members as social.** Members don't know they're in a group. No notifications, no activity feed.
