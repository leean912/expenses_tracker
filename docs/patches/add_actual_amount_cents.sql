-- Patch: add actual_amount_cents to expenses table
--
-- actual_amount_cents = the user's real out-of-pocket in home currency:
--   • personal expense (manual/recurring): same as home_amount_cents
--   • split_payer expense: payer's own share only (not the full bill total)
--   • settlement expense: share amount (same as home_amount_cents)
--   • income rows: keep same as home_amount_cents (excluded from all spend calcs)
--
-- Run steps in order in the Supabase SQL editor.

-- ── Step 1: Add column ────────────────────────────────────────────────────────

alter table expenses add column if not exists actual_amount_cents bigint;

-- ── Step 2: Backfill existing rows ────────────────────────────────────────────
-- All non-split_payer rows are already correct (actual = full amount).
-- split_payer rows from before this patch will remain wrong (full bill = actual),
-- but that's acceptable for historical data.

update expenses set actual_amount_cents = home_amount_cents
where actual_amount_cents is null;

-- ── Step 3: Update create_split_bill ─────────────────────────────────────────
-- Sets actual_amount_cents on the payer's auto-expense to their share only.

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
  p_home_amount_cents bigint default null,
  p_home_currency text default null,
  p_conversion_rate numeric default null,
  p_account_id uuid default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id                uuid := auth.uid();
  v_bill_id                uuid;
  v_expense_id             uuid;
  v_share                  record;
  v_payer_share_cents      bigint;
  v_payer_share_home_cents bigint;
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
      where id = p_category_id
        and user_id = v_user_id
        and deleted_at is null
    ) then
      raise exception 'Category does not belong to you';
    end if;
  end if;

  if p_account_id is not null then
    if not exists (
      select 1 from accounts
      where id = p_account_id
        and user_id = v_user_id
        and is_archived = false
        and deleted_at is null
    ) then
      raise exception 'Account does not belong to you';
    end if;
  end if;

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

  for v_share in select * from jsonb_to_recordset(p_shares)
    as x(user_id uuid, share_cents bigint)
  loop
    if v_share.user_id <> v_user_id then
      if not exists (
        select 1 from contacts
        where owner_id = v_user_id
          and friend_id = v_share.user_id
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

  -- Find payer's own share for actual_amount_cents
  select (elem->>'share_cents')::bigint into v_payer_share_cents
  from jsonb_array_elements(p_shares) as elem
  where (elem->>'user_id')::uuid = p_paid_by
  limit 1;

  if p_conversion_rate is not null then
    v_payer_share_home_cents := round(
      coalesce(v_payer_share_cents, 0)::numeric / p_conversion_rate
    )::bigint;
  elsif p_home_currency is not null then
    v_payer_share_home_cents := coalesce(v_payer_share_cents, 0);
  else
    v_payer_share_home_cents := null;
  end if;

  insert into expenses (
    user_id, type, source, source_split_bill_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    actual_amount_cents,
    category_id, account_id, collab_id,
    note, expense_date,
    google_place_id, place_name, latitude, longitude, receipt_url
  ) values (
    p_paid_by, 'expense', 'split_payer', v_bill_id,
    p_total_amount_cents, p_currency,
    p_home_amount_cents, p_home_currency, p_conversion_rate,
    coalesce(v_payer_share_home_cents, p_home_amount_cents),
    p_category_id, p_account_id, p_collab_id,
    coalesce(p_note, 'Split bill'), p_expense_date,
    p_google_place_id, p_place_name, p_latitude, p_longitude, p_receipt_url
  ) returning id into v_expense_id;

  return jsonb_build_object(
    'split_bill_id', v_bill_id,
    'payer_expense_id', v_expense_id
  );
end;
$$;

-- ── Step 4: Update settle_split_share ────────────────────────────────────────
-- Sets actual_amount_cents = share home amount on both expense rows.

create or replace function settle_split_share(
  p_share_id uuid,
  p_category_id uuid default null,
  p_account_id uuid default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id          uuid := auth.uid();
  v_share            record;
  v_bill             record;
  v_settlement_id    uuid;
  v_payer_expense_id uuid;
  v_settler_expense_id uuid;
  v_share_home_cents bigint;
  v_payer_name       text;
  v_settler_name     text;
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

  select coalesce(display_name, username, 'Someone') into v_payer_name
    from profiles where id = v_bill.paid_by;

  select coalesce(display_name, username, 'Someone') into v_settler_name
    from profiles where id = v_user_id;

  if v_bill.conversion_rate is not null then
    v_share_home_cents := round(v_share.share_cents::numeric / v_bill.conversion_rate)::bigint;
  elsif v_bill.home_currency is not null then
    v_share_home_cents := v_share.share_cents;
  else
    v_share_home_cents := null;
  end if;

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

  -- Settler's expense: actual = same as amount (it's all their own money)
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    actual_amount_cents,
    category_id, account_id, collab_id,
    note, expense_date,
    google_place_id, place_name, latitude, longitude
  ) values (
    v_user_id, 'expense', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    v_share_home_cents,
    p_category_id, p_account_id, v_bill.collab_id,
    coalesce('Paid to ' || v_payer_name || ': ' || v_bill.note, 'Paid to ' || v_payer_name), current_date,
    v_bill.google_place_id, v_bill.place_name, v_bill.latitude, v_bill.longitude
  ) returning id into v_settler_expense_id;

  -- Payer's income row
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    actual_amount_cents,
    category_id, collab_id,
    note, expense_date
  ) values (
    v_bill.paid_by, 'income', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    v_share_home_cents,
    v_bill.category_id, v_bill.collab_id,
    coalesce('Received from ' || v_settler_name || ': ' || v_bill.note, 'Received from ' || v_settler_name), current_date
  ) returning id into v_payer_expense_id;

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

