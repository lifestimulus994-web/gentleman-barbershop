-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — finances (income / salaries / ledger)
--  Run once in: Supabase Dashboard → SQL Editor → New query → Run
--  Safe to re-run (idempotent).
-- ════════════════════════════════════════════════════════════

-- ─── Per-barber commission % (barber's salary share of each service) ──
alter table barbers
  add column if not exists commission_pct int not null default 50
  check (commission_pct between 0 and 100);

-- ─── Payment channel on a completed booking ───────────────────────
--  Set when a booking is marked 'done':
--    cash → ქეში | bog → საქართველოს ბანკი | tbc → თიბისი ბანკი
alter table bookings
  add column if not exists payment_method text
  check (payment_method in ('cash','bog','tbc'));

-- ─── Manual ledger: extra income + expenses the admin enters by hand ──
--  kind = 'income'  → adds to revenue   (პროდუქცია, ყავა, დაბანა, სასმელი…)
--  kind = 'expense' → subtracts         (ხარჯი, ხელფასის გატანა…)
create table if not exists finance_entries (
  id         uuid primary key default gen_random_uuid(),
  entry_date date not null default current_date,
  kind       text not null check (kind in ('income','expense')),
  category   text not null,            -- e.g. 'პროდუქცია', 'ხარჯი'
  label      text,                     -- optional free note / description
  amount     numeric(10,2) not null check (amount >= 0),
  barber_id  uuid references barbers(id) on delete set null,  -- optional link
  created_at timestamptz default now()
);

create index if not exists finance_entries_date_idx on finance_entries(entry_date);

-- ─── Row Level Security: only authenticated admins touch finances ──
alter table finance_entries enable row level security;

drop policy if exists "auth all finance"   on finance_entries;
drop policy if exists "auth update barbers" on barbers;

create policy "auth all finance" on finance_entries
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- allow admins to edit each barber's commission %
create policy "auth update barbers" on barbers
  for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- ─── Grants for the API roles ────────────────────────────────
grant select, insert, update, delete on finance_entries to authenticated;
grant update on barbers to authenticated;

-- ─── Tell PostgREST to reload its schema cache (avoids "table/column not found") ──
notify pgrst, 'reload schema';
