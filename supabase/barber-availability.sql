-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — per-date barber availability
--  Run AFTER schema.sql, in: SQL Editor → Run. Idempotent.
--
--  A row here = the barber is NOT available on that specific date
--  (an ad-hoc absence, even on a normal working day).
--  The website hides that barber's times for that date; staff can
--  still override (add a booking manually) from the admin panels.
-- ════════════════════════════════════════════════════════════

create table if not exists barber_days_off (
  id         uuid primary key default gen_random_uuid(),
  barber_id  uuid not null references barbers(id) on delete cascade,
  off_date   date not null,
  reason     text,
  created_at timestamptz default now(),
  unique (barber_id, off_date)
);
create index if not exists barber_days_off_date_idx on barber_days_off(off_date);

-- ─── RLS: everyone reads (to hide availability), staff manages ──
alter table barber_days_off enable row level security;

drop policy if exists "read days off"        on barber_days_off;
drop policy if exists "staff manage days off" on barber_days_off;
create policy "read days off" on barber_days_off
  for select using (true);
create policy "staff manage days off" on barber_days_off
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

grant select on barber_days_off to anon, authenticated;
grant insert, update, delete on barber_days_off to authenticated;

-- ─── Hard guard: anon (website) can't book/reschedule onto an off day ──
--  Fires on INSERT and UPDATE; staff (authenticated) may override.
create or replace function public.block_unavailable_booking()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.role() = 'anon' and NEW.status <> 'cancelled' then
    if exists (
      select 1 from barber_days_off
      where barber_id = NEW.barber_id and off_date = (NEW.starts_at)::date
    ) then
      raise exception 'barber_unavailable' using errcode = 'P0001';
    end if;
  end if;
  return NEW;
end; $$;

drop trigger if exists trg_block_unavailable on bookings;
create trigger trg_block_unavailable
  before insert or update on bookings
  for each row execute function public.block_unavailable_booking();

notify pgrst, 'reload schema';
