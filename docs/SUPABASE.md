# Supabase Setup & RPC Catalog

## Initial Deployment

### Step 1: Create a Supabase project

1. Go to https://supabase.com → New Project
2. Name: `expense-tracker-prod` (or `expense-tracker-dev` for staging)
3. Region: Singapore (closest to Malaysian users)
4. Database password: store in 1Password / Bitwarden

### Step 2: Run the schema

1. Open SQL Editor in Supabase Dashboard
2. Paste the entire contents of `expense_tracker_schema.sql`
3. Click Run
4. Verify "Success. No rows returned" message
5. Inspect the Table Editor — should see 14 tables

### Step 3: Configure Auth providers

**Google:**
1. Authentication → Providers → Google → Enable
2. Provide OAuth Client ID + Secret from Google Cloud Console
3. Add redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback`

**Apple:**
1. Authentication → Providers → Apple → Enable
2. Provide Services ID, Team ID, Key ID, Private Key from Apple Developer
3. Add redirect URI matching Google's

### Step 4: Test the trigger

1. Authentication → Users → Add user → manually create a test user
2. Check Table Editor:
   - `profiles` row exists for the new user (with username = NULL)
   - `categories` has 11 rows (defaults)
   - `accounts` has 2 rows (Cash + Bank)

5. Verify the collab trigger: create a test collab and check that a `collab_members` row is auto-created for the owner.

If any of these are missing, the `handle_new_user` trigger isn't firing — check trigger setup in SQL Editor.

### Step 5: Verify RLS

In SQL Editor as the test user, run:
```sql
select * from profiles;        -- should return only their row
select * from categories;      -- should return only their categories
```

In SQL Editor as anonymous (logged out):
```sql
select * from profiles;        -- should return 0 rows
```

## RPC Catalog (24 functions)

All RPCs are `security definer`. They internally validate `auth.uid()` and reject if null. RPCs are called from Flutter via `supabase.rpc('function_name', params: {...})`.

### Currency

| RPC | Purpose |
|---|---|
| `change_home_currency(p_new_currency)` | Atomic archive of all expenses + flip the home currency on profile |

### Profile / Username

| RPC | Purpose |
|---|---|
| `set_username(p_username)` | Set the user's unique handle (immutable in MVP, format-validated) |
| `check_username_available(p_username)` | Live check during signup form — returns boolean |

### Categories

| RPC | Purpose |
|---|---|
| `create_custom_category(p_name, p_icon, p_color)` | Create a new category. Enforces 5-custom limit for free tier |

### Accounts

| RPC | Purpose |
|---|---|
| `create_account(p_name, p_icon, p_color, p_currency)` | Create a new custom account. Enforces 10-custom-account limit for free tier |
| `my_account_spending(p_start, p_end)` | Returns spending per account in a date range (analytics) |

### Groups

| RPC | Purpose |
|---|---|
| `create_group(p_name, p_member_user_ids, p_icon, p_color)` | Create a new group. Validates members are contacts. 2-group limit for free tier |
| `add_group_member(p_group_id, p_user_id)` | Add member (creator only, must be contact) |
| `remove_group_member(p_group_id, p_user_id)` | Soft-remove member from group (creator only) |
| `delete_group(p_group_id)` | Soft-delete the group (creator only) |

### Contacts

| RPC | Purpose |
|---|---|
| `add_contact(p_identifier, p_nickname)` | Add by username or email. Auto-creates bidirectional rows |

### Split Bills

| RPC | Purpose |
|---|---|
| `create_split_bill(...)` | Create bill + shares + payer's auto-expense. Validates participants are contacts |
| `settle_split_share(p_share_id, p_category_id, p_account_id)` | Mark share settled, create both expense rows, copy bill's conversion |
| `unsettle_split_share(p_share_id)` | Soft-undo a settlement |
| `dispute_split_share(p_share_id, p_reason)` | Mark share disputed with reason |

### Collabs

| RPC | Purpose |
|---|---|
| `add_collab_member(p_collab_id, p_user_id)` | Owner adds a contact to the collab |
| `leave_collab(p_collab_id)` | Member self-removes (owner can't — must delete collab instead) |
| `close_collab(p_collab_id)` | Mark collab closed/read-only (warns about unsettled splits but doesn't block) |

### Helpers

| RPC | Purpose |
|---|---|
| `my_activity_feed(p_cursor, p_limit)` | Recent activity events (computed across multiple tables) |

### Internal (triggers)

| Function | Purpose |
|---|---|
| `handle_new_user()` | Auto-fires on auth.users insert; creates profile + seeds categories + seeds accounts |
| `handle_new_collab()` | Auto-fires on collabs insert; creates collab_members row for owner |
| `set_updated_at()` | Generic trigger function for `updated_at` columns |

## Calling RPCs from Flutter

```dart
// Simple RPC
final result = await supabase.rpc('check_username_available', params: {
  'p_username': 'alice',
});
// returns: true / false

