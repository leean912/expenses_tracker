# tags

User-defined labels for expenses and split bills. Orthogonal to categories and accounts — a tag spans multiple categories (e.g. "Income Tax" covers both Medical and Education expenses).

## Columns

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | NOT NULL | gen_random_uuid() | Primary key |
| `user_id` | uuid | NOT NULL | — | Owner (FK → profiles) |
| `name` | text | NOT NULL | — | Display name |
| `color` | text | NOT NULL | `'#888780'` | Hex color for chip display |
| `is_default` | boolean | NOT NULL | false | True for system-seeded tags (cannot be deleted) |
| `requires_premium` | boolean | NOT NULL | false | True when tag exceeds free tier limit after subscription lapses; unlocks on resubscribe. **Not yet in DB — migration required** (mirrors accounts/categories pattern) |
| `sort_order` | integer | NOT NULL | 0 | Display ordering (defaults first) |
| `created_at` | timestamptz | NOT NULL | now() | — |
| `updated_at` | timestamptz | NOT NULL | now() | — |
| `deleted_at` | timestamptz | NULL | — | Soft-delete timestamp |

## Default Tags

One default tag is seeded for every new user via `handle_new_user()`:

| Name | Color | Purpose |
|------|-------|---------|
| `Income Tax` | `#4A90D9` | Malaysian income tax relief tracking |

Default tags (`is_default = true`) cannot be deleted — no delete icon is shown in the UI, and `deleteTag` in Flutter guards against it.

## Freemium Limits

- **Free tier**: up to 5 custom (non-default) active tags
- **Premium/Lifetime**: unlimited tags
- Soft-deleted tags do not count toward the limit
- `requires_premium = true` tags do not count toward the free limit (so a downgraded user with locked tags can still fill their 5 free slots)
- Restoring a soft-deleted tag (via `create_tag` with same name) bypasses the limit check — restore always happens before the freemium gate
- Premium users creating beyond the 5-slot threshold get `requires_premium = true` on new tags; these lock automatically on subscription lapse

## Constraints

- **Soft deletes**: `deleted_at` is set for deleted tags; restored by `create_tag` RPC (case-insensitive name match)
- **RLS**: `users manage own tags` policy — users can only read/write their own tags

## Relationships

- `expenses.tag_id` → `tags.id` ON DELETE SET NULL
- `split_bills.tag_id` → `tags.id` ON DELETE SET NULL
- Tag propagates from `split_bills` → payer's auto-created expense row (via `create_split_bill` RPC)
- Tag is optionally attached to settler's expense row (via `settle_split_share` RPC, `p_tag_id` param)

## Business Rules

- Tags are name + color only (no icons)
- One tag can span multiple categories (that's the point — e.g. "Income Tax" covers Medical + Education)
- `create_tag` RPC handles soft-delete restore atomically: same name (case-insensitive) → restore instead of insert
- Flutter `UpgradeSheet` is shown with title `'Tags is a Pro feature'` when the free limit is hit
