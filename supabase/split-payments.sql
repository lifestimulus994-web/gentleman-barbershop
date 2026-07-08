-- ════════════════════════════════════════════════════════════
--  Gentleman Barbershop — split payments (ქეში + ბარათი ერთდროულად)
--  Run once in: Supabase Dashboard → SQL Editor → New query → Run
--  Safe to re-run (idempotent).
-- ════════════════════════════════════════════════════════════

-- ─── Per-method paid amounts on a booking ─────────────────────
--  Used when payment_method = 'split': how much arrived in each channel.
--  For single-method payments these stay NULL and the full price
--  is attributed to payment_method.
alter table bookings
  add column if not exists paid_cash numeric(10,2),
  add column if not exists paid_bog  numeric(10,2),
  add column if not exists paid_tbc  numeric(10,2);

-- ─── Allow 'split' as a payment method ────────────────────────
alter table bookings drop constraint if exists bookings_payment_method_check;
alter table bookings add constraint bookings_payment_method_check
  check (payment_method in ('cash','bog','tbc','split'));

-- ─── Payment channel on manual ledger entries ─────────────────
--  cash → სალაროდან/სალაროში | bog / tbc → ბანკის ანგარიშით.
--  Only method='cash' entries affect the cash drawer (ნაშთი).
--  Existing rows default to 'cash'.
alter table finance_entries
  add column if not exists method text not null default 'cash'
  check (method in ('cash','bog','tbc'));

-- ─── Tell PostgREST to reload its schema cache ────────────────
notify pgrst, 'reload schema';
