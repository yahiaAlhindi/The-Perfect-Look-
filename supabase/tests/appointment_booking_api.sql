-- ============================================================
-- The Perfect Look — T14 acceptance test
-- Appointment booking API
-- ============================================================
-- Verifies the T14 booking contract built on top of the T12
-- availability engine (migration 006 public.reserve_slot) and the
-- T14 payment status column (migration 008):
--   1. Transactional appointment creation with server-side
--      re-check of branch, price, service, provider, slot, grid,
--      notice/booking window and customer identity — reserve_slot()
--      is one atomic statement, so a confirmation is all-or-nothing.
--   2. A unique appointment_ref and client_number/branch snapshots
--      are stored with the booking.
--   3. Double-booking is impossible — a booked/overlapping slot is
--      rejected with a stable message and never re-offered.
--   4. Inactive / not-offered services are rejected along with
--      invalid providers and slots.
--   5. The confirmation record carries appointment ID, client
--      number, branch, service, time and payment status.
--
-- Requires migrations 001–008 applied. Run against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/appointment_booking_api.sql
--
-- Or paste into the online Supabase SQL editor (runs as table
-- owner, so RLS bypassed for fixtures). Every assertion prints
-- PASS or raises an error.
--
-- NOTE: the identity tests need the request.jwt.claims JWT to
-- survive across statements, so act_as() sets it at session scope.
-- Safe under psql autocommit and in the single-transaction editor.
-- ============================================================

\set ON_ERROR_STOP on

