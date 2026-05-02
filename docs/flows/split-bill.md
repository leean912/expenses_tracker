# Split Bill Flow

The collaborative spending feature. Covers creating, settling, and disputing split bills.

## Mental model

A "split bill" is a record that says "Alice paid RM 100 for dinner; Bob, Charlie, and Alice each owe RM 33.33." It creates:
1. A `split_bills` row (the header)
2. N `split_bill_shares` rows (one per participant)
3. An auto-`expenses` row for Alice (the payer's full expense)

When Bob settles, it creates:
1. A `settlements` row (the audit trail)
2. An `expenses` row for Bob (his payment as expense)
3. An `expenses` row for Alice (her receipt as income)

## Creating a split bill

### Form UX

```
┌──────────────────────────────────┐
│  ← New Split Bill                │
│                                  │
│  RM [   120.00   ]               │
│                                  │
│  📝 Dinner at Sushi King         │
│                                  │
│  📁 Food                         │
│                                  │
│  📅 Today                        │
│                                  │
│  Split with:                     │
│  [ Pick a group ▼ ]              │
│  ─── or ───                      │
│  [ + Add people ]                │
│                                  │
│  Participants (3):               │
│   ✓ You          (paid)          │
│   ✓ Bob          RM 40           │
│   ✓ Charlie      RM 40           │
│                                  │
│  [ Save split ]                  │
└──────────────────────────────────┘
```

Fields:
- Amount, note, category, date — same as personal expense
- **Split with** — pick a group (pre-fills) or add individuals
- **Participants** — list with auto-calculated shares
- Each share editable for custom amounts

### Equal split logic

```
Total: RM 120
Participants: 3 (Alice, Bob, Charlie)

Equal split:
  120 / 3 = 40
  → Alice: RM 40, Bob: RM 40, Charlie: RM 40

If 100 / 3 = 33.33...:
  → Two get 33.33, one gets 33.34 (extra cent)
```

```dart
List<Share> equalSplit(int totalCents, List<String> userIds) {
  final n = userIds.length;
  final base = totalCents ~/ n;
  final remainder = totalCents - (base * n);
  
  return List.generate(n, (i) {
    return Share(
      userId: userIds[i],
      shareCents: i < remainder ? base + 1 : base,
    );
  });
}
```

### Calling create_split_bill

```dart
final shares = [
  {'user_id': aliceId, 'share_cents': 4000},
  {'user_id': bobId, 'share_cents': 4000},
  {'user_id': charlieId, 'share_cents': 4000},
];

final result = await supabase.rpc('create_split_bill', params: {
  'p_paid_by': currentUserId,         // MVP: must equal creator
  'p_total_amount_cents': 12000,
  'p_currency': 'MYR',
  'p_note': 'Dinner at Sushi King',
  'p_expense_date': '2026-04-25',
  'p_category_id': foodCategoryId,
  'p_collab_id': null,
  'p_group_id': null,                 // optional
  'p_google_place_id': null,
  'p_place_name': null,
  'p_latitude': null,
  'p_longitude': null,
  'p_receipt_url': null,
  'p_shares': shares,
  'p_home_amount_cents': 12000,        // same currency = same amount
  'p_home_currency': 'MYR',
  'p_conversion_rate': null,           // null for same-currency
});

print('Created bill ID: ${result['split_bill_id']}');
print('Payer expense ID: ${result['payer_expense_id']}');
```

The RPC validates:
- Creator is authenticated
- `p_paid_by == auth.uid()` (MVP restriction)
- Each participant is in creator's contacts (or is the creator themselves)
- `p_category_id` belongs to creator
- `p_group_id` belongs to creator (if provided)
- `p_collab_id` is one the creator is a member of (if provided)

### After creation

Database state:
```
split_bills:        1 new row
split_bill_shares:  3 new rows (Alice settled, Bob+Charlie pending)
expenses:           1 new row (Alice's full RM 120 expense, source='split_payer')
```

Bob and Charlie can now see the bill in their app under "Pending splits."

## Foreign currency split bill

```
Alice (in Japan) creates split:
  Total: ¥12,000
  Bob's share: ¥4,000
  Conversion rate: 30 (1 MYR = 30 JPY)
```

```dart
final amountCents = 1200000;  // ¥12,000
final rate = 30.0;
final homeAmountCents = (amountCents / rate).round();  // 40000 (RM 400)

await supabase.rpc('create_split_bill', params: {
  // ... other fields ...
  'p_total_amount_cents': amountCents,
  'p_currency': 'JPY',
  'p_home_amount_cents': homeAmountCents,
  'p_home_currency': 'MYR',
  'p_conversion_rate': rate,
  'p_shares': [
    {'user_id': aliceId, 'share_cents': 400000},  // ¥4,000
    {'user_id': bobId, 'share_cents': 400000},
    {'user_id': charlieId, 'share_cents': 400000},
  ],
});
```

Bob sees the bill in his app:
```
"Dinner ¥12,000 (≈ RM 400)"
"Your share: ¥4,000 (≈ RM 133.33)"
```

The conversion is computed from the bill's stored snapshot (Alice's rate). Bob doesn't enter his own rate.

