# groups

Personal shortcut lists for split bill participants. Only visible to the creator. Group members don't know they're in someone's group.

**Important**: Groups are NOT shared workspaces. They're private bookmarks for "the people I usually split with."

## Purpose

When Alice creates the same kind of split bill repeatedly (e.g., monthly rent with roommates Bob + Charlie), manually picking participants every time is tedious. Groups let her save "Roommates" once and reuse it.

## Schema

```sql
create table groups (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references profiles(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  icon text not null default 'group',
  color text not null default '#378ADD',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `created_by` | uuid | The user who owns this group (only person who can see/edit it) |
| `name` | text | Display name (e.g., "Roommates", "Office Lunch") |
| `icon` | text | Material icon name |
| `color` | text | Hex color |
| `deleted_at` | timestamptz | Soft delete |

## The "creator-only" model

Unlike WhatsApp groups (where members see each other), these groups are **private to the creator**:

- Bob doesn't know Alice has a group called "Roommates" with him in it
- Bob can't see who else is in Alice's "Roommates"
- Bob can have his OWN "Roommates" group with different members

This intentional simplicity:
- ✓ No social complexity
- ✓ No notifications needed
- ✓ No member-management UI
- ✓ Just a UX shortcut

## Freemium limits

- **Free tier**: 2 groups
- **Premium tier**: unlimited

Most users have 1-2 distinct circles ("Roommates" + "Office Lunch"). Power users (multiple friend groups, family + work + gym) hit the limit and upgrade.

Enforced in `create_group` RPC.

## RLS policies

```sql
alter table groups enable row level security;
create policy groups_all on groups
  for all using (created_by = auth.uid()) with check (created_by = auth.uid());
```

Single policy: creator-only access. No SELECT for group members (they don't even know the group exists).

## Used by

- `group_members` (one-to-many child)
- `split_bills.group_id` (optional tag, ON DELETE SET NULL)

When a group is deleted, past split bills keep their `group_id = NULL` (lose the tag, but data preserved).

## Group is independent of split bills

This is important: **deleting a group doesn't affect ongoing split bills.** Past splits keep working. The `group_id` was just a metadata tag, not a permission boundary.

This means:
- Alice can delete "Roommates" group while bills are still pending
- Bob still sees those bills normally
- Settlement still works
- Only Alice's UI loses the "Roommates" filter/shortcut

## Common queries

```dart
// My groups
final groups = await supabase.from('groups')
  .select()
  .is_('deleted_at', null)
  .order('created_at', ascending: false);

// My groups with member count
final groups = await supabase.from('groups')
  .select('*, members:group_members(count)')
  .is_('deleted_at', null);

// My groups with member preview
final groups = await supabase.from('groups')
  .select('*, members:group_members(user:profiles(id, username, display_name))')
  .is_('deleted_at', null);
```

## RPCs

| RPC | Purpose |
|---|---|
| `create_group(p_name, p_member_user_ids, p_icon, p_color)` | Create group with initial members. Validates limit + members are contacts |
| `add_group_member(p_group_id, p_user_id)` | Add a contact to existing group |
| `remove_group_member(p_group_id, p_user_id)` | Soft-remove member |
| `delete_group(p_group_id)` | Soft-delete group |

All RPCs validate creator ownership.

## Use in split bills

When creating a split bill, the user can optionally pick a group:

```dart
// Show group picker
final group = await showGroupPicker();

// Pre-fill participants from group_members
final groupMembers = await supabase.from('group_members')
  .select('user_id')
  .eq('group_id', group.id)
  .is_('removed_at', null);

// Allow user to add/remove individuals from this list
// Then call create_split_bill with p_group_id and p_shares
```

The bill stores `group_id` for filtering ("show me all Roommates splits"), but doesn't enforce the participant list — Alice can deviate from the group for a one-off split.

## Common mistakes

1. **Don't assume group_id locks participants.** It's just a tag. Users can pick a group then add/remove specific people.

2. **Don't notify group members.** They don't know the group exists. No notifications, no activity feed entries.

3. **Don't validate "members must be in the group" when creating a bill.** Validate "members must be in your contacts" (which the RPC already does). The group is a shortcut, not a constraint.