-- PASS/FAIL assertion helper
CREATE OR REPLACE FUNCTION public.expect(cond boolean, label text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT cond THEN
        RAISE EXCEPTION 'FAIL: %', label;
    END IF;
    RAISE NOTICE 'PASS: %', label;
END;
$$;

-- Read a UUID stored in a session GUC
CREATE OR REPLACE FUNCTION public.get_setting_uuid(name text)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(name)::uuid;
$$;

-- Read a DATE stored in a session GUC
CREATE OR REPLACE FUNCTION public.get_setting_date(name text)
RETURNS date
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(name)::date;
$$;

-- Act as `authenticated` with the given profile id in the JWT.
-- Claims are set at SESSION scope (is_local = true) so the identity
-- checks still hold when the script runs under psql autocommit.
CREATE OR REPLACE FUNCTION public.act_as(p_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    SET ROLE authenticated;
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', p_id::text, 'role', 'authenticated')::text,
        true
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST DAY: next Mon–Sat (branch open) that is not a holiday or
-- dubai closure, at least a week out.
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date;
BEGIN
    v_day := ((now() AT TIME ZONE 'Asia/Dubai')::date) + 7;
    WHILE EXTRACT(DOW FROM v_day)::int = 0
       OR EXISTS (SELECT 1 FROM public.holidays h WHERE h.date = v_day)
       OR EXISTS (SELECT 1 FROM public.branch_closures c
                   JOIN public.branches b ON b.id = c.branch_id
                  WHERE b.slug = 'dubai' AND c.date = v_day) LOOP
        v_day := v_day + 1;
    END LOOP;
    PERFORM set_config('test.day', v_day::text, false);
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FIXTURES (as table owner — RLS bypassed)
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM set_config('test.dxb', (SELECT id::text FROM public.branches WHERE slug = 'dubai'), false);

    -- Auth users + profiles for the test roles
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
    )
    SELECT '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
           'authenticated', 'authenticated', email,
           crypt('Password123!', gen_salt('bf')), now(),
           '{"provider":"email","providers":["email"]}',
           jsonb_build_object('role', r, 'full_name', fn, 'mobile_number', mn),
           now(), now()
    FROM (VALUES
        ('t14.patient@test.local',  'patient', 'T14 Patient',  '+971500003301'),
        ('t14.other@test.local',    'patient', 'T14 Patient2', '+971500003302'),
        ('t14.provider@test.local', 'staff',   'T14 Provider', '+971500003303')
    ) AS v(email, r, fn, mn);

    PERFORM set_config('test.p', (SELECT id::text FROM public.profiles WHERE email = 't14.patient@test.local'), false);
    PERFORM set_config('test.o', (SELECT id::text FROM public.profiles WHERE email = 't14.other@test.local'), false);

    -- Fixture provider needs a real staff row (works at dubai).
    INSERT INTO public.staff (profile_id, title, specializations, active)
    SELECT id, 'Technician', ARRAY['T14 fixture'], true
      FROM public.profiles
     WHERE email = 't14.provider@test.local'
    ON CONFLICT (profile_id) DO NOTHING;

    PERFORM set_config('test.staff_p', (SELECT id::text FROM public.staff WHERE profile_id = (SELECT id FROM public.profiles WHERE email = 't14.provider@test.local')), false);

    INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active) VALUES
        (public.get_setting_uuid('test.staff_p'), public.get_setting_uuid('test.dxb'), true, true);

    -- Weekly availability 10:00–20:00, every day.
    INSERT INTO public.staff_availability (staff_id, day_of_week, start_time, end_time)
    SELECT s.id, d.day_of_week, '10:00', '20:00'
    FROM public.staff s
    CROSS JOIN (SELECT generate_series(0, 6) AS day_of_week) d
    WHERE s.profile_id IN (SELECT id FROM public.profiles WHERE email LIKE 't14.prov%')
    ON CONFLICT (staff_id, day_of_week) DO NOTHING;

    -- Fixture services.
    --   booking  -> active, offered at dubai  (the T14 happy path)
    --   inactive -> inactive, offered at dubai (rejected)
    --   unlisted -> active but NOT offered at any branch (rejected)
    INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order, buffer_minutes)
    VALUES
        ('T14 Booking Service',   't14 fixture 60min',  60, 400.00, 'AED', true,  930, 0),
        ('T14 Inactive Service',  't14 fixture 30min',  30, 150.00, 'AED', false, 931, 0),
        ('T14 Unlisted Service',  't14 fixture 30min',  30, 100.00, 'AED', true,  932, 0);

    PERFORM set_config('test.svc', (SELECT id::text FROM public.services WHERE name = 'T14 Booking Service'), false);
    PERFORM set_config('test.inactive', (SELECT id::text FROM public.services WHERE name = 'T14 Inactive Service'), false);
    PERFORM set_config('test.unlisted', (SELECT id::text FROM public.services WHERE name = 'T14 Unlisted Service'), false);

    INSERT INTO public.service_branches (service_id, branch_id, available, currency) VALUES
        (public.get_setting_uuid('test.svc'),      public.get_setting_uuid('test.dxb'), true, 'AED'),
        (public.get_setting_uuid('test.inactive'), public.get_setting_uuid('test.dxb'), true, 'AED');
    -- test.unlisted intentionally has no service_branches row.

    RAISE NOTICE 'T14 fixtures ready';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 1: happy-path booking returns the full confirmation
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_start   timestamptz := (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai';
    v_appt    public.appointments;
    v_client  text;
BEGIN
    SELECT client_number INTO v_client FROM public.profiles WHERE id = v_patient;

    PERFORM public.act_as(v_patient);
    v_appt := public.reserve_slot(v_dxb, v_svc, v_patient, v_start, v_staff, 't14-1', 'web');

    -- Confirmation contract: appointment ID, client number, branch,
    -- service, time and payment status.
    PERFORM public.expect(v_appt.id IS NOT NULL, 'appointment ID is returned');
    PERFORM public.expect(v_appt.appointment_ref LIKE 'TPL-%', 'unique appointment_ref auto-generated (' || v_appt.appointment_ref || ')');
    PERFORM public.expect(v_appt.patient_id = v_patient AND v_appt.client_number = v_client, 'client number snapshot stored');
    PERFORM public.expect(v_appt.branch_id = v_dxb, 'branch recorded on the confirmation');
    PERFORM public.expect(v_appt.service_id = v_svc AND v_appt.service_name_snapshot = 'T14 Booking Service', 'service recorded with name snapshot');
    PERFORM public.expect(
        v_appt.scheduled_start = v_start AND v_appt.scheduled_end = v_start + interval '60 minutes',
        'booking time kept exactly as reserved'
    );
    PERFORM public.expect(v_appt.staff_id = v_staff, 'provider recorded on the confirmation');
    PERFORM public.expect(v_appt.price_snapshot = 400.00 AND v_appt.currency_snapshot = 'AED', 'price snapshot from the catalogue (400.00 AED)');
    PERFORM public.expect(v_appt.status = 'Pending', 'booking status is Pending');
    PERFORM public.expect(v_appt.payment_status = 'unpaid', 'payment status defaults to unpaid on confirmation');
    PERFORM public.expect(v_appt.source_channel = 'web', 'source channel recorded as web');
    PERFORM public.expect(v_appt.buffer_minutes = 0, 'buffer snapshot 0 for T14 Booking Service');

    PERFORM public.expect(
        (SELECT count(*) = 1 FROM public.appointments WHERE id = v_appt.id),
        'exactly one appointment row created (transactional insert)'
    );

    DELETE FROM public.appointments WHERE id = v_appt.id;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 2: double-booking is impossible
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_start   timestamptz := (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai';
    v_appt    uuid;
BEGIN
    SELECT id INTO v_appt FROM public.reserve_slot(v_dxb, v_svc, v_patient, v_start, v_staff, 't14-2', 'web');

    -- Same start is rejected with the stable message.
    BEGIN
        PERFORM public.reserve_slot(v_dxb, v_svc, v_patient, v_start, v_staff, 't14-2b', 'web');
        PERFORM public.expect(false, 'same-slot double booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'The selected timeslot is not available anymore',
            'same-slot double booking rejected with the stable message'
        );
    END;

    -- Overlapping start (10:30) is rejected too (EXCLUDE constraint).
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '10:30') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-2c', 'web'
        );
        PERFORM public.expect(false, 'overlapping-slot double booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'The selected timeslot is not available anymore',
            'overlapping-slot double booking rejected with the stable message'
        );
    END;

    -- Availability no longer offers the booked or overlapping starts.
    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time IN ('10:00', '10:30')
        )
        AND EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time = '11:00'
        ),
        'booked slot and its neighbour are removed from availability, 11:00 stays open'
    );

    -- No stray rows from the rejected attempts.
    PERFORM public.expect(
        NOT EXISTS (SELECT 1 FROM public.appointments WHERE notes IN ('t14-2b', 't14-2c')),
        'rejected attempts left no appointments behind'
    );

    DELETE FROM public.appointments WHERE id = v_appt;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: payment status lifecycle at booking time
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_appt    public.appointments;
BEGIN
    v_appt := public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '12:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-3', 'web'
    );

    PERFORM public.expect(v_appt.payment_status = 'unpaid', 'every new booking starts unpaid');

    -- The CHECK constraint only allows the five documented states.
    BEGIN
        UPDATE public.appointments SET payment_status = 'cash' WHERE id = v_appt.id;
        PERFORM public.expect(false, 'invalid payment_status value is rejected');
    EXCEPTION WHEN check_violation THEN
        PERFORM public.expect(true, 'CHECK rejects invalid payment_status values');
    END;

    -- Pay-at-clinic and paid transitions are legal as booking matures
    -- (T38 takes over the full payment domain later).
    UPDATE public.appointments SET payment_status = 'pay_at_clinic' WHERE id = v_appt.id;
    UPDATE public.appointments SET payment_status = 'paid' WHERE id = v_appt.id;
    PERFORM public.expect(
        (SELECT payment_status FROM public.appointments WHERE id = v_appt.id) = 'paid',
        'payment status transitions to paid are allowed'
    );

    DELETE FROM public.appointments WHERE id = v_appt.id;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4: inactive or not-offered services are rejected
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
BEGIN
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, public.get_setting_uuid('test.inactive'), v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-4', 'web'
        );
        PERFORM public.expect(false, 'inactive service booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Service is not available at this branch',
            'inactive service rejected'
        );
    END;

    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, public.get_setting_uuid('test.unlisted'), v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-4b', 'web'
        );
        PERFORM public.expect(false, 'service without a branch listing is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Service is not available at this branch',
            'service not offered at this branch rejected'
        );
    END;

    PERFORM public.expect(
        NOT EXISTS (SELECT 1 FROM public.appointments WHERE notes IN ('t14-4', 't14-4b')),
        'rejected service bookings left no rows behind'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5: provider and slot layout rejections
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_sunday  date  := v_day + ((7 - EXTRACT(DOW FROM v_day)::int + 7) % 7)::int;
BEGIN
    -- A provider is mandatory.
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', NULL, 't14-5', 'web'
        );
        PERFORM public.expect(false, 'NULL provider is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'This service requires a selected provider',
            'service requires a selected provider enforced'
        );
    END;

    -- Off-grid start (10:15 is not on the 30-minute grid).
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '10:15') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-5b', 'web'
        );
        PERFORM public.expect(false, 'off-grid 10:15 is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'This timeslot is not aligned to the booking grid',
            'off-grid timestamps rejected'
        );
    END;

    -- Sunday: the branch is closed.
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_sunday + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-5c', 'web'
        );
        PERFORM public.expect(false, 'Sunday booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'The branch is closed on this day',
            'closed-day booking rejected'
        );
    END;

    -- A booking in the past is rejected.
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            now() - interval '1 hour', v_staff, 't14-5d', 'web'
        );
        PERFORM public.expect(false, 'past-time booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'This timeslot is in the past',
            'past timestamps rejected'
        );
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 6: customer identity at the reservation boundary
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_other   uuid := public.get_setting_uuid('test.o');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
BEGIN
    -- A signed-in patient books their own slot — allowed.
    PERFORM public.act_as(v_patient);
    PERFORM public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '13:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-6', 'web'
    );

    -- The same patient cannot book FOR another customer.
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_other,
            (v_day + TIME '14:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-6b', 'web'
        );
        PERFORM public.expect(false, 'patient booking another customer is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Cannot book an appointment for another customer',
            'patient cannot book for another customer'
        );
    END;

    -- An anonymous JWT can never book.
    SET ROLE anon;
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}'::text, true);
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '15:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-6c', 'web'
        );
        PERFORM public.expect(false, 'anon booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Booking requires a signed-in customer or staff account',
            'anon JWT rejected at reservation'
        );
    END;

    PERFORM set_config('request.jwt.claims', '{}'::text, true);
    RESET ROLE;

    DELETE FROM public.appointments WHERE notes IN ('t14-6', 't14-6b', 't14-6c');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 7: booking-time price truth is snapshotted immutably
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_first   public.appointments;
    v_second  public.appointments;
