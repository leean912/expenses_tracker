-- Fix: settle_split_share was setting home_amount_cents = null for same-currency bills
-- (when conversion_rate is null). The home screen displays home_amount_cents, so
-- those settlement expenses appeared as 0. Now same-currency shares copy share_cents.

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

  -- Cross-currency: derive from conversion_rate. Same currency: home = local.
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
