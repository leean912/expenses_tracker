# Friend Request System

## Overview

Replace the current auto-bidirectional contacts model with an explicit friend request flow. User A sends a request → User B approves → both become friends. Blocking is frontend-only: pending friends are invisible to split bill / collab / group pickers.

**Key design decisions:**
- Mutual unfriend: deleting a friend removes both rows atomically
- Frontend-only enforcement: RPCs (`create_split_bill`, `create_group`, `add_collab_member`) are NOT changed — accepted-only filtering happens in the provider layer
- Two separate Flutter providers: one for the contacts screen (UI), one for pickers (split bill / collab / groups)
- Incoming requests live in a dedicated provider + bottom sheet, accessible via an AppBar button with a red dot badge

---

## Edge Case Matrix

| Scenario | Result |
|----------|--------|
| A adds B (neither has rows) | A→B created as `pending`; B sees request in inbox |
| B accepts A's request | A→B updated to `accepted`; B→A inserted as `accepted` |
| B declines A's request | A→B row hard-deleted; A has no contact row for B |
| B adds A while A→B is `pending` | Auto-accept both (mutual add); both become `accepted` |
| A deletes B (both `accepted`) | Both A→B and B→A hard-deleted; clean slate |
| A adds B after mutual delete | A→B created as `pending` (B→A is gone, no ghost rows) |
| A adds B but B→A is `accepted` | **Cannot happen** with mutual delete — B→A only exists if B is also `accepted` friend of A |
| A adds B when A→B is already `pending` | RPC returns "request already sent" error |
| A adds B when A→B is already `accepted` | RPC returns "already friends" error |
| Add yourself | RPC blocks with existing check |
| User not found | RPC returns `user_not_found` hint |

---

## Database Changes

### 1. Schema migration

```sql
-- Add status column (default 'accepted' so migration is safe for existing rows)
ALTER TABLE contacts
  ADD COLUMN status text NOT NULL DEFAULT 'accepted'
  CHECK (status IN ('pending', 'accepted'));

-- Backfill all existing rows (they were all mutually accepted)
UPDATE contacts SET status = 'accepted';

-- Index for fast inbox queries (B looking up requests sent to them)
CREATE INDEX contacts_pending_idx ON contacts(friend_id) WHERE status = 'pending';
```

### 2. RLS policy update

```sql
-- Drop old select policy
DROP POLICY IF EXISTS contacts_select ON contacts;

-- New: owner sees their own rows; recipient sees pending rows sent to them
CREATE POLICY contacts_select ON contacts FOR SELECT
  USING (
    owner_id = auth.uid()
    OR (friend_id = auth.uid() AND status = 'pending')
  );

-- Insert and delete policies unchanged (owner_id = auth.uid())
```

**Why the RLS change:** Under the old model, B's row was auto-created so B could always see it. Under the new model, only A→B is created initially. B needs to read that row to action the request.