-- ── Step 5: Update creator_mark_share_paid ────────────────────────────────────
-- Sets actual_amount_cents on participant expense and creator income rows.

create or replace function creator_mark_share_paid(p_share_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id                uuid := auth.uid();
  v_share                  record;
  v_bill                   record;
  v_settlement_id          uuid;
  v_income_id              uuid;
  v_participant_expense_id uuid;
  v_share_home_cents       bigint;
  v_participant_name       text;
  v_creator_name           text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_share from split_bill_shares where id = p_share_id;
  if not found then
    raise exception 'Share not found';
  end if;

  select * into v_bill from split_bills where id = v_share.split_bill_id;
  if not found then
    raise exception 'Bill not found';
  end if;

  if v_bill.created_by <> v_user_id then
    raise exception 'Only the bill creator can call creator_mark_share_paid';
  end if;

  if v_share.user_id = v_user_id then
    raise exception 'Cannot mark your own share via this function';
  end if;

  if v_share.status <> 'pending' then
    raise exception 'Share is not pending (status: %)', v_share.status;
  end if;

  select coalesce(display_name, username, 'Someone') into v_participant_name
    from profiles where id = v_share.user_id;

  select coalesce(display_name, username, 'Someone') into v_creator_name
    from profiles where id = v_user_id;

  if v_bill.conversion_rate is not null then
    v_share_home_cents := round(v_share.share_cents::numeric / v_bill.conversion_rate)::bigint;
  elsif v_bill.home_currency is not null then
    v_share_home_cents := v_share.share_cents;
  else
    v_share_home_cents := null;
  end if;

  insert into settlements (
    split_bill_id, split_bill_share_id,
    from_user_id, to_user_id,
    amount_cents, currency, note, settled_on
  ) values (
    v_bill.id, v_share.id,
    v_share.user_id, v_user_id,
    v_share.share_cents, v_bill.currency,
    coalesce('Received from ' || v_participant_name || ': ' || v_bill.note,
             'Received from ' || v_participant_name),
    current_date
  ) returning id into v_settlement_id;

  -- Creator income row
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    actual_amount_cents,
    category_id, collab_id,
    note, expense_date
  ) values (
    v_user_id, 'income', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    v_share_home_cents,
    v_bill.category_id, v_bill.collab_id,
    coalesce('Received from ' || v_participant_name || ': ' || v_bill.note,
             'Received from ' || v_participant_name),
    current_date
  ) returning id into v_income_id;

  -- Participant's expense row (category/account null — cross-user categories invalid)
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    actual_amount_cents,
    category_id, account_id, collab_id,
    note, expense_date
  ) values (
    v_share.user_id, 'expense', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    v_share_home_cents,
    null, null, v_bill.collab_id,
    coalesce('Paid to ' || v_creator_name || ': ' || v_bill.note,
             'Paid to ' || v_creator_name),
    current_date
  ) returning id into v_participant_expense_id;

  update split_bill_shares
  set status        = 'settled',
      settled_at    = now(),
      settlement_id = v_settlement_id,
      updated_at    = now()
  where id = p_share_id;

  return jsonb_build_object(
    'settlement_id',          v_settlement_id,
    'income_expense_id',      v_income_id,
    'participant_expense_id', v_participant_expense_id
  );
end;
$$;

