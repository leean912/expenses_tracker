-- ═══════════════════════════════════════════════════════════════════
-- SPLIT V2 — EMAIL-BASED (NON-ONBOARDED) PARTICIPANTS
-- ═══════════════════════════════════════════════════════════════════
-- Allows Alice to split a bill with Bob before Bob signs up.
-- Alice provides Bob's email → a pending_split_shares row is created.
-- When Bob signs up, handle_new_user() automatically claims it:
--   1. Inserts a real split_bill_shares row for Bob
--   2. Creates bidirectional contacts (Alice↔Bob)
--   3. Marks the pending row claimed
--
-- APPLY ORDER:
--   Run these statements AFTER the base schema (expense_tracker_schema.sql).
--   Each section is idempotent-safe via CREATE OR REPLACE / ON CONFLICT.
--
-- SECTIONS:
--   1. pending_split_shares table + indexes + RLS
--   2. create_split_bill RPC (replace — adds p_email_shares param)
--   3. handle_new_user trigger function (replace — claims pending shares)
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- 1. PENDING_SPLIT_SHARES
-- Holds email-based share slots that haven't been claimed yet.
-- Once the invitee signs up, this row is migrated to split_bill_shares
-- and marked claimed. Rows are never hard-deleted.
-- ═══════════════════════════════════════════════════════════════════
create table if not exists pending_split_shares (
  id            uuid primary key default gen_random_uuid(),
  split_bill_id uuid not null references split_bills(id) on delete cascade,
  invited_by    uuid not null references profiles(id)   on delete cascade,

  invitee_email text not null
    check (invitee_email = lower(trim(invitee_email))),  -- always stored normalised
  share_cents   bigint not null check (share_cents >= 0),
  split_method  text not null default 'equal'
    check (split_method in ('equal', 'percentage', 'exact', 'shares')),

  created_at    timestamptz not null default now(),

  -- Filled in once the invitee signs up
  claimed_at    timestamptz,
  claimed_by    uuid references profiles(id) on delete set null,

  -- One slot per person per bill (email normalised)
  unique (split_bill_id, invitee_email)
);

-- Fast lookup when handle_new_user() needs to claim on signup
create index if not exists idx_pending_shares_email
  on pending_split_shares(invitee_email)
  where claimed_at is null;

-- Creator can browse unclaimed invites they sent
create index if not exists idx_pending_shares_invited_by
  on pending_split_shares(invited_by)
  where claimed_at is null;

-- RLS
alter table pending_split_shares enable row level security;

-- Only the inviter can read their own pending rows.
-- (Invitee hasn't signed up yet, so no read policy for them here.
--  After claim, the real split_bill_shares row is what they read.)
create policy pss_select on pending_split_shares
  for select using (invited_by = auth.uid());

-- Insert via create_split_bill RPC (security definer) — this is a fallback guard.
create policy pss_insert on pending_split_shares
  for insert with check (invited_by = auth.uid());

