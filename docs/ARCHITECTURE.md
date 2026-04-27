# Architecture

## Stack Overview

```
┌─────────────────────────────────────────────────────┐
│  Flutter (iOS / Android / future Web+Desktop)       │
│  - Riverpod for state                               │
│  - go_router for navigation                         │
│  - Supabase Flutter SDK for data access             │
└────────────────────────┬────────────────────────────┘
                         │ HTTPS (REST + Realtime)
                         ▼
┌─────────────────────────────────────────────────────┐
│  Supabase                                           │
│  ├─ PostgreSQL (15+) with RLS enforced              │
│  ├─ Auth (Google + Apple OAuth)                     │
│  ├─ Edge Functions (V2: cron jobs, webhooks)        │
│  └─ Storage (V2: receipts, avatars)                 │
└─────────────────────────────────────────────────────┘
```

## Why This Stack

**Flutter**: Single codebase for iOS and Android. Strong widget library. Good performance.

**Supabase**: Hosted Postgres with built-in auth, real-time subscriptions, RLS, and edge functions. Eliminates the need for custom backend code for 90% of operations.

**RLS-first design**: Security policies are enforced at the database layer, not application layer. Even if a Flutter bug exposed an arbitrary query, RLS prevents data leaks across users.

## Authentication Flow

```
1. User taps "Sign in with Google" / "Sign in with Apple"
2. OAuth completes → Supabase auth.users row created
3. Trigger handle_new_user() fires:
   - Creates profiles row (username = NULL initially)
   - Seeds 11 default categories
   - Seeds 2 default accounts (Cash + Bank)
4. Flutter checks profile.username
   - If NULL → show "Pick username" screen (blocking)
   - If set → proceed to main app
5. User picks unique username via set_username RPC
6. Main app loads
```

When a collab is created, `handle_new_collab()` trigger fires and auto-inserts the owner into `collab_members` with `role='owner'`.

## Data Access Pattern

```
Flutter Layer → Supabase RPC / Query → PostgreSQL → RLS check → Response
```

**RPCs vs direct queries**:
- Use RPCs for complex multi-row operations (create_split_bill, settle_split_share, close_collab)
- Use direct queries for simple lists (recent expenses, my categories, my accounts)
- RPCs run as `security definer` so they can enforce business logic that crosses RLS boundaries

## Key Design Principles

### 1. Per-user data isolation

Every table has RLS policies that filter by `auth.uid()`. No data is "globally" readable.

```sql
-- Example: expenses RLS
create policy exp_select on expenses for select using (user_id = auth.uid());
create policy exp_insert on expenses for insert with check (user_id = auth.uid());
```

### 2. Soft deletes

Almost every table has a `deleted_at timestamptz` column. Hard deletes are rare. This:
- Preserves history for split bill participants (Bob can still see settled bills even if Alice deletes)
- Allows undo flows
- Supports audit trails

### 3. Frozen conversions

When Alice logs a foreign-currency expense, the row stores:
- `amount_cents` (foreign)
- `home_amount_cents` (calculated at entry time)
- `conversion_rate` (the rate she used)
- `home_currency`

This means historical analytics are accurate even if Alice later updates rates. **Past expenses never change.**

### 4. Activity feed computed, not stored

There is no `notifications` or `events` table. Recent activity is derived on-demand by the `my_activity_feed` RPC, which UNIONs across:
- split_bills (created)
- split_bill_shares (settled, disputed)
- collab_members (added)
- collabs (closed)
- expenses with collab_id (added by other members)
- contacts (added by others)

Single source of truth: the underlying tables.

### 5. Categories per user

Each user has their OWN set of categories (auto-seeded with 11 defaults). When creating split bills:
- The bill's `category_id` must belong to the creator
- When Bob settles his share, his `expenses` row uses HIS own category

This prevents cross-user category pollution. Alice's "Food" category and Bob's "Food" category are different rows.

### 6. Accounts are tags, not balance trackers

`accounts` table has no `current_balance` column. Each expense optionally tags an account_id. Analytics like "spending by account this month" sum `expenses.home_amount_cents` per `account_id` — the database never stores running balances.

## Data Lifecycle

### Personal expense
```
User taps + → Flutter form → INSERT into expenses → done
```

### Split bill
```
Alice creates → create_split_bill RPC:
  1. INSERT into split_bills (with home conversion snapshot)
  2. INSERT N rows into split_bill_shares (one per participant)
  3. INSERT into expenses (Alice's auto-payer expense)
```

### Settlement
```
Bob settles → settle_split_share RPC:
  1. INSERT into settlements (immutable history)
  2. INSERT into expenses (Bob's expense, his category, his account)
  3. INSERT into expenses (Alice's income, her category)
  4. UPDATE split_bill_shares.status = 'settled'
```

### Collab close
```
Alice (owner) closes collab → close_collab RPC:
  1. UPDATE collabs.status = 'closed', closed_at = now()
  (no import needed — expenses were always in personal books)
```

## Failure Modes & Recovery

**Network drop during multi-row RPC**: All RPCs are wrapped in implicit transactions. Either all rows are written, or none.

**Collab member leaves mid-collab**: Their `left_at` is set, RLS revokes visibility of other members' expenses. Their own collab-tagged expenses remain in their personal books.

**Concurrent edits**: Last-write-wins on `updated_at`. MVP doesn't have conflict resolution beyond this. V2 with offline sync will need vector clocks or CRDTs.

**Auth failure**: Supabase SDK retries with refresh token. If that fails, user is signed out and shown login.

## V2 Architecture Hooks

The schema includes columns/concepts ready for V2 features without requiring migrations:

| V2 Feature | Schema Hook |
|---|---|
| Receipt images | `expenses.receipt_url`, `split_bills.receipt_url` |
| Avatars | `profiles.avatar_url` |
| Collab cover photos | `collabs.cover_photo_url` |
| Live FX rates | `expenses.conversion_rate` already stored per-row |
| Push notifications | Activity feed RPC produces same shape; just add FCM tokens |
| Custom split types | `split_bill_shares.split_method` (already 'equal'/'custom' enum) |
| Disputes with refund | `split_bill_shares.dispute_reason` already exists |