-- ── Step 6: Update recurring RPCs ────────────────────────────────────────────
-- create_recurring_expense: actual = full amount (personal expense)
-- create_recurring_split_bill: actual = payer's share only
-- process_recurring_jobs (cron): same rules for both loops

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
  v_user_id          uuid := auth.uid();
  v_tier             text;
  v_count            integer;
  v_requires_premium boolean;
  v_new_id           uuid;
  v_expense_id       uuid := null;
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
    v_user_id, trim(p_title), p_amount_cents, p_type, p_category_id, p_account_id, p_note, p_frequency,
    case when p_first_run_at <= current_date then
      case p_frequency
        when 'daily'   then p_first_run_at + interval '1 day'
        when 'monthly' then p_first_run_at + interval '1 month'
        when 'yearly'  then p_first_run_at + interval '1 year'
      end
    else p_first_run_at end,
    v_requires_premium
  ) returning id into v_new_id;

  if p_first_run_at <= current_date then
    insert into expenses (
      user_id, type, source, source_recurring_expense_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      actual_amount_cents,
      category_id, account_id, note, expense_date
    ) values (
      v_user_id, p_type, 'recurring', v_new_id,
      p_amount_cents, 'MYR',
      p_amount_cents, 'MYR', 1,
      p_amount_cents,
      p_category_id, p_account_id, coalesce(p_note, trim(p_title)), current_date
    ) returning id into v_expense_id;
  end if;

  return jsonb_build_object(
    'recurring_expense_id', v_new_id,
    'requires_premium',     v_requires_premium,
    'expense_id',           v_expense_id
  );
end; $$;


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
  v_user_id           uuid := auth.uid();
  v_tier              text;
  v_count             integer;
  v_requires_premium  boolean;
  v_new_id            uuid;
  v_share             record;
  v_total_custom      bigint := 0;
  v_bill_id           uuid   := null;
  v_participant_cnt   integer;
  v_equal_cents       bigint;
  v_remainder         bigint;
  v_share_idx         integer;
  v_payer_share_cents bigint;
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
    v_user_id, trim(p_title), p_amount_cents, p_split_method, p_category_id, p_account_id, p_note, p_frequency,
    case when p_first_run_at <= current_date then
      case p_frequency
        when 'daily'   then p_first_run_at + interval '1 day'
        when 'monthly' then p_first_run_at + interval '1 month'
        when 'yearly'  then p_first_run_at + interval '1 year'
      end
    else p_first_run_at end,
    v_requires_premium
  ) returning id into v_new_id;

  for v_share in
    select (s->>'user_id')::uuid as user_id, (s->>'share_cents')::bigint as share_cents
    from jsonb_array_elements(p_shares) s
  loop
    if v_share.user_id <> v_user_id and not exists (
      select 1 from contacts where owner_id = v_user_id and friend_id = v_share.user_id
    ) then raise exception 'Participant is not in your contacts: %', v_share.user_id; end if;

    insert into recurring_split_bill_shares (recurring_split_bill_id, user_id, share_cents)
    values (v_new_id, v_share.user_id,
      case when p_split_method = 'custom' then v_share.share_cents else null end);
  end loop;

  if p_first_run_at <= current_date then
    select count(*) into v_participant_cnt
    from recurring_split_bill_shares where recurring_split_bill_id = v_new_id;

    insert into split_bills (
      created_by, paid_by,
      total_amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      note, expense_date, category_id
    ) values (
      v_user_id, v_user_id,
      p_amount_cents, 'MYR',
      p_amount_cents, 'MYR', 1,
      coalesce(p_note, trim(p_title)), current_date, p_category_id
    ) returning id into v_bill_id;

    if p_split_method = 'equal' then
      v_equal_cents := p_amount_cents / v_participant_cnt;
      v_remainder   := p_amount_cents - (v_equal_cents * v_participant_cnt);
      v_share_idx   := 0;

      for v_share in
        select * from recurring_split_bill_shares
        where recurring_split_bill_id = v_new_id
        order by created_at
      loop
        v_share_idx := v_share_idx + 1;
        insert into split_bill_shares (split_bill_id, user_id, share_cents, split_method, status)
        values (
          v_bill_id, v_share.user_id,
          v_equal_cents + case when v_share_idx <= v_remainder then 1 else 0 end,
          'equal',
          case when v_share.user_id = v_user_id then 'settled' else 'pending' end
        );
        if v_share.user_id = v_user_id then
          v_payer_share_cents := v_equal_cents + case when v_share_idx <= v_remainder then 1 else 0 end;
        end if;
      end loop;

    else
      for v_share in
        select * from recurring_split_bill_shares where recurring_split_bill_id = v_new_id
      loop
        insert into split_bill_shares (split_bill_id, user_id, share_cents, split_method, status)
        values (
          v_bill_id, v_share.user_id,
          v_share.share_cents,
          'custom',
          case when v_share.user_id = v_user_id then 'settled' else 'pending' end
        );
        if v_share.user_id = v_user_id then
          v_payer_share_cents := v_share.share_cents;
        end if;
      end loop;
    end if;

    insert into expenses (
      user_id, type, source, source_split_bill_id, source_recurring_split_bill_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      actual_amount_cents,
      category_id, account_id, note, expense_date
    ) values (
      v_user_id, 'expense', 'recurring', v_bill_id, v_new_id,
      p_amount_cents, 'MYR',
      p_amount_cents, 'MYR', 1,
      coalesce(v_payer_share_cents, p_amount_cents),
      p_category_id, p_account_id, coalesce(p_note, trim(p_title)), current_date
    );
  end if;

  return jsonb_build_object(
    'recurring_split_bill_id', v_new_id,
    'requires_premium',        v_requires_premium,
    'split_bill_id',           v_bill_id
  );
