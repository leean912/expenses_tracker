# Expense Tracker — Design Documentation

This folder contains the complete design specification for the expense tracker app, including database schema, table relationships, business flows, and architectural decisions.

## Project Overview

**What it is**: A cross-platform mobile app for tracking personal monthly expenses, splitting bills with friends, and managing collaborative shared expenses (collabs).

**Target market**: Malaysian users primarily (MYR home currency), expanding to broader Southeast Asia.

**Stack**:
- Frontend: Flutter (iOS, Android, future web/desktop)
- Backend: Supabase (PostgreSQL + Auth + RLS + Edge Functions)
- Auth: Google + Apple sign-in
- State management: Riverpod
- Routing: go_router

**Positioning**: Spending tracker, NOT a personal finance / net-worth app. Users log purchases, the app doesn't reconcile bank balances.

## Design Philosophy

1. **Log purchases, never money movements.** Currency conversions, ATM withdrawals, and bank transfers are NOT logged as expenses. Only goods and services count.
2. **Per-user data isolation via RLS.** Every query filters by `auth.uid()`. No shared workspaces leak data.
3. **Accounts are tags, not balance trackers.** No `current_balance` field — accounts categorize HOW money was paid, not how much remains.
4. **Frozen-rate snapshots.** Every foreign-currency expense stores its conversion rate at entry time. Historical accuracy is preserved.
5. **Activity feed computed from data.** No `notifications` table — events are derived on-demand from existing rows.
6. **Auto-bidirectional contacts.** No friend-request flow — adding someone creates both directions atomically.

## Document Index

### Top-level

| Document | Purpose |
|---|---|
| [README.md](./README.md) | This file — project overview |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | High-level system design and stack rationale |
| [SCHEMA.md](./SCHEMA.md) | Schema SQL deployment guide + section map |
| [ERD.md](./ERD.md) | Entity-relationship diagram + visual schema overview |
| [SUPABASE.md](./SUPABASE.md) | Deployment guide + RPC catalog |
| [FREEMIUM.md](./FREEMIUM.md) | Pricing tiers, free-tier limits, upgrade triggers |

### Per-table specs ([tables/](./tables/))

| Domain | Tables |
|---|---|
| Identity | [profiles](./tables/profiles.md), [contacts](./tables/contacts.md) |
| Organization | [categories](./tables/categories.md), [accounts](./tables/accounts.md), [groups](./tables/groups.md), [group_members](./tables/group_members.md) |
| Collab | [collabs](./tables/collabs.md), [collab_members](./tables/collab_members.md) |
| Personal finance | [expenses](./tables/expenses.md), [budgets](./tables/budgets.md) |
| Split bills | [split_bills](./tables/split_bills.md), [split_bill_shares](./tables/split_bill_shares.md), [settlements](./tables/settlements.md) |

### User flows ([flows/](./flows/))

| Flow | Description |
|---|---|
| [Authentication](./flows/auth.md) | OAuth → username pick → main app |
| [Expense logging](./flows/expense-logging.md) | Add personal expense with category + account |
| [Split bill](./flows/split-bill.md) | Create → settle → dispute lifecycle |
| [Collab](./flows/collab.md) | Create → invite → log → close → import |
| [Activity feed](./flows/activity-feed.md) | How events are computed from data |

## Quick Stats

| Metric | Count |
|---|---|
| Tables | 13 |
| RPCs | 24 |
| RLS policies | 37 |
| Indexes | 35 |
| Triggers | 12 |

## Deferred to V2

These features are intentionally NOT in MVP:

- Image storage (avatars, receipts, collab cover photos)
- Receipt OCR
- Multi-currency settlement (currently uses bill creator's rate for everyone)
- Live FX rate fetching from API
- Community / public collabs
- Push notifications (FCM layer on top of activity feed)
- Offline sync with conflict resolution
- Custom split types (percentage, exact amounts, shares)
- Recurring expenses
- Friend requests with approval
- Custom group admin roles
- Account balance reconciliation
- Bank sync (Plaid/TrueLayer)

When implementing V2 features, refer to this doc set first to understand the existing model before extending.
