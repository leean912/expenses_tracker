# Activity Feed Flow

How recent activity is shown to users. Computed on-demand from existing tables — there is NO `notifications` or `events` table.

## Mental model

The activity feed is a UNION of recent events across multiple tables:
- New split bills (you're a participant)
- Settlements (someone paid you, you paid someone)
- Disputes
- Collab events (added to collab, collab closed, expense added)
- Contact additions (someone added you)

Each row in those tables has a timestamp; the feed orders by timestamp DESC.

```
                  ┌──────────────────────┐
                  │  my_activity_feed    │
                  │       RPC            │
                  └──────┬───────────────┘
                         │ UNION ALL
       ┌─────────────────┼─────────────────┐
       │                 │                 │
       ▼                 ▼                 ▼
  split_bills      split_bill_shares    collab_members
       │                 │                 │
       ▼                 ▼                 ▼
  expenses(collab)  contacts          settlements (V2)
```

Order by `occurred_at DESC` → that's the feed.

## Why no notifications table

We deliberately don't store events in a separate table. Reasons:

1. **Always accurate** — the feed reflects current state, not stale notifications
2. **No double-counting** — if a split bill is deleted, its events disappear from the feed automatically
3. **Less infrastructure** — no events table means no event creation logic in every RPC
4. **Smaller database** — events would dwarf actual data over time
5. **Simpler RLS** — each source table already has RLS; the feed inherits it

The trade-off: no "read/unread" tracking. We accept this — most modern apps don't track read state, they just show recent activity.

## RPC: my_activity_feed

```sql
my_activity_feed(p_cursor timestamptz, p_limit integer)
returns jsonb
```

Returns a JSON array of activity events, newest first.

```dart
// First page (most recent activity)
final activities = await supabase.rpc('my_activity_feed', params: {
  'p_cursor': null,
  'p_limit': 30,
});

// Returns something like:
// [
//   {
//     "type": "share_settled",
//     "occurred_at": "2026-04-25T10:30:00Z",
//     "payload": { ... }
//   },
//   ...
// ]
```

## Cursor pagination

For infinite scroll, pass the oldest `occurred_at` as the cursor:

```dart
String? cursor;

// First load
final firstPage = await supabase.rpc('my_activity_feed', params: {
  'p_cursor': null,
  'p_limit': 30,
});

if (firstPage.isNotEmpty) {
  cursor = firstPage.last['occurred_at'];
}

// Load more
final nextPage = await supabase.rpc('my_activity_feed', params: {
  'p_cursor': cursor,  // newer than cursor → returns OLDER
  'p_limit': 30,
});
```

The RPC takes `p_cursor` as "show events older than this timestamp."

## Event types

The feed currently supports these event types:

### `split_created`
```json
{
  "type": "split_created",
  "occurred_at": "2026-04-25T10:00:00Z",
  "payload": {
    "split_bill_id": "uuid",
    "created_by": "alice_id",
    "note": "Dinner at Sushi King",
    "amount_cents": 12000,
    "currency": "MYR",
    "your_share_cents": 4000
  }
}
```

Fired when someone creates a split bill where you're a participant (excluding yourself as creator).

UI: "Alice created a split: Dinner at Sushi King — your share RM 40"

### `share_settled`
```json
{
  "type": "share_settled",
  "occurred_at": "2026-04-25T11:00:00Z",
  "payload": {
    "split_bill_id": "uuid",
    "settler_id": "bob_id",
    "note": "Dinner at Sushi King",
    "amount_cents": 4000,
    "currency": "MYR"
  }
}
```

Fired when someone settled their share on a bill YOU created (you're the payer receiving money).

UI: "Bob settled RM 40 for Dinner at Sushi King"

### `share_disputed`
```json
{
  "type": "share_disputed",
  "occurred_at": "2026-04-25T12:00:00Z",
  "payload": {
    "split_bill_id": "uuid",
    "disputer_id": "bob_id",
    "note": "Dinner at Sushi King",
    "reason": "Bill was actually only RM 100",
    "amount_cents": 4000
  }
}
```

Fired when someone disputes their share on a bill you created.

UI: "Bob disputed his share: 'Bill was actually only RM 100'"

### `added_to_collab`
```json
{
  "type": "added_to_collab",
  "occurred_at": "2026-04-25T08:00:00Z",
  "payload": {
    "collab_id": "uuid",
    "collab_name": "Japan 2026",
    "added_by": "alice_id"
  }
}
```

Fired when someone adds you to a collab (you're a member, not the owner).

UI: "Alice added you to Japan 2026"

### `collab_closed`
```json
{
  "type": "collab_closed",
  "occurred_at": "2026-05-15T20:00:00Z",
  "payload": {
    "collab_id": "uuid",
    "collab_name": "Japan 2026",
    "closed_by": "alice_id"
  }
}
```

Fired when a collab you're in is closed by the owner.

UI: "Japan 2026 was closed"

### `collab_expense_added`
```json
{
  "type": "collab_expense_added",
  "occurred_at": "2026-05-03T19:30:00Z",
  "payload": {
    "collab_id": "uuid",
    "collab_expense_id": "uuid",
    "created_by": "bob_id",
    "note": "Ramen dinner",
    "amount_cents": 200000,
    "currency": "JPY"
  }
}
```

Fired when SOMEONE ELSE adds a collab expense in a collab you're in (not your own).

UI: "Bob added ¥2,000 — Ramen dinner in Japan 2026"

### `contact_added`
```json
{
  "type": "contact_added",
  "occurred_at": "2026-04-20T15:00:00Z",
  "payload": {
    "by_user_id": "alice_id"
  }
}
```

Fired when someone adds you as a contact.

UI: "Alice added you as a contact"

## Rendering in Flutter

```dart
Widget buildActivityItem(Map<String, dynamic> activity) {
  final type = activity['type'] as String;
  final payload = activity['payload'] as Map<String, dynamic>;
  final occurredAt = DateTime.parse(activity['occurred_at']);
  
  switch (type) {
    case 'split_created':
      return SplitCreatedTile(payload: payload, occurredAt: occurredAt);
    case 'share_settled':
      return ShareSettledTile(payload: payload, occurredAt: occurredAt);
    case 'share_disputed':
      return ShareDisputedTile(payload: payload, occurredAt: occurredAt);
    case 'added_to_collab':
      return AddedToCollabTile(payload: payload, occurredAt: occurredAt);
    case 'collab_closed':
      return CollabClosedTile(payload: payload, occurredAt: occurredAt);
    case 'collab_expense_added':
      return CollabExpenseAddedTile(payload: payload, occurredAt: occurredAt);
    case 'contact_added':
      return ContactAddedTile(payload: payload, occurredAt: occurredAt);
    default:
      return SizedBox.shrink();
  }
}
```

Each tile widget knows how to fetch any extra data it needs (e.g., the user's display_name from their UUID) and render appropriately.

## Display format

Group by date for readability:

```
┌──────────────────────────────────┐
│  Activity                        │
│                                  │
│  Today                           │
│   • Bob settled RM 40            │
│     2 hours ago                  │
│                                  │
│   • Alice created split:         │
│     Dinner at Sushi King         │
│     5 hours ago                  │
│                                  │
│  Yesterday                       │
│   • Charlie disputed his share   │
│     "Bill was actually..."       │
│                                  │
│   • You hit 100% of Food budget  │ ← V2 (computed locally)
│                                  │
│  Earlier                         │
│   • Alice added you to           │
│     Japan 2026                   │
│                                  │
│  [ Load more ]                   │
└──────────────────────────────────┘
```

## No "unread" badges in MVP

The home screen doesn't show "5 unread activity items." Reasons:

- Activity isn't stored, so we can't track read state
- Most users don't care about exact counts
- "Action needed" badges (computed from pending splits, pending imports) are more useful

If you want a "did anything happen" indicator, query for events newer than the user's last app open:

```dart
// Get last activity timestamp
final lastSeenStr = prefs.getString('last_activity_seen');
final lastSeen = lastSeenStr != null ? DateTime.parse(lastSeenStr) : null;

// Get latest activity from feed
final activities = await supabase.rpc('my_activity_feed', params: {'p_limit': 1});

bool hasNewActivity = false;
if (activities.isNotEmpty) {
  final latest = DateTime.parse(activities.first['occurred_at']);
  hasNewActivity = lastSeen == null || latest.isAfter(lastSeen);
}

// Show dot on activity icon if hasNewActivity
```

When user opens the activity tab:

```dart
await prefs.setString('last_activity_seen', DateTime.now().toIso8601String());
```

This is a lightweight way to show "new" without database tracking.

## Real-time updates (V2)

For real-time activity, V2 can subscribe to the source tables:

```dart
// Subscribe to new shares involving me
supabase.from('split_bill_shares')
  .stream(primaryKey: ['id'])
  .eq('user_id', currentUserId)
  .listen((shares) {
    // New share appeared — refresh activity feed
  });

// Subscribe to collabs I'm in
final myCollabIds = (await supabase.from('collab_members')
  .select('collab_id')
  .eq('user_id', currentUserId)
  .is_('left_at', null))
  .map((r) => r['collab_id']).toList();

supabase.from('expenses')
  .stream(primaryKey: ['id'])
  .in_('collab_id', myCollabIds)
  .listen((expenses) {
    // New collab expense — refresh feed
  });
```

For MVP, just use pull-to-refresh on the activity tab.

## Performance

The RPC unions across many tables. Each source has indexes on the relevant columns:

- `expenses.user_id, expense_date` (for personal events)
- `split_bill_shares.user_id, status` (for share events)
- `collab_members.user_id` (for collab membership events)
- `contacts.friend_id` (for "added me as contact" events)

The cursor pagination keeps each query bounded. Even with thousands of activities, returning the latest 30 is fast (~50-100ms).

## Common mistakes

1. **Don't try to insert into a notifications table.** There isn't one.

2. **Don't compute the activity feed in Flutter.** Use the RPC. It handles all the union logic.

3. **Don't expect activity to be infinite.** Eventually you'll exhaust the underlying data. Show "No more activity" gracefully.

4. **Don't filter activities client-side after fetching.** Use the cursor + limit properly.

5. **Don't show activity for actions YOU performed.** The RPC already excludes self-actions in most cases. (E.g., when you create a split bill, you don't see "you created a split.")
