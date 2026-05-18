# Tags Feature Plan

**Status**: Planned, not started  
**Scope**: New `tags` table, `tag_id` on expenses + split_bills, tag picker on all expense creation flows, tag filter on export screen, Tags management screen under Settings

---

## Concept

Tags are a **second dimension of classification** orthogonal to categories and accounts:
- **Category** = *what type* of expense (Food, Transport)
- **Account** = *how it was paid* (Maybank, Cash)
- **Tag** = *what purpose/context* (Income Tax Relief, Business, Medical)

One tag spans multiple categories — e.g. "Income Tax Relief" covers both Medical and Education expenses. Primary use case is export filtering.

## Design Decisions

- No icons — tags are name + color only (colored text chips)
- No freemium gate — users can create unlimited tags
- Soft delete with name-based restore — creating a tag with the same name as a soft-deleted tag restores it (case-insensitive match)
- `tag_id` on both `split_bills` header (propagated to payer's expense) and available when settling
- Collab split bills: same behavior as regular split bills
- Tags management screen under Settings in `more_screen.dart` (between Accounts and Budgets)

---

## Step 1 — Supabase: New `tags` table

Run in Supabase SQL Editor:

```sql
CREATE TABLE tags (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name       text        NOT NULL,
  color      text        NOT NULL DEFAULT '#888780',
  sort_order integer     NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

-- RLS
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users manage own tags"
  ON tags FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Index
CREATE INDEX idx_tags_user_id ON tags(user_id) WHERE deleted_at IS NULL;
```

---

## Step 2 — Supabase: Add `tag_id` to `expenses` and `split_bills`

```sql
ALTER TABLE expenses
  ADD COLUMN tag_id uuid REFERENCES tags(id) ON DELETE SET NULL;

ALTER TABLE split_bills
  ADD COLUMN tag_id uuid REFERENCES tags(id) ON DELETE SET NULL;

CREATE INDEX idx_expenses_tag_id ON expenses(tag_id) WHERE deleted_at IS NULL;
```

---

## Step 3 — Supabase: `create_tag` RPC

Logic: case-insensitive check for soft-deleted tag with same name → restore it. Otherwise insert new row.

```sql
CREATE OR REPLACE FUNCTION create_tag(
  p_name  text,
  p_color text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tag_id  uuid;
BEGIN
  -- Restore soft-deleted tag with same name (case-insensitive)
  UPDATE tags
  SET deleted_at = NULL,
      color      = p_color,
      updated_at = now()
  WHERE user_id   = v_user_id
    AND lower(name) = lower(p_name)
    AND deleted_at IS NOT NULL
  RETURNING id INTO v_tag_id;

  IF v_tag_id IS NOT NULL THEN
    RETURN v_tag_id;
  END IF;

  -- Insert new tag
  INSERT INTO tags (user_id, name, color)
  VALUES (v_user_id, p_name, p_color)
  RETURNING id INTO v_tag_id;

  RETURN v_tag_id;
END;
$$;
```

---

## Step 4 — Supabase: Update `create_split_bill` RPC

Add `p_tag_id uuid DEFAULT NULL` parameter. Pass it to:
1. The payer's auto-created expense row (`tag_id = p_tag_id`)
2. The `split_bills` insert (`tag_id = p_tag_id`)

Find the existing RPC in Supabase and add the parameter + two column assignments.

---

## Step 5 — Supabase: Update `settle_split_share` RPC

Add `p_tag_id uuid DEFAULT NULL` parameter. Pass it only to the **settler's** auto-created expense row. Do NOT apply to the payer's income row.

---

## Step 6 — Flutter: New `tags` module

Create the following files:

### `lib/modules/tags/data/models/tag_model.dart`
```dart
class TagModel {
  final String id;
  final String name;
  final String color;
  final int sortOrder;

  const TagModel({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
  });

  factory TagModel.fromJson(Map<String, dynamic> json) => TagModel(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    sortOrder: json['sort_order'] as int,
  );
}
```

### `lib/modules/tags/data/repositories/tag_repository.dart`
- `fetchTags()` → select all where `deleted_at IS NULL`, order by `sort_order, name`
- `createTag(name, color)` → calls `create_tag` RPC
- `deleteTag(id)` → `UPDATE tags SET deleted_at = now() WHERE id = id`

### `lib/modules/tags/providers/tags_provider.dart`
- `tagsProvider` → `AsyncNotifier<List<TagModel>>`, wraps `fetchTags()`
- `pickerTagsProvider` → same as tagsProvider (no freemium filter needed)

### `lib/modules/tags/providers/manage_tags_provider.dart`
- Handles create + soft-delete, invalidates `tagsProvider` on change

### `lib/modules/tags/presentation/screens/tags_screen.dart`
- List of existing tags as colored chips/rows
- FAB or inline form to create a new tag (name + color picker)
- Swipe-to-delete or delete button → soft delete

### `lib/modules/tags/presentation/widgets/tag_picker.dart`
- Reusable chip picker (same pattern as `_CategoryPicker` / `_AccountPicker` in export_screen.dart)
- Shows "None" chip + all user tags as colored chips
- Returns selected `String? tagId`

---

## Step 7 — Flutter: Routing

In `lib/core/routes/routes.dart`:
- Add `const settingsTagsRoute = '/settings/tags';`
- Add route entry pointing to `TagsScreen`

---

## Step 8 — Flutter: More screen

In `lib/modules/home/presentation/screens/more_screen.dart`:

Add after the Accounts `ListTile` (before Budgets):

```dart
const Divider(height: 1, indent: 56, color: AppColors.border),
ListTile(
  leading: const Icon(
    Icons.label_outline_rounded,
    color: AppColors.textSecondary,
  ),
  title: const Text(
    'Tags',
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.textPrimary,
    ),
  ),
  trailing: const Icon(
    Icons.chevron_right_rounded,
    color: AppColors.textTertiary,
  ),
  onTap: () => context.push(settingsTagsRoute),
),
```

---

## Step 9 — Flutter: Export screen

### `lib/modules/export/providers/export_provider.dart`
Add to `ExportFilter` state:
- `selectedTagIds Set<String>?` (null = all tags)

Add methods:
- `toggleTag(String id)`
- `selectAllTags()`

In the export query: if `selectedTagIds != null`, add `.in_('tag_id', selectedTagIds!.toList())` filter.

### `lib/modules/export/presentation/screens/export_screen.dart`
Add a Tags section between Accounts and Sort By:

```dart
// ── Tags ────────────────────────────────────────────────────────────────────
_SectionLabel('Tags'),
const SizedBox(height: AppSpacing.md),
tagsAsync.when(
  loading: () => const _LoadingChips(),
  error: (_, _) => const _ErrorChips('tags'),
  data: (tags) => tags.isEmpty
      ? Text('No tags yet. Create tags in Settings.',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary))
      : _TagPicker(
          tags: tags,
          selectedIds: filter.selectedTagIds,
          onToggle: (id) => ref.read(exportPdfProvider.notifier).toggleTag(id),
          onSelectAll: () => ref.read(exportPdfProvider.notifier).selectAllTags(),
        ),
),
const SizedBox(height: AppSpacing.xxl),
```

`_TagPicker` is the same chip pattern as `_CategoryPicker` but without icon rendering.

---

## Step 10 — Flutter: Add expense form

In the create/edit expense provider and screen:
- Add `tagId String?` to state
- Add tag picker row in the form (optional, below category picker)
- Pass `tag_id: tagId` in the Supabase insert payload

---

## Step 11 — Flutter: Add split bill form

In the create split bill provider and screen:
- Add `tagId String?` to state
- Add tag picker row in the form (optional)
- Pass `p_tag_id: tagId` in the `create_split_bill` RPC call

---

## Step 12 — Flutter: Settle split share

In the settle flow (wherever `settle_split_share` is called):
- Add `tagId String?` to the settlement state/form if there's a confirm sheet
- Pass `p_tag_id: tagId` in the RPC call
- If settle is a one-tap action with no confirmation sheet, skip tag for now (tag defaults to NULL)

---

## Step 13 — Flutter: Collab expense + collab split bill

Same changes as Steps 10 and 11 respectively. Collab expenses go through the same `expenses` table so the tag column is already there after Step 2.

---

## What is NOT changed

- Analysis/charts screens (tags have no analysis dimension)
- Budget tracking
- Activity feed (`my_activity_feed` RPC)
- Auth flow, contacts system
- Settlement display UI (tag is silently stored on expense row)
- Freemium limits (tags are ungated)

---

## Implementation Order

1. Steps 1–5: All Supabase changes first (SQL + RPC updates)
2. Step 6: Flutter tags module (model, repo, providers)
3. Step 7–8: Routing + more_screen entry point
4. Step 9: Export screen (primary use case)
5. Steps 10–13: Wire into all creation flows
