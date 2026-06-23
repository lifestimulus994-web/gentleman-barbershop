-- ============================================================
--  Gentleman Barbershop - remove duplicate barbers / services
--  Cause: schema.sql seed ran more than once; random-uuid PK meant
--  "on conflict do nothing" never fired, so names appear twice.
--  Run once: Supabase Dashboard -> SQL Editor -> New query -> Run.
--  Safe to re-run (idempotent).
-- ============================================================

-- 1. Point existing bookings at the surviving barber (kept = lowest sort,id per name)
update bookings
set barber_id = (
  select b2.id from barbers b2
  where b2.name_en = (select b1.name_en from barbers b1 where b1.id = bookings.barber_id)
  order by b2.sort, b2.id
  limit 1
);

-- 2. Point existing bookings at the surviving service
update bookings
set service_id = (
  select s2.id from services s2
  where s2.name_en = (select s1.name_en from services s1 where s1.id = bookings.service_id)
  order by s2.sort, s2.id
  limit 1
);

-- 3. Delete duplicate barbers (their working_hours cascade away)
delete from barbers
where id <> (
  select b2.id from barbers b2
  where b2.name_en = barbers.name_en
  order by b2.sort, b2.id
  limit 1
);

-- 4. Delete duplicate services
delete from services
where id <> (
  select s2.id from services s2
  where s2.name_en = services.name_en
  order by s2.sort, s2.id
  limit 1
);

-- 5. Prevent recurrence: name must be unique
alter table barbers  drop constraint if exists barbers_name_en_key;
alter table barbers  add  constraint barbers_name_en_key  unique (name_en);
alter table services drop constraint if exists services_name_en_key;
alter table services add  constraint services_name_en_key unique (name_en);
