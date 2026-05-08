-- Fix: create_recurring_expense now fires the first expense immediately
-- when first_run_at is today, instead of waiting for the midnight cron.
-- next_run_at is advanced to the next occurrence so the cron won't double-fire.

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
      category_id, account_id, note, expense_date
    ) values (
      v_user_id, p_type, 'recurring', v_new_id,
      p_amount_cents, 'MYR',
      p_amount_cents, 'MYR', 1,
      p_category_id, p_account_id, coalesce(p_note, trim(p_title)), current_date
    ) returning id into v_expense_id;
  end if;

  return jsonb_build_object(
    'recurring_expense_id', v_new_id,
    'requires_premium',     v_requires_premium,
    'expense_id',           v_expense_id
  );
end; $$;
