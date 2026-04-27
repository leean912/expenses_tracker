# Entity-Relationship Diagram

## Visual ERD

The full visual ERD is in `expense_tracker_final_erd.png` (in the project root or `docs/` folder).

## Table Inventory

```
14 tables total, organized into 5 domains:

Identity (2)
├── profiles          — user account, settings, subscription tier
└── contacts          — friend list (auto-bidirectional)

Organization (4)
├── categories        — per-user spending categories (with 11 defaults seeded)
├── accounts          — payment method tags (with Cash + Bank seeded)
├── groups            — personal shortcut lists for split bill participants
└── group_members     — who's in each group (only creator sees the group)

Collab (2)
├── collabs           — collaborative shared expense workspace
└── collab_members    — who's in the collab

Personal Finance (2)
├── expenses          — all personal expense + income rows
└── budgets           — monthly/weekly/yearly budget targets per category

Split Bills (3)
├── split_bills       — shared bill records
├── split_bill_shares — per-participant share + settlement status
└── settlements       — immutable history of payback events
```

## Key Relationships

### Identity domain

```
profiles (1) ────< contacts (M)        owner_id
profiles (1) ────< contacts (M)        friend_id
```

Each contact row has both an `owner_id` (whose contact list this is) and a `friend_id` (who is the friend). Adding a contact creates two rows: A→B and B→A.

### Organization domain

```
profiles (1) ────< categories (M)
profiles (1) ────< accounts (M)
profiles (1) ────< groups (M)          created_by
groups (1) ──────< group_members (M)
profiles (1) ────< group_members (M)   user_id
```

All organizational tables are owned by a single user. Groups have a creator-only visibility model — the people inside a group don't know they're in someone's group list.

### Collab domain

```
profiles (1) ────< collabs (M)            owner_id
collabs (1) ─────< collab_members (M)
profiles (1) ────< collab_members (M)     user_id
```

A collab can have many members (the owner is auto-added as a member with `role='owner'`). Collab expenses live in the `expenses` table tagged with `collab_id` — there is no separate collab_expenses table.

### Personal finance domain

```
profiles (1) ────< expenses (M)
categories (0..1) < expenses (M)       category_id
accounts (0..1) ─< expenses (M)        account_id
collabs (0..1) ───< expenses (M)        collab_id
profiles (1) ────< budgets (M)
categories (0..1) < budgets (M)        category_id (null = overall budget)
```

Expenses are the heart of the app. Each row optionally references a category (their own), an account (their own), and/or a trip. Budgets target a category (or all spending if `category_id IS NULL`).

**Cross-domain links from expenses**:
```
expenses.source_split_bill_id  → split_bills(id)
expenses.source_settlement_id  → settlements(id)
expenses.collab_id             → collabs(id)   (NULL for non-collab expenses)
```

These let analytics tell where each row originated:
- `source = 'manual'` — user typed it in (includes collab expenses)
- `source = 'split_payer'` — auto-created when split bill made (creator paid full)
- `source = 'settlement'` — auto-created when share was settled

### Split bills domain

```
profiles (1) ────< split_bills (M)         created_by
profiles (1) ────< split_bills (M)         paid_by
collabs (0..1) ───< split_bills (M)         collab_id (optional tag)
groups (0..1) ───< split_bills (M)         group_id (optional tag)
categories (0..1)< split_bills (M)         category_id (creator's category)

split_bills (1) ─< split_bill_shares (M)
profiles (1) ────< split_bill_shares (M)   user_id
split_bill_shares (0..1) > settlements (M) settlement_id

split_bills (1) ─< settlements (M)
profiles (1) ────< settlements (M)         from_user_id
profiles (1) ────< settlements (M)         to_user_id
```

A split bill has multiple shares (one per participant). When a participant settles, a settlement row is created and linked to the share. Settlements are immutable — to "unsettle," the row is soft-deleted (`deleted_at IS NOT NULL`).

## Data Flow Diagram

How data flows when key actions happen:

### Create a split bill in foreign currency

```
Alice (in Japan) creates "Dinner ¥12,000" split with Bob (¥4000)
        │
        ▼
create_split_bill RPC
        │
        ├──► INSERT split_bills
        │       (currency='JPY', conversion_rate=30,
        │        home_amount_cents=40000, home_currency='MYR')
        │
        ├──► INSERT split_bill_shares (Alice: ¥4000, Bob: ¥4000, Charlie: ¥4000)
        │
        └──► INSERT expenses (Alice's payer expense)
                (amount: ¥12000, home_amount: RM 400, source: 'split_payer')
```

### Bob settles his share

```
Bob taps "Mark as settled"
        │
        ▼
settle_split_share RPC
        │
        ├──► Reads bill conversion (30, MYR)
        ├──► Computes Bob's share home cents: ¥4000 / 30 = RM 133.33
        │
        ├──► INSERT settlements (Bob → Alice, ¥4000)
        │
        ├──► INSERT expenses
        │       Bob's expense: ¥4000, RM 133.33, his category, his account
        │
        ├──► INSERT expenses
        │       Alice's income: ¥4000, RM 133.33, bill's category
        │
        └──► UPDATE split_bill_shares (status='settled', settled_at=now())
```

### Collab close

```
Alice (owner) closes collab "Japan 2026"
        │
        ▼
close_collab RPC
        └──► UPDATE collabs (status='closed', closed_at=now())

No import needed. Expenses were logged directly into the
expenses table with collab_id from the start.
```

## Cardinality Summary

| Relationship | Type |
|---|---|
| profile → contacts | 1 to many (as both owner and friend) |
| profile → categories | 1 to many (auto-seeded with 11) |
| profile → accounts | 1 to many (auto-seeded with 2) |
| profile → groups | 1 to many (creator) |
| group → group_members | 1 to many |
| profile → collabs | 1 to many (as owner) |
| collab → collab_members | 1 to many |
| collab → expenses | 1 to many (via collab_id tag) |
| profile → expenses | 1 to many |
| profile → budgets | 1 to many |
| split_bill → split_bill_shares | 1 to many (one per participant) |
| split_bill_share → settlement | 0 or 1 |
| split_bill → settlements | 1 to many |

## Foreign Key Cascade Behavior

| FK | Behavior on parent delete |
|---|---|
| Most user_id refs to profiles | `ON DELETE CASCADE` (delete user = wipe their data) |
| expenses.category_id | `ON DELETE SET NULL` (deleting category doesn't lose expense) |
| expenses.account_id | `ON DELETE SET NULL` |
| expenses.collab_id | `ON DELETE SET NULL` (collab deleted → expense stays, collab_id nulled) |
| split_bills.group_id | `ON DELETE SET NULL` |
| split_bills.category_id | `ON DELETE SET NULL` |
| split_bill_shares.split_bill_id | `ON DELETE CASCADE` |
| settlements.split_bill_id | `ON DELETE CASCADE` |

## Indexes Strategy

35 indexes total, with these purposes:

- **User-isolation lookups** (`*_user_*` indexes): Speed up RLS-filtered queries
- **Date-range queries** (`*_date_*` indexes): For monthly/yearly analytics
- **Status filters** (e.g., `where status = 'pending'`): Partial indexes excluding archived/deleted
- **Source tracking** (`*_source_*`): Trace expenses back to their split bill / trip / settlement origin

Almost all indexes include `WHERE deleted_at IS NULL` to keep them lean.
