-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — let managers add/edit/delete finances
--  Run AFTER roles.sql, in: SQL Editor → Run. Idempotent.
--
--  Day-to-day money handling (paying out salaries, logging expenses
--  and extra income) is done by managers now, not only the owner.
--  We widen the finance_entries WRITE policy from owner-only to any
--  authenticated staff. READ stays as-is (both owner & manager view).
-- ════════════════════════════════════════════════════════════

drop policy if exists "owner write finance" on finance_entries;
drop policy if exists "auth all finance"    on finance_entries;
drop policy if exists "staff write finance"  on finance_entries;

create policy "staff write finance" on finance_entries
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

notify pgrst, 'reload schema';
