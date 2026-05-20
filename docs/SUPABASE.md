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
5. Inspect the Table Editor — should see 15 tables

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
   - `tags` has 1 row (Income Tax, #4A90D9)

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

## RPC Catalog (29 functions)

All RPCs are `security definer`. They internally validate `auth.uid()` and reject if null. RPCs are called from Flutter via `supabase.rpc('function_name', params: {...})`.

### Analytics (aggregation RPCs)

These RPCs exist to bypass the PostgREST 1000-row response limit. Because they return a single JSON object (computed entirely inside PostgreSQL), they are immune to the limit regardless of how many underlying expense rows exist. Both home and actual amounts are always returned so Flutter can toggle between display modes without re-fetching.

SQL source: `expense_tracker_schema.sql` (sections 14s–14v).

| RPC | Params | Purpose |
|---|---|---|
| `home_analytics(p_start, p_end)` | `date, date` | Home screen: period totals, avg/day, this/last month change, per-category spend. Returns one JSON. |
| `analysis_summary(p_start, p_end, p_include_collab)` | `date, date, boolean` | Analysis screen: by-category, by-account, by-tag, daily buckets, daily-per-category buckets. Returns one JSON with pre-aggregated daily rows (max 365/year); Dart does week/month bucketing. Untagged expenses appear as `tag_name = 'Untagged'` in `by_tag`. |
| `collab_summary(p_collab_id)` | `uuid` | Collab detail header + members screen: all-time spend totals (excluding settlement rows) + per-member spend map. Returns both `total_spent_cents` (home_amount) and `total_actual_cents` (actual_amount). No date filter. |
| `collab_analytics(p_collab_id, p_start, p_end)` | `uuid, date, date` | Collab analysis screen: self-only category/account breakdowns + daily buckets per member. Returns one JSON. |

**JSON field convention for dual-amount RPCs:**
- `*_total_cents` — uses `home_amount_cents` (full bill amount, e.g. split payer shows full split bill)
- `*_actual_cents` — uses `actual_amount_cents` (real out-of-pocket, falls back to `home_amount_cents` when null)

### Currency

| RPC | Purpose |
|---|---|
| `change_home_currency(p_new_currency)` | Atomic archive of all expenses + flip the home currency on profile |

### Profile / Username

| RPC | Purpose |
|---|---|
| `set_username(p_username)` | Set the user's unique handle (immutable in MVP, format-validated) |
| `check_username_available(p_username)` | Live check during signup form — returns boolean |

### Tags

| RPC | Purpose |
|---|---|
| `create_tag(p_name, p_color)` | Create a new tag. Restores soft-deleted tag with same name (always allowed, before limit check). Enforces 5-custom limit for free tier counting only `requires_premium = false` tags (raises `hint = 'upgrade_required'`). Default tags do not count toward the limit. Premium users can create unlimited tags; tags created beyond the 5-slot free threshold are marked `requires_premium = true` so they lock automatically if the subscription lapses. |

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
| `remove_group_member(p_group_id, p_user_id)` | Hard-delete member from group (creator only) |
| `delete_group(p_group_id)` | Hard-delete the group and its members (creator only) |

### Contacts

| RPC | Purpose |
|---|---|
| `add_contact(p_identifier, p_nickname)` | Add by username or email. Auto-creates bidirectional rows (MVP). V2: returns `{ result: 'pending' \| 'accepted' }` when friend request system is deployed |
| `accept_contact_request(p_from_user_id)` | **V2** — Accept an incoming pending request; inserts reverse `accepted` row |
| `decline_contact_request(p_from_user_id)` | **V2** — Hard-delete the pending row sent by `p_from_user_id` |
| `remove_contact(p_friend_id)` | **V2** — Mutual unfriend: hard-deletes both directions atomically. See `docs/tables/contacts.md` for full edge case matrix |

### Split Bills

| RPC | Purpose |
|---|---|
| `create_split_bill(...)` | Create bill + shares + payer's auto-expense. Validates onboarded participants are contacts. Email participants (V2) go to `pending_split_shares` |
| `settle_split_share(p_share_id, p_category_id, p_account_id, p_tag_id)` | Mark share settled, create both expense rows, copy bill's conversion. `p_tag_id` applied to settler's expense row only (not payer's income row). |
| `creator_mark_share_paid(p_share_id)` | Bill creator marks a participant's share as paid on their behalf. Creates settlement + income row for creator + expense row for participant (category/account null — cross-user categories invalid). |
| `unsettle_split_share(p_share_id)` | Soft-undo a settlement |
| `dispute_split_share(p_share_id, p_reason)` | Mark share disputed with reason |

### Collabs

| RPC | Purpose |
|---|---|
| `add_collab_member(p_collab_id, p_user_id)` | Owner adds a contact to the collab |
| `leave_collab(p_collab_id)` | Member self-removes (owner can't — must delete collab instead) |
| `close_collab(p_collab_id)` | Mark collab closed/read-only (warns about unsettled splits but doesn't block) |

### Recurring

| RPC | Purpose |
|---|---|
| `create_recurring_expense(p_title, p_amount_cents, p_frequency, p_first_run_at, p_type, p_category_id, p_account_id, p_note, p_tag_id)` | Create a recurring expense template. Fires immediately if `first_run_at <= today`. 3 active limit for free tier. `p_tag_id` applied to template and any immediately-fired expense row. |
| `update_recurring_expense(p_id, p_title, p_amount_cents, p_frequency, p_next_run_at, p_type, p_category_id, p_account_id, p_note, p_tag_id)` | Update a recurring expense template. All params optional except `p_id`. |
| `create_recurring_split_bill(p_title, p_amount_cents, p_frequency, p_first_run_at, p_split_method, p_shares, p_category_id, p_account_id, p_note, p_tag_id)` | Create a recurring split bill template. Fires immediately if `first_run_at <= today`. 1 active limit for free tier. `p_tag_id` applied to template and any immediately-fired payer expense row. |
| `update_recurring_split_bill(p_id, p_title, p_amount_cents, p_frequency, p_next_run_at, p_split_method, p_category_id, p_account_id, p_note, p_tag_id, p_shares)` | Update a recurring split bill template metadata and/or shares. All params optional except `p_id`. |

### Referrals

| RPC | Purpose |
|---|---|
| `apply_referral_code(p_code)` | Apply a referral code during onboarding. Every 5th referral awards the referrer 7 premium days. Returns `{ referrer_id, bonus_days, new_count }`. |
| `get_referral_stats()` | Returns `{ referral_code, total_referrals, bonus_expires_at, referrals_until_next }` for the current user |
| `process_subscription_expirations()` | Called by pg_cron at 16:00 UTC daily. Downgrades expired premium users, preserving referral premium if still active. Pauses premium recurring items for free users. |

### Helpers

| RPC | Purpose |
|---|---|
| `my_activity_feed(p_cursor, p_limit)` | Recent activity events (computed across multiple tables) |

### Internal (triggers)

| Function | Purpose |
|---|---|
| `handle_new_user()` | Auto-fires on auth.users insert; creates profile + seeds categories + seeds accounts + seeds default tag (Income Tax) + claims any pending_split_shares (V2) |
| `handle_new_collab()` | Auto-fires on collabs insert; creates collab_members row for owner |
| `set_updated_at()` | Generic trigger function for `updated_at` columns |
| `generate_referral_code()` | Generates unique 8-char code. Used as `DEFAULT` on `profiles.referral_code`. |

### Storage Buckets V2 — Not yet deployed

Receipt image upload is a V2 Premium feature. No DB migration needed — `receipt_url text` columns already exist on `expenses` and `split_bills`, and `create_split_bill` already accepts `p_receipt_url`.

**Bucket**: `receipts`  
**Visibility**: Public-readable, write-restricted to owner's own folder  
**Path format**: `<user_id>/<uuid>.jpg`  
**URL stored in DB**: Permanent Supabase public URL (no expiry)

**Why public-readable (not private)**: Split bill participants need to view the receipt. If the bucket is private, only the uploader can generate signed URLs — Bob can't view Alice's receipt. Public URL + write restriction is the correct trade-off.

**Freemium gate — CRITICAL**: The gate is **client-side only**. Storage policies allow any authenticated user to upload to their own folder; they do NOT enforce premium tier. Free users who bypass the client check can upload. This is acceptable — receipt upload is a convenience feature, not a data-integrity gate.

```dart
// In receipt icon tap handler (all 3 form files)
if (profile.subscriptionTier == 'free') {
  showUpgradeSheet(context); // 'Attach receipt photos — Premium feature.'
  return;
}
```

#### Storage Policies (run once in Supabase Dashboard → SQL Editor)

```sql
-- Anyone authenticated can view any receipt (split bill participants need access)
create policy "public read receipts"
  on storage.objects for select
  using (bucket_id = 'receipts');

-- Users can only upload to their own folder
create policy "users upload own receipts"
  on storage.objects for insert
  with check (bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text);

-- Users can only delete their own receipts
create policy "users delete own receipts"
  on storage.objects for delete
  using (bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text);
```

#### Upload Flow

```
image_picker (camera or gallery)
  → flutter_image_compress: JPEG quality 85% → 70% → 50% until <1MB
  → supabase.storage.from('receipts').uploadBinary('<user_id>/<uuid>.jpg', bytes)
  → getPublicUrl(path) → store URL in form state → pass to DB on submit
```

New packages: `fvm flutter pub add image_picker flutter_image_compress`  
New service: `lib/core/services/receipt_upload_service.dart` (pick → compress → upload → return URL)

iOS — add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>To attach a receipt photo to your expense</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>To choose a receipt photo from your gallery</string>
```

#### Delete Flow

Each record supports one receipt. To replace: delete first, then upload.

```dart
// Reconstruct storage path from the public URL for deletion:
// URL format: https://<project>.supabase.co/storage/v1/object/public/receipts/<user_id>/<file>.jpg
final storagePath = publicUrl.split('/object/public/receipts/').last;
await supabase.storage.from('receipts').remove([storagePath]);
// then UPDATE receipt_url = null on the DB row
```

#### Flutter Files to Change (when implementing)

| File | Change |
|---|---|
| `lib/core/services/receipt_upload_service.dart` | **New** — pick, compress, upload logic |
| `add_expense_sheet.dart` | Receipt picker for personal expense + split tabs |
| `collab_split_bill_sheet.dart` | Receipt picker, pass URL to RPC |
| `group_split_bill_sheet.dart` | Receipt picker, pass URL to RPC |
| Expense detail screen | Thumbnail if `receipt_url != null`, tap to full-screen |
| Split bill detail screen | Thumbnail if `receipt_url != null`, tap to full-screen |

### Split V2 — Not yet deployed

Defined in `docs/split_v2.sql`. Run after the base schema when ready.

| Component | What changes |
|---|---|
| `pending_split_shares` table | New table. Stores email-based share slots for non-onboarded participants |
| `create_split_bill(...)` | New optional param `p_email_shares jsonb`. Email participants bypass contacts check and land in `pending_split_shares` |
| `handle_new_user()` | Extended to claim pending shares on signup: inserts real `split_bill_shares` row + creates bidirectional contacts |

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

For simple lists where RPC is overkill, use direct queries against tables.

**Important — PostgREST 1000-row limit**: Any `.select()` call returns at most 1000 rows silently. For lists that could grow large (expense history, split bills, collabs), use `.range(from, to)` for pagination with a `hasMore` flag. For export (full dataset), loop with 500-row pages. For analytics/aggregation on unbounded data, always use an RPC.

```dart
// My expenses — paginated (30 per page)
final expenses = await supabase
  .from('expenses')
  .select('*, category:categories(name, icon, color)')
  .gte('expense_date', '2026-04-01')
  .lte('expense_date', '2026-04-30')
  .order('expense_date', ascending: false)
  .range(0, 29); // page 0: rows 0–29; page 1: rows 30–59; etc.

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