**Security note:** The pending row exposes `nickname` (which is A's nickname for B — can be null at request time). B cannot read A's other contact rows.

---

## RPC Changes

### Modified: `add_contact(p_identifier, p_nickname)`

New logic (replaces the current two-row insert):

```
1. Resolve p_identifier to target user_id (existing logic)
2. Error if target = auth.uid() ("cannot add yourself")
3. Check A→B row:
   - exists as 'accepted' → error "already friends"
   - exists as 'pending'  → error "request already sent"
4. Check B→A row:
   - exists as 'pending'  → auto-accept: UPDATE B→A to 'accepted', INSERT A→B as 'accepted', return { result: 'accepted' }
5. Default: INSERT A→B as 'pending', return { result: 'pending' }
```

Returns `{ result: 'pending' | 'accepted' }` so Flutter can show the right snackbar.

### New: `accept_contact_request(p_from_user_id uuid)`

```sql
-- Atomically accept an incoming pending request
UPDATE contacts SET status = 'accepted'
  WHERE owner_id = p_from_user_id AND friend_id = auth.uid() AND status = 'pending';

INSERT INTO contacts (owner_id, friend_id, status)
  VALUES (auth.uid(), p_from_user_id, 'accepted')
  ON CONFLICT (owner_id, friend_id) DO UPDATE SET status = 'accepted';
```

### New: `decline_contact_request(p_from_user_id uuid)`

```sql
-- Hard-delete the pending row
DELETE FROM contacts
  WHERE owner_id = p_from_user_id AND friend_id = auth.uid() AND status = 'pending';
```

### New: `remove_contact(p_friend_id uuid)`

```sql
-- Mutual unfriend: delete both directions atomically
DELETE FROM contacts
  WHERE (owner_id = auth.uid() AND friend_id = p_friend_id)
     OR (owner_id = p_friend_id AND friend_id = auth.uid());
```

Replaces the current Flutter-side direct `.delete().eq('id', contactId)`.

---

## Flutter Changes

### New file: `lib/modules/contacts/data/models/contact_request_model.dart`

```dart
class ContactRequestModel {
  final String id;          // contact row id (for keying widgets)
  final String fromUserId;  // owner_id — who sent the request
  final String? username;
  final String displayName;
  final String? avatarUrl;

  factory ContactRequestModel.fromJson(Map<String, dynamic> json) {
    final from = json['from'] as Map<String, dynamic>? ?? {};
    return ContactRequestModel(
      id: json['id'],
      fromUserId: from['id'],
      username: from['username'],
      displayName: from['display_name'] ?? '',
      avatarUrl: from['avatar_url'],
    );
  }
}
```

Query to fetch: `contacts` where `friend_id = auth.uid() AND status = 'pending'`, join `from:profiles!owner_id(id, username, display_name, avatar_url)`.

### New file: `lib/modules/contacts/providers/contact_requests_provider.dart`

```dart
// Fetches incoming pending requests (rows where friend_id = me, status = 'pending')
// Methods: acceptRequest(fromUserId), declineRequest(fromUserId)
// On accept/decline: invalidates contactsProvider + self so friends list and badge update together
```

### Modified: `lib/modules/contacts/providers/contacts_provider.dart`

| Change | Detail |
|--------|--------|
| `_fetch()` query | Add `.eq('status', 'accepted')` filter |
| `addContact()` | Handle `{ result: 'pending' \| 'accepted' }` return from RPC; return an enum/string so the dialog can show the right message |
| `deleteContact()` | Replace direct `.delete()` with `supabase.rpc('remove_contact', params: { 'p_friend_id': friendId })` |

### New provider: `acceptedContactsProvider`

A lightweight read-only provider with the same query as `contactsProvider` (`owner_id = auth.uid() AND status = 'accepted'`). Kept separate so split bill / collab screens are decoupled from the contacts screen's notifier state.

```dart
final acceptedContactsProvider = FutureProvider<List<ContactModel>>((ref) async {
  // same fetch as contactsProvider but no mutation methods
});
```

### Modified: `lib/modules/contacts/presentation/screens/contacts_screen.dart`

| Change | Detail |
|--------|--------|
| AppBar `actions` | Add Requests `IconButton` (e.g. `Icons.person_rounded`) |
| Red dot badge | `Stack` + small red `Container` overlay when `contactRequestsProvider` has items |
| `_RequestsSheet` | New bottom sheet widget — lists `ContactRequestModel` items with Accept / Decline buttons per row |
| `_AddFriendDialog` snackbar | Show "Request sent." when result is `pending`, "Friend added." when `accepted` |
| `_GroupsTab` (line 329) | `ref.read(contactsProvider)` → `ref.read(acceptedContactsProvider)` |

### `_RequestsSheet` behaviour

- Empty state: "No pending requests."
- Each row: display name + `@username`, Accept button, Decline button
- Accept: calls `acceptRequest` → invalidates `contactRequestsProvider` + `contactsProvider` → friends list and badge both update
- Decline: calls `declineRequest` → invalidates `contactRequestsProvider` → row disappears from sheet

### Files that swap `contactsProvider` → `acceptedContactsProvider`

| File | Line | Usage |
|------|------|-------|
| `add_expense_sheet.dart` | 1541 | Split bill participant picker |
| `collab_members_screen.dart` | 719 | Add collab member picker |
| `group_split_bill_sheet.dart` | 944 | Group split bill participant picker |
| `recurring_split_bill_form_screen.dart` | 885 | Recurring split bill participant picker |
| `group_detail_screen.dart` | 440 | Add member to existing group |

No logic changes in these files — just swap the provider reference. The accepted-only filter in the provider is what prevents pending friends from appearing in pickers.

---

## Migration Steps (in order)

1. **Run SQL migration** in Supabase SQL Editor:
   - Alter table, backfill, add index
   - Update RLS policy

2. **Deploy new RPCs** in Supabase SQL Editor:
   - `accept_contact_request`
   - `decline_contact_request`
   - `remove_contact`
   - Update `add_contact`

3. **Flutter changes** (can be done in parallel with DB prep):
   - Add `ContactRequestModel`
   - Add `contactRequestsProvider`
   - Add `acceptedContactsProvider`
   - Modify `contactsProvider`
   - Modify `contacts_screen.dart`
   - Swap provider references in 5 other screens

4. **Test scenarios** using the edge case matrix above

---

## Out of Scope (future considerations)

- **Outgoing pending visibility**: Users cannot currently see requests they've sent that are awaiting approval. Could add a "Sent" section in `_RequestsSheet` querying `owner_id = auth.uid() AND status = 'pending'` with a Cancel option.
- **Push notifications**: Notify B when A sends a request (requires push notification infrastructure).
- **Backend enforcement**: Currently frontend-only. If stronger guarantee is needed, `create_split_bill`, `create_group`, and `add_collab_member` RPCs should also check `status = 'accepted'`.
- **Activity feed**: `contact_added` event type would split into `contact_request_received` (actionable) and `contact_accepted` (informational).