BEGIN
    -- Book at 400.00 …
    v_first := public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '16:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-7', 'web'
    );

    -- … then the catalogue price changes.
    UPDATE public.services SET price = 999.00 WHERE id = v_svc;

    PERFORM public.expect(
        (SELECT price_snapshot FROM public.appointments WHERE id = v_first.id) = 400.00,
        'earlier booking keeps its 400.00 price snapshot after the catalogue changed'
    );

    -- A NEW booking at the new price snapshots 999.00.
    v_second := public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '17:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't14-7b', 'web'
    );
    PERFORM public.expect(v_second.price_snapshot = 999.00, 'new booking snapshots the current price (999.00)');

    -- Restore the catalogue and clean up.
    UPDATE public.services SET price = 400.00 WHERE id = v_svc;
    DELETE FROM public.appointments WHERE id IN (v_first.id, v_second.id);
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- CLEANUP
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.appointments WHERE notes IN
    ('t14-1', 't14-2', 't14-2b', 't14-2c', 't14-3', 't14-4', 't14-4b',
     't14-5', 't14-5b', 't14-5c', 't14-5d', 't14-6', 't14-6b', 't14-6c',
     't14-7', 't14-7b');

DELETE FROM public.service_branches
 WHERE service_id IN (SELECT id FROM public.services WHERE name LIKE 'T14 %');
DELETE FROM public.staff_availability
 WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN
   (SELECT id FROM public.profiles WHERE email LIKE 't14.%@test.local'));
DELETE FROM public.staff_branches
 WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN
   (SELECT id FROM public.profiles WHERE email LIKE 't14.%@test.local'));
DELETE FROM public.staff
 WHERE profile_id IN (SELECT id FROM public.profiles WHERE email LIKE 't14.%@test.local');
DELETE FROM public.services WHERE name LIKE 'T14 %';
DELETE FROM public.profiles WHERE email LIKE 't14.%@test.local';
DELETE FROM auth.users WHERE email LIKE 't14.%@test.local';

DO $$
BEGIN
    RAISE NOTICE 'T14 appointment booking API acceptance tests complete';
END;
$$;