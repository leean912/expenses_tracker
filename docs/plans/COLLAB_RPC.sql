-- Run both functions in the Supabase SQL Editor.
-- They replace the client-side aggregation in collab_analysis_provider.dart and
-- collab_expenses_provider.dart, which were vulnerable to the 1000-row PostgREST limit.

-- ── 1. collab_summary ─────────────────────────────────────────────────────────
-- All-time totals for a collab (no date filter).
-- Returns the collab's lifetime net spend + per-member net spend.
-- Used by: detail screen header, members screen.
create or replace function collab_summary(p_collab_id uuid)
returns json
language sql
security definer
as $$
  with
  base as (
    select
      e.user_id,
      e.home_amount_cents,
      e.type,
      p.display_name
    from expenses e
    left join profiles p on p.id = e.user_id
    where e.collab_id   = p_collab_id
      and e.deleted_at  is null
      and e.archived_at is null
  ),
  totals as (
    select
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0) as total_spent_cents,
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0) as total_income_cents
    from base
  ),
  member_totals as (
    select
      user_id,
      display_name,
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0) -
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0) as spent_cents
    from base
    group by user_id, display_name
  )
  select json_build_object(
    'total_spent_cents',  (select total_spent_cents  - total_income_cents from totals),
    'total_income_cents', (select total_income_cents from totals),
    'member_totals',
        coalesce((select json_agg(row_to_json(member_totals)) from member_totals), '[]'::json)
  );
$$;


-- ── 2. collab_analytics ───────────────────────────────────────────────────────
-- Date-filtered aggregated analytics for a collab.
-- Returns self-only category/account breakdowns + daily buckets per member.
-- Dart does day-level bucketing on the pre-aggregated rows (max 365 rows/year).
-- Used by: analysis screen.
create or replace function collab_analytics(
  p_collab_id uuid,
  p_start      date,
  p_end        date
)
returns json
language sql
security definer
as $$
  with
  base as (
    select
      e.user_id,
      e.home_amount_cents,
      e.type,
      e.expense_date,
      e.category_id,
      e.account_id,
      c.name  as category_name,
      c.color as category_color,
      a.name  as account_name,
      p.display_name
    from expenses e
    left join categories c on c.id = e.category_id
    left join accounts  a on a.id = e.account_id
    left join profiles  p on p.id = e.user_id
    where e.collab_id    = p_collab_id
      and e.expense_date between p_start and p_end
      and e.deleted_at   is null
      and e.archived_at  is null
  ),
  totals as (
    select
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0) as total_spent_cents,
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0) as total_income_cents
    from base
  ),
  self_cat as (
    select
      category_id,
      category_name,
      category_color,
      coalesce(sum(home_amount_cents), 0) as total_cents
    from base
    where type    = 'expense'
      and user_id = auth.uid()
    group by category_id, category_name, category_color
  ),
  self_account as (
    select
      account_id,
      account_name,
      coalesce(sum(home_amount_cents), 0) as total_cents
    from base
    where type    = 'expense'
      and user_id = auth.uid()
    group by account_id, account_name
  ),
  daily_buckets as (
    select
      expense_date                                                              as bucket_date,
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0)      as spend_cents,
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0)      as income_cents
    from base
    group by expense_date
    order by expense_date
  ),
  daily_member as (
    select
      expense_date                                                              as bucket_date,
      user_id,
      display_name,
      coalesce(sum(home_amount_cents) filter (where type = 'expense'), 0)      as spend_cents,
      coalesce(sum(home_amount_cents) filter (where type = 'income'),  0)      as income_cents
    from base
    group by expense_date, user_id, display_name
    order by expense_date
  )
  select json_build_object(
    'total_spent_cents',    (select total_spent_cents  from totals),
    'total_income_cents',   (select total_income_cents from totals),
    'self_category',
        coalesce((select json_agg(row_to_json(self_cat))      from self_cat),      '[]'::json),
    'self_account',
        coalesce((select json_agg(row_to_json(self_account))  from self_account),  '[]'::json),
    'daily_buckets',
        coalesce((select json_agg(row_to_json(daily_buckets)) from daily_buckets), '[]'::json),
    'daily_member_buckets',
        coalesce((select json_agg(row_to_json(daily_member))  from daily_member),  '[]'::json)
  );
$$;
