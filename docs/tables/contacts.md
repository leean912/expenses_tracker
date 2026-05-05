# contacts

User's friend list. Auto-bidirectional — adding Bob as a contact creates two rows (Alice→Bob and Bob→Alice).

## Purpose

Track who a user can split bills with, add to groups, or invite to trips. There's no friend-request flow in MVP — adding someone is immediate.

## Schema

```sql
create table contacts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  friend_id uuid not null references profiles(id) on delete cascade,
  nickname text,
  created_at timestamptz not null default now(),
  unique (owner_id, friend_id),
  check (owner_id <> friend_id)
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `owner_id` | uuid | The user whose contact list this row belongs to |
| `friend_id` | uuid | The user being saved as a contact |
| `nickname` | text | Optional custom display name (e.g., "Bobby" instead of "Robert Tan") |
| `created_at` | timestamptz | When added |

## Constraints

- `unique (owner_id, friend_id)` — can't have duplicate contact entries
- `check (owner_id <> friend_id)` — can't add yourself as a contact
- Both FKs cascade — if either user deletes their account, the contact rows go away

## The auto-bidirectional model

When Alice adds Bob via `add_contact`:

```
Alice's perspective:
  INSERT INTO contacts (owner_id=alice, friend_id=bob, nickname='Bob')

Bob's perspective:
  INSERT INTO contacts (owner_id=bob, friend_id=alice, nickname=NULL)
```

Two rows. Both created in one RPC call. If Alice removes Bob, only her row is deleted — Bob still has Alice in his contacts unless he removes her too.

This model:
- ✓ No friend request approval needed
- ✓ Either party can remove without breaking the other
- ✓ Simple mental model
- ✗ Can't prevent unwanted contact requests (acceptable for MVP)

## RLS policies

```sql
create policy contacts_select on contacts for select using (owner_id = auth.uid());
create policy contacts_insert on contacts for insert with check (owner_id = auth.uid());
create policy contacts_delete on contacts for delete using (owner_id = auth.uid());
```

Each user only sees their own contact list. The reverse contact (friend's row) is invisible to them.

## Adding contacts via RPC

```dart
// By email
await supabase.rpc('add_contact', params: {
  'p_identifier': 'bob@example.com',
  'p_nickname': null,
});

// By username
await supabase.rpc('add_contact', params: {
  'p_identifier': '@bob',  // or just 'bob'
});
```

The RPC:
1. Detects email vs username (presence of `@` and `.`)
2. Looks up the friend's `profiles.id`
3. Errors with hint `user_not_found` if not found
4. Inserts both directions atomically (handles re-activation on conflict)

## Removing contacts

```dart
// Hard-delete — Flutter side
await supabase.from('contacts').delete().eq('id', contactId);
```

This only deletes the user's own row. The reverse row (friend's perspective) is unaffected — they can still see the user as a contact.

## Used in

- **Split bill validation**: `create_split_bill` checks each participant is in the creator's contacts
- **Group member validation**: `create_group` and `add_group_member` check the user is a contact
- **Collab member validation**: `add_collab_member` checks the user is a contact
- **Contact list UI**: Direct query for contacts list with friend's profile info

## Common queries

```dart
// My contacts (with friend's profile data)
final contacts = await supabase.from('contacts')
  .select('id, nickname, friend:profiles!friend_id(id, username, display_name, avatar_url)')
  .order('created_at', ascending: false);

// Search my contacts by name/username
final filtered = await supabase.from('contacts')
  .select('*, friend:profiles!friend_id(*)')
  .or('friend.username.ilike.%alice%,friend.display_name.ilike.%alice%');
```

## Edge cases

**Re-adding a removed contact**: If Alice previously removed Bob, calling `add_contact` again inserts a fresh row. The `unique (owner_id, friend_id)` constraint prevents duplicates.

**Adding a non-app user**: Returns error with `hint = 'user_not_found'`. Flutter should offer an "Invite" share sheet at this point.

**Adding yourself**: Blocked by RPC ("Cannot add yourself as a contact").
