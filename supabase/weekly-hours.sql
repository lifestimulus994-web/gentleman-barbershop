-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — weekly default hours, editable by admin
--  Run once in: Supabase Dashboard → SQL Editor → New query → Run
--  Safe to re-run (idempotent).
-- ════════════════════════════════════════════════════════════

-- ─── Let authenticated admins edit the weekly schedule ────────
--  (working_hours previously was select-only for the panel roles)
drop policy if exists "auth manage hours" on working_hours;
create policy "auth manage hours" on working_hours
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant insert, update, delete on working_hours to authenticated;

-- ─── One-time defaults ────────────────────────────────────────
--  თაზო & რუსლანი → 12:00–17:00, everyone else → 10:00–20:00.
--  Only updates EXISTING weekday rows, so each barber's weekly
--  days off (missing rows) are preserved.
update working_hours wh
set open_time = '12:00', close_time = '17:00'
from barbers b
where b.id = wh.barber_id and b.name_ka in ('თაზო','რუსლანი');

update working_hours wh
set open_time = '10:00', close_time = '20:00'
from barbers b
where b.id = wh.barber_id and b.name_ka not in ('თაზო','რუსლანი');

-- ─── Tell PostgREST to reload its schema cache ────────────────
notify pgrst, 'reload schema';
