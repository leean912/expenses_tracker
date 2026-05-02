-- Patch: add p_account_id to create_split_bill RPC
-- Run this in the Supabase SQL editor.

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
  v_user_id uuid := auth.uid();
  v_bill_id uuid;
  v_expense_id uuid;
  v_share record;
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

  insert into expenses (
    user_id, type, source, source_split_bill_id,
    amount_cents, currency,
    home_amount_cents, home_currency, conversion_rate,
    category_id, account_id, collab_id,
    note, expense_date,
    google_place_id, place_name, latitude, longitude, receipt_url
  ) values (
    p_paid_by, 'expense', 'split_payer', v_bill_id,
    p_total_amount_cents, p_currency,
    p_home_amount_cents, p_home_currency, p_conversion_rate,
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