## Settling a share

### From Bob's perspective

Bob opens the app, sees pending split:

```
┌──────────────────────────────────┐
│  Dinner at Sushi King            │
│  Alice paid RM 120               │
│  Today                           │
│                                  │
│  Your share: RM 40               │
│                                  │
│  [ Mark as Settled ]             │
│  [ Dispute ]                     │
└──────────────────────────────────┘
```

Bob taps "Mark as Settled." A bottom sheet asks for his category + account:

```
┌──────────────────────────────────┐
│  Mark as Settled                 │
│                                  │
│  RM 40 to Alice                  │
│                                  │
│  Category:  [ Food ▼ ]           │
│  Account:   [ Touch'nGo ▼ ]      │
│                                  │
│  [ Confirm ]                     │
└──────────────────────────────────┘
```

```dart
await supabase.rpc('settle_split_share', params: {
  'p_share_id': bobsShareId,
  'p_category_id': bobsFoodCategoryId,  // Bob's own category
  'p_account_id': bobsTouchNGoAccountId, // Bob's own account
});
```

The RPC:
1. Validates Bob owns this share
2. Validates `p_category_id` and `p_account_id` belong to Bob
3. Creates `settlements` row (Bob → Alice)
4. Creates Bob's expense row (RM 40, his category, his account, source='settlement')
5. Creates Alice's income row (RM 40, bill's category, source='settlement')
6. Updates `split_bill_shares.status = 'settled'`

### Database state after settlement

```
split_bill_shares (Bob's): status='settled', settled_at=now(), settlement_id=<new>
settlements: new row (Bob → Alice, RM 40)
expenses (Bob's):   new row, type=expense, RM 40, Food, Touch'nGo
expenses (Alice's): new row, type=income,  RM 40, Food (her), no account
```

Both users immediately see updated state.

## Disputing a share

Bob thinks the amount is wrong:

```
┌──────────────────────────────────┐
│  Dispute share                   │
│                                  │
│  RM 40 — your share              │
│                                  │
│  Reason:                         │
│  [ I think the bill was actually │
│    only RM 100, so my share      │
│    should be RM 33.33. ]         │
│                                  │
│  [ Submit Dispute ]              │
└──────────────────────────────────┘
```

```dart
await supabase.rpc('dispute_split_share', params: {
  'p_share_id': bobsShareId,
  'p_reason': 'I think the bill was actually only RM 100...',
});
```

Updates `split_bill_shares.status = 'disputed'` and stores the reason.

Alice (the creator) sees:
```
[ICON: warning]
Bob disputed his share
"I think the bill was actually only RM 100..."
[ Resolve ]
```

To resolve: Alice can either:
- **Edit the bill** (if no other shares are settled) — adjust amounts, dispute auto-clears
- **Override** — convince Bob offline; Bob then settles normally
- **Soft-delete the bill** — start over

There's no formal "Alice approves resolution" RPC in MVP. The dispute is informational. V2 may add resolution flows.

## Unsettling a share

If Bob marked settled by accident:

```
[ Mark as Settled ]  ← already settled, button disabled
[ Unsettle ]         ← shown next to settled status
```

```dart
await supabase.rpc('unsettle_split_share', params: {
  'p_share_id': bobsShareId,
});
```

The RPC:
1. Soft-deletes the settlement row (`deleted_at = now()`)
2. Soft-deletes both expense + income rows
3. Resets share status to 'pending'
4. Clears `settled_at`, `settlement_id`

This brings everything back to pre-settlement state.

## Edge cases

### Bill creator wants to edit after Bob settled

UI should disable amount editing if any share is settled:

```dart
final hasSettledShares = await supabase.from('split_bill_shares')
  .select('*', const FetchOptions(count: CountOption.exact))
  .eq('split_bill_id', billId)
  .eq('status', 'settled')
  .count();

final canEditAmount = hasSettledShares == 0;
```

If user wants to edit anyway, force them to unsettle first (with confirmation: "Bob will need to mark settled again").

### Settler is no longer a contact

Edge case: Alice removed Bob as contact AFTER creating the split. Bob can still settle (he sees his pending share). No re-validation on settle.

### Different currencies (MVP simplification)

If Alice (MYR home) creates a bill with Bob (USD home):
- Alice's app: shows MYR conversion
- Bob's app: shows the same MYR conversion (Bob can mentally convert)
- Bob settles → his expense uses Alice's rate (which is wrong from Bob's perspective)

This is the MVP compromise. Cross-currency split bills are rare for the Malaysian target market. V2 can add per-user conversion.

## Reading split bills

