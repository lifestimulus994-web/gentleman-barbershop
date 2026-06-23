-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — per-date barber working hours
--  Run AFTER schema.sql + barber-availability.sql, in: SQL Editor → Run.
--  Idempotent.
--
--  A row here OVERRIDES the weekly `working_hours` for ONE specific date
--  (e.g. "today Ruslan starts at 12:00 instead of 11:00").
--  Priority when computing a barber's free slots:
--    1) barber_days_off (full day off)  → barber unavailable
--    2) barber_day_hours (this row)     → use these open/close times
--    3) working_hours (weekly default)  → fall back to normal schedule
-- ════════════════════════════════════════════════════════════

create table if not exists barber_day_hours (
  id         uuid primary key default gen_random_uuid(),
  barber_id  uuid not null references barbers(id) on delete cascade,
  work_date  date not null,
  open_time  time not null,
  close_time time not null,
  created_at timestamptz default now(),
  unique (barber_id, work_date),
  check (open_time < close_time)
);
create index if not exists barber_day_hours_date_idx on barber_day_hours(work_date);

-- ─── RLS: everyone reads (website needs it to compute slots), staff manages ──
alter table barber_day_hours enable row level security;

drop policy if exists "read day hours"         on barber_day_hours;
drop policy if exists "staff manage day hours"  on barber_day_hours;
create policy "read day hours" on barber_day_hours
  for select using (true);
create policy "staff manage day hours" on barber_day_hours
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

grant select on barber_day_hours to anon, authenticated;
grant insert, update, delete on barber_day_hours to authenticated;

notify pgrst, 'reload schema';
