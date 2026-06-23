-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — wipe TEST/operational data
--  Run in: Supabase Dashboard → SQL Editor → New query → Run.
--
--  ⚠️ DELETES ALL: bookings (calendar), finance_entries (income/expense),
--     barber_days_off, barber_day_hours.
--  ✅ KEEPS: barbers, services, working_hours (the catalog/config).
--
--  This is IRREVERSIBLE. Only run it when you want a clean slate.
--  NOTE: if a line errors "relation ... does not exist", that table
--  isn't set up yet — just delete that one line and run the rest.
-- ════════════════════════════════════════════════════════════

truncate table bookings         restart identity;
truncate table finance_entries  restart identity;
truncate table barber_days_off  restart identity;
truncate table barber_day_hours restart identity;

-- quick check — each should report 0
select 'bookings'        as t, count(*) from bookings
union all select 'finance_entries',  count(*) from finance_entries
union all select 'barber_days_off',  count(*) from barber_days_off;
