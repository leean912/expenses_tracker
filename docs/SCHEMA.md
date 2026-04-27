# Schema SQL Reference

The complete database schema is in `expense_tracker_schema.sql` (in the project root, alongside this `docs/` folder).

## File Stats

```
13 tables
22 RPCs
36 RLS policies
35 indexes
12 triggers
```

## How to Use

### Fresh Supabase project

1. Create a new Supabase project at supabase.com
2. Open the SQL Editor
3. Paste the entire contents of `expense_tracker_schema.sql`
4. Click Run
5. Verify "Success. No rows returned" — should see 14 tables in Table Editor

For a complete deployment guide including auth provider setup, see [SUPABASE.md](./SUPABASE.md).

### Modifying the schema

When you need to change the schema:

1. **Don't edit the deployed schema directly via the Supabase UI.** Always edit the source SQL file.
2. Update relevant docs in `docs/tables/` and `docs/flows/`.
3. Update the ERD in `expense_tracker_final_erd.png` if structure changes.
4. Test in a staging Supabase project before applying to production.

### Schema Section Map

The SQL file is organized into numbered sections:

```
0.  EXTENSIONS         — Postgres extensions (pgcrypto for gen_random_uuid)
1.  PROFILES           — user accounts
2.  CONTACTS           — friend lists
3.  CATEGORIES         — spending categories (per user)
4.  ACCOUNTS           — payment method tags (per user)
5.  GROUPS             — personal shortcut lists
5b. GROUP_MEMBERS      — who's in each group
6.  COLLABS            — collaborative shared expense workspace
6b. COLLAB_MEMBERS     — collab participants
7.  EXPENSES           — personal expense + income rows
8.  BUDGETS            — spending targets
9.  SPLIT_BILLS        — shared bill records
10. SPLIT_BILL_SHARES  — per-participant shares
11. SETTLEMENTS        — payback history
12. TRIGGERS           — auto-fire functions
13. RPC FUNCTIONS      — 24 callable functions
14. RLS POLICIES       — row-level security per table
15. STORAGE BUCKETS    — V2 deferred (image storage)
```

### V2 deferred sections

The schema includes column placeholders for V2 features (e.g., `avatar_url`, `cover_photo_url`, `receipt_url`). These remain NULL in MVP — when V2 storage buckets are added, the columns will start being populated. No migration needed.

## Per-table Documentation

For details on each table, see the corresponding doc in `docs/tables/`:

- [profiles](./tables/profiles.md)
- [contacts](./tables/contacts.md)
- [categories](./tables/categories.md)
- [accounts](./tables/accounts.md)
- [groups](./tables/groups.md)
- [group_members](./tables/group_members.md)
- [collabs](./tables/collabs.md)
- [collab_members](./tables/collab_members.md)
- [expenses](./tables/expenses.md)
- [budgets](./tables/budgets.md)
- [split_bills](./tables/split_bills.md)
- [split_bill_shares](./tables/split_bill_shares.md)
- [settlements](./tables/settlements.md)