// RPC that returns JSON
final response = await supabase.rpc('create_account', params: {
  'p_name': 'Maybank Savings',
  'p_icon': 'account_balance',
  'p_color': '#378ADD',
});
// returns: { account_id, custom_count, tier }

// RPC that returns table (use .select() pattern)
final spending = await supabase.rpc('my_account_spending', params: {
  'p_start_date': '2026-04-01',
  'p_end_date': '2026-04-30',
});
// returns: List<Map<String, dynamic>>
```

## Direct Queries Reference

For simple lists where RPC is overkill, use direct queries against tables:

```dart
// My expenses this month
final expenses = await supabase
  .from('expenses')
  .select('*, category:categories(name, icon, color)')
  .gte('expense_date', '2026-04-01')
  .lte('expense_date', '2026-04-30')
  .order('expense_date', ascending: false);

// My active categories
final categories = await supabase
  .from('categories')
  .select()
  .order('sort_order');
// RLS automatically filters to user's own

// My active accounts (non-archived)
final accounts = await supabase
  .from('accounts')
  .select()
  .eq('is_archived', false)
  .order('sort_order');

// My pending split shares
final pending = await supabase
  .from('split_bill_shares')
  .select('*, bill:split_bills(*)')
  .eq('status', 'pending')
  .neq('archived_at', null);
```

## Real-time Subscriptions (V2)

Supabase supports real-time updates via Postgres replication. Useful for:

- Activity feed: subscribe to inserts on `split_bill_shares` where `user_id = current_user`
- Collab log: subscribe to `expenses` where `collab_id IN (my_collabs)`
- Group updates: subscribe to `group_members` for groups you created

For MVP, just use pull-to-refresh. Real-time can be added later without schema changes.

```dart
// V2 example — not needed for MVP
final subscription = supabase
  .from('split_bill_shares')
  .stream(primaryKey: ['id'])
  .eq('user_id', currentUserId)
  .listen((rows) {
    // Update local state
  });
```

## Common Issues

### Infinite recursion in RLS policies

Caused by two tables whose RLS policies reference each other. In this schema, `split_bills` and `split_bill_shares` had a mutual reference:
- `sb_select` on `split_bills` queried `split_bill_shares`
- `shares_select` on `split_bill_shares` queried `split_bills`

Fix: the `is_split_participant(bill_id)` security definer function in section 15g breaks the cycle. It reads `split_bill_shares` directly (bypassing RLS), so `split_bills` policy no longer triggers `shares_select`. Do not remove this function.

If you see `42P17: infinite recursion detected in policy for relation "X"`, check whether any policy on X queries a table whose policy also queries X.

### "Permission denied" errors

Almost always RLS-related. Either:
- The user isn't authenticated (no `auth.uid()`)
- The row's `user_id` doesn't match `auth.uid()`
- Trying to read another user's data without a valid relationship (e.g., not a collab member)

Debug: in Supabase SQL Editor, set `SET ROLE authenticated; SET request.jwt.claim.sub = '<user-uuid>';` then run the query.

### Trigger not firing

If `handle_new_user` doesn't fire:
1. Check the trigger exists: `select * from pg_trigger where tgname = 'trg_on_auth_user_created'`
2. Check the function: `select * from pg_proc where proname = 'handle_new_user'`
3. Try inserting a test user via SQL: `insert into auth.users (...) values (...)` and watch logs

### RPC returning unexpected nulls

Common cause: parameter type mismatch. Postgres is strict — passing a string when bigint is expected gives a confusing null. Always check the RPC signature and match exactly.

### Foreign key violations

Most common: trying to settle a split with a `p_category_id` that doesn't belong to the settler. The RPC raises an explicit error in this case.
