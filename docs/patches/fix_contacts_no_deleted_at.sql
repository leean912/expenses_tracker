-- Fix: contacts table does not have a deleted_at column.
-- Enhancement: if first_run_at is today, fire the split bill immediately on creation.
-- Run these in the Supabase SQL editor.

-- ── create_recurring_split_bill ───────────────────────────────────
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
  v_bill_id          uuid   := null;
  v_participant_cnt  integer;
  v_equal_cents      bigint;
  v_remainder        bigint;
  v_share_idx        integer;
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

  -- If first run is today or past, fire immediately and advance next_run_at.
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

  -- Fire the first split bill immediately if first_run_at is today or past.
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
      end loop;
    end if;

    insert into expenses (
      user_id, type, source, source_split_bill_id, source_recurring_split_bill_id,
      amount_cents, currency,
      home_amount_cents, home_currency, conversion_rate,
      category_id, account_id, note, expense_date
    ) values (
      v_user_id, 'expense', 'recurring', v_bill_id, v_new_id,
      p_amount_cents, 'MYR',
      p_amount_cents, 'MYR', 1,
      p_category_id, p_account_id, coalesce(p_note, trim(p_title)), current_date
    );
  end if;

  return jsonb_build_object(
    'recurring_split_bill_id', v_new_id,
    'requires_premium',        v_requires_premium,
    'split_bill_id',           v_bill_id
  );
end; $$;


-- ── update_recurring_split_bill ───────────────────────────────────
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
        select 1 from contacts where owner_id = v_user_id and friend_id = v_share.user_id
      ) then raise exception 'Participant is not in your contacts: %', v_share.user_id; end if;

      insert into recurring_split_bill_shares (recurring_split_bill_id, user_id, share_cents)
      values (p_id, v_share.user_id,
        case when v_method = 'custom' then v_share.share_cents else null end);
    end loop;
  end if;
end; $$;
