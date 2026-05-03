# profiles

The user account table. Every authenticated user has exactly one profile row, created automatically by the `handle_new_user()` trigger when an `auth.users` row is created.

## Purpose

Store user identity, preferences, and subscription state. This is the "root" table — every other user-owned table FK references `profiles.id`.

## Schema

```sql
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  username text unique
    check (username is null or username ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null,
  avatar_url text,
  default_currency text not null default 'MYR',
  subscription_tier text not null default 'free'
    check (subscription_tier in ('free', 'premium', 'lifetime')),
  subscription_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

## Columns

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK, also FK to `auth.users(id)`. Cascades on auth user delete. |
| `email` | text | From OAuth provider. Unique across all users. |
| `username` | text | User-chosen handle. NULL until user picks one in onboarding. Unique. Lowercase, 3-20 chars, allows digits + underscore + any starting char. Immutable in MVP. |
| `display_name` | text | Human-readable name. From OAuth or fallback to email prefix. Editable. |
| `avatar_url` | text | NULL in MVP (V2 feature). |
| `default_currency` | text | ISO code (default 'MYR'). User's home currency. |
| `subscription_tier` | text | 'free', 'premium', or 'lifetime'. |
| `subscription_expires_at` | timestamptz | NULL for free + lifetime. Set when premium subscription is active. |

## Auto-creation flow

When a user signs in via Google/Apple for the first time:

```
1. Supabase creates auth.users row
2. Trigger trg_on_auth_user_created fires
3. handle_new_user() function runs:
   - Inserts profiles row (with username = NULL)
   - Seeds 11 categories with is_default = true
   - Seeds 2 accounts: Cash + Bank in user's currency
4. Flutter detects profiles.username IS NULL → routes to "Pick username" screen
```

## Username constraints

- Format: `^[a-z0-9_]{3,20}$`
- Length: 3-20 chars
- Lowercase only
- Allowed chars: a-z, 0-9, underscore
- Any of the above can appear at the start

The DB-level check constraint enforces format. The `set_username` RPC additionally:
- Checks uniqueness (raises 'username_taken' hint)
- Refuses to change once set (raises 'username_immutable' hint)

`check_username_available(p_username)` provides live validation during signup form typing.

## Subscription state machine

```
free ─────────┐                    
   │          │                    
   ▼          ▼                    
premium ──► lifetime               
   │                                
   ▼                                
free (when subscription_expires_at < now())
```

Flutter checks `subscription_expires_at` on app launch. If past expiry, the app sets `tier = 'free'`. Lifetime never expires (`subscription_expires_at IS NULL`).

## RLS policies

```sql
create policy profile_self on profiles for all
  using (id = auth.uid()) with check (id = auth.uid());

create policy profile_lookup on profiles for select
  using (auth.uid() is not null);
```

Two policies:
- **profile_self**: User can do anything to their own profile
- **profile_lookup**: Any authenticated user can READ any profile (needed for username lookups and contact display)

The lookup policy reveals only public-safe data. Email is unique-checked but visible only when intentionally shared (via direct query like `add_contact`).

## Relationships

- One `profiles` → many of almost every other table (the "owner" relationship)
- One `profiles` → many `contacts` (as `owner_id` AND as `friend_id`)
- One `profiles` → many `collab_members`, `group_members`, `split_bill_shares`

## Common queries

```dart
// Get current user's profile
final profile = await supabase.from('profiles').select().single();

// Look up a user by username (for add_contact UX)
final user = await supabase.from('profiles')
  .select('id, username, display_name, avatar_url')
  .eq('username', 'alice')
  .maybeSingle();

// Update display name
await supabase.from('profiles').update({
  'display_name': 'Alice Tan',
}).eq('id', currentUserId);
```

## Common mistakes to avoid

1. **Don't write to `profiles` directly during signup** — let the trigger handle it. Writing manually causes a duplicate-key error if the trigger has already run.

2. **Don't use email as the user identifier** in Flutter. Use `auth.uid()` (UUID). Email can change in V2; UUID is stable.

3. **Don't show `profiles.email` in public UI.** Email is sensitive. Use `display_name` and `username` everywhere.
