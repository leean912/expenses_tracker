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
- **No `deleted_at` column** — contacts are hard-deleted, not soft-deleted. Never use `deleted_at is null` when querying this table in RPCs or Flutter code.

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

---

## V2: Friend Request System (not yet deployed)

Replace auto-bidirectional with an explicit approve/decline flow. Only one row is created initially (A→B as `pending`). B must accept for the bidirectional relationship to form.

### Schema migration

```sql
-- Add status column (default 'accepted' so existing rows are unaffected)
ALTER TABLE contacts
  ADD COLUMN status text NOT NULL DEFAULT 'accepted'
  CHECK (status IN ('pending', 'accepted'));

-- Index for fast inbox queries (B looking up requests sent to them)
CREATE INDEX contacts_pending_idx ON contacts(friend_id) WHERE status = 'pending';
```

### RLS policy update

```sql
DROP POLICY IF EXISTS contacts_select ON contacts;

-- Owner sees their own rows; recipient sees pending rows sent to them
CREATE POLICY contacts_select ON contacts FOR SELECT
  USING (
    owner_id = auth.uid()
    OR (friend_id = auth.uid() AND status = 'pending')
  );
```

### Edge case matrix

| Scenario | Result |
|----------|--------|
| A adds B (no rows exist) | A→B inserted as `pending`; B sees request in inbox |
| B accepts A's request | A→B updated to `accepted`; B→A inserted as `accepted` |
| B declines A's request | A→B hard-deleted |
| B adds A while A→B is `pending` | Auto-accept both; both become `accepted` |
| A deletes B (both `accepted`) | Both A→B and B→A hard-deleted |
| A adds B after mutual delete | A→B inserted as `pending` (clean state) |
| A adds B when A→B already `pending` | Error: "request already sent" |
| A adds B when A→B already `accepted` | Error: "already friends" |

### New / modified RPCs

**Modified `add_contact`** — returns `{ result: 'pending' | 'accepted' }`:
1. Resolve identifier → `target_user_id`
2. Error if target = self
3. If A→B exists as `accepted` → error "already friends"
4. If A→B exists as `pending` → error "request already sent"
5. If B→A exists as `pending` → auto-accept both (mutual add) → return `{ result: 'accepted' }`
6. Default: INSERT A→B as `pending` → return `{ result: 'pending' }`

**New `accept_contact_request(p_from_user_id uuid)`**:
```sql
UPDATE contacts SET status = 'accepted'
  WHERE owner_id = p_from_user_id AND friend_id = auth.uid() AND status = 'pending';
INSERT INTO contacts (owner_id, friend_id, status)
  VALUES (auth.uid(), p_from_user_id, 'accepted')
  ON CONFLICT (owner_id, friend_id) DO UPDATE SET status = 'accepted';
```

**New `decline_contact_request(p_from_user_id uuid)`**:
```sql
DELETE FROM contacts
  WHERE owner_id = p_from_user_id AND friend_id = auth.uid() AND status = 'pending';
```

**New `remove_contact(p_friend_id uuid)`** — mutual unfriend:
```sql
DELETE FROM contacts
  WHERE (owner_id = auth.uid() AND friend_id = p_friend_id)
     OR (owner_id = p_friend_id AND friend_id = auth.uid());
```
Replaces Flutter-side direct `.delete().eq('id', contactId)`.

### Flutter changes

- `ContactModel` must expose `status` field (pending badge on outgoing requests)
- New `contactRequestsProvider` — fetches incoming `pending` rows with `from:profiles!owner_id` join
- New `acceptedContactsProvider` — fetches only `accepted` rows; used **exclusively by all pickers** (split bill, collab, groups, recurring split bill) so pending friends never appear in those flows
- Contacts screen: AppBar Requests button with red dot badge; `_RequestsSheet` bottom sheet with Accept/Decline per row
- 5 picker files swap `contactsProvider` → `acceptedContactsProvider`

### Out of scope (future)

- Push notifications when A sends B a request
- RPC-level enforcement in `create_split_bill`, `create_group`, `add_collab_member` (currently frontend-only via `acceptedContactsProvider`)
