# Expense Logging Flow

The most-used flow in the app. Covers logging personal expenses (and income) — the core daily action.

## Core principles

1. **Log purchases, not money movements.** Buying coffee = expense. ATM withdrawal = NOT an expense. Currency conversion = NOT an expense.
2. **Quick by default.** Most users log on the go. Optimize for fewest taps.
3. **Edit-friendly.** Users frequently fix typos or change categories. Make editing easy.

## The expense form

```
┌──────────────────────────────────┐
│  ← New Expense                   │
│                                  │
│  RM [   50.00   ]                │
│      ▲ big numeric input         │
│                                  │
│  📅 Today, 25 April              │
│                                  │
│  📁 Food                          │
│                                  │
│  💳 Maybank                      │
│                                  │
│  📝 Lunch at Sushi King          │
│                                  │
│  📍 Add location (optional)      │
│                                  │
│  [ Save ]                        │
└──────────────────────────────────┘
```

Fields:
- **Amount** (required) — large numeric keypad as primary focus
- **Date** (defaults to today, tappable to change)
- **Category** (required, defaults to last-used)
- **Account** (optional, defaults to last-used)
- **Note** (optional, free text)
- **Location** (optional, V2 adds Google Places autocomplete)

## Flow: log a simple expense

```
1. User taps "+" floating action button
2. Form opens with amount input focused, keyboard up
3. User types "50"
4. Taps category → bottom sheet of their categories → picks "Food"
5. Taps account → picks "Maybank"
6. Optionally types a note
7. Taps Save
8. INSERT into expenses
9. Form closes, returns to home with success toast
```

Total: ~5-8 taps for a complete log. Faster if defaults match (last-used category/account).

## Schema mapping

```dart
await supabase.from('expenses').insert({
  'user_id': currentUserId,
  'type': 'expense',
  'source': 'manual',
  'amount_cents': 5000,  // RM 50.00
  'currency': 'MYR',
  'home_amount_cents': 5000,
  'home_currency': 'MYR',
  'conversion_rate': null,  // same currency
  'category_id': foodCategoryId,
  'account_id': maybankAccountId,
  'note': 'Lunch at Sushi King',
  'expense_date': '2026-04-25',
});
```

## Foreign currency expense

When `currency != home_currency`, Flutter prompts for the rate:

```
User picks currency: JPY (instead of default MYR)
  → App detects mismatch
  → Show inline rate input

  ┌──────────────────────────────────┐
  │  ¥ [   3000   ]                  │
  │                                  │
  │  Currency: JPY                   │
  │                                  │
  │  Conversion to MYR:              │
  │  1 MYR = [   30   ] JPY          │
  │  ≈ RM 100.00                     │
  │                                  │
  │  [ Save ]                        │
  └──────────────────────────────────┘
```

Flutter caches the last rate per currency in `SharedPreferences`:

```dart
// On expense save
await prefs.setDouble('fx_${currency}_${homeCurrency}', rate);

// On next foreign expense entry
final cachedRate = prefs.getDouble('fx_${currency}_${homeCurrency}');
if (cachedRate != null) {
  rateController.text = cachedRate.toString();  // pre-fill
}
```

The expense is saved with the rate AND home conversion:

```dart
final amountCents = (parsedAmount * 100).round();
final homeAmountCents = (amountCents / rate).round();

await supabase.from('expenses').insert({
  'user_id': currentUserId,
  'type': 'expense',
  'source': 'manual',
  'amount_cents': amountCents,         // ¥3000 = 300000 cents in JPY
  'currency': 'JPY',
  'home_amount_cents': homeAmountCents, // RM 100 = 10000 cents in MYR
  'home_currency': 'MYR',
  'conversion_rate': rate,              // 30
  'category_id': travelCategoryId,
  'note': 'Taxi from airport',
  'expense_date': '2026-04-25',
});
```

## Income flow

Same form, but with a `type` toggle at the top:

```
[ Expense ] [ Income ]
   ▲ default
```

When set to Income:
- Amount input shows green (instead of red/neutral)
- Save button says "Add Income"
- `type = 'income'` in the INSERT

