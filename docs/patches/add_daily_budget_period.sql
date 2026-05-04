-- Add 'daily' to the budgets.period check constraint.
-- The old constraint must be dropped and recreated because PostgreSQL
-- does not support ALTER CONSTRAINT for check constraints.

alter table budgets
  drop constraint if exists budgets_period_check;

alter table budgets
  add constraint budgets_period_check
    check (period in ('daily', 'weekly', 'monthly', 'yearly'));