-- Allow the update needed during claim (handle_new_user runs security definer).
-- Direct updates are intentionally not granted to normal users.
create policy pss_update on pending_split_shares
  for update using (invited_by = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
-- 2. create_split_bill (REPLACE)
-- Adds p_email_shares jsonb parameter.
-- Format: '[{"email": "bob@example.com", "share_cents": 4000}]'
-- Email participants bypass the contacts check and go to
-- pending_split_shares. They are NOT in split_bill_shares until they
-- sign up and handle_new_user() claims the row.
-- ═══════════════════════════════════════════════════════════════════
create or replace function create_split_bill(
  p_paid_by              uuid,
  p_total_amount_cents   bigint,
  p_currency             text,
  p_note                 text,
  p_expense_date         date,
  p_category_id          uuid,
  p_collab_id            uuid,
  p_google_place_id      text,
  p_place_name           text,
  p_latitude             double precision,
  p_longitude            double precision,
  p_receipt_url          text,
  p_shares               jsonb,                        -- onboarded participants (user_id based)
  p_group_id             uuid    default null,
  p_home_amount_cents    bigint  default null,
  p_home_currency        text    default null,
  p_conversion_rate      numeric default null,
  p_email_shares         jsonb   default '[]'::jsonb   -- NEW: non-onboarded participants
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id      uuid := auth.uid();
  v_bill_id      uuid;
  v_expense_id   uuid;
  v_share        record;
  v_email_share  record;
  v_norm_email   text;
  v_pending_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if p_paid_by <> v_user_id then
    raise exception 'MVP: only the payer can create a split bill. Have the actual payer create it.';
  end if;

  if p_category_id is not null then
    if not exists (
      select 1 from categories
      where id = p_category_id and user_id = v_user_id and deleted_at is null
    ) then
      raise exception 'Category does not belong to you';
    end if;
  end if;

  if p_group_id is not null then
    if not exists (
      select 1 from groups
      where id = p_group_id and created_by = v_user_id and deleted_at is null
    ) then
      raise exception 'Group does not belong to you';
    end if;
  end if;

  if p_collab_id is not null then
    if not exists (
      select 1 from collab_members
      where collab_id = p_collab_id and user_id = v_user_id and left_at is null
    ) then
      raise exception 'You are not a member of this collab';
    end if;
  end if;

  -- Create the split bill
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

  -- Insert onboarded shares (existing behaviour — contact-validated)
  for v_share in select * from jsonb_to_recordset(p_shares)
    as x(user_id uuid, share_cents bigint)
  loop
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

  -- Insert email-based shares (non-onboarded participants)
  -- No contact check — invitee doesn't have a profile yet.
  -- Validate email format minimally (contains @ and .).
  for v_email_share in select * from jsonb_to_recordset(p_email_shares)
    as x(email text, share_cents bigint)
  loop
    v_norm_email := lower(trim(v_email_share.email));

    if v_norm_email is null or v_norm_email not like '%@%.%' then
      raise exception 'Invalid email for pending share: %', v_email_share.email;
    end if;

    -- If this email already belongs to a real profile, reject — caller should
    -- have used p_shares (user_id based). Avoids duplicate share slots.
    if exists (select 1 from profiles where lower(email) = v_norm_email) then
      raise exception 'User with email % is already onboarded. Use p_shares with their user_id instead.', v_norm_email
        using hint = 'use_p_shares';
    end if;

    insert into pending_split_shares (split_bill_id, invited_by, invitee_email, share_cents)
    values (v_bill_id, v_user_id, v_norm_email, v_email_share.share_cents)
    on conflict (split_bill_id, invitee_email) do nothing;

    v_pending_count := v_pending_count + 1;
  end loop;

  -- Auto-create payer's expense (full amount)
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
    'split_bill_id',       v_bill_id,
    'payer_expense_id',    v_expense_id,
    'pending_shares_sent', v_pending_count    -- NEW: count of email invites created
  );
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 3. handle_new_user (REPLACE)
-- Extended to claim any pending_split_shares where
-- invitee_email matches the new user's email.
-- For each pending share found:
--   a. Inserts a real split_bill_shares row
--   b. Creates bidirectional contacts (inviter↔new user)
--   c. Marks the pending row claimed
-- ═══════════════════════════════════════════════════════════════════
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_profile_id uuid;
  default_cats text[][] := array[
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
    array['Cash', 'cash', 'payments', '#4CAF50'],
    array['Bank', 'bank', 'account_balance', '#378ADD']
  ];
  v_currency  text;
  v_pending   record;
  i           integer;
begin
  v_currency := coalesce(new.raw_user_meta_data->>'default_currency', 'MYR');

  -- Create profile row
  insert into profiles (id, email, display_name, avatar_url, default_currency)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'display_name',
      split_part(coalesce(new.email, 'User'), '@', 1)
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

  -- ── Claim pending split shares ────────────────────────────────────────────
  -- Any split bills Alice sent to this email before Bob signed up are now
  -- converted to real split_bill_shares rows. Contacts are auto-created.
  for v_pending in
    select * from pending_split_shares
    where invitee_email = lower(coalesce(new.email, ''))
      and claimed_at is null
  loop
    -- Real share row (skip if slot already taken — shouldn't happen, but safe)
    insert into split_bill_shares (split_bill_id, user_id, share_cents, split_method, status)
    values (v_pending.split_bill_id, new_profile_id, v_pending.share_cents, v_pending.split_method, 'pending')
    on conflict (split_bill_id, user_id) do nothing;

    -- Bidirectional contacts: inviter → new user
    insert into contacts (owner_id, friend_id)
    values (v_pending.invited_by, new_profile_id)
    on conflict (owner_id, friend_id) do update set deleted_at = null;

    -- Bidirectional contacts: new user → inviter
    insert into contacts (owner_id, friend_id)
    values (new_profile_id, v_pending.invited_by)
    on conflict (owner_id, friend_id) do update set deleted_at = null;

    -- Mark claimed
    update pending_split_shares
    set claimed_at = now(),
        claimed_by = new_profile_id
    where id = v_pending.id;
  end loop;

  return new;
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- END OF SPLIT V2 PATCH
-- ═══════════════════════════════════════════════════════════════════
