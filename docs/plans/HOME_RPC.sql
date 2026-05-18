-- Run both functions in the Supabase SQL Editor.
-- They replace the client-side aggregation that was vulnerable to the 1000-row
-- PostgREST limit.  Flutter calls these via supabase.rpc('...').

-- ── 1. home_analytics ─────────────────────────────────────────────────────────
-- Aggregates all analytics for the home screen in a single DB round-trip.
-- Returns both home_amount_cents totals AND actual_amount_cents totals so the
-- Flutter side can switch between "Total" and "Actual" without a re-fetch.
create or replace function home_analytics(p_start date, p_end date)
returns json
language sql
security definer
as $$
  with
  period_exp as (
    select
      e.home_amount_cents,
      coalesce(e.actual_amount_cents, e.home_amount_cents) as actual_cents,
      e.category_id,
      c.name as category_name
    from expenses e
    left join categories c on c.id = e.category_id
    where e.user_id     = auth.uid()
      and e.expense_date between p_start and p_end
      and e.deleted_at  is null
      and e.archived_at is null
      and e.type        = 'expense'
  ),
  this_month as (
    select
      coalesce(sum(home_amount_cents), 0)                                as total_cents,
      coalesce(sum(coalesce(actual_amount_cents, home_amount_cents)), 0) as actual_cents
    from expenses
    where user_id     = auth.uid()
      and expense_date between date_trunc('month', now())::date
                           and (date_trunc('month', now() + interval '1 month') - interval '1 day')::date
      and deleted_at  is null
      and archived_at is null
      and type        = 'expense'
  ),
  last_month as (
    select
      coalesce(sum(home_amount_cents), 0)                                as total_cents,
      coalesce(sum(coalesce(actual_amount_cents, home_amount_cents)), 0) as actual_cents
    from expenses
    where user_id     = auth.uid()
      and expense_date between date_trunc('month', now() - interval '1 month')::date
                           and (date_trunc('month', now()) - interval '1 day')::date
      and deleted_at  is null
      and archived_at is null
      and type        = 'expense'
  ),
  cat_spend as (
    select
      category_id,
      category_name,
      coalesce(sum(home_amount_cents), 0) as total_cents,
      coalesce(sum(actual_cents), 0)      as actual_cents
    from period_exp
    group by category_id, category_name
  ),
  period_totals as (
    select
      coalesce(sum(home_amount_cents), 0) as total_cents,
      coalesce(sum(actual_cents), 0)      as actual_cents
    from period_exp
  )
  select json_build_object(
    'period_total_cents',       (select total_cents  from period_totals),
    'period_actual_cents',      (select actual_cents from period_totals),
    'avg_per_day_cents',
        (select total_cents from period_totals) / greatest(p_end - p_start + 1, 1),
    'actual_avg_per_day_cents',
        (select actual_cents from period_totals) / greatest(p_end - p_start + 1, 1),
    'top_category',
        coalesce((select category_name from cat_spend order by actual_cents desc limit 1), '—'),
    'this_month_total_cents',   (select total_cents  from this_month),
    'this_month_actual_cents',  (select actual_cents from this_month),
    'last_month_total_cents',   (select total_cents  from last_month),
    'last_month_actual_cents',  (select actual_cents from last_month),
    'category_spend',
        coalesce((select json_agg(row_to_json(cat_spend)) from cat_spend), '[]'::json)
  );
$$;


-- ── 2. analysis_summary ───────────────────────────────────────────────────────
-- Aggregates all data needed by the analysis screen.  Returns both total and
-- actual cents for every breakdown so the Total/Actual toggle works without a
-- re-fetch.  Daily granularity is returned; Dart does the week/month bucketing.
create or replace function analysis_summary(
  p_start          date,
  p_end            date,
  p_include_collab boolean default true
)
returns json
language sql
security definer
as $$
  with
  base as (
    select
      e.home_amount_cents,
      coalesce(e.actual_amount_cents, e.home_amount_cents) as actual_cents,
      e.type,
      e.expense_date,
      e.category_id,
      e.account_id,
      c.name  as category_name,
      c.color as category_color,
      a.name  as account_name
    from expenses e
    left join categories c on c.id = e.category_id
    left join accounts  a on a.id = e.account_id
    where e.user_id     = auth.uid()
      and e.expense_date between p_start and p_end
      and e.deleted_at  is null
      and e.archived_at is null
      and (p_include_collab or e.collab_id is null)
  ),
  by_category as (
    select
      category_id,
      category_name,
      category_color,
      coalesce(sum(home_amount_cents), 0) as total_cents,
      coalesce(sum(actual_cents), 0)      as actual_cents
    from base
    where type = 'expense'
    group by category_id, category_name, category_color
  ),
  by_account as (
    select
      account_id,
      account_name,
      coalesce(sum(home_amount_cents), 0) as total_cents,
      coalesce(sum(actual_cents), 0)      as actual_cents
    from base
    where type = 'expense'
    group by account_id, account_name
  ),
  daily_buckets as (
    select
      expense_date                                                              as bucket_date,
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0)      as spend_cents,
      coalesce(sum(actual_cents)      filter (where type = 'expense'), 0)      as actual_cents,
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0)      as income_cents
    from base
    group by expense_date
    order by expense_date
  ),
  daily_cat as (
    select
      expense_date                                as bucket_date,
      category_id,
      coalesce(sum(home_amount_cents), 0)         as spend_cents,
      coalesce(sum(actual_cents), 0)              as actual_cents
    from base
    where type = 'expense'
    group by expense_date, category_id
    order by expense_date
  ),
  totals as (
    select
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0) as total_spent_cents,
      coalesce(sum(actual_cents)      filter (where type = 'expense'), 0) as total_actual_cents,
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0) as total_income_cents
    from base
  )
  select json_build_object(
    'total_spent_cents',      (select total_spent_cents  from totals),
    'total_actual_cents',     (select total_actual_cents from totals),
    'total_income_cents',     (select total_income_cents from totals),
    'by_category',            coalesce((select json_agg(row_to_json(by_category))  from by_category),  '[]'::json),
    'by_account',             coalesce((select json_agg(row_to_json(by_account))   from by_account),   '[]'::json),
    'daily_buckets',          coalesce((select json_agg(row_to_json(daily_buckets)) from daily_buckets),'[]'::json),
    'daily_category_buckets', coalesce((select json_agg(row_to_json(daily_cat))    from daily_cat),    '[]'::json)
  );
$$;