```dart
// All my pending shares (I owe these)
final pending = await supabase.from('split_bill_shares')
  .select('*, bill:split_bills(*, payer:profiles!paid_by(*))')
  .eq('user_id', currentUserId)
  .eq('status', 'pending')
  .is_('archived_at', null);

// Bills I created (mine to track)
final myBills = await supabase.from('split_bills')
  .select('*, shares:split_bill_shares(*, user:profiles(*))')
  .eq('created_by', currentUserId)
  .is_('deleted_at', null)
  .order('expense_date', ascending: false);

// Detail of a single bill
final billDetail = await supabase.from('split_bills')
  .select('''
    *,
    shares:split_bill_shares(
      *,
      user:profiles(id, username, display_name, avatar_url),
      settlement:settlements(*)
    ),
    creator:profiles!created_by(*),
    payer:profiles!paid_by(*),
    category:categories(*),
    collab:collabs(*),
    group:groups(*)
  ''')
  .eq('id', billId)
  .single();
```

## V2: Splitting with non-onboarded users (email-based)

> **Not yet deployed.** Schema and logic are in `docs/split_v2.sql`. Apply that file after `expense_tracker_schema.sql` when ready.

### The problem

`create_split_bill` requires every participant's `user_id`, which means they must already have a profile. If Alice wants to split with Bob before Bob signs up, the current schema blocks it.

### How it works in V2

Alice provides Bob's email in a new `p_email_shares` parameter. The RPC:
1. Validates the email isn't already a real profile (if it is, caller should use `p_shares` with the user_id instead)
2. Inserts a row into `pending_split_shares` — NOT into `split_bill_shares`
3. Returns `pending_shares_sent: 1` in the result JSON

When Bob signs up, `handle_new_user()` detects the pending row and automatically:
1. Inserts a real `split_bill_shares` row (status = 'pending')
2. Creates bidirectional contacts (Alice ↔ Bob)
3. Marks the pending row claimed

Bob opens the app for the first time and sees the split in his activity feed.

### Calling create_split_bill with email participants

```dart
final result = await supabase.rpc('create_split_bill', params: {
  'p_paid_by': currentUserId,
  'p_total_amount_cents': 12000,
  'p_currency': 'MYR',
  'p_note': 'Dinner at Sushi King',
  'p_expense_date': '2026-04-25',
  'p_category_id': foodCategoryId,
  'p_collab_id': null,
  'p_group_id': null,
  'p_google_place_id': null,
  'p_place_name': null,
  'p_latitude': null,
  'p_longitude': null,
  'p_receipt_url': null,

  // Onboarded participants (user_id based — existing behaviour)
  'p_shares': [
    {'user_id': charlieId, 'share_cents': 4000},
    {'user_id': currentUserId, 'share_cents': 4000},
  ],

  // Non-onboarded participants (email based — V2)
  'p_email_shares': [
    {'email': 'bob@email.com', 'share_cents': 4000},
  ],
});

print('bill: ${result['split_bill_id']}');
print('pending invites sent: ${result['pending_shares_sent']}');  // 1
```

### UI considerations for pending email participants

Pending email participants are in `pending_split_shares`, not `split_bill_shares`. When rendering the bill detail view, query both:

```dart
// Real shares (onboarded participants)
final shares = await supabase
  .from('split_bill_shares')
  .select('*, user:profiles(id, username, display_name, avatar_url)')
  .eq('split_bill_id', billId);

// Pending email shares (V2)
final pending = await supabase
  .from('pending_split_shares')
  .select('invitee_email, share_cents, claimed_at')
  .eq('split_bill_id', billId)
  .is_('claimed_at', null);

// Merge for display — show pending participants with a clock/pending badge
```

- Show a "pending" indicator (e.g., email address + clock icon) for unclaimed participants
- Disable "Settle" and "Dispute" actions for pending rows
- Optionally show a "Remind" button to prompt Alice to re-send the invite link

### Edge cases

| Scenario | Behaviour |
|---|---|
| Bob signs up with a different email | Pending row never claimed. Alice must manually add Bob and redo the split |
| Bill deleted before Bob signs up | `pending_split_shares` row cascade-deleted. Nothing claimed on signup |
| Alice invites bob@email.com who is already onboarded | RPC raises error with `hint = 'use_p_shares'`. UI should pre-check and fall back to user_id path |
| Same email invited twice to same bill | `unique (split_bill_id, invitee_email)` deduplicates silently |

## Common mistakes

1. **Don't insert split_bills directly.** Always use `create_split_bill` RPC.

2. **Don't pass another user's category_id to create_split_bill.** RPC will error. Use creator's own category.

3. **Don't try to settle on someone else's behalf.** RPC blocks settlements where `auth.uid() != share.user_id`.

4. **Don't show "settle" button for the payer.** Their share is auto-settled by the RPC.

5. **Don't validate `sum(shares) == total`.** Round-off errors are normal. Acceptable to be off by a few cents on equal splits.

6. **Don't forget to validate participants are contacts.** The RPC handles this, but UI should pre-filter participant picker to contacts only.
