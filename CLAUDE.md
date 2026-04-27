# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
- Simple reads: direct Supabase queries (`.from('expenses').select(...)`)
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
