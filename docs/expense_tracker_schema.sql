-- ═══════════════════════════════════════════════════════════════════
-- EXPENSE TRACKER — COMPLETE SUPABASE SCHEMA
-- ═══════════════════════════════════════════════════════════════════
-- MVP v1.0 — locked architecture
-- Flutter + Supabase, personal offline, splits online
-- Paste this into the Supabase SQL editor in order.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- 0. EXTENSIONS
-- ═══════════════════════════════════════════════════════════════════
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";


-- ═══════════════════════════════════════════════════════════════════
-- 1. PROFILES
-- Extends auth.users with app-specific fields.
-- Auto-created on signup via trigger (see section 15).
-- ═══════════════════════════════════════════════════════════════════
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

create index idx_profiles_email on profiles(email);
create index idx_profiles_username on profiles(username) where username is not null;
create index idx_profiles_subscription on profiles(subscription_tier)
  where subscription_tier <> 'free';


-- ═══════════════════════════════════════════════════════════════════
-- 2. CONTACTS — user's friend list
-- ═══════════════════════════════════════════════════════════════════
create table contacts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  friend_id uuid not null references profiles(id) on delete cascade,
  nickname text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(owner_id, friend_id),
  check (owner_id <> friend_id)
);

create index idx_contacts_owner on contacts(owner_id);


-- ═══════════════════════════════════════════════════════════════════
-- 3. CATEGORIES
-- Auto-seeded on profile creation (see section 13).
-- ═══════════════════════════════════════════════════════════════════
create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  icon text not null default 'receipt',
  color text not null default '#888888',
  is_default boolean not null default false,
  requires_premium boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_categories_user_active on categories(user_id, sort_order) where deleted_at is null;
create unique index idx_categories_user_name_unique on categories(user_id, lower(name)) where deleted_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 4. ACCOUNTS — user's payment methods / money sources (tag only, no balance)
-- Tracks WHERE money was spent from (Maybank, Cash, CIMB Credit, etc.)
-- Auto-seeded with Cash + Bank on profile creation.
-- Free tier: 5 custom accounts; Premium: unlimited.
-- ═══════════════════════════════════════════════════════════════════
create table accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  account_type text not null
    check (account_type in ('cash', 'bank', 'credit_card', 'investment', 'wallet', 'loan', 'other')),
  icon text not null default 'account_balance_wallet',
  color text not null default '#378ADD',
  currency text not null default 'MYR',
  is_archived boolean not null default false,
  requires_premium boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_accounts_user_active on accounts(user_id, sort_order)
  where deleted_at is null and is_archived = false;

create index idx_accounts_user_all on accounts(user_id, sort_order)
  where deleted_at is null;

create unique index idx_accounts_user_name_unique on accounts(user_id, lower(name)) where deleted_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 5. GROUPS — personal shortcut lists for recurring split participants
-- Only visible to the creator. Group members don't know they're in it.
-- Pure UX convenience to pre-fill participants when creating splits.
-- Free tier: 2 groups; Premium: unlimited.
-- ═══════════════════════════════════════════════════════════════════
create table groups (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references profiles(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  icon text not null default 'group',
  color text not null default '#378ADD',
  requires_premium boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_groups_creator on groups(created_by) where deleted_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 5b. GROUP_MEMBERS — people in the creator's group
-- Each member must be in the creator's contacts (validated by RPC).
-- ═══════════════════════════════════════════════════════════════════
create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  removed_at timestamptz,
  unique (group_id, user_id)
);

create index idx_group_members_group on group_members(group_id)
  where removed_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 6. COLLABS
-- Shared expense workspace. Members log expenses tagged with collab_id
-- directly in the expenses table — no separate collab_expenses table.
-- Lifecycle: active → closed (read-only). No import step.
-- ═══════════════════════════════════════════════════════════════════
create table collabs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  description text,
  cover_photo_url text,
  start_date date,
  end_date date,
  currency text not null default 'MYR',              -- collab's primary currency (e.g. JPY)
  home_currency text not null default 'MYR',         -- owner's home currency at creation (frozen)
  exchange_rate numeric(20, 10),                     -- 1 home_currency = X collab_currency. Null if same currency.
  budget_cents bigint,                               -- optional shared total budget in home_currency
  status text not null default 'active'
    check (status in ('active', 'closed')),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (end_date is null or start_date is null or end_date >= start_date),
  check (
    (currency = home_currency and exchange_rate is null)
    or (currency <> home_currency and exchange_rate is not null and exchange_rate > 0)
  )
);

create index idx_collabs_owner_active on collabs(owner_id, start_date desc) where deleted_at is null;
create index idx_collabs_status on collabs(status) where deleted_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 6b. COLLAB_MEMBERS — participants in a collab
-- Owner is auto-added with role='owner' via trigger.
-- ═══════════════════════════════════════════════════════════════════
create table collab_members (
  id uuid primary key default gen_random_uuid(),
  collab_id uuid not null references collabs(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  personal_budget_cents bigint,                                -- optional personal spending cap in collab's home_currency
  unique (collab_id, user_id)
);

create index idx_collab_members_user_active on collab_members(user_id) where left_at is null;
create index idx_collab_members_collab_active on collab_members(collab_id) where left_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 7. EXPENSES — personal expense + income records
-- Fully owned by a single user.
-- Rows may be manually created OR auto-created from split settlements.
-- Collab expenses are tagged with collab_id; all active collab members
-- can read them via RLS (see section 15e), but write is owner-only.
-- ═══════════════════════════════════════════════════════════════════
create table expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,

  -- Classification
  type text not null default 'expense' check (type in ('expense', 'income')),
  source text not null default 'manual'
    check (source in ('manual', 'settlement', 'split_payer')),
  source_split_bill_id uuid,       -- FK added after split_bills table exists
  source_settlement_id uuid,       -- FK added after settlements table exists

  category_id uuid references categories(id) on delete set null,
  collab_id uuid references collabs(id) on delete set null,   -- null = personal expense
  account_id uuid references accounts(id) on delete set null,

  -- Amount — always positive; type column determines +/- in UI
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null,

  -- Home currency conversion, frozen at time of entry
  home_amount_cents bigint,
  home_currency text,
  conversion_rate numeric(20, 10),  -- 1 home_currency = X this.currency (snapshot at entry)

  note text,
  expense_date date not null default current_date,

  -- Location via Google Places
  google_place_id text,
  place_name text,
  latitude double precision,
  longitude double precision,

  receipt_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  archived_at timestamptz,
  archived_reason text
);

create index idx_expenses_user_date on expenses(user_id, expense_date desc)
  where deleted_at is null and archived_at is null;

create index idx_expenses_user_created on expenses(user_id, created_at desc)
  where deleted_at is null and archived_at is null;

create index idx_expenses_collab on expenses(collab_id, expense_date desc)
  where collab_id is not null and deleted_at is null and archived_at is null;

create index idx_expenses_category on expenses(category_id)
  where deleted_at is null and archived_at is null;

create index idx_expenses_place on expenses(google_place_id)
  where google_place_id is not null and deleted_at is null;

create index idx_expenses_source_split on expenses(source_split_bill_id)
  where source_split_bill_id is not null;

