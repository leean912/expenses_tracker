# categories

Per-user spending categories. Each user has their own categories (auto-seeded with 11 defaults on signup).

## Purpose

Categorize expenses for analytics ("how much did I spend on Food this month?"). Categories are per-user — Alice's "Food" and Bob's "Food" are different rows with different IDs.

## Schema

```sql
create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  icon text not null default 'category',
  color text not null default '#888888',
  is_default boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `user_id` | uuid | Owner |
| `name` | text | Display name (e.g., "Food", "Transport") |
| `icon` | text | Material icon name (e.g., "restaurant", "directions_car") |
| `color` | text | Hex color (e.g., "#E85D24") |
| `is_default` | boolean | True for auto-seeded defaults; false for user-created customs |
| `sort_order` | integer | Display order |
| `deleted_at` | timestamptz | Soft delete |

## Default seeded categories

Auto-created via `handle_new_user()` trigger on signup:

| Name | Icon | Color | Sort |
|---|---|---|---|
| Food | restaurant | #E85D24 | 1 |
| Transport | directions_car | #378ADD | 2 |
| Shopping | shopping_bag | #D4537E | 3 |
| Bills | receipt_long | #BA7517 | 4 |
| Entertainment | movie | #7F77DD | 5 |
| Health | favorite | #E24B4A | 6 |
| Travel | flight | #1D9E75 | 7 |
| Education | school | #185FA5 | 8 |
| Gifts | redeem | #F0997B | 9 |
| Other | category | #888780 | 10 |
| Trip | luggage | #00838F | 11 |

These cover the common Malaysian spending categories.

## Custom categories (freemium)

Users can add custom categories via `create_custom_category` RPC. Limit:

- **Free tier**: 5 custom categories (= 16 total when including defaults)
- **Premium tier**: unlimited

When the limit is reached, RPC raises an exception with `hint = 'upgrade_required'`. Flutter should show the upgrade screen.

```dart
try {
  await supabase.rpc('create_custom_category', params: {
    'p_name': 'Coffee',
    'p_icon': 'local_cafe',
    'p_color': '#6F4E37',
  });
} on PostgrestException catch (e) {
  if (e.hint == 'upgrade_required') {
    showUpgradeSheet();
  }
}
```

## RLS policies

```sql
alter table categories enable row level security;
create policy cat_select on categories for select using (user_id = auth.uid());
create policy cat_insert on categories for insert with check (user_id = auth.uid());
create policy cat_update on categories for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
```

Each user only sees their own categories. No cross-user access.

## Used by

- `expenses.category_id` (nullable, ON DELETE SET NULL)
- `expenses.category_id` covers both personal and collab expenses (same table)
- `split_bills.category_id` (creator's category, ON DELETE SET NULL)
- `budgets.category_id` (nullable, NULL = overall budget)

When a category is deleted (soft), all references become NULL. Expenses don't disappear — they just become "Uncategorized."

## Common queries

```dart
// My active categories
final categories = await supabase.from('categories')
  .select()
  .is_('deleted_at', null)
  .order('sort_order');

// My custom categories count (for limit UI)
final customCount = await supabase.from('categories')
  .select('*', const FetchOptions(count: CountOption.exact))
  .eq('is_default', false)
  .is_('deleted_at', null)
  .count();
```

## Editing rules

**Defaults can be edited** but their `is_default` stays true (so they're treated as defaults for limit-counting purposes).

**Defaults can be soft-deleted** but it's user-friendly to warn first ("This is a default category. Delete anyway?").

**Custom categories** behave like defaults for everything except they count toward the 5-custom limit.

## Common mistakes

1. **Don't hardcode category IDs in Flutter.** They're user-specific UUIDs. Always look up by name + user, or store the ID after fetch.

2. **Don't assume the user has a category named "Food."** They might rename or delete it. Use the ID after first fetch.

3. **Don't allow Flutter to insert categories directly.** Use `create_custom_category` RPC so the freemium limit is enforced.
