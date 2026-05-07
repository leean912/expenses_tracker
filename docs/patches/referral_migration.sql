-- ═══════════════════════════════════════════════════════════════════
-- REFERRAL SYSTEM — SQL MIGRATION
-- Run in Supabase SQL editor after the main schema is deployed.
--
-- Design: referral_premium_expires_at in profiles IS the "bank".
-- Each new referral pushes the date forward by 3 days from the
-- later of (paid subscription expiry, current referral expiry, now).
-- No RevenueCat promotional API needed — Flutter reads
-- referral_premium_expires_at directly from the profile.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- 1. generate_referral_code
-- 8-char uppercase alphanumeric, collision-safe loop.
-- Set as DEFAULT on profiles.referral_code so handle_new_user()
-- automatically assigns a code without any trigger changes.
-- ═══════════════════════════════════════════════════════════════════

create or replace function generate_referral_code()
returns text language plpgsql as $$
declare
  v_chars text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  v_code  text;
begin
  loop
    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(v_chars, (floor(random() * 36) + 1)::int, 1);
    end loop;
    exit when not exists (select 1 from profiles where referral_code = v_code);
  end loop;
  return v_code;
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 2. PATCH profiles TABLE
-- ═══════════════════════════════════════════════════════════════════

alter table profiles
  add column referral_code               text unique
    check (referral_code ~ '^[A-Z0-9]{8}$'),
  add column referral_premium_expires_at timestamptz;

-- Backfill existing users
update profiles
set referral_code = generate_referral_code()
where referral_code is null;

-- Lock it down: not null + default for all future inserts
alter table profiles
  alter column referral_code set not null,
  alter column referral_code set default generate_referral_code();


-- ═══════════════════════════════════════════════════════════════════
-- 3. REFERRALS TABLE
-- unique(referee_id) enforces each user can only be referred once.
-- ═══════════════════════════════════════════════════════════════════

create table referrals (
  id           uuid primary key default gen_random_uuid(),
  referrer_id  uuid not null references profiles(id) on delete cascade,
  referee_id   uuid not null references profiles(id) on delete cascade,
  bonus_days   int not null default 3,
  granted_at   timestamptz not null default now(),
  unique(referee_id)
);

create index idx_referrals_referrer on referrals(referrer_id);

alter table referrals enable row level security;

create policy "referrals_select_own" on referrals for select
  using (referrer_id = auth.uid() or referee_id = auth.uid());


-- ═══════════════════════════════════════════════════════════════════
-- 4. apply_referral_code RPC
-- Called once during onboarding by the new user (referee).
-- Pushes referral_premium_expires_at forward on the referrer by 3 days
-- from the latest of: their paid sub expiry, existing referral expiry, now.
-- For free referrers: immediately activates premium in profiles.
-- For paid referrers: referral premium will activate after paid sub ends.
-- ═══════════════════════════════════════════════════════════════════

create or replace function apply_referral_code(p_code text)
returns jsonb language plpgsql security definer as $$
declare
  v_referee_id   uuid := auth.uid();
  v_referrer_id  uuid;
  v_clean_code   text := upper(trim(p_code));
  v_new_expiry   timestamptz;