end; $$;


create or replace function process_recurring_jobs()
returns jsonb language plpgsql security definer as $$
declare
  v_rec               record;
  v_rsb               record;
  v_share             record;
  v_bill_id           uuid;
  v_participant_cnt   integer;
  v_equal_cents       bigint;
  v_remainder         bigint;
  v_share_idx         integer;
  v_payer_share_cents bigint;
  v_fired_expenses    integer := 0;
  v_fired_splits      integer := 0;
begin

  -- ── Recurring expenses ───────────────────────────────────────────
  for v_rec in
    select * from recurring_expenses
    where is_active = true and deleted_at is null and next_run_at <= (now() at time zone 'Asia/Kuala_Lumpur')::date
    order by next_run_at
  loop
    insert into expenses (
      user_id, type, source, source_recurring_expense_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      actual_amount_cents,
      category_id, account_id, note, expense_date
    ) values (
      v_rec.user_id, v_rec.type, 'recurring', v_rec.id,
      v_rec.amount_cents, 'MYR',
      v_rec.amount_cents, 'MYR', 1,
      v_rec.amount_cents,
      v_rec.category_id, v_rec.account_id,
      coalesce(v_rec.note, v_rec.title), (now() at time zone 'Asia/Kuala_Lumpur')::date
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
    where is_active = true and deleted_at is null and next_run_at <= (now() at time zone 'Asia/Kuala_Lumpur')::date
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
      coalesce(v_rsb.note, v_rsb.title), (now() at time zone 'Asia/Kuala_Lumpur')::date, v_rsb.category_id
    ) returning id into v_bill_id;

    v_payer_share_cents := null;

    if v_rsb.split_method = 'equal' then
      v_equal_cents := v_rsb.amount_cents / v_participant_cnt;
      v_remainder   := v_rsb.amount_cents - (v_equal_cents * v_participant_cnt);
      v_share_idx   := 0;

      for v_share in
        select * from recurring_split_bill_shares
        where recurring_split_bill_id = v_rsb.id
        order by created_at
      loop
        v_share_idx := v_share_idx + 1;
        insert into split_bill_shares (split_bill_id, user_id, share_cents, split_method, status)
        values (
          v_bill_id, v_share.user_id,
          v_equal_cents + case when v_share_idx <= v_remainder then 1 else 0 end,
          'equal',
          case when v_share.user_id = v_rsb.user_id then 'settled' else 'pending' end
        );
        if v_share.user_id = v_rsb.user_id then
          v_payer_share_cents := v_equal_cents + case when v_share_idx <= v_remainder then 1 else 0 end;
        end if;
      end loop;

    else
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
        if v_share.user_id = v_rsb.user_id then
          v_payer_share_cents := v_share.share_cents;
        end if;
      end loop;
    end if;

    insert into expenses (
      user_id, type, source, source_split_bill_id, source_recurring_split_bill_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      actual_amount_cents,
      category_id, account_id, note, expense_date
    ) values (
      v_rsb.user_id, 'expense', 'recurring', v_bill_id, v_rsb.id,
      v_rsb.amount_cents, 'MYR',
      v_rsb.amount_cents, 'MYR', 1,
      coalesce(v_payer_share_cents, v_rsb.amount_cents),
      v_rsb.category_id, v_rsb.account_id, coalesce(v_rsb.note, v_rsb.title), (now() at time zone 'Asia/Kuala_Lumpur')::date
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
