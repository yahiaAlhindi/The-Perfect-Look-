-- ============================================================
-- The Perfect Look — T14: Appointment booking API
-- ============================================================
-- Migration: 008_appointment_booking_api.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             004/005 (T37), 006_availability_engine.sql (T12)
--
-- The transactional booking API itself is public.reserve_slot()
-- (migration 006, T12): it re-checks branch, price, service,
-- provider, slot, grid alignment, notice/booking window, capacity,
-- blocked periods, and customer identity server-side inside one
-- atomic statement, then inserts with client-number / price / buffer
-- snapshots and returns the full appointment confirmation record
-- (appointment ID, client number, branch, service, time).
--
-- This migration supplies the ONE piece of the T14 confirmation
-- contract that 006 did not yet store: payment status (T14
-- acceptance criterion: "confirmation data includes ... payment
-- status"). Payment is initially unpaid / pay-at-clinic; T38 owns
-- the full payment domain (invoices, provider webhook transitions)
-- and replaces this minimal status.
-- ============================================================

ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS payment_status text
        NOT NULL DEFAULT 'unpaid'
        CHECK (payment_status IN (
            'unpaid',
            'pay_at_clinic',
            'partially_paid',
            'paid',
            'refunded'
        ));

COMMENT ON COLUMN public.appointments.payment_status IS
    'Booking-time payment state (T14). Confirmation reports this; T38 introduces the full payment domain (invoices, provider transitions).';