begin
  if v_referee_id is null then
    raise exception 'Not authenticated';
  end if;

  if v_clean_code !~ '^[A-Z0-9]{8}$' then
    raise exception 'Invalid referral code format'
      using errcode = 'P0001', hint = 'invalid_code';
  end if;

  select id into v_referrer_id
  from profiles where referral_code = v_clean_code;

  if v_referrer_id is null then
    raise exception 'Referral code not found'
      using errcode = 'P0001', hint = 'invalid_code';
  end if;

  if v_referrer_id = v_referee_id then
    raise exception 'Cannot use your own referral code'
      using errcode = 'P0001', hint = 'own_code';
  end if;

  if exists (select 1 from referrals where referee_id = v_referee_id) then
    raise exception 'You have already used a referral code'
      using errcode = 'P0001', hint = 'already_used';
  end if;

  insert into referrals (referrer_id, referee_id, bonus_days)
  values (v_referrer_id, v_referee_id, 3);

  -- New expiry = max(paid sub expiry, current referral expiry, now) + 3 days
  select greatest(
    coalesce(subscription_expires_at, now()),
    coalesce(referral_premium_expires_at, now())
  ) + interval '3 days'
  into v_new_expiry
  from profiles where id = v_referrer_id;

  -- Always update referral_premium_expires_at
  update profiles
  set referral_premium_expires_at = v_new_expiry
  where id = v_referrer_id;

  -- For free referrers: activate premium immediately in profiles
  update profiles
  set subscription_tier       = 'premium',
      subscription_expires_at = v_new_expiry
  where id = v_referrer_id
    and subscription_tier = 'free';

  return jsonb_build_object('referrer_id', v_referrer_id, 'bonus_days', 3);
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 5. get_referral_stats RPC
-- ═══════════════════════════════════════════════════════════════════

create or replace function get_referral_stats()
returns jsonb language plpgsql security definer as $$
declare
  v_user_id    uuid := auth.uid();
  v_code       text;
  v_expires_at timestamptz;
  v_count      int;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select referral_code, referral_premium_expires_at
  into   v_code, v_expires_at
  from profiles where id = v_user_id;

  select count(*) into v_count
  from referrals where referrer_id = v_user_id;

  return jsonb_build_object(
    'referral_code',    v_code,
    'total_referrals',  v_count,
    'bonus_expires_at', v_expires_at
  );
end;
$$;


-- ═══════════════════════════════════════════════════════════════════
-- 6. UPDATE process_subscription_expirations
-- Extended to preserve referral premium when paid sub expires:
-- if referral_premium_expires_at is still in the future, keep the
-- user on premium (at the referral expiry) instead of downgrading.
-- ═══════════════════════════════════════════════════════════════════

create or replace function process_subscription_expirations()
returns jsonb language plpgsql security definer as $$
declare
  v_user            record;
  v_downgraded      integer := 0;
  v_referral_kept   integer := 0;
  v_deactivated_re  integer := 0;
  v_deactivated_rsb integer := 0;
  v_rows            integer;
begin
  for v_user in
    select id, referral_premium_expires_at
    from profiles
    where subscription_tier = 'premium'
      and subscription_expires_at is not null
      and subscription_expires_at < now()
  loop
    if v_user.referral_premium_expires_at is not null
       and v_user.referral_premium_expires_at > now() then
      -- Paid sub expired but referral premium is still active: transition to referral premium
      update profiles
      set subscription_expires_at = v_user.referral_premium_expires_at
      where id = v_user.id;
      v_referral_kept := v_referral_kept + 1;
    else
      -- No active referral premium: downgrade to free
      update profiles
      set subscription_tier = 'free',
          subscription_expires_at = null
      where id = v_user.id;
      v_downgraded := v_downgraded + 1;
    end if;
  end loop;

  -- Deactivate premium items for all free users
  update recurring_expenses
  set is_active = false
  where deleted_at is null
    and is_active = true
    and requires_premium = true
    and user_id in (select id from profiles where subscription_tier = 'free');

  get diagnostics v_rows = row_count;
  v_deactivated_re := v_rows;

  update recurring_split_bills
  set is_active = false
  where deleted_at is null
    and is_active = true
    and requires_premium = true
    and user_id in (select id from profiles where subscription_tier = 'free');

  get diagnostics v_rows = row_count;
  v_deactivated_rsb := v_rows;

  return jsonb_build_object(
    'ran_at',                    now(),
    'users_downgraded',          v_downgraded,
    'referral_premium_kept',     v_referral_kept,
    'recurring_expenses_paused', v_deactivated_re,
    'recurring_splits_paused',   v_deactivated_rsb
  );
end;
$$;

-- Note: The existing pg_cron job 'process-subscription-expirations' already
-- runs this function at 16:00 UTC. No new cron job needed.
