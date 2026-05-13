-- Feature: creator_mark_share_paid RPC
-- Allows the bill creator to mark a participant's pending share as paid on their
-- behalf (e.g. they paid cash and the creator wants to record it).
--
-- What it does atomically:
--   1. INSERT settlements row  (from = participant, to = creator)
--   2. INSERT income expense for the creator
--   3. INSERT expense row for the participant (category_id = null, account_id = null
--      since we can't reference the creator's categories cross-user)
--   4. UPDATE split_bill_shares status = 'settled'

create or replace function creator_mark_share_paid(p_share_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_id          uuid := auth.uid();
  v_share            record;
  v_bill             record;
  v_settlement_id    uuid;
  v_income_id        uuid;
  v_participant_expense_id uuid;
  v_share_home_cents bigint;
  v_participant_name text;
  v_creator_name     text;
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

  -- Compute home amount using the bill's frozen conversion rate
  if v_bill.conversion_rate is not null then
    v_share_home_cents := round(v_share.share_cents::numeric / v_bill.conversion_rate)::bigint;
  elsif v_bill.home_currency is not null then
    v_share_home_cents := v_share.share_cents;
  else
    v_share_home_cents := null;
  end if;

  -- 1. Record the settlement (from = participant, to = creator)
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

  -- 2. Income row for the creator
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    category_id, collab_id,
    note, expense_date
  ) values (
    v_user_id, 'income', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    v_bill.category_id, v_bill.collab_id,
    coalesce('Received from ' || v_participant_name || ': ' || v_bill.note,
             'Received from ' || v_participant_name),
    current_date
  ) returning id into v_income_id;

  -- 3. Expense row for the participant (category/account null — cross-user categories invalid)
  insert into expenses (
    user_id, type, source, source_split_bill_id, source_settlement_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    category_id, account_id, collab_id,
    note, expense_date
  ) values (
    v_share.user_id, 'expense', 'settlement', v_bill.id, v_settlement_id,
    v_share.share_cents, v_bill.currency,
    v_share_home_cents, v_bill.home_currency, v_bill.conversion_rate,
    null, null, v_bill.collab_id,
    coalesce('Paid to ' || v_creator_name || ': ' || v_bill.note,
             'Paid to ' || v_creator_name),
    current_date
  ) returning id into v_participant_expense_id;

  -- 4. Mark the share settled
  update split_bill_shares
  set status        = 'settled',
      settled_at    = now(),
      settlement_id = v_settlement_id,
      updated_at    = now()
  where id = p_share_id;

  return jsonb_build_object(
    'settlement_id',         v_settlement_id,
    'income_expense_id',     v_income_id,
    'participant_expense_id', v_participant_expense_id
  );
end;
$$;
