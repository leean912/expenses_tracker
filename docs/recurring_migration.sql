-- ═══════════════════════════════════════════════════════════════════
-- RECURRING FEATURE — SQL MIGRATION
-- Run in Supabase SQL editor after the main schema is deployed.
-- Three new tables + patches to expenses + 9 RPCs + RLS + pg_cron.
-- ═══════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════
-- 1. PATCH expenses TABLE
-- Add 'recurring' source + FK columns to trace template origin.
-- ═══════════════════════════════════════════════════════════════════

alter table expenses drop constraint expenses_source_check;
alter table expenses
  add constraint expenses_source_check
  check (source in ('manual', 'settlement', 'split_payer', 'recurring'));

alter table expenses
  add column source_recurring_expense_id uuid,
  add column source_recurring_split_bill_id uuid;


-- ═══════════════════════════════════════════════════════════════════
-- 2. RECURRING_EXPENSES
-- Template for a personal recurring expense or income entry.
-- MYR only (MVP). Free tier: max 3. Premium: unlimited.
-- ═══════════════════════════════════════════════════════════════════

create table recurring_expenses (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references profiles(id) on delete cascade,
  title            text not null check (length(trim(title)) > 0),
  amount_cents     bigint not null check (amount_cents > 0),
  type             text not null default 'expense' check (type in ('expense', 'income')),
  category_id      uuid references categories(id) on delete set null,
  account_id       uuid references accounts(id) on delete set null,
  note             text,
  frequency        text not null check (frequency in ('daily', 'monthly', 'yearly')),
  next_run_at      date not null,
  is_active        boolean not null default true,
  requires_premium boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

create index idx_recurring_expenses_user on recurring_expenses(user_id)
  where deleted_at is null;
create index idx_recurring_expenses_due on recurring_expenses(next_run_at)
  where is_active = true and deleted_at is null;

create trigger trg_recurring_expenses_updated_at
  before update on recurring_expenses
  for each row execute function set_updated_at();


-- ═══════════════════════════════════════════════════════════════════
-- 3. RECURRING_SPLIT_BILLS
-- Template for a recurring split bill. Creator = payer (MVP invariant).
-- MYR only (MVP). Free tier: max 1. Premium: unlimited.
-- ═══════════════════════════════════════════════════════════════════

create table recurring_split_bills (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references profiles(id) on delete cascade,
  title            text not null check (length(trim(title)) > 0),
  amount_cents     bigint not null check (amount_cents > 0),
  split_method     text not null default 'equal' check (split_method in ('equal', 'custom')),
  category_id      uuid references categories(id) on delete set null,
  account_id       uuid references accounts(id) on delete set null,
  note             text,
  frequency        text not null check (frequency in ('daily', 'monthly', 'yearly')),
  next_run_at      date not null,
  is_active        boolean not null default true,
  requires_premium boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

create index idx_recurring_split_bills_user on recurring_split_bills(user_id)
  where deleted_at is null;
create index idx_recurring_split_bills_due on recurring_split_bills(next_run_at)
  where is_active = true and deleted_at is null;

create trigger trg_recurring_split_bills_updated_at
  before update on recurring_split_bills
  for each row execute function set_updated_at();


-- ═══════════════════════════════════════════════════════════════════
-- 4. RECURRING_SPLIT_BILL_SHARES
-- One row per participant per template.
-- equal split: share_cents is null (computed at fire time as amount / count).
-- custom split: share_cents is set; SUM enforced by create/update RPCs.
-- ═══════════════════════════════════════════════════════════════════

create table recurring_split_bill_shares (
  id                       uuid primary key default gen_random_uuid(),
  recurring_split_bill_id  uuid not null references recurring_split_bills(id) on delete cascade,
  user_id                  uuid not null references profiles(id) on delete cascade,
  share_cents              bigint check (share_cents is null or share_cents > 0),
  created_at               timestamptz not null default now(),
  unique (recurring_split_bill_id, user_id)
);

create index idx_recurring_shares_bill on recurring_split_bill_shares(recurring_split_bill_id);
create index idx_recurring_shares_user on recurring_split_bill_shares(user_id);


-- ═══════════════════════════════════════════════════════════════════
-- 5. DEFERRED FKs from expenses back to recurring tables
-- ═══════════════════════════════════════════════════════════════════

alter table expenses
  add constraint fk_expenses_source_recurring_expense
  foreign key (source_recurring_expense_id) references recurring_expenses(id) on delete set null;

alter table expenses
  add constraint fk_expenses_source_recurring_split_bill
  foreign key (source_recurring_split_bill_id) references recurring_split_bills(id) on delete set null;


-- ═══════════════════════════════════════════════════════════════════
-- 6. RLS
-- ═══════════════════════════════════════════════════════════════════

alter table recurring_expenses enable row level security;
alter table recurring_split_bills enable row level security;
alter table recurring_split_bill_shares enable row level security;

create policy "re_select" on recurring_expenses for select using (auth.uid() = user_id);
create policy "re_insert" on recurring_expenses for insert with check (auth.uid() = user_id);
create policy "re_update" on recurring_expenses for update using (auth.uid() = user_id);

create policy "rsb_select" on recurring_split_bills for select using (auth.uid() = user_id);
create policy "rsb_insert" on recurring_split_bills for insert with check (auth.uid() = user_id);
create policy "rsb_update" on recurring_split_bills for update using (auth.uid() = user_id);

create policy "rsbs_select" on recurring_split_bill_shares for select using (
  exists (select 1 from recurring_split_bills where id = recurring_split_bill_id and user_id = auth.uid())
);
create policy "rsbs_insert" on recurring_split_bill_shares for insert with check (
  exists (select 1 from recurring_split_bills where id = recurring_split_bill_id and user_id = auth.uid())
);
create policy "rsbs_update" on recurring_split_bill_shares for update using (
  exists (select 1 from recurring_split_bills where id = recurring_split_bill_id and user_id = auth.uid())
);
create policy "rsbs_delete" on recurring_split_bill_shares for delete using (
  exists (select 1 from recurring_split_bills where id = recurring_split_bill_id and user_id = auth.uid())
);


-- ═══════════════════════════════════════════════════════════════════
-- 7. CLIENT RPCs
-- ═══════════════════════════════════════════════════════════════════

-- ── create_recurring_expense ──────────────────────────────────────
create or replace function create_recurring_expense(
  p_title        text,
  p_amount_cents bigint,
  p_frequency    text,
  p_first_run_at date,
  p_type         text    default 'expense',
  p_category_id  uuid    default null,
  p_account_id   uuid    default null,
  p_note         text    default null
) returns jsonb language plpgsql security definer as $$
declare
  v_user_id        uuid := auth.uid();
  v_tier           text;
  v_count          integer;
  v_requires_premium boolean;
  v_new_id         uuid;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  select subscription_tier into v_tier from profiles where id = v_user_id;

  select count(*) into v_count from recurring_expenses
  where user_id = v_user_id and deleted_at is null;

  if v_tier = 'free' and v_count >= 3 then
    raise exception 'Free tier limit reached (3 recurring expenses). Upgrade to Premium for unlimited.'
      using errcode = 'P0001', hint = 'upgrade_required';
  end if;

  v_requires_premium := (v_tier <> 'free') and (v_count >= 3);

  if p_category_id is not null and not exists (
    select 1 from categories where id = p_category_id and user_id = v_user_id and deleted_at is null
  ) then raise exception 'Category does not belong to you'; end if;

  if p_account_id is not null and not exists (
    select 1 from accounts where id = p_account_id and user_id = v_user_id and deleted_at is null
  ) then raise exception 'Account does not belong to you'; end if;

  insert into recurring_expenses (
    user_id, title, amount_cents, type, category_id, account_id, note, frequency, next_run_at, requires_premium
  ) values (
    v_user_id, trim(p_title), p_amount_cents, p_type, p_category_id, p_account_id, p_note, p_frequency, p_first_run_at,
    v_requires_premium
  ) returning id into v_new_id;

  return jsonb_build_object('recurring_expense_id', v_new_id, 'requires_premium', v_requires_premium);
end; $$;


-- ── update_recurring_expense ──────────────────────────────────────
create or replace function update_recurring_expense(
  p_id           uuid,
  p_title        text    default null,
  p_amount_cents bigint  default null,
  p_frequency    text    default null,
  p_next_run_at  date    default null,
  p_type         text    default null,
  p_category_id  uuid    default null,
  p_account_id   uuid    default null,
  p_note         text    default null
) returns void language plpgsql security definer as $$
declare v_user_id uuid := auth.uid(); begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  update recurring_expenses set
    title        = coalesce(p_title,        title),
    amount_cents = coalesce(p_amount_cents, amount_cents),
    frequency    = coalesce(p_frequency,    frequency),
    next_run_at  = coalesce(p_next_run_at,  next_run_at),
    type         = coalesce(p_type,         type),
    category_id  = p_category_id,
    account_id   = p_account_id,
    note         = p_note
  where id = p_id and user_id = v_user_id and deleted_at is null;

  if not found then raise exception 'Recurring expense not found'; end if;
end; $$;


-- ── toggle_recurring_expense ──────────────────────────────────────
create or replace function toggle_recurring_expense(p_id uuid, p_is_active boolean)
returns void language plpgsql security definer as $$
declare v_user_id uuid := auth.uid(); begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  update recurring_expenses set is_active = p_is_active
  where id = p_id and user_id = v_user_id and deleted_at is null;
  if not found then raise exception 'Recurring expense not found'; end if;
end; $$;


-- ── delete_recurring_expense ──────────────────────────────────────
create or replace function delete_recurring_expense(p_id uuid)
returns void language plpgsql security definer as $$
declare v_user_id uuid := auth.uid(); begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  update recurring_expenses set deleted_at = now(), is_active = false
  where id = p_id and user_id = v_user_id and deleted_at is null;
  if not found then raise exception 'Recurring expense not found'; end if;
end; $$;


-- ── create_recurring_split_bill ───────────────────────────────────
-- p_shares: [{"user_id":"<uuid>","share_cents":<int|null>}, ...]
-- For equal split pass share_cents as null in each element.
-- Creator must include themselves in p_shares (they are the payer).
create or replace function create_recurring_split_bill(
  p_title        text,
  p_amount_cents bigint,
  p_frequency    text,
  p_first_run_at date,
  p_split_method text,
  p_shares       jsonb,
  p_category_id  uuid default null,
  p_account_id   uuid default null,
  p_note         text default null
) returns jsonb language plpgsql security definer as $$
declare
  v_user_id          uuid := auth.uid();
  v_tier             text;
  v_count            integer;
  v_requires_premium boolean;
  v_new_id           uuid;
  v_share            record;
  v_total_custom     bigint := 0;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  select subscription_tier into v_tier from profiles where id = v_user_id;

  select count(*) into v_count from recurring_split_bills
  where user_id = v_user_id and deleted_at is null;

  if v_tier = 'free' and v_count >= 1 then
    raise exception 'Free tier limit reached (1 recurring split bill). Upgrade to Premium for unlimited.'
      using errcode = 'P0001', hint = 'upgrade_required';
  end if;

  v_requires_premium := (v_tier <> 'free') and (v_count >= 1);

  if p_category_id is not null and not exists (
    select 1 from categories where id = p_category_id and user_id = v_user_id and deleted_at is null
  ) then raise exception 'Category does not belong to you'; end if;

  if p_account_id is not null and not exists (
    select 1 from accounts where id = p_account_id and user_id = v_user_id and deleted_at is null
  ) then raise exception 'Account does not belong to you'; end if;

  if not exists (
    select 1 from jsonb_array_elements(p_shares) s where (s->>'user_id')::uuid = v_user_id
  ) then raise exception 'Creator must be included as a participant'; end if;

  if p_split_method = 'custom' then
    select sum((s->>'share_cents')::bigint) into v_total_custom from jsonb_array_elements(p_shares) s;
    if v_total_custom <> p_amount_cents then
      raise exception 'Custom shares must sum to total amount.'
        using errcode = 'P0001', hint = 'invalid_shares';
    end if;
  end if;

  insert into recurring_split_bills (
    user_id, title, amount_cents, split_method, category_id, account_id, note, frequency, next_run_at, requires_premium
  ) values (
    v_user_id, trim(p_title), p_amount_cents, p_split_method, p_category_id, p_account_id, p_note, p_frequency, p_first_run_at,
    v_requires_premium
  ) returning id into v_new_id;

  for v_share in
    select (s->>'user_id')::uuid as user_id, (s->>'share_cents')::bigint as share_cents
    from jsonb_array_elements(p_shares) s
  loop
    if v_share.user_id <> v_user_id and not exists (
      select 1 from contacts where owner_id = v_user_id and friend_id = v_share.user_id and deleted_at is null
    ) then raise exception 'Participant is not in your contacts: %', v_share.user_id; end if;

    insert into recurring_split_bill_shares (recurring_split_bill_id, user_id, share_cents)
    values (v_new_id, v_share.user_id,
      case when p_split_method = 'custom' then v_share.share_cents else null end);
  end loop;

  return jsonb_build_object('recurring_split_bill_id', v_new_id, 'requires_premium', v_requires_premium);
end; $$;


-- ── update_recurring_split_bill ───────────────────────────────────
-- If p_shares is provided it replaces all participants entirely.
create or replace function update_recurring_split_bill(
  p_id           uuid,
  p_title        text    default null,
  p_amount_cents bigint  default null,
  p_frequency    text    default null,
  p_next_run_at  date    default null,
  p_split_method text    default null,
  p_category_id  uuid    default null,
  p_account_id   uuid    default null,
  p_note         text    default null,
  p_shares       jsonb   default null
) returns void language plpgsql security definer as $$
declare
  v_user_id   uuid := auth.uid();
  v_template  record;
  v_share     record;
  v_method    text;
  v_amount    bigint;
  v_total     bigint := 0;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  select * into v_template from recurring_split_bills
  where id = p_id and user_id = v_user_id and deleted_at is null;
  if not found then raise exception 'Recurring split bill not found'; end if;

  v_method := coalesce(p_split_method, v_template.split_method);
  v_amount := coalesce(p_amount_cents, v_template.amount_cents);

  if p_shares is not null and v_method = 'custom' then
    select sum((s->>'share_cents')::bigint) into v_total from jsonb_array_elements(p_shares) s;
    if v_total <> v_amount then
      raise exception 'Custom shares must sum to total amount.'
        using errcode = 'P0001', hint = 'invalid_shares';
    end if;
  end if;

  update recurring_split_bills set
    title        = coalesce(p_title,        title),
    amount_cents = v_amount,
    split_method = v_method,
    frequency    = coalesce(p_frequency,    frequency),
    next_run_at  = coalesce(p_next_run_at,  next_run_at),
    category_id  = p_category_id,
    account_id   = p_account_id,
    note         = p_note
  where id = p_id;

  if p_shares is not null then
    delete from recurring_split_bill_shares where recurring_split_bill_id = p_id;

    for v_share in
      select (s->>'user_id')::uuid as user_id, (s->>'share_cents')::bigint as share_cents
      from jsonb_array_elements(p_shares) s
    loop
      if v_share.user_id <> v_user_id and not exists (
        select 1 from contacts where owner_id = v_user_id and friend_id = v_share.user_id and deleted_at is null
      ) then raise exception 'Participant is not in your contacts: %', v_share.user_id; end if;

      insert into recurring_split_bill_shares (recurring_split_bill_id, user_id, share_cents)
      values (p_id, v_share.user_id,
        case when v_method = 'custom' then v_share.share_cents else null end);
    end loop;
  end if;
end; $$;


-- ── toggle_recurring_split_bill ───────────────────────────────────
create or replace function toggle_recurring_split_bill(p_id uuid, p_is_active boolean)
returns void language plpgsql security definer as $$
declare v_user_id uuid := auth.uid(); begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  update recurring_split_bills set is_active = p_is_active
  where id = p_id and user_id = v_user_id and deleted_at is null;
  if not found then raise exception 'Recurring split bill not found'; end if;
end; $$;


-- ── delete_recurring_split_bill ───────────────────────────────────
create or replace function delete_recurring_split_bill(p_id uuid)
returns void language plpgsql security definer as $$
declare v_user_id uuid := auth.uid(); begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;
  update recurring_split_bills set deleted_at = now(), is_active = false
  where id = p_id and user_id = v_user_id and deleted_at is null;
  if not found then raise exception 'Recurring split bill not found'; end if;
end; $$;


-- ═══════════════════════════════════════════════════════════════════
-- 8. INTERNAL CRON RPC
-- Called by pg_cron daily at 16:00 UTC (00:00 MYT, midnight Malaysia time).
-- security definer bypasses RLS so it can write on behalf of any user.
-- ═══════════════════════════════════════════════════════════════════

create or replace function process_recurring_jobs()
returns jsonb language plpgsql security definer as $$
declare
  v_rec             record;
  v_rsb             record;
  v_share           record;
  v_bill_id         uuid;
  v_participant_cnt integer;
  v_equal_cents     bigint;
  v_remainder       bigint;
  v_share_idx       integer;
  v_fired_expenses  integer := 0;
  v_fired_splits    integer := 0;
begin

  -- ── Recurring expenses ───────────────────────────────────────────
  for v_rec in
    select * from recurring_expenses
    where is_active = true and deleted_at is null and next_run_at <= current_date
    order by next_run_at
  loop
    insert into expenses (
      user_id, type, source, source_recurring_expense_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      category_id, account_id, note, expense_date
    ) values (
      v_rec.user_id, v_rec.type, 'recurring', v_rec.id,
      v_rec.amount_cents, 'MYR',
      v_rec.amount_cents, 'MYR', 1,
      v_rec.category_id, v_rec.account_id,
      coalesce(v_rec.note, v_rec.title), current_date
    );

    update recurring_expenses set next_run_at = case v_rec.frequency
      when 'daily'   then v_rec.next_run_at + interval '1 day'
      when 'monthly' then v_rec.next_run_at + interval '1 month'
      when 'yearly'  then v_rec.next_run_at + interval '1 year'
    end where id = v_rec.id;

    v_fired_expenses := v_fired_expenses + 1;
  end loop;


  -- ── Recurring split bills ────────────────────────────────────────
  for v_rsb in
    select * from recurring_split_bills
    where is_active = true and deleted_at is null and next_run_at <= current_date
    order by next_run_at
  loop
    select count(*) into v_participant_cnt
    from recurring_split_bill_shares where recurring_split_bill_id = v_rsb.id;

    insert into split_bills (
      created_by, paid_by,
      total_amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      note, expense_date, category_id
    ) values (
      v_rsb.user_id, v_rsb.user_id,
      v_rsb.amount_cents, 'MYR',
      v_rsb.amount_cents, 'MYR', 1,
      coalesce(v_rsb.note, v_rsb.title), current_date, v_rsb.category_id
    ) returning id into v_bill_id;

    if v_rsb.split_method = 'equal' then
      v_equal_cents := v_rsb.amount_cents / v_participant_cnt;
      v_remainder   := v_rsb.amount_cents - (v_equal_cents * v_participant_cnt);
      v_share_idx   := 0;

      for v_share in
        select * from recurring_split_bill_shares
        where recurring_split_bill_id = v_rsb.id
        order by created_at  -- stable order so remainder goes to first N participants
      loop
        v_share_idx := v_share_idx + 1;
        insert into split_bill_shares (split_bill_id, user_id, share_cents, split_method, status)
        values (
          v_bill_id, v_share.user_id,
          v_equal_cents + case when v_share_idx <= v_remainder then 1 else 0 end,
          'equal',
          case when v_share.user_id = v_rsb.user_id then 'settled' else 'pending' end
        );
      end loop;

    else  -- custom
      for v_share in
        select * from recurring_split_bill_shares where recurring_split_bill_id = v_rsb.id
      loop
        insert into split_bill_shares (split_bill_id, user_id, share_cents, split_method, status)
        values (
          v_bill_id, v_share.user_id,
          v_share.share_cents,
          'exact',
          case when v_share.user_id = v_rsb.user_id then 'settled' else 'pending' end
        );
      end loop;
    end if;

    -- Auto-create payer's expense (full bill amount)
    insert into expenses (
      user_id, type, source, source_split_bill_id, source_recurring_split_bill_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      category_id, account_id, note, expense_date
    ) values (
      v_rsb.user_id, 'expense', 'recurring', v_bill_id, v_rsb.id,
      v_rsb.amount_cents, 'MYR',
      v_rsb.amount_cents, 'MYR', 1,
      v_rsb.category_id, v_rsb.account_id, coalesce(v_rsb.note, v_rsb.title), current_date
    );

    update recurring_split_bills set next_run_at = case v_rsb.frequency
      when 'daily'   then v_rsb.next_run_at + interval '1 day'
      when 'monthly' then v_rsb.next_run_at + interval '1 month'
      when 'yearly'  then v_rsb.next_run_at + interval '1 year'
    end where id = v_rsb.id;

    v_fired_splits := v_fired_splits + 1;
  end loop;

  return jsonb_build_object(
    'fired_at',            now(),
    'expenses_created',    v_fired_expenses,
    'split_bills_created', v_fired_splits
  );
end; $$;


-- ═══════════════════════════════════════════════════════════════════
-- 9. SUBSCRIPTION EXPIRY HANDLER
-- Runs before the recurring cron. Handles expired premium users:
--   • If referral_premium_expires_at is still active → transition to referral premium
--   • Otherwise → downgrade to free
-- Then deactivates premium-only recurring items for all free users:
--   • recurring_expenses:    deactivate where requires_premium = true
--   • recurring_split_bills: deactivate where requires_premium = true
-- The app detects the tier change on next launch and shows a notice.
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
  -- Step 1: Handle expired premium users
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

  -- Step 2: Deactivate premium items for ALL free users
  -- (handles manual downgrades, failed runs, and the loop above)
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
end; $$;


-- ═══════════════════════════════════════════════════════════════════
-- 10. PG_CRON SETUP
-- Enable via: Supabase Dashboard → Database → Extensions → pg_cron
-- Order: expirations run at 00:00 MYT, recurring jobs run at 00:10 MYT
-- so downgraded users are already capped before jobs fire.
-- ═══════════════════════════════════════════════════════════════════

-- create extension if not exists pg_cron;  -- enable in Dashboard first

select cron.schedule(
  'process-subscription-expirations',  -- unique job name
  '0 16 * * *',                        -- 16:00 UTC daily (= 00:00 MYT)
  $$ select process_subscription_expirations() $$
);

select cron.schedule(
  'process-recurring-jobs',   -- unique job name
  '10 16 * * *',              -- 16:10 UTC daily (= 00:10 MYT)
  $$ select process_recurring_jobs() $$
);

-- Verify:  select * from cron.job;
-- Remove:  select cron.unschedule('process-subscription-expirations');
--          select cron.unschedule('process-recurring-jobs');

-- If rescheduling an existing recurring job (already registered at 00:00 MYT):
--   select cron.unschedule('process-recurring-jobs');
--   select cron.schedule('process-recurring-jobs', '10 16 * * *', $$ select process_recurring_jobs() $$);
