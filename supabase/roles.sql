-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — roles: owner (founder) vs manager (staff)
--  Run AFTER schema.sql and finance.sql, in: SQL Editor → Run.
--  Safe to re-run (idempotent).
--
--  owner   → full control (founder). Sees commission %, edits finances.
--  manager → manages bookings, VIEWS finances read-only, no % editing.
-- ════════════════════════════════════════════════════════════

-- ─── 1. Staff directory: who may log in and at what role ──────
create table if not exists staff (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  role       text not null default 'manager' check (role in ('owner','manager')),
  created_at timestamptz default now()
);

-- ─── 2. Role helper (security definer so it can read `staff`) ──
create or replace function public.is_owner()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and role = 'owner');
$$;
grant execute on function public.is_owner() to authenticated, anon;

-- ─── 3. RLS on staff: a user may read their own row; owner reads all ──
alter table staff enable row level security;
drop policy if exists "read own staff" on staff;
create policy "read own staff" on staff
  for select using (id = auth.uid() or public.is_owner());
grant select on staff to authenticated;

-- ─── 4. Seed the founder as owner ─────────────────────────────
--  ⚠️ Replace the email below with YOUR admin login email if different.
insert into staff (id, email, role)
  select id, email, 'owner' from auth.users
  where lower(email) = lower('kiladzedaviti99@gmail.com')
  on conflict (id) do update set role = 'owner';

--  To add an administrator (manager): first create their login in
--  Supabase → Authentication → Add user, then run (with their email):
--
--  insert into staff (id, email, role)
--    select id, email, 'manager' from auth.users
--    where lower(email) = lower('manager@example.com')
--    on conflict (id) do update set role = 'manager';

-- ─── 5. Finances: all staff VIEW, only owner CHANGES ──────────
drop policy if exists "auth all finance"    on finance_entries;
drop policy if exists "staff read finance"  on finance_entries;
drop policy if exists "owner write finance" on finance_entries;
create policy "staff read finance" on finance_entries
  for select using (auth.role() = 'authenticated');
create policy "owner write finance" on finance_entries
  for all using (public.is_owner()) with check (public.is_owner());

-- ─── 6. Commission %: only the owner may change it ────────────
drop policy if exists "auth update barbers"  on barbers;
drop policy if exists "owner update barbers" on barbers;
create policy "owner update barbers" on barbers
  for update using (public.is_owner()) with check (public.is_owner());

-- (bookings policies unchanged — both owner and manager fully manage them)

-- ─── 7. Realtime: broadcast booking changes to both panels live ──
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='bookings'
  ) then
    alter publication supabase_realtime add table bookings;
  end if;
end $$;

notify pgrst, 'reload schema';
