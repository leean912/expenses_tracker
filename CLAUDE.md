# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Direction

**Spendz** is a financial habits app built for Malaysians, not just an expense tracker. The goal is to help Malaysians understand their spending patterns and build healthier financial habits over time. WE MALAYSIAN CAN SAVE BETTER!

**What makes Spendz different:**
- **Awareness over accounting** — we show users what they spent and help them reflect, not just log numbers
- **Friends system** — users add friends (contacts) by username; split bills and collabs are friend-first social features
- **Split bills with friends** — collaborative expense splitting where friends see and settle their own shares
- **Collabs** — shared trip/event budgets where multiple friends track spending together
- **Recurring expenses & recurring split bills** — set-and-forget tracking for regular costs
- **Simple and minimal** — no clutter, no overwhelming dashboards; clarity is a feature
- **Always synced** — Supabase real-time backend keeps all devices in sync automatically; no manual backup or export needed

When building features, ask: does this help the user understand their finances better, or does it add friction? Favor clarity and simplicity over completeness.

## Commands

This project uses FVM (Flutter Version Manager) pinned to Flutter 3.38.5 (`.fvmrc`). Prefix Flutter commands with `fvm` if FVM is active.

```bash
# Dependencies
flutter pub get

# Code generation (required after changing env.dart or any @Envied annotated file)
flutter pub run build_runner build --delete-conflicting-outputs

# Lint
flutter analyze

# Tests
flutter test
flutter test test/path/to/test.dart  # single test file

# Run
flutter run -d <device-id>

# Build
flutter build ios
flutter build apk
```

## Environment

Environment variables are managed via `envied`. Before running the app:
1. Create `env/.env.dev` and/or `env/.env.prod` with `SUPABASE_API_URL` and `SUPABASE_API_KEY`
2. Run `build_runner build` to generate `lib/core/config/env.g.dart`

The `Env` singleton in `lib/service_locator.dart` switches between debug/prod based on `kDebugMode`. The `supabase` singleton (also in `service_locator.dart`) is the Supabase client used everywhere.

## Architecture

**Stack**: Flutter + Riverpod (state) + go_router (routing) + Supabase (Postgres + Auth + RLS)

**Module structure** (`lib/modules/`): Features are organized by domain — `expenses/`, `split_bills/`, `contacts/`, `analysis/`, `profile/`. These are currently scaffolded but empty.

**Data access pattern**: Flutter → Supabase SDK → PostgreSQL (with RLS enforced at DB layer)
- Simple reads: direct Supabase queries (`.from('expenses').select(...)`) — but only for bounded datasets
- Analytics/aggregation on unbounded data: always use an RPC — PostgREST silently truncates `.select()` results at 1000 rows
- Paginated lists: use `.range(from, to)` with a `hasMore` flag for infinite scroll (home expenses, collab expenses)
- Complex multi-row writes: RPCs (`supabase.rpc('create_split_bill', params: {...})`)
- RPCs run as `security definer` to enforce business logic across RLS boundaries

**Auth flow**: Google/Apple OAuth → `handle_new_user()` DB trigger fires (creates profile, seeds 11 categories + 2 accounts) → Flutter checks `profile.username` → if null, show blocking username screen → `set_username` RPC → main app

## Database Schema (Supabase)

14 tables across 5 domains. Full specs in `docs/tables/`, ERD in `docs/ERD.md`, RPC catalog in `docs/SUPABASE.md`.

| Domain | Tables |
|--------|--------|
| Identity | `profiles`, `contacts` |
| Organization | `categories`, `accounts`, `groups`, `group_members` |
| Collab | `collabs`, `collab_members` |
| Personal finance | `expenses`, `budgets` |
| Split bills | `split_bills`, `split_bill_shares`, `settlements` |

**Key invariants:**
- **Soft deletes everywhere**: Nearly all tables have `deleted_at timestamptz`. Don't hard-delete records.
- **Frozen FX rates**: Foreign-currency expenses store `conversion_rate` and `home_amount_cents` at entry time. Historical expenses are immutable.
- **Accounts are tags, not balances**: `accounts` has no `current_balance` — it categorizes how money was paid.
- **Activity feed is computed**: No notifications table. The `my_activity_feed` RPC unions across underlying tables on demand.
- **Auto-bidirectional contacts**: Adding a contact atomically creates both A→B and B→A rows.
- **Per-user categories**: Each user has their own category rows; cross-user category references are invalid.
- **Collab expenses live in `expenses`**: No separate table. Tag `collab_id` on the expense row. RLS on `expenses` allows all active collab members to read each other's collab-tagged rows (but write is still owner-only).
- **Collab budget is informational**: `collabs.budget_cents` is a shared total in `home_currency`. Compute remaining as `budget_cents - SUM(expenses.home_amount_cents WHERE collab_id = ...)`. No DB enforcement.

**Key RPCs** (defined on Supabase, called via `supabase.rpc(...)`):
- `home_analytics(p_start, p_end)` — home screen aggregated totals + category spend (immune to 1000-row limit)
- `analysis_summary(p_start, p_end, p_include_collab)` — analysis screen: by-category, by-account, daily buckets
- `collab_summary(p_collab_id)` — collab header + members screen: all-time net spend per member
- `collab_analytics(p_collab_id, p_start, p_end)` — collab analysis screen: breakdowns + daily member buckets
- `create_split_bill` — creates bill + shares + payer expense atomically
- `settle_split_share` — creates settlement + expense rows, updates share status
- `close_collab` — marks collab read-only (no import step needed)
- `set_username` — sets unique username on profile
- `my_activity_feed` — computes recent activity on demand

## Documentation

All design docs live in `docs/`:
- `docs/ARCHITECTURE.md` — stack rationale, data lifecycle diagrams, failure modes
- `docs/SCHEMA.md` — full SQL deployment guide (2,256 lines, 76 statements)
- `docs/SUPABASE.md` — RPC catalog with signatures and descriptions
- `docs/flows/` — user flow walkthroughs (auth, expense logging, split bill, trip, activity feed)
- `docs/tables/` — per-table specs with column definitions and business rules

Read relevant docs before implementing any feature that touches the database layer.

## Freemium Limits

Free tier enforces limits on categories (16 total) and groups (2). Premium removes limits. See `docs/FREEMIUM.md`. When adding features that create user-owned records, check if the relevant table has a freemium cap.