create index idx_expenses_account on expenses(account_id, expense_date desc)
  where account_id is not null and deleted_at is null and archived_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 8. BUDGETS
-- ═══════════════════════════════════════════════════════════════════
create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  category_id uuid references categories(id) on delete cascade,
  limit_cents bigint not null check (limit_cents > 0),
  period text not null default 'monthly' check (period in ('daily', 'weekly', 'monthly', 'yearly')),
  currency text not null default 'MYR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_budgets_user_active on budgets(user_id) where deleted_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 9. SPLIT_BILLS — shared bill records
-- ═══════════════════════════════════════════════════════════════════
create table split_bills (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references profiles(id) on delete cascade,
  paid_by uuid not null references profiles(id) on delete cascade,

  total_amount_cents bigint not null check (total_amount_cents > 0),
  currency text not null default 'MYR',

  -- Home currency conversion snapshot (from creator's perspective, frozen at creation)
  -- All participants see the bill in this home currency using this rate.
  home_amount_cents bigint,
  home_currency text,
  conversion_rate numeric(20, 10),  -- 1 home_currency = X this.currency

  note text,
  expense_date date not null default current_date,

  category_id uuid references categories(id) on delete set null,
  collab_id uuid references collabs(id) on delete set null,   -- optional: tag bill to a collab
  group_id uuid references groups(id) on delete set null,

  google_place_id text,
  place_name text,
  latitude double precision,
  longitude double precision,
  receipt_url text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index idx_split_bills_created_by on split_bills(created_by)
  where deleted_at is null;

create index idx_split_bills_paid_by on split_bills(paid_by)
  where deleted_at is null;

create index idx_split_bills_collab on split_bills(collab_id, expense_date desc)
  where collab_id is not null and deleted_at is null;

create index idx_split_bills_group on split_bills(group_id, expense_date desc)
  where group_id is not null and deleted_at is null;


-- Now add the deferred FK from expenses -> split_bills
alter table expenses
  add constraint fk_expenses_source_split_bill
  foreign key (source_split_bill_id) references split_bills(id) on delete set null;


-- ═══════════════════════════════════════════════════════════════════
-- 10. SPLIT_BILL_SHARES — per-participant shares + status
-- ═══════════════════════════════════════════════════════════════════
create table split_bill_shares (
  id uuid primary key default gen_random_uuid(),
  split_bill_id uuid not null references split_bills(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,

  share_cents bigint not null check (share_cents >= 0),
  split_method text not null default 'equal'
    check (split_method in ('equal', 'percentage', 'exact', 'shares')),

  status text not null default 'pending'
    check (status in ('pending', 'acknowledged', 'disputed', 'settled', 'cancelled')),
  dispute_reason text,

  acknowledged_at timestamptz,
  settled_at timestamptz,
  settlement_id uuid,  -- FK added after settlements table

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  archived_reason text,

  unique (split_bill_id, user_id)
);

create index idx_shares_user_status on split_bill_shares(user_id, status)
  where archived_at is null;

create index idx_shares_bill on split_bill_shares(split_bill_id)
  where archived_at is null;


-- ═══════════════════════════════════════════════════════════════════
-- 12. SETTLEMENTS — immutable payback history
-- ═══════════════════════════════════════════════════════════════════
create table settlements (
  id uuid primary key default gen_random_uuid(),
  split_bill_id uuid references split_bills(id) on delete set null,
  split_bill_share_id uuid references split_bill_shares(id) on delete set null,

  from_user_id uuid not null references profiles(id) on delete cascade,
  to_user_id uuid not null references profiles(id) on delete cascade,

  amount_cents bigint not null check (amount_cents > 0),
  currency text not null default 'MYR',

  note text,
  settled_on date not null default current_date,

  created_at timestamptz not null default now(),
  deleted_at timestamptz,  -- for "unsettle" toggle flow

  check (from_user_id <> to_user_id)
);

create index idx_settlements_from on settlements(from_user_id, settled_on desc)
  where deleted_at is null;

create index idx_settlements_to on settlements(to_user_id, settled_on desc)
  where deleted_at is null;

create index idx_settlements_bill on settlements(split_bill_id)
  where deleted_at is null;


-- Now add deferred FKs
alter table split_bill_shares
  add constraint fk_shares_settlement
  foreign key (settlement_id) references settlements(id) on delete set null;

alter table expenses
  add constraint fk_expenses_source_settlement
  foreign key (source_settlement_id) references settlements(id) on delete set null;


-- ═══════════════════════════════════════════════════════════════════
-- 13. TRIGGERS
-- ═══════════════════════════════════════════════════════════════════

-- 13a. Auto-update updated_at on every row modification
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_profiles_updated_at
  before update on profiles
  for each row execute function set_updated_at();

create trigger trg_categories_updated_at
  before update on categories
  for each row execute function set_updated_at();

create trigger trg_accounts_updated_at
  before update on accounts
  for each row execute function set_updated_at();

create trigger trg_groups_updated_at
  before update on groups
  for each row execute function set_updated_at();

create trigger trg_collabs_updated_at
  before update on collabs
  for each row execute function set_updated_at();

create trigger trg_expenses_updated_at
  before update on expenses
  for each row execute function set_updated_at();

create trigger trg_budgets_updated_at
  before update on budgets
  for each row execute function set_updated_at();

create trigger trg_split_bills_updated_at
  before update on split_bills
  for each row execute function set_updated_at();

create trigger trg_shares_updated_at
  before update on split_bill_shares
  for each row execute function set_updated_at();


-- 13c. Auto-add collab owner as collab member when a collab is created
create or replace function handle_new_collab()
returns trigger language plpgsql security definer as $$
begin
  insert into collab_members (collab_id, user_id, role, joined_at)
  values (new.id, new.owner_id, 'owner', now());
  return new;
end;
$$;

create trigger trg_on_collab_created
  after insert on collabs
  for each row execute function handle_new_collab();


-- 13b. Auto-create profile + seed default categories + default accounts when a user signs up
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$ 
declare
  new_profile_id uuid;
  default_cats text[][] := array[
    -- [name, icon, color]
    array['Food',          'restaurant',     '#E85D24'],
    array['Transport',     'directions_car', '#378ADD'],
    array['Shopping',      'shopping_bag',   '#D4537E'],
    array['Bills',         'receipt_long',   '#BA7517'],
    array['Entertainment', 'movie',          '#7F77DD'],
    array['Health',        'favorite',       '#E24B4A'],
    array['Travel',        'flight',         '#1D9E75'],
    array['Education',     'school',         '#185FA5'],
    array['Gifts',         'redeem',         '#F0997B'],
    array['Other',         'category',       '#888780'],
    array['Trip',          'luggage',        '#00838F']
  ];
  default_accts text[][] := array[
    -- [name, type, icon, color]
    array['Cash', 'cash', 'payments', '#4CAF50'],
    array['Bank', 'bank', 'account_balance', '#378ADD']
  ];
  v_currency text;
  i integer;
begin
  v_currency := coalesce(new.raw_user_meta_data->>'default_currency', 'MYR');

  -- Create the profile row
  -- For Google: full_name comes in raw_user_meta_data->>'full_name'
  -- For Apple: name may or may not be provided depending on user choice
  -- Email is always available from auth.users.email
  insert into profiles (id, email, display_name, avatar_url, default_currency)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'display_name',
      split_part(coalesce(new.email, 'User'), '@', 1)  -- fallback to email prefix
    ),
    new.raw_user_meta_data->>'avatar_url',
    v_currency
  )
  returning id into new_profile_id;

  -- Seed default categories
  for i in 1..array_length(default_cats, 1) loop
    insert into categories (user_id, name, icon, color, is_default, sort_order)
    values (
      new_profile_id,
      default_cats[i][1],
      default_cats[i][2],
      default_cats[i][3],
      true,
      i
    );
  end loop;

  -- Seed default accounts (Cash + Bank)
  for i in 1..array_length(default_accts, 1) loop
    insert into accounts (user_id, name, account_type, icon, color, currency, sort_order)
    values (
      new_profile_id,
      default_accts[i][1],
      default_accts[i][2],
      default_accts[i][3],
      default_accts[i][4],
      v_currency,
      i
    );
  end loop;

  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();


-- ═══════════════════════════════════════════════════════════════════
-- 14. RPC FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

-- 14a. Change home currency (atomic archive + switch)
create or replace function change_home_currency(p_new_currency text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_old_currency text;
  v_archived_expenses integer;
  v_archived_shares integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select default_currency into v_old_currency
  from profiles where id = v_user_id;

  -- Archive personal expenses
  update expenses
  set archived_at = now(), archived_reason = 'currency_change'
  where user_id = v_user_id
    and archived_at is null
    and deleted_at is null;
  get diagnostics v_archived_expenses = row_count;

  -- Archive user's split shares (their view only)
  update split_bill_shares
  set archived_at = now(), archived_reason = 'currency_change'
  where user_id = v_user_id
    and archived_at is null;
  get diagnostics v_archived_shares = row_count;

  -- Soft-delete current budgets (currency-specific)
  update budgets
  set deleted_at = now()
  where user_id = v_user_id
    and deleted_at is null;

  -- Update home currency
  update profiles
  set default_currency = p_new_currency
  where id = v_user_id;

  return jsonb_build_object(
    'old_currency', v_old_currency,
    'new_currency', p_new_currency,
    'archived_expenses', v_archived_expenses,
    'archived_shares', v_archived_shares,
    'archived_at', now()
  );
end;
$$;


-- 14a-2. Set username for the current user (immutable in MVP once set)
-- Called after first sign-in via the "pick username" onboarding screen.
create or replace function set_username(p_username text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_username text;
  v_normalized text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_username is null or length(trim(p_username)) = 0 then
    raise exception 'Username is required';
  end if;

  v_normalized := lower(trim(p_username));

  -- Validate format (3-20 chars, lowercase + digits + underscore, any starting char)
  if not (v_normalized ~ '^[a-z0-9_]{3,20}$') then
    raise exception 'Invalid username format. Use 3-20 lowercase letters, digits, or underscores.'
      using errcode = 'P0001', hint = 'invalid_format';
  end if;

  -- Get current username
  select username into v_existing_username from profiles where id = v_user_id;

  -- MVP: username is immutable once set
  if v_existing_username is not null then
    raise exception 'Username already set. Changing it is not yet supported.'
      using errcode = 'P0001', hint = 'username_immutable';
  end if;

  -- Check uniqueness
  if exists (select 1 from profiles where username = v_normalized) then
    raise exception 'Username already taken'
      using errcode = 'P0001', hint = 'username_taken';
  end if;

  update profiles set username = v_normalized where id = v_user_id;

  return jsonb_build_object('username', v_normalized);
end;
$$;


-- 14a-3. Check if a username is available (for live validation in signup form)
-- Returns true if available, false if taken or invalid format.
create or replace function check_username_available(p_username text)
returns boolean
language plpgsql
security definer
as $$
declare
  v_normalized text;
begin
  if p_username is null then
    return false;
  end if;

  v_normalized := lower(trim(p_username));

  -- Validate format first
  if not (v_normalized ~ '^[a-z0-9_]{3,20}$') then
    return false;
  end if;

  -- Check if taken
  return not exists (select 1 from profiles where username = v_normalized);
end;
$$;


-- 14b. Create a split bill with shares + auto-create payer's expense
-- MVP restriction: the creator must also be the payer (paid_by = auth.uid()).
-- This avoids cross-user category pollution in the auto-created expense.
-- V2 may lift this restriction with a separate per-user categorization flow.
create or replace function create_split_bill(
  p_paid_by uuid,
  p_total_amount_cents bigint,
  p_currency text,
  p_note text,
  p_expense_date date,
  p_category_id uuid,
  p_collab_id uuid,
  p_google_place_id text,
  p_place_name text,
  p_latitude double precision,
  p_longitude double precision,
  p_receipt_url text,
  p_shares jsonb,
  p_group_id uuid default null,
  -- Home-currency conversion snapshot (optional; Flutter computes from collab rate or prompts inline)
  p_home_amount_cents bigint default null,
  p_home_currency text default null,
  p_conversion_rate numeric default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_bill_id uuid;
  v_expense_id uuid;
  v_share record;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- MVP: creator must be the payer. Ensures their own category
  -- lands on their own auto-created expense row.
  if p_paid_by <> v_user_id then
    raise exception 'MVP: only the payer can create a split bill. Have the actual payer create it.';
  end if;

  -- Validate that p_category_id (if provided) belongs to the creator
  if p_category_id is not null then
    if not exists (
      select 1 from categories
      where id = p_category_id
        and user_id = v_user_id
        and deleted_at is null
    ) then
      raise exception 'Category does not belong to you';
    end if;
  end if;

  -- Validate that p_group_id (if provided) belongs to the creator
  if p_group_id is not null then
    if not exists (
      select 1 from groups
      where id = p_group_id
        and created_by = v_user_id
        and deleted_at is null
    ) then
      raise exception 'Group does not belong to you';
    end if;
  end if;

  -- Validate that p_collab_id (if provided) is one the creator is an active member of
  if p_collab_id is not null then
    if not exists (
      select 1 from collab_members
      where collab_id = p_collab_id
        and user_id = v_user_id
        and left_at is null
    ) then
      raise exception 'You are not a member of this collab';
    end if;
  end if;

  -- Create the split bill (with conversion snapshot from creator's perspective)
  insert into split_bills (
    created_by, paid_by, total_amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    note, expense_date, category_id, collab_id, group_id,
    google_place_id, place_name, latitude, longitude, receipt_url
  ) values (
    v_user_id, p_paid_by, p_total_amount_cents, p_currency,
    p_home_amount_cents, p_home_currency, p_conversion_rate,
    p_note, p_expense_date, p_category_id, p_collab_id, p_group_id,
    p_google_place_id, p_place_name, p_latitude, p_longitude, p_receipt_url
  ) returning id into v_bill_id;

  -- Insert shares, validating each participant is in the creator's contacts
  for v_share in select * from jsonb_to_recordset(p_shares)
    as x(user_id uuid, share_cents bigint)
  loop
    -- Validate: participant is either the creator themselves or an active contact
    if v_share.user_id <> v_user_id then
      if not exists (
        select 1 from contacts
        where owner_id = v_user_id
          and friend_id = v_share.user_id
          and deleted_at is null
      ) then
        raise exception 'Participant is not in your contacts: %', v_share.user_id;
      end if;
    end if;

    insert into split_bill_shares (split_bill_id, user_id, share_cents, status)
    values (
      v_bill_id,
      v_share.user_id,
      v_share.share_cents,
      case when v_share.user_id = p_paid_by then 'settled' else 'pending' end
    );
  end loop;

  -- Auto-create the payer's expense (full amount) with home conversion snapshot
  insert into expenses (
    user_id, type, source, source_split_bill_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    category_id, collab_id,
    note, expense_date,
    google_place_id, place_name, latitude, longitude, receipt_url
  ) values (
    p_paid_by, 'expense', 'split_payer', v_bill_id,
    p_total_amount_cents, p_currency,
    p_home_amount_cents, p_home_currency, p_conversion_rate,
    p_category_id, p_collab_id,
    coalesce(p_note, 'Split bill'), p_expense_date,
    p_google_place_id, p_place_name, p_latitude, p_longitude, p_receipt_url
  ) returning id into v_expense_id;

  return jsonb_build_object(
    'split_bill_id', v_bill_id,
    'payer_expense_id', v_expense_id
  );
end;
$$;


-- 14c. Mark a share as settled → creates settlement + expense rows
-- Settler passes their OWN category and account for their expense row.
-- Home conversion is read from the bill (Alice's snapshot at bill creation).
-- Both settler's expense and payer's income use the same rate — they're looking at the same bill.
create or replace function settle_split_share(
  p_share_id uuid,
  p_category_id uuid default null,  -- settler's own category for their expense
  p_account_id uuid default null    -- settler's own account (which one they paid from)
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_share record;
  v_bill record;
  v_settlement_id uuid;
  v_payer_expense_id uuid;
  v_settler_expense_id uuid;
  v_share_home_cents bigint;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_share from split_bill_shares where id = p_share_id;
  if not found then
    raise exception 'Share not found';
  end if;

  if v_share.user_id <> v_user_id then
    raise exception 'Can only settle your own share';
  end if;

  if v_share.status = 'settled' then
    raise exception 'Share already settled';
  end if;

  -- If settler provided a category, validate it belongs to them
  if p_category_id is not null then
    if not exists (
      select 1 from categories
      where id = p_category_id
        and user_id = v_user_id
        and deleted_at is null
    ) then
      raise exception 'Category does not belong to you';
    end if;
  end if;

  -- If settler provided an account, validate it belongs to them
  if p_account_id is not null then
    if not exists (
      select 1 from accounts
      where id = p_account_id
        and user_id = v_user_id
        and deleted_at is null
    ) then
      raise exception 'Account does not belong to you';
    end if;
  end if;

  select * into v_bill from split_bills where id = v_share.split_bill_id;

  -- Compute this share's portion of the home amount (preserve bill's snapshot rate)
  -- Cross-currency: derive from conversion_rate. Same currency: home = local.
  if v_bill.conversion_rate is not null then
    v_share_home_cents := round(v_share.share_cents::numeric / v_bill.conversion_rate)::bigint;
  elsif v_bill.home_currency is not null then
    v_share_home_cents := v_share.share_cents;
  else
    v_share_home_cents := null;
  end if;

  -- Create settlement row
  insert into settlements (
    split_bill_id, split_bill_share_id,
    from_user_id, to_user_id,
    amount_cents, currency, note, settled_on
  ) values (
    v_bill.id, v_share.id,
    v_user_id, v_bill.paid_by,
    v_share.share_cents, v_bill.currency,
    coalesce('Settled: ' || v_bill.note, 'Split settlement'), current_date
  ) returning id into v_settlement_id;

  -- Auto-create settler's expense row (they paid the payer)
  -- Uses settler's own category and account (p_category_id, p_account_id)
  -- Conversion rate is copied from the bill (Alice's snapshot)
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    category_id, account_id, collab_id,
    note, expense_date,
    google_place_id, place_name, latitude, longitude
  ) values (
    v_user_id, 'expense', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    p_category_id, p_account_id, v_bill.collab_id,
    coalesce('Paid for: ' || v_bill.note, 'Split settlement'), current_date,
    v_bill.google_place_id, v_bill.place_name, v_bill.latitude, v_bill.longitude
  ) returning id into v_settler_expense_id;

  -- Auto-create payer's income row (they received money)
  -- Uses bill's category (which is the payer's own category since creator = payer)
  -- Same home conversion as the bill — they're looking at the same transaction.
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    category_id,
    note, expense_date
  ) values (
    v_bill.paid_by, 'income', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    v_bill.category_id,
    coalesce('Received for: ' || v_bill.note, 'Split settlement'), current_date
  ) returning id into v_payer_expense_id;

  -- Update the share status
  update split_bill_shares
  set status = 'settled',
      settled_at = now(),
      settlement_id = v_settlement_id
  where id = p_share_id;

  return jsonb_build_object(
    'settlement_id', v_settlement_id,
    'settler_expense_id', v_settler_expense_id,
    'payer_expense_id', v_payer_expense_id
  );
end;
$$;


-- 14d. Unsettle a share (for re-settle toggle flow)
create or replace function unsettle_split_share(p_share_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_share record;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_share from split_bill_shares where id = p_share_id;
  if not found then
    raise exception 'Share not found';
  end if;

  if v_share.user_id <> v_user_id then
    raise exception 'Can only unsettle your own share';
  end if;

  if v_share.status <> 'settled' then
    raise exception 'Share is not settled';
  end if;

  -- Soft-delete the linked settlement
  update settlements
  set deleted_at = now()
  where id = v_share.settlement_id and deleted_at is null;

  -- Soft-delete the linked expense rows (both sides)
  update expenses
  set deleted_at = now()
  where source_settlement_id = v_share.settlement_id
    and deleted_at is null;

  -- Reset share to pending
  update split_bill_shares
  set status = 'pending',
      settled_at = null,
      settlement_id = null
  where id = p_share_id;

  return jsonb_build_object(
    'share_id', p_share_id,
    'status', 'pending'
  );
end;
$$;


-- 14e. Dispute a share
create or replace function dispute_split_share(
  p_share_id uuid,
  p_reason text
) returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_share record;
begin
  select * into v_share from split_bill_shares where id = p_share_id;
  if not found then raise exception 'Share not found'; end if;
  if v_share.user_id <> v_user_id then
    raise exception 'Can only dispute your own share';
  end if;

  update split_bill_shares
  set status = 'disputed',
      dispute_reason = p_reason
  where id = p_share_id;
end;
$$;


-- 14f. Create a custom category (enforces free-tier limit of 5 custom categories)
-- Recycles soft-deleted records with the same name instead of inserting a new row.
-- requires_premium is recalculated at creation time based on current tier + free slot count.
create or replace function create_custom_category(
  p_name text,
  p_icon text,
  p_color text
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_free_count integer;
  v_requires_premium boolean;
  v_recycled_id uuid;
  v_new_id uuid;
  v_max_sort integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Category name is required';
  end if;

  -- Get user's subscription tier
  select subscription_tier into v_tier
  from profiles where id = v_user_id;

  -- Check for active duplicate name (case-insensitive)
  if exists (
    select 1 from categories
    where user_id = v_user_id
      and lower(name) = lower(trim(p_name))
      and deleted_at is null
  ) then
    raise exception 'A category with this name already exists.'
      using errcode = 'P0001', hint = 'duplicate_name';
  end if;

  -- Count free-tier custom categories (premium-flagged ones don't consume free slots)
  select count(*) into v_free_count
  from categories
  where user_id = v_user_id
    and is_default = false
    and deleted_at is null
    and requires_premium = false;

  -- Block free users who have hit the limit
  if v_tier = 'free' and v_free_count >= 5 then
    raise exception 'Free tier limit reached (5 custom categories). Upgrade to Premium for unlimited.'
      using errcode = 'P0001', hint = 'upgrade_required';
  end if;

  -- Premium users creating beyond the free limit get the record flagged
  v_requires_premium := (v_tier <> 'free') and (v_free_count >= 5);

  -- Recycle soft-deleted record with same name if one exists
  select id into v_recycled_id
  from categories
  where user_id = v_user_id
    and lower(name) = lower(trim(p_name))
    and deleted_at is not null
  limit 1;

  if v_recycled_id is not null then
    update categories
    set deleted_at = null,
        icon = coalesce(p_icon, 'category'),
        color = coalesce(p_color, '#888888'),
        requires_premium = v_requires_premium,
        updated_at = now()
    where id = v_recycled_id;

    return jsonb_build_object(
      'category_id', v_recycled_id,
      'recycled', true,
      'requires_premium', v_requires_premium,
      'tier', v_tier
    );
  end if;

  -- Insert new record
  select coalesce(max(sort_order), 0) + 1 into v_max_sort
  from categories
  where user_id = v_user_id and deleted_at is null;

  insert into categories (user_id, name, icon, color, is_default, requires_premium, sort_order)
  values (v_user_id, trim(p_name), coalesce(p_icon, 'category'), coalesce(p_color, '#888888'), false, v_requires_premium, v_max_sort)
  returning id into v_new_id;

  return jsonb_build_object(
    'category_id', v_new_id,
    'recycled', false,
    'requires_premium', v_requires_premium,
    'tier', v_tier
  );
end;
$$;


-- 14g. Create an account (bank/cash/credit/etc) — enforces 5-account limit for free tier
-- Accounts are tags for "how/where money was spent" — no balance tracking.
-- Recycles soft-deleted records with the same name instead of inserting a new row.
-- requires_premium is recalculated at creation time based on current tier + free slot count.
create or replace function create_account(
  p_name text,
  p_account_type text,
  p_icon text default null,
  p_color text default null,
  p_currency text default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_free_count integer;
  v_requires_premium boolean;
  v_recycled_id uuid;
  v_new_id uuid;
  v_max_sort integer;
  v_currency text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Account name is required';
  end if;

  -- Get user's subscription tier
  select subscription_tier into v_tier
  from profiles where id = v_user_id;

  -- Check for active duplicate name (case-insensitive)
  if exists (
    select 1 from accounts
    where user_id = v_user_id
      and lower(name) = lower(trim(p_name))
      and deleted_at is null
  ) then
    raise exception 'An account with this name already exists.'
      using errcode = 'P0001', hint = 'duplicate_name';
  end if;

  -- Count free-tier custom accounts (premium-flagged ones don't consume free slots)
  select count(*) into v_free_count
  from accounts
  where user_id = v_user_id
    and is_default = false
    and is_archived = false
    and deleted_at is null
    and requires_premium = false;

  -- Block free users who have hit the limit
  if v_tier = 'free' and v_free_count >= 5 then
    raise exception 'Free tier limit reached (5 custom accounts). Upgrade to Premium for unlimited.'
      using errcode = 'P0001', hint = 'upgrade_required';
  end if;

  -- Premium users creating beyond the free limit get the record flagged
  v_requires_premium := (v_tier <> 'free') and (v_free_count >= 5);

  -- Default currency to user's home currency
  if p_currency is null then
    select default_currency into v_currency from profiles where id = v_user_id;
  else
    v_currency := p_currency;
  end if;

  -- Recycle soft-deleted record with same name if one exists
  select id into v_recycled_id
  from accounts
  where user_id = v_user_id
    and lower(name) = lower(trim(p_name))
    and deleted_at is not null
  limit 1;

  if v_recycled_id is not null then
    update accounts
    set deleted_at = null,
        account_type = p_account_type,
        icon = coalesce(p_icon, 'account_balance_wallet'),
        color = coalesce(p_color, '#378ADD'),
        currency = v_currency,
        requires_premium = v_requires_premium,
        is_archived = false,
        updated_at = now()
    where id = v_recycled_id;

    return jsonb_build_object(
      'account_id', v_recycled_id,
      'recycled', true,
      'requires_premium', v_requires_premium,
      'tier', v_tier
    );
  end if;

  -- Insert new record
  select coalesce(max(sort_order), 0) + 1 into v_max_sort
  from accounts where user_id = v_user_id and deleted_at is null;

  insert into accounts (
    user_id, name, account_type, icon, color, currency, requires_premium, sort_order
  ) values (
    v_user_id, trim(p_name), p_account_type,
    coalesce(p_icon, 'account_balance_wallet'),
    coalesce(p_color, '#378ADD'),
    v_currency,
    v_requires_premium,
    v_max_sort
  ) returning id into v_new_id;

  return jsonb_build_object(
    'account_id', v_new_id,
    'recycled', false,
    'requires_premium', v_requires_premium,
    'tier', v_tier
  );
end;
$$;


-- 14h. Get spending per account for the current user (for analytics)
-- Returns total spending (type='expense') per account within an optional date range.
create or replace function my_account_spending(
  p_start_date date default null,
  p_end_date date default null
) returns table (
  account_id uuid,
  account_name text,
  account_type text,
  icon text,
  color text,
  currency text,
  total_expense_cents bigint,
  total_income_cents bigint,
  transaction_count integer
)
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  return query
  select
    a.id,
    a.name,
    a.account_type,
    a.icon,
    a.color,
    a.currency,
    coalesce(sum(case when e.type = 'expense' then e.home_amount_cents else 0 end), 0)::bigint,
    coalesce(sum(case when e.type = 'income'  then e.home_amount_cents else 0 end), 0)::bigint,
    count(e.id)::integer
  from accounts a
  left join expenses e on e.account_id = a.id
    and e.user_id = v_user_id
    and e.deleted_at is null
    and e.archived_at is null
    and (p_start_date is null or e.expense_date >= p_start_date)
    and (p_end_date   is null or e.expense_date <= p_end_date)
  where a.user_id = v_user_id
    and a.deleted_at is null
  group by a.id, a.name, a.account_type, a.icon, a.color, a.currency, a.sort_order
  order by a.sort_order, a.name;
end;
$$;


-- 14i. Create a group (personal shortcut list) — enforces 2-group limit for free tier
-- Auto-adds all p_member_user_ids; each must be in creator's contacts.
-- requires_premium is recalculated at creation time based on current tier + free group count.
create or replace function create_group(
  p_name text,
  p_member_user_ids uuid[] default array[]::uuid[],
  p_icon text default null,
  p_color text default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
  v_free_count integer;
  v_requires_premium boolean;
  v_new_id uuid;
  v_member_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'Group name is required';
  end if;

  -- Get user's subscription tier
  select subscription_tier into v_tier from profiles where id = v_user_id;

  -- Count free-tier groups (premium-flagged ones don't consume free slots)
  -- groups has no deleted_at — they are hard-deleted
  select count(*) into v_free_count
  from groups
  where created_by = v_user_id
    and requires_premium = false;

  -- Enforce 2-group limit for free users
  if v_tier = 'free' and v_free_count >= 2 then
    raise exception 'Free tier limit reached (2 groups). Upgrade to Premium for unlimited.'
      using errcode = 'P0001', hint = 'upgrade_required';
  end if;

  -- Premium users creating beyond the free limit get the record flagged
  v_requires_premium := (v_tier <> 'free') and (v_free_count >= 2);

  -- Validate all members are in creator's contacts
  foreach v_member_id in array p_member_user_ids loop
    if v_member_id = v_user_id then
      continue;  -- skip self (shouldn't be in list anyway, but safe)
    end if;
    if not exists (
      select 1 from contacts
      where owner_id = v_user_id
        and friend_id = v_member_id
    ) then
      raise exception 'Member is not in your contacts: %', v_member_id;
    end if;
  end loop;

  -- Create the group
  insert into groups (created_by, name, icon, color, requires_premium)
  values (
    v_user_id, trim(p_name),
    coalesce(p_icon, 'group'),
    coalesce(p_color, '#378ADD'),
    v_requires_premium
  )
  returning id into v_new_id;

  -- Add members (deduplicating input array)
  foreach v_member_id in array p_member_user_ids loop
    if v_member_id <> v_user_id then
      insert into group_members (group_id, user_id)
      values (v_new_id, v_member_id)
      on conflict (group_id, user_id) do nothing;
    end if;
  end loop;

  return jsonb_build_object(
    'group_id', v_new_id,
    'requires_premium', v_requires_premium,
    'tier', v_tier
  );
end;
$$;


-- 14j. Add a member to a group (creator only, must be a contact)
create or replace function add_group_member(
  p_group_id uuid,
  p_user_id uuid
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_group groups;
  v_member_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_group from groups where id = p_group_id;
  if not found then raise exception 'Group not found'; end if;
  if v_group.created_by <> v_user_id then
    raise exception 'Only the group creator can add members';
  end if;

  if p_user_id = v_user_id then
    raise exception 'Cannot add yourself to your own group';
  end if;

  -- Must be a contact
  if not exists (
    select 1 from contacts
    where owner_id = v_user_id and friend_id = p_user_id
  ) then
    raise exception 'User must be in your contacts';
  end if;

  insert into group_members (group_id, user_id)
  values (p_group_id, p_user_id)
  on conflict (group_id, user_id) do nothing
  returning id into v_member_id;

  return jsonb_build_object('member_id', v_member_id);
end;
$$;


-- 14k. Remove a member from a group (creator only, hard-delete)
create or replace function remove_group_member(
  p_group_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_group groups;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_group from groups where id = p_group_id;
  if not found then raise exception 'Group not found'; end if;
  if v_group.created_by <> v_user_id then
    raise exception 'Only the group creator can remove members';
  end if;

  delete from group_members
  where group_id = p_group_id
    and user_id = p_user_id;
end;
$$;


-- 14l. Delete a group (creator only, hard-delete)
-- group_members cascade. split_bills.group_id is set null via FK ON DELETE SET NULL.
create or replace function delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_group groups;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_group from groups where id = p_group_id;
  if not found then raise exception 'Group not found'; end if;
  if v_group.created_by <> v_user_id then
    raise exception 'Only the group creator can delete the group';
  end if;

  delete from groups where id = p_group_id;
end;
$$;


-- 14m. Add a contact by username or email — auto-creates bidirectional contact rows
-- MVP: no invitation/approval flow. Either user can remove the contact later.
-- p_identifier accepts: "@username", "username", or "email@example.com"
create or replace function add_contact(
  p_identifier text,
  p_nickname text default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_friend_id uuid;
  v_my_contact_id uuid;
  v_lookup text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_identifier is null or length(trim(p_identifier)) = 0 then
    raise exception 'Username or email is required';
  end if;

  v_lookup := lower(trim(p_identifier));

  -- Determine if it's a username or email
  if v_lookup like '%@%.%' then
    -- Email format (contains @ and .)
    select id into v_friend_id from profiles where lower(email) = v_lookup;
  else
    -- Treat as username; strip leading @ if present
    if v_lookup like '@%' then
      v_lookup := substring(v_lookup from 2);
    end if;
    select id into v_friend_id from profiles where username = v_lookup;
  end if;

  if v_friend_id is null then
    raise exception 'No user found'
      using errcode = 'P0001', hint = 'user_not_found';
  end if;

  if v_friend_id = v_user_id then
    raise exception 'You cannot add yourself as a contact';
  end if;

  -- Create forward contact (me → friend)
  insert into contacts (owner_id, friend_id, nickname)
  values (v_user_id, v_friend_id, p_nickname)
  on conflict (owner_id, friend_id)
  do update set nickname = coalesce(excluded.nickname, contacts.nickname)
  returning id into v_my_contact_id;

  -- Create reverse contact (friend → me)
  insert into contacts (owner_id, friend_id)
  values (v_friend_id, v_user_id)
  on conflict (owner_id, friend_id) do nothing;

  return jsonb_build_object(
    'contact_id', v_my_contact_id,
    'friend_id', v_friend_id
  );
end;
$$;


-- 14n. Add a contact to a collab (owner only, must be a contact)
create or replace function add_collab_member(
  p_collab_id uuid,
  p_user_id uuid
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_collab collabs;
  v_is_contact boolean;
  v_member_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_collab from collabs
  where id = p_collab_id and deleted_at is null;
  if not found then raise exception 'Collab not found'; end if;

  if v_collab.owner_id <> v_user_id then
    raise exception 'Only collab owner can add members';
  end if;

  if v_collab.status <> 'active' then
    raise exception 'Can only add members to active collabs';
  end if;

  -- Must be a contact (trust boundary — only add friends)
  select exists(
    select 1 from contacts
    where owner_id = v_user_id
      and friend_id = p_user_id
      and deleted_at is null
  ) into v_is_contact;

  if not v_is_contact then
    raise exception 'User must be in your contacts before adding to collab';
  end if;

  -- Insert or re-activate if previously left
  insert into collab_members (collab_id, user_id, role, joined_at, left_at)
  values (p_collab_id, p_user_id, 'member', now(), null)
  on conflict (collab_id, user_id)
  do update set left_at = null, joined_at = now()
  returning id into v_member_id;

  return jsonb_build_object(
    'member_id', v_member_id,
    'collab_id', p_collab_id,
    'user_id', p_user_id
  );
end;
$$;


-- 14o. Leave a collab (any member can leave themselves)
-- Owner cannot leave — they'd have to delete the collab or transfer ownership.
create or replace function leave_collab(p_collab_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_collab collabs;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_collab from collabs
  where id = p_collab_id and deleted_at is null;
  if not found then raise exception 'Collab not found'; end if;

  if v_collab.owner_id = v_user_id then
    raise exception 'Collab owner cannot leave the collab. Delete it instead.';
  end if;

  update collab_members
  set left_at = now()
  where collab_id = p_collab_id
    and user_id = v_user_id
    and left_at is null;

  return jsonb_build_object('collab_id', p_collab_id, 'left_at', now());
end;
$$;


-- 14p. Close a collab (owner only) — makes it read-only, no new expenses can be tagged
create or replace function close_collab(p_collab_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_collab collabs;
  v_unsettled integer;
  v_total_expenses integer;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_collab from collabs
  where id = p_collab_id and deleted_at is null;
  if not found then raise exception 'Collab not found'; end if;
  if v_collab.owner_id <> v_user_id then
    raise exception 'Only collab owner can close the collab';
  end if;
  if v_collab.status <> 'active' then
    raise exception 'Collab is not active';
  end if;

  -- Count unsettled splits for informational return
  select count(*) into v_unsettled
  from split_bill_shares s
  join split_bills b on b.id = s.split_bill_id
  where b.collab_id = p_collab_id
    and s.status in ('pending', 'disputed', 'acknowledged')
    and s.archived_at is null
    and b.deleted_at is null;

  -- Count collab expenses
  select count(*) into v_total_expenses
  from expenses
  where collab_id = p_collab_id and deleted_at is null;

  update collabs
  set status = 'closed', closed_at = now()
  where id = p_collab_id;

  return jsonb_build_object(
    'collab_id', p_collab_id,
    'closed_at', now(),
    'total_expenses', v_total_expenses,
    'unsettled_splits_remaining', v_unsettled
  );
end;
$$;


-- 14q. Activity feed (Splitwise-style) — no separate notifications table
-- Merges events from multiple tables into one chronological feed.
-- Cursor pagination: pass the oldest occurred_at from the previous page.
create or replace function my_activity_feed(
  p_cursor timestamptz default null,
  p_limit integer default 30
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id uuid := auth.uid();
  v_cutoff timestamptz := coalesce(p_cursor, now() + interval '1 day');
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  with activities as (
    -- Split bills you participate in (created by someone else)
    select
      'split_created'::text as type,
      sb.created_at as occurred_at,
      jsonb_build_object(
        'split_bill_id', sb.id,
        'created_by', sb.created_by,
        'note', sb.note,
        'amount_cents', sb.total_amount_cents,
        'currency', sb.currency,
        'your_share_cents', sbs.share_cents
      ) as payload
    from split_bills sb
    join split_bill_shares sbs on sbs.split_bill_id = sb.id
    where sbs.user_id = v_user_id
      and sb.created_at < v_cutoff
      and sb.deleted_at is null
      and sb.created_by <> v_user_id  -- exclude self-created

    union all

    -- Someone settled a share of a bill you created (as payer)
    select
      'share_settled'::text as type,
      sbs.settled_at as occurred_at,
      jsonb_build_object(
        'split_bill_id', sb.id,
        'settler_id', sbs.user_id,
        'note', sb.note,
        'amount_cents', sbs.share_cents,
        'currency', sb.currency
      ) as payload
    from split_bill_shares sbs
    join split_bills sb on sb.id = sbs.split_bill_id
    where sb.paid_by = v_user_id
      and sbs.user_id <> v_user_id
      and sbs.status = 'settled'
      and sbs.settled_at is not null
      and sbs.settled_at < v_cutoff
      and sbs.archived_at is null
      and sb.deleted_at is null

    union all

    -- Someone disputed a share of a bill you created
    select
      'share_disputed'::text as type,
      sbs.updated_at as occurred_at,
      jsonb_build_object(
        'split_bill_id', sb.id,
        'disputer_id', sbs.user_id,
        'note', sb.note,
        'reason', sbs.dispute_reason,
        'amount_cents', sbs.share_cents
      ) as payload
    from split_bill_shares sbs
    join split_bills sb on sb.id = sbs.split_bill_id
    where sb.created_by = v_user_id
      and sbs.status = 'disputed'
      and sbs.updated_at < v_cutoff
      and sbs.archived_at is null
      and sb.deleted_at is null

    union all

    -- You were added to a collab (by someone else)
    select
      'added_to_collab'::text as type,
      cm.joined_at as occurred_at,
      jsonb_build_object(
        'collab_id', c.id,
        'collab_name', c.name,
        'added_by', c.owner_id
      ) as payload
    from collab_members cm
    join collabs c on c.id = cm.collab_id
    where cm.user_id = v_user_id
      and cm.role = 'member'
      and cm.left_at is null
      and cm.joined_at < v_cutoff
      and c.deleted_at is null

    union all

    -- A collab you're in was closed (by the owner)
    select
      'collab_closed'::text as type,
      c.closed_at as occurred_at,
      jsonb_build_object(
        'collab_id', c.id,
        'collab_name', c.name,
        'closed_by', c.owner_id
      ) as payload
    from collabs c
    join collab_members cm on cm.collab_id = c.id
    where cm.user_id = v_user_id
      and cm.left_at is null
      and c.closed_at is not null
      and c.closed_at < v_cutoff
      and c.deleted_at is null

    union all

    -- Someone else added an expense to a collab you're in
    select
      'collab_expense_added'::text as type,
      e.created_at as occurred_at,
      jsonb_build_object(
        'collab_id', e.collab_id,
        'expense_id', e.id,
        'created_by', e.user_id,
        'note', e.note,
        'amount_cents', e.amount_cents,
        'currency', e.currency
      ) as payload
    from expenses e
    join collab_members cm on cm.collab_id = e.collab_id
    where cm.user_id = v_user_id
      and cm.left_at is null
      and e.user_id <> v_user_id
      and e.collab_id is not null
      and e.created_at < v_cutoff
      and e.deleted_at is null

    union all

    -- Someone added you as a contact
    select
      'contact_added'::text as type,
      c.created_at as occurred_at,
      jsonb_build_object(
        'by_user_id', c.owner_id
      ) as payload
    from contacts c
    where c.friend_id = v_user_id
      and c.owner_id <> v_user_id
      and c.deleted_at is null
      and c.created_at < v_cutoff
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.occurred_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from activities
    order by occurred_at desc
    limit p_limit
  ) a;

  return v_result;
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 15. RLS — ENABLE + POLICIES
-- ═══════════════════════════════════════════════════════════════════

-- 15a. PROFILES
alter table profiles enable row level security;

create policy profiles_select on profiles for select using (
  id = auth.uid()
  or id in (
    -- Anyone in a collab with you
    select cm2.user_id
    from collab_members cm1
    join collab_members cm2 on cm1.collab_id = cm2.collab_id
    where cm1.user_id = auth.uid()
      and cm1.left_at is null
      and cm2.left_at is null
  )
  or id in (
    -- Anyone in your contacts
    select friend_id from contacts
    where owner_id = auth.uid()
  )
  or id in (
    -- Anyone you're in a split with
    select user_id from split_bill_shares
    where split_bill_id in (
      select split_bill_id from split_bill_shares
      where user_id = auth.uid()
    )
  )
);

create policy profiles_update_own on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());


-- 15b. CONTACTS
alter table contacts enable row level security;

create policy contacts_select on contacts
  for select using (owner_id = auth.uid());

create policy contacts_insert on contacts
  for insert with check (owner_id = auth.uid());

create policy contacts_update on contacts
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy contacts_delete on contacts
  for delete using (owner_id = auth.uid());


-- 15c. CATEGORIES
alter table categories enable row level security;

create policy cat_select on categories for select using (user_id = auth.uid());
create policy cat_insert on categories for insert with check (user_id = auth.uid());
create policy cat_update on categories for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- 15c-2. ACCOUNTS — fully user-owned, no sharing
alter table accounts enable row level security;

create policy acc_select on accounts for select using (user_id = auth.uid());
create policy acc_insert on accounts for insert with check (user_id = auth.uid());
create policy acc_update on accounts for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- 15c-3. GROUPS — creator-only visibility (personal shortcut lists)
alter table groups enable row level security;

create policy groups_all on groups
  for all using (created_by = auth.uid()) with check (created_by = auth.uid());


-- 15c-4. GROUP_MEMBERS — creator of the group has full access
alter table group_members enable row level security;

create policy gm_all on group_members
  for all using (
    group_id in (select id from groups where created_by = auth.uid())
  ) with check (
    group_id in (select id from groups where created_by = auth.uid())
  );


-- 15d-helper. Returns collab IDs the calling user is an active member of.
-- security definer so it runs without RLS, breaking the cm_select recursion.
create or replace function auth_collab_ids()
returns setof uuid
language sql
security definer
stable
as $$
  select collab_id from collab_members
  where user_id = auth.uid() and left_at is null
$$;


-- 15d. COLLABS — accessible by owner and all active members
alter table collabs enable row level security;

create policy collabs_select on collabs for select using (
  owner_id = auth.uid()
  or id in (select auth_collab_ids())
);

create policy collabs_insert on collabs for insert with check (owner_id = auth.uid());

-- Only owner can update collab metadata (name, dates, status, budget, etc.)
create policy collabs_update on collabs for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());


-- 15d-2. COLLAB_MEMBERS
alter table collab_members enable row level security;

-- Members of a collab can see the whole member list (to know their collab mates)
create policy cm_select on collab_members for select using (
  user_id = auth.uid()
  or collab_id in (select auth_collab_ids())
);

-- Insert only via add_collab_member RPC (security definer) or handle_new_collab trigger (security definer).
-- Both bypass RLS, so this policy exists only as a fallback guard.
-- Do NOT add user_id = auth.uid() here — that would let any user self-insert into any collab.
create policy cm_insert on collab_members for insert with check (
  collab_id in (
    select id from collabs where owner_id = auth.uid()
  )
);

-- Members can update their own row (leave). Owner can update any member's row.
create policy cm_update on collab_members for update using (
  user_id = auth.uid()
  or collab_id in (
    select id from collabs where owner_id = auth.uid()
  )
);


-- 15e. EXPENSES
-- Own expenses are always visible.
-- Expenses tagged to a collab are visible to all active members of that collab.
-- Write operations (insert/update/delete) are always owner-only.
alter table expenses enable row level security;

create policy exp_select on expenses for select using (
  user_id = auth.uid()
  or (
    collab_id is not null
    and collab_id in (select auth_collab_ids())
  )
);

create policy exp_insert on expenses for insert with check (user_id = auth.uid());
create policy exp_update on expenses for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- 15f. BUDGETS
alter table budgets enable row level security;

create policy bud_select on budgets for select using (user_id = auth.uid());
create policy bud_insert on budgets for insert with check (user_id = auth.uid());
create policy bud_update on budgets for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- 15g. SPLIT_BILLS
alter table split_bills enable row level security;

-- Security definer helper: checks split_bill_shares without triggering its RLS,
-- breaking the mutual-recursion cycle between sb_select and shares_select.
create or replace function is_split_participant(p_bill_id uuid)
returns boolean language sql security definer stable as $$
  select exists (
    select 1 from split_bill_shares
    where split_bill_id = p_bill_id and user_id = auth.uid()
  );
$$;

create policy sb_select on split_bills for select using (
  created_by = auth.uid()
  or paid_by = auth.uid()
  or is_split_participant(id)
);

create policy sb_insert on split_bills for insert with check (created_by = auth.uid());

-- MVP: creator-only edit. V2 will extend to paid_by.
create policy sb_update on split_bills for update
  using (created_by = auth.uid()) with check (created_by = auth.uid());


-- 15h. SPLIT_BILL_SHARES
alter table split_bill_shares enable row level security;

-- Note: do not query split_bill_shares from within this policy (self-recursion),
-- and do not query split_bills here if split_bills policy queries split_bill_shares
-- (mutual recursion). Creator/payer visibility is handled via sb_select above.
create policy shares_select on split_bill_shares for select using (
  user_id = auth.uid()
  or split_bill_id in (
    select id from split_bills
    where created_by = auth.uid() or paid_by = auth.uid()
  )
);

create policy shares_insert on split_bill_shares for insert with check (
  split_bill_id in (
    select id from split_bills where created_by = auth.uid()
  )
);

-- Creator edits amounts; participants update own status
create policy shares_update on split_bill_shares for update using (
  user_id = auth.uid()
  or split_bill_id in (
    select id from split_bills where created_by = auth.uid()
  )
);


-- 15i. SETTLEMENTS
alter table settlements enable row level security;

create policy set_select on settlements for select using (
  from_user_id = auth.uid() or to_user_id = auth.uid()
);

create policy set_insert on settlements for insert with check (from_user_id = auth.uid());

-- UPDATE allowed only to support soft-delete (unsettle)
create policy set_update on settlements for update using (
  from_user_id = auth.uid() or to_user_id = auth.uid()
);


-- ═══════════════════════════════════════════════════════════════════
-- 16. STORAGE BUCKETS — NOT USED IN MVP (deferred to V2)
-- ═══════════════════════════════════════════════════════════════════
-- MVP decision: no image storage. The following columns exist in the
-- schema but will remain null in MVP:
--   • profiles.avatar_url
--   • collabs.cover_photo_url
--   • expenses.receipt_url
--   • split_bills.receipt_url
--
-- In V2, create Supabase Storage buckets and populate these columns:
--
-- bucket: receipts (private)
--   Storage policy: user can read/write their own folder /<user_id>/...
--
-- bucket: avatars (public)
--   Storage policy: user can write to /<user_id>/..., anyone can read
--
-- Example storage policy for receipts:
--   create policy "users manage own receipts"
--     on storage.objects for all
--     using (bucket_id = 'receipts'
--            and (storage.foldername(name))[1] = auth.uid()::text)
--     with check (bucket_id = 'receipts'
--                 and (storage.foldername(name))[1] = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════════════
-- END OF SCHEMA
-- ═══════════════════════════════════════════════════════════════════
