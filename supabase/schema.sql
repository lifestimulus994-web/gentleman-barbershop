-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — database schema + seed data
--  Run once in: Supabase Dashboard → SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════

create extension if not exists btree_gist;

-- ─── Tables ──────────────────────────────────────────────────
create table if not exists barbers (
  id      uuid primary key default gen_random_uuid(),
  name_ka text not null,
  name_en text not null unique,
  sort    int  default 0,
  active  boolean default true
);

create table if not exists services (
  id           uuid primary key default gen_random_uuid(),
  name_ka      text not null,
  name_en      text not null unique,
  price        int  not null,
  duration_min int  not null,
  sort         int  default 0,
  active       boolean default true
);

-- weekday: 0=Sunday … 6=Saturday (matches JS Date.getDay())
create table if not exists working_hours (
  id         uuid primary key default gen_random_uuid(),
  barber_id  uuid not null references barbers(id) on delete cascade,
  weekday    int  not null check (weekday between 0 and 6),
  open_time  time not null,
  close_time time not null,
  unique (barber_id, weekday)
);

create table if not exists bookings (
  id             uuid primary key default gen_random_uuid(),
  barber_id      uuid not null references barbers(id),
  service_id     uuid not null references services(id),
  customer_name  text not null,
  customer_phone text not null,
  starts_at      timestamp not null,   -- local Tbilisi time, no tz
  ends_at        timestamp not null,
  status         text not null default 'confirmed',
  created_at     timestamptz default now(),
  -- prevents double-booking the same barber at overlapping times
  constraint no_overlap exclude using gist (
    barber_id with =,
    tsrange(starts_at, ends_at) with &&
  ) where (status <> 'cancelled')
);

-- ─── Seed: barbers ───────────────────────────────────────────
insert into barbers (name_ka, name_en, sort) values
  ('რუსლანი', 'Ruslan', 1),
  ('თაზო',    'Tazo',   2),
  ('რაული',   'Rauli',  3),
  ('მარი',    'Mari',   4),
  ('ნაბი',    'Nabi',   5)
on conflict do nothing;

-- ─── Seed: services ──────────────────────────────────────────
insert into services (name_ka, name_en, price, duration_min, sort) values
  ('თმის შეჭრა',        'Haircut',        35, 30,  1),
  ('წვერის შესწორება',  'Beard trim',     30, 30,  2),
  ('თმა + წვერი',       'Hair + Beard',   60, 60,  3),
  ('გადაპარსვა',        'Shave',          20, 20,  4),
  ('გადაპარსვა + წვერი','Shave + Beard',  50, 50,  5),
  ('ბავშვი',            'Kids',           30, 30,  6),
  ('თმის დაწვნა',       'Hair styling',   10, 20,  7),
  ('თმის შეღებვა',      'Hair coloring',  50, 60,  8),
  ('წვერის შეღებვა',    'Beard coloring', 30, 40,  9),
  ('შუგარინგი',         'Sugaring',        5, 20, 10),
  ('წარბები',           'Eyebrows',       20, 20, 11)
on conflict do nothing;

-- ─── Seed: working hours (all 11:00–20:00, minus each barber's day off) ──
-- Days off → Ruslan: Mon | Tazo: Mon+Tue | Rauli: Thu | Mari: Tue | Nabi: none
insert into working_hours (barber_id, weekday, open_time, close_time)
select b.id, d.weekday, time '11:00', time '20:00'
from barbers b
cross join generate_series(0,6) as d(weekday)
where not (
     (b.name_en = 'Ruslan' and d.weekday in (1))
  or (b.name_en = 'Tazo'   and d.weekday in (1,2))
  or (b.name_en = 'Rauli'  and d.weekday in (4))
  or (b.name_en = 'Mari'   and d.weekday in (2))
)
on conflict do nothing;

-- ─── Row Level Security ──────────────────────────────────────
alter table barbers       enable row level security;
alter table services      enable row level security;
alter table working_hours enable row level security;
alter table bookings      enable row level security;

-- public (anon) may read the catalog
drop policy if exists "read barbers"  on barbers;
drop policy if exists "read services" on services;
drop policy if exists "read hours"    on working_hours;
create policy "read barbers"  on barbers       for select using (active);
create policy "read services" on services      for select using (active);
create policy "read hours"    on working_hours for select using (true);

-- public (anon) may create a booking, but NOT read others' bookings (PII)
drop policy if exists "create booking"     on bookings;
drop policy if exists "auth read bookings" on bookings;
drop policy if exists "auth edit bookings" on bookings;
create policy "create booking"     on bookings for insert with check (true);
create policy "auth read bookings" on bookings for select using (auth.role() = 'authenticated');
create policy "auth edit bookings" on bookings for update using (auth.role() = 'authenticated');

-- table grants for the API roles
grant usage on schema public to anon, authenticated;
grant select on barbers, services, working_hours to anon, authenticated;
grant insert on bookings to anon, authenticated;
grant select, update, delete on bookings to authenticated;

-- ─── busy_slots(): anon-callable, returns only busy time ranges (no PII) ──
create or replace function public.busy_slots(p_barber uuid, p_date date)
returns table (starts_at timestamp, ends_at timestamp)
language sql
security definer
set search_path = public
as $$
  select starts_at, ends_at
  from bookings
  where barber_id = p_barber
    and starts_at::date = p_date
    and status <> 'cancelled';
$$;
grant execute on function public.busy_slots(uuid, date) to anon, authenticated;
