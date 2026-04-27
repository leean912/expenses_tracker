# Collab Flow

A shared expense workspace. Members log expenses directly into their personal `expenses` table tagged with a `collab_id`. All active members can see each other's expenses via RLS.

## Mental model

A collab is a **shared view** over the `expenses` table — not a separate table. When Alice logs an expense with `collab_id = <Japan 2026>`, Bob (also a member) can see it immediately. The expense is Alice's from day one: it counts toward her personal analytics, she owns it, and only she can edit or delete it.

```
[Owner creates collab]
       │
       ▼
   ACTIVE — members log expenses tagged with collab_id
            all members see all collab-tagged expenses
       │
       │ (owner taps Close — optional)
       ▼
   CLOSED — read-only; no new expenses can be tagged
```

No import step. No separate table. Closing is just archiving.

## Creating a collab

### Form

```
┌──────────────────────────────────┐
│  ← New Collab                    │
│                                  │
│  Name:        [ Japan 2026 ]     │
│  Description: [           ]      │
│                                  │
│  Start date:  [ 2026-05-01 ]     │  (optional)
│  End date:    [ 2026-05-14 ]     │  (optional)
│                                  │
│  Budget (MYR): [ 2000.00 ]       │  (optional)
│                                  │
│  Currency:    [ JPY ▼ ]          │
│                                  │
│  Conversion to your home (MYR):  │
│  1 MYR = [   30   ] JPY          │
│                                  │
│  [ Create ]                      │
└──────────────────────────────────┘
```

If currency == home currency, hide the conversion section.

### Insert

```dart
await supabase.from('collabs').insert({
  'owner_id': currentUserId,
  'name': 'Japan 2026',
  'start_date': '2026-05-01',        // optional
  'end_date': '2026-05-14',          // optional
  'currency': 'JPY',
  'home_currency': 'MYR',
  'exchange_rate': 30.0,
  'budget_cents': 200000,            // optional — RM 2000
});
```

The `handle_new_collab()` trigger auto-adds the owner as a `collab_member` with `role='owner'`.

## Adding members

```dart
await supabase.rpc('add_collab_member', params: {
  'p_collab_id': collabId,
  'p_user_id': bobId,
});
```

The RPC validates the caller is the owner, the collab is active, and Bob is in the owner's contacts.

## Logging a collab expense

Members log expenses exactly like personal expenses, but include `collab_id`:

```dart
final collabRate = 30.0;
final amountCents = 300000;  // ¥3000
final homeAmountCents = (amountCents / collabRate).round();  // RM 100

await supabase.from('expenses').insert({
  'user_id': currentUserId,
  'type': 'expense',
  'source': 'manual',
  'collab_id': collabId,             // tags this expense to the collab
  'amount_cents': amountCents,
  'currency': 'JPY',
  'home_amount_cents': homeAmountCents,
  'home_currency': 'MYR',
  'conversion_rate': collabRate,     // frozen at entry time
  'category_id': transportCategoryId,
  'note': 'Taxi from airport',
  'expense_date': '2026-05-01',
});
```

This expense:
- Immediately appears in Alice's personal analytics
- Is visible to all active collab members via RLS
- Is owned by Alice — only she can edit or delete it

## Collab log view

Query all expenses in the collab — RLS returns rows from all members:

```dart
final collabExpenses = await supabase.from('expenses')
  .select('*, owner:profiles!user_id(id, username, display_name), category:categories(name, icon, color)')
  .eq('collab_id', collabId)
  .is_('deleted_at', null)
  .order('expense_date', ascending: false)
  .order('created_at', ascending: false);
```

```
┌──────────────────────────────────┐
│  Japan 2026                      │
│  Budget: RM 2,000                │
│  Spent:  RM 1,500  (75%)         │
│  Left:   RM 500                  │
│  ──────────────────────────────  │
│                                  │
│  May 14                          │
│   ¥8,000  Hotel        [Bob]     │
│   ¥2,500  Sushi dinner [Alice]   │
│                                  │
│  May 13                          │
│   ¥3,000  Taxi         [Alice]   │
│   ¥5,000  Souvenirs    [Charlie] │
│                                  │
└──────────────────────────────────┘
```

Members can only edit/delete their own rows — even though they can see all rows.

## Budget remaining

Computed from the `expenses` table directly:

```dart
final collab = await supabase.from('collabs')
  .select('budget_cents, home_currency')
  .eq('id', collabId)
  .single();

final spent = await supabase.from('expenses')
  .select('home_amount_cents.sum()')
  .eq('collab_id', collabId)
  .is_('deleted_at', null)
  .single();

final remaining = collab['budget_cents'] - (spent['sum'] ?? 0);
```

## Closing a collab

Optional. Owner can close when the collab is done — this makes it read-only (no new expenses can be tagged to it):

```dart
await supabase.rpc('close_collab', params: {'p_collab_id': collabId});
```

Existing expenses are untouched. There's no import — expenses were always in personal books.

## Members leaving

```dart
await supabase.rpc('leave_collab', params: {'p_collab_id': collabId});
```

Sets `collab_members.left_at = now()`. The member:
- No longer sees the collab in their list
- No longer has RLS access to other members' collab-tagged expenses
- Their own expenses tagged with this `collab_id` remain in their personal books

## Common mistakes

1. **Don't try to add non-contacts as members.** RPC validates contact relationship.

2. **Don't let members edit each other's expenses.** RLS allows SELECT for all members but UPDATE/DELETE is owner-only. Enforce in UI too.

3. **Don't change `collab.currency` or `collab.home_currency` after creation.** They're snapshots used to show the collab-level rate. Each expense's rate is frozen independently at entry time.

4. **Don't show collab expenses in personal analytics without the `collab_id` context.** When a user views "my April spending," their collab expenses are included. That's intentional — filter them out with `WHERE collab_id IS NULL` only if building a "personal-only" view.