Income examples:
- Salary
- Refund
- Cashback
- Gift received

Income from settlements is auto-created — users don't manually log "Bob paid me back."

## Editing an existing expense

```
1. User taps an expense in the timeline
2. Detail screen shows all fields
3. Tap edit (pencil icon) or any field
4. Edit form opens (same as create form, pre-filled)
5. User changes fields
6. UPDATE expenses
7. Returns to detail / timeline
```

```dart
await supabase.from('expenses')
  .update({
    'amount_cents': 5500,  // changed from 5000
    'note': 'Lunch at Sushi King (updated)',
    'updated_at': DateTime.now().toIso8601String(),
  })
  .eq('id', expenseId);
```

The `set_updated_at` trigger fires automatically — but explicitly setting it can be useful for cache invalidation logic.

## Deleting an expense

Soft delete via UPDATE:

```dart
await supabase.from('expenses')
  .update({'deleted_at': DateTime.now().toIso8601String()})
  .eq('id', expenseId);
```

The expense disappears from queries (most have `WHERE deleted_at IS NULL`). The row stays in the DB for audit / undo.

Provide an Undo snackbar:

```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Expense deleted'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () async {
        await supabase.from('expenses')
          .update({'deleted_at': null})
          .eq('id', expenseId);
      },
    ),
    duration: Duration(seconds: 5),
  ),
);
```

## Restrictions on auto-created expenses

Some expenses have `source != 'manual'`. They came from RPCs:
- `source = 'split_payer'` → auto-created when you created a split bill
- `source = 'settlement'` → auto-created when a split was settled

For these:
- **Allow editing**: category, account, note (user wants to recategorize)
- **Disallow editing**: amount, currency, expense_date (would break the source's accounting)

Flutter UI hides the amount field for non-manual expenses, or shows it grayed out.

## Quick-entry shortcut (V2)

For power users, "Quick add" mode skips most fields:

```
Tap and hold "+" → Quick form:
  RM [   50  ]   Food   Save
```

Just amount + category + save. Account = last-used. Note = empty. Date = today.

This is V2 polish — MVP can ship with the full form only.

## Validation

Client-side:
- Amount > 0
- Currency selected
- Category selected (required in MVP, optional in V2)

Database-side:
- `amount_cents > 0` (CHECK constraint)
- `category_id` must belong to user (RLS)
- `account_id` must belong to user (RLS)

Server returns `PostgrestException` if any validation fails. Show user-friendly error.

## Filters and search

The expense timeline supports filters:

```dart
var query = supabase.from('expenses').select('*, category:categories(*), account:accounts(*)');

// Date range
query = query.gte('expense_date', startDate).lte('expense_date', endDate);

// Filter by type
if (typeFilter != null) {
  query = query.eq('type', typeFilter);  // 'expense' or 'income'
}

// Filter by category
if (categoryId != null) {
  query = query.eq('category_id', categoryId);
}

// Filter by account
if (accountId != null) {
  query = query.eq('account_id', accountId);
}

// Filter by source (for "manual only" toggle)
if (manualOnly) {
  query = query.eq('source', 'manual');
}

// Always exclude deleted + archived
query = query
  .is_('deleted_at', null)
  .is_('archived_at', null);

// Order
query = query
  .order('expense_date', ascending: false)
  .order('created_at', ascending: false);

final results = await query.limit(50);
```

Search by note text (V2 adds full-text search):

```dart
final results = await supabase.from('expenses')
  .select()
  .ilike('note', '%lunch%')
  .is_('deleted_at', null);
```

## Common mistakes

1. **Don't auto-suggest categories based on note text in MVP.** That's V2 ML territory. Just use last-used as default.

2. **Don't validate that category currency matches expense currency.** Categories don't have currency. Only accounts do (for V2).

3. **Don't allow typing negative amounts.** Use the type toggle for income; keep amount positive.

4. **Don't let users edit `source` or `source_*_id` fields directly.** They're internal.

5. **Don't forget to compute `home_amount_cents` for foreign expenses.** Without it, monthly totals will be wrong.
