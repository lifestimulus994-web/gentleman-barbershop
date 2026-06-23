-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — customer self-service for bookings
--  Run AFTER schema.sql, in: SQL Editor → Run. Idempotent.
--
--  • Each public booking gets a secret manage_token (the customer keeps it).
--  • The customer can VIEW / RESCHEDULE / CANCEL only via that exact token.
--  • A second upcoming booking from the same phone (public site) is blocked.
-- ════════════════════════════════════════════════════════════

-- ─── 1. Secret token on each booking ──────────────────────────
alter table bookings add column if not exists manage_token uuid;
create index if not exists bookings_manage_token_idx on bookings(manage_token);

-- ─── 2. Block duplicate upcoming bookings from the public site ──
--  Applies to anon (website) only — staff/admin may still add freely.
create or replace function public.block_duplicate_booking()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.role() = 'anon' then
    if exists (
      select 1 from bookings
      where status <> 'cancelled'
        and ends_at > (now() at time zone 'Asia/Tbilisi')
        and regexp_replace(customer_phone, '\D', '', 'g')
            = regexp_replace(NEW.customer_phone, '\D', '', 'g')
    ) then
      raise exception 'duplicate_booking' using errcode = 'P0001';
    end if;
  end if;
  return NEW;
end; $$;

drop trigger if exists trg_block_duplicate on bookings;
create trigger trg_block_duplicate
  before insert on bookings
  for each row execute function public.block_duplicate_booking();

-- ─── 3. View one booking by its token (no other PII leaks) ─────
create or replace function public.get_my_booking(p_token uuid)
returns table(
  id uuid, starts_at timestamp, ends_at timestamp, status text,
  service_id uuid, barber_id uuid, duration_min int,
  service_ka text, service_en text, barber_ka text, barber_en text,
  customer_name text
)
language sql security definer stable set search_path = public as $$
  select b.id, b.starts_at, b.ends_at, b.status,
         b.service_id, b.barber_id, s.duration_min,
         s.name_ka, s.name_en, bb.name_ka, bb.name_en,
         b.customer_name
  from bookings b
  join services s  on s.id  = b.service_id
  join barbers  bb on bb.id = b.barber_id
  where b.manage_token = p_token;
$$;
grant execute on function public.get_my_booking(uuid) to anon, authenticated;

-- ─── 4. Cancel by token ───────────────────────────────────────
create or replace function public.cancel_my_booking(p_token uuid)
returns text language plpgsql security definer set search_path = public as $$
declare b bookings;
begin
  select * into b from bookings where manage_token = p_token;
  if not found              then return 'not_found';        end if;
  if b.status = 'cancelled' then return 'already_cancelled'; end if;
  if b.status = 'done'      then return 'done';             end if;
  if b.starts_at < (now() at time zone 'Asia/Tbilisi') then return 'past'; end if;
  update bookings set status = 'cancelled' where id = b.id;
  return 'ok';
end; $$;
grant execute on function public.cancel_my_booking(uuid) to anon, authenticated;

-- ─── 5. Reschedule by token — change service / barber / time ───
--  (validates working hours + overlap; name & phone stay untouched)
drop function if exists public.reschedule_my_booking(uuid, timestamp, timestamp);
create or replace function public.reschedule_my_booking(
  p_token uuid, p_service uuid, p_barber uuid, p_starts timestamp, p_ends timestamp
) returns text language plpgsql security definer set search_path = public as $$
declare b bookings; v_wd int; wh record; dh record;
begin
  select * into b from bookings where manage_token = p_token;
  if not found                 then return 'not_found';    end if;
  if b.status <> 'confirmed'   then return 'not_editable';  end if;
  if p_starts < (now() at time zone 'Asia/Tbilisi') then return 'past'; end if;

  -- per-date hours override wins over the weekly schedule (when present)
  select open_time, close_time into dh
    from barber_day_hours
    where barber_id = p_barber and work_date = (p_starts)::date;
  if found then
    if p_starts::time < dh.open_time or p_ends::time > dh.close_time then
      return 'outside_hours';
    end if;
  else
    v_wd := extract(dow from p_starts)::int;
    select open_time, close_time into wh
      from working_hours where barber_id = p_barber and weekday = v_wd;
    if not found then return 'barber_off'; end if;
    if p_starts::time < wh.open_time or p_ends::time > wh.close_time then
      return 'outside_hours';
    end if;
  end if;

  begin
    update bookings
      set service_id = p_service, barber_id = p_barber,
          starts_at  = p_starts,  ends_at   = p_ends
      where id = b.id;
  exception when exclusion_violation then
    return 'taken';
  end;
  return 'ok';
end; $$;
grant execute on function public.reschedule_my_booking(uuid, uuid, uuid, timestamp, timestamp) to anon, authenticated;

notify pgrst, 'reload schema';
