-- ============================================================
-- The Perfect Look — T12 acceptance test
-- Branch-aware availability engine
-- ============================================================
-- Verifies the T12 server-side guarantees (migration 006):
--   1. Slots respect branch hours, provider schedules, service
--      duration/buffers, holidays, closures, blocked periods,
--      capacity, and existing appointments — all in Asia/Dubai
--      (branch timezone is carried through every row/query).
--   2. A staff member working at two branches cannot be
--      double-booked — slot generation never offers the second
--      branch slot, reserve_slot() rejects it, and the DB
--      EXCLUDE constraint rejects overlapping raw inserts.
--   3. The concurrency boundary: overlapping bookings (same start
--      via the T3 unique index, or a different start that overlaps
--      via the T12 EXCLUDE constraint) are rejected at the
--      database for every channel.
--      Parallel-requests proof: run
--        supabase/tests/availability_engine_parallel.ps1 (or .sh)
--      after this file — N concurrent reserve_slot() calls for one
--      slot → exactly one success.
--
-- Requires migrations 001–006 applied. Run against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/availability_engine.sql
--
-- Or paste into the online Supabase SQL editor (runs as table
-- owner, so RLS bypassed for fixtures). Every assertion prints
-- PASS or raises an error.
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

-- Act as `authenticated` with the given profile id in the JWT
CREATE OR REPLACE FUNCTION public.act_as(p_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    SET ROLE authenticated;
    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', p_id::text, 'role', 'authenticated')::text,
        false
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
    PERFORM set_config('test.auh', (SELECT id::text FROM public.branches WHERE slug = 'abu-dhabi'), false);

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
        ('av.patient@test.local',  'patient', 'AV Patient',   '+971500000301'),
        ('av.staff@test.local',    'staff',   'AV Staff',     '+971500000302'),
        ('av.admin@test.local',    'admin',   'AV Admin',     '+971500000303'),
        ('av.provider@test.local', 'staff',   'AV Provider',  '+971500000304'),
        ('av.prov2@test.local',    'staff',   'AV Provider2', '+971500000305')
    ) AS v(email, r, fn, mn);

    PERFORM set_config('test.p',   (SELECT id::text FROM public.profiles WHERE email = 'av.patient@test.local'), false);
    PERFORM set_config('test.a',   (SELECT id::text FROM public.profiles WHERE email = 'av.admin@test.local'), false);

    -- Fixture providers need real staff rows.
    INSERT INTO public.staff (profile_id, title, specializations, active)
    SELECT id, 'Technician', ARRAY['AV fixture'], true
      FROM public.profiles
     WHERE email IN ('av.provider@test.local', 'av.prov2@test.local')
    ON CONFLICT (profile_id) DO NOTHING;

    PERFORM set_config('test.staff_p', (SELECT id::text FROM public.staff WHERE profile_id = (SELECT id FROM public.profiles WHERE email = 'av.provider@test.local')), false);
    PERFORM set_config('test.staff_b', (SELECT id::text FROM public.staff WHERE profile_id = (SELECT id FROM public.profiles WHERE email = 'av.prov2@test.local')), false);

    -- Fixture provider P works at BOTH dubai + abu-dhabi (multi-branch staff).
    INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active) VALUES
        (public.get_setting_uuid('test.staff_p'), public.get_setting_uuid('test.dxb'), true,  true),
        (public.get_setting_uuid('test.staff_p'), public.get_setting_uuid('test.auh'), false, true);

    -- Fixture provider B works at dubai only (used for the capacity test).
    INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active) VALUES
        (public.get_setting_uuid('test.staff_b'), public.get_setting_uuid('test.dxb'), false, true);

    -- Weekly availability 10:00–20:00 for both providers, every day.
    INSERT INTO public.staff_availability (staff_id, day_of_week, start_time, end_time)
    SELECT s.id, d.day_of_week, '10:00', '20:00'
    FROM public.staff s
    CROSS JOIN (SELECT generate_series(0, 6) AS day_of_week) d
    WHERE s.profile_id IN (SELECT id FROM public.profiles WHERE email LIKE 'av.prov%')
    ON CONFLICT (staff_id, day_of_week) DO NOTHING;

    -- Fixture services + availability
    INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order, buffer_minutes)
    VALUES
        ('AV Test Service',    'av fixture 60min',       60, 350.00, 'AED', true, 920, 0),
        ('AV Buffer Service',  'av fixture 30min+buffer', 30, 200.00, 'AED', true, 921, 30);

    PERFORM set_config('test.svc', (SELECT id::text FROM public.services WHERE name = 'AV Test Service'), false);
    PERFORM set_config('test.buf', (SELECT id::text FROM public.services WHERE name = 'AV Buffer Service'), false);

    INSERT INTO public.service_branches (service_id, branch_id, available, currency)
    VALUES
        (public.get_setting_uuid('test.svc'), public.get_setting_uuid('test.dxb'), true, 'AED'),
        (public.get_setting_uuid('test.svc'), public.get_setting_uuid('test.auh'), true, 'AED'),
        (public.get_setting_uuid('test.buf'), public.get_setting_uuid('test.dxb'), true, 'AED');

    RAISE NOTICE 'T12 fixtures ready';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 1: slots respect branch hours in Asia/Dubai
-- ─────────────────────────────────────────────────────────────

-- 60 min service on a 30 min grid over 10:00–20:00 → 19 slots.
SELECT public.expect(
    (SELECT count(*)
       FROM public.get_availability(
           public.get_setting_uuid('test.dxb'),
           public.get_setting_uuid('test.svc'),
           public.get_setting_date('test.day'),
           public.get_setting_date('test.day'),
           public.get_setting_uuid('test.staff_p'))) = 19,
    'slots generated for the branch open day (10:00-20:00, 60min service, 30min grid -> 19)'
);

-- All slot times are Asia/Dubai wall times within [10:00, 20:00].
SELECT public.expect(
    NOT EXISTS (
        SELECT 1
          FROM public.get_availability(
              public.get_setting_uuid('test.dxb'),
              public.get_setting_uuid('test.svc'),
              public.get_setting_date('test.day'),
              public.get_setting_date('test.day'),
              public.get_setting_uuid('test.staff_p')) a
         WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time < '10:00'::time
            OR (a.slot_end   AT TIME ZONE 'Asia/Dubai')::time > '20:00'::time
            OR a.slot_date <> public.get_setting_date('test.day')
    ),
    'every slot is within Asia/Dubai branch hours on the requested date'
);

-- Branch + timezone carried in every slot row.
SELECT public.expect(
    (SELECT bool_and(x.branch_id = public.get_setting_uuid('test.dxb')
                     AND x.branch_name = 'The Perfect Look — Dubai'
                     AND x.timezone = 'Asia/Dubai'
                     AND x.service_id = public.get_setting_uuid('test.svc')
                     AND x.duration_minutes = 60)
       FROM public.get_availability(
           public.get_setting_uuid('test.dxb'),
           public.get_setting_uuid('test.svc'),
           public.get_setting_date('test.day'),
           public.get_setting_date('test.day'),
           public.get_setting_uuid('test.staff_p')) x),
    'branch and timezone are carried in every slot row'
);

-- The engine also returns nothing for a closed day (Sunday).
SELECT public.expect(
    (SELECT count(*) = 0
       FROM public.get_availability(
           public.get_setting_uuid('test.dxb'),
           public.get_setting_uuid('test.svc'),
           (public.get_setting_date('test.day') + ((7 - EXTRACT(DOW FROM public.get_setting_date('test.day'))::int + 7) % 7)::int),
           (public.get_setting_date('test.day') + ((7 - EXTRACT(DOW FROM public.get_setting_date('test.day'))::int + 7) % 7)::int),
           public.get_setting_uuid('test.staff_p'))),
    'no slots on a closed day (Sunday)'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: holidays and branch closures remove the whole day
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.holidays (date, reason)
VALUES (public.get_setting_date('test.day'), 'AV test holiday');

SELECT public.expect(
    (SELECT count(*) = 0
       FROM public.get_availability(
           public.get_setting_uuid('test.dxb'),
           public.get_setting_uuid('test.svc'),
           public.get_setting_date('test.day'),
           public.get_setting_date('test.day'),
           public.get_setting_uuid('test.staff_p'))),
    'clinic holiday removes all slots for the day'
);

DELETE FROM public.holidays WHERE date = public.get_setting_date('test.day');

INSERT INTO public.branch_closures (branch_id, date, reason)
VALUES (public.get_setting_uuid('test.dxb'), public.get_setting_date('test.day'), 'AV test closure');

SELECT public.expect(
    (SELECT count(*) = 0
       FROM public.get_availability(
           public.get_setting_uuid('test.dxb'),
           public.get_setting_uuid('test.svc'),
           public.get_setting_date('test.day'),
           public.get_setting_date('test.day'),
           public.get_setting_uuid('test.staff_p'))),
    'branch closure removes all slots for the day'
);

DELETE FROM public.branch_closures WHERE branch_id = public.get_setting_uuid('test.dxb') AND date = public.get_setting_date('test.day');

-- ─────────────────────────────────────────────────────────────
-- TEST 3: provider blocked period (leave) removes covered slots
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.blocked_periods (staff_id, start_datetime, end_datetime, reason)
VALUES (
    public.get_setting_uuid('test.staff_p'),
    (public.get_setting_date('test.day') + TIME '10:00') AT TIME ZONE 'Asia/Dubai',
    (public.get_setting_date('test.day') + TIME '13:00') AT TIME ZONE 'Asia/Dubai',
    'AV test leave'
);

-- 10:00→12:30 starts (6) are covered by the block; 13:00+ remain → 19-6=13.
SELECT public.expect(
    (SELECT count(*) = 13
       FROM public.get_availability(
           public.get_setting_uuid('test.dxb'),
           public.get_setting_uuid('test.svc'),
           public.get_setting_date('test.day'),
           public.get_setting_date('test.day'),
           public.get_setting_uuid('test.staff_p'))),
    'provider leave removes the covered slots (6 removed -> 13 remain)'
);

DELETE FROM public.blocked_periods WHERE reason = 'AV test leave';

-- ─────────────────────────────────────────────────────────────
-- TEST 4: existing appointments (with buffers) remove slots
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_buf     uuid := public.get_setting_uuid('test.buf');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_start   timestamptz := (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai';
    v_appt    uuid;
BEGIN
    PERFORM public.reserve_slot(v_dxb, v_svc, v_patient, v_start, v_staff, 't4', 'web');
    SELECT id INTO v_appt FROM public.appointments WHERE notes = 't4';

    -- 60min booking 10:00–11:00 blocks the 10:00 and 10:30 starts → 17.
    PERFORM public.expect(
        (SELECT count(*) = 17
           FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff)),
        'existing appointment removes itself and overlapping slots (17 remain)'
    );
    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time IN ('10:00', '10:30')
        )
        AND EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time = '11:00'
        ),
        '10:00 and 10:30 are gone, 11:00 is open'
    );

    DELETE FROM public.appointments WHERE id = v_appt;

    -- Buffered service: 10:00–10:30 booking with a 30min buffer occupies
    -- [10:00, 11:00) → removes the 10:00 and 10:30 starts (20 total → 18).
    PERFORM public.reserve_slot(
        v_dxb, v_buf, v_patient,
        (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't4b', 'web');
    SELECT id INTO v_appt FROM public.appointments WHERE notes = 't4b';

    PERFORM public.expect(
        (SELECT count(*) = 18
           FROM public.get_availability(v_dxb, v_buf, v_day, v_day, v_staff)),
        'buffer occupies the follow-up slot too (30min booking + 30min buffer -> 18 remain)'
    );
    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_buf, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time IN ('10:00', '10:30')
        )
        AND EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_buf, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time = '11:00'
        ),
        'buffered slots 10:00/10:30 are gone, 11:00 is open'
    );

    DELETE FROM public.appointments WHERE id = v_appt;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5: multi-branch staff cannot be double-booked
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff   uuid := public.get_setting_uuid('test.staff_p');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_auh     uuid := public.get_setting_uuid('test.auh');
    v_day     date  := public.get_setting_date('test.day');
    v_10      timestamptz := (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai';
    v_appt    uuid;
BEGIN
    -- Book provider P at Dubai 10:00.
    SELECT id INTO v_appt FROM public.reserve_slot(v_dxb, v_svc, v_patient, v_10, v_staff, 't5', 'web');

    -- Slot generation at Abu Dhabi must NOT offer the conflicting start
    -- while keeping the rest of the day open (P is a multi-branch provider).
    PERFORM public.expect(
        (SELECT count(*) = 17
           FROM public.get_availability(v_auh, v_svc, v_day, v_day, v_staff)),
        'abu-dhabi slot list excludes the cross-branch conflict (17 of 19 remain)'
    );
    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_auh, v_svc, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time IN ('10:00', '10:30')
        )
        AND EXISTS (
            SELECT 1 FROM public.get_availability(v_auh, v_svc, v_day, v_day, v_staff) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time = '11:00'
        ),
        'provider booked at dubai 10:00 -> not offered 10:00/10:30 at abu-dhabi (11:00 open)'
    );

    -- reserve_slot at Abu Dhabi 10:00 must be rejected atomically.
    BEGIN
        PERFORM public.reserve_slot(v_auh, v_svc, v_patient, v_10, v_staff, 't5b', 'web');
        PERFORM public.expect(false, 'cross-branch reserve_slot is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'The selected timeslot is not available anymore',
            'cross-branch reserve_slot rejected with the stable message'
        );
    END;
    PERFORM public.expect(
        NOT EXISTS (SELECT 1 FROM public.appointments WHERE notes = 't5b'),
        'rejected reservation left no appointment behind'
    );

    -- A raw insert that bypasses the function is still stopped by the DB
    -- (different start, overlaps the Dubai booking -> EXCLUDE constraint).
    BEGIN
        INSERT INTO public.appointments (
            patient_id, service_id, branch_id, staff_id,
            scheduled_start, scheduled_end, status, notes,
            client_number, service_name_snapshot, price_snapshot,
            currency_snapshot, source_channel, buffer_minutes
        ) VALUES (
            v_patient, v_svc, v_auh, v_staff,
            v_10 + interval '30 minutes', v_10 + interval '90 minutes',
            'Pending', 't5c', '0', 'x', 0, 'AED', 'web', 0
        );
        PERFORM public.expect(false, 'raw overlapping insert is rejected');
    EXCEPTION WHEN exclusion_violation OR unique_violation THEN
        PERFORM public.expect(true, 'raw overlapping insert rejected by DB constraint');
    END;

    -- The exact same start at a second branch is stopped by the T3 unique index.
    BEGIN
        INSERT INTO public.appointments (
            patient_id, service_id, branch_id, staff_id,
            scheduled_start, scheduled_end, status, notes,
            client_number, service_name_snapshot, price_snapshot,
            currency_snapshot, source_channel, buffer_minutes
        ) VALUES (
            v_patient, v_svc, v_auh, v_staff,
            v_10, v_10 + interval '60 minutes',
            'Pending', 't5d', '0', 'x', 0, 'AED', 'web', 0
        );
        PERFORM public.expect(false, 'raw same-start insert at second branch is rejected');
    EXCEPTION WHEN unique_violation OR exclusion_violation THEN
        PERFORM public.expect(true, 'raw same-start insert rejected by unique index');
    END;

    DELETE FROM public.appointments WHERE id = v_appt;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 6: branch capacity
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient uuid := public.get_setting_uuid('test.p');
    v_staff_p uuid := public.get_setting_uuid('test.staff_p');
    v_staff_b uuid := public.get_setting_uuid('test.staff_b');
    v_svc     uuid := public.get_setting_uuid('test.svc');
    v_dxb     uuid := public.get_setting_uuid('test.dxb');
    v_day     date  := public.get_setting_date('test.day');
    v_dummy   uuid;
BEGIN
    UPDATE public.branches SET max_concurrent_appointments = 1 WHERE id = v_dxb;

    SELECT id FROM public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff_p, 't6', 'web'
    ) INTO v_dummy;

    -- Another provider's 10:00 slot is blocked by capacity; 11:00 stays open.
    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff_b) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time = '10:00'
        )
        AND EXISTS (
            SELECT 1 FROM public.get_availability(v_dxb, v_svc, v_day, v_day, v_staff_b) a
             WHERE (a.slot_start AT TIME ZONE 'Asia/Dubai')::time = '11:00'
        ),
        'branch capacity 1 removes the second concurrent provider slot, later slot stays open'
    );

    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff_b, 't6b', 'web'
        );
        PERFORM public.expect(false, 'capacity-full reserve_slot is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'The selected timeslot is not available anymore',
            'capacity-full reserve_slot rejected with the stable message'
        );
    END;

    -- 11:00 for the second provider books fine ([11:00,12:00) does not overlap).
    PERFORM public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '11:00') AT TIME ZONE 'Asia/Dubai', v_staff_b, 't6c', 'web'
    );

    UPDATE public.branches SET max_concurrent_appointments = NULL WHERE id = v_dxb;
    DELETE FROM public.appointments WHERE notes IN ('t6', 't6b', 't6c');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 7: reserve_slot snapshots the booking-time truth
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient    uuid := public.get_setting_uuid('test.p');
    v_staff      uuid := public.get_setting_uuid('test.staff_p');
    v_svc        uuid := public.get_setting_uuid('test.svc');
    v_dxb        uuid := public.get_setting_uuid('test.dxb');
    v_day        date  := public.get_setting_date('test.day');
    v_start14    timestamptz := (v_day + TIME '14:00') AT TIME ZONE 'Asia/Dubai';
    v_appt       public.appointments;
BEGIN
    v_appt := public.reserve_slot(v_dxb, v_svc, v_patient, v_start14, v_staff, 't7', 'web');

    PERFORM public.expect(v_appt.branch_id = v_dxb, 'appointment created at the requested branch');
    PERFORM public.expect(v_appt.staff_id = v_staff AND v_appt.patient_id = v_patient, 'provider and patient recorded');
    PERFORM public.expect(v_appt.status = 'Pending', 'default status is Pending');
    PERFORM public.expect(v_appt.appointment_ref LIKE 'TPL-%', 'appointment_ref auto-generated (' || v_appt.appointment_ref || ')');
    PERFORM public.expect(v_appt.client_number IS NOT NULL, 'client_number snapshot taken');
    PERFORM public.expect(v_appt.service_name_snapshot = 'AV Test Service', 'service name snapshot taken');
    PERFORM public.expect(v_appt.price_snapshot = 350.00, 'price snapshot from catalogue (350.00)');
    PERFORM public.expect(v_appt.currency_snapshot = 'AED', 'currency snapshot is AED');
    PERFORM public.expect(v_appt.buffer_minutes = 0, 'buffer snapshot 0 for AV Test Service');
    PERFORM public.expect(v_appt.source_channel = 'web', 'source channel recorded as web');
    PERFORM public.expect(
        v_appt.scheduled_start = v_start14
        AND v_appt.scheduled_end = v_start14 + interval '60 minutes',
        'timeslot kept exactly as reserved'
    );

    DELETE FROM public.appointments WHERE id = v_appt.id;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 8: authorization at the reservation boundary
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient  uuid := public.get_setting_uuid('test.p');
    v_other    uuid := public.get_setting_uuid('test.a'); -- a different profile
    v_staff    uuid := public.get_setting_uuid('test.staff_p');
    v_svc      uuid := public.get_setting_uuid('test.svc');
    v_dxb      uuid := public.get_setting_uuid('test.dxb');
    v_day      date  := public.get_setting_date('test.day');
BEGIN
    -- A signed-in patient books their own slot — allowed.
    PERFORM public.act_as(v_patient);
    PERFORM public.reserve_slot(
        v_dxb, v_svc, v_patient,
        (v_day + TIME '15:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't8a', 'web'
    );

    -- The same patient cannot book FOR another customer.
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_other,
            (v_day + TIME '15:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't8b', 'web'
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
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}'::text, false);
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '16:00') AT TIME ZONE 'Asia/Dubai', v_staff, 't8c', 'web'
        );
        PERFORM public.expect(false, 'anon booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Booking requires a signed-in customer or staff account',
            'anon JWT rejected at reservation'
        );
    END;

    PERFORM set_config('request.jwt.claims', '{}'::text, false);
    RESET ROLE;

    DELETE FROM public.appointments WHERE notes IN ('t8a', 't8b', 't8c');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 9: layout and branch-scope rejections
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_patient   uuid := public.get_setting_uuid('test.p');
    v_staff_p   uuid := public.get_setting_uuid('test.staff_p');
    v_staff_b   uuid := public.get_setting_uuid('test.staff_b');
    v_svc       uuid := public.get_setting_uuid('test.svc');
    v_buf       uuid := public.get_setting_uuid('test.buf');
    v_dxb       uuid := public.get_setting_uuid('test.dxb');
    v_auh       uuid := public.get_setting_uuid('test.auh');
    v_day       date  := public.get_setting_date('test.day');
    v_sunday    date  := v_day + ((7 - EXTRACT(DOW FROM v_day)::int + 7) % 7)::int;
BEGIN
    -- Buffer service is not available at Abu Dhabi.
    BEGIN
        PERFORM public.reserve_slot(
            v_auh, v_buf, v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff_p, NULL, 'web'
        );
        PERFORM public.expect(false, 'buffer service unavailable at abu-dhabi');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Service is not available at this branch',
            'service not available at this branch rejected'
        );
    END;

    -- A provider is mandatory.
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', NULL, NULL, 'web'
        );
        PERFORM public.expect(false, 'NULL provider is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'This service requires a selected provider',
            'service requires a selected provider enforced'
        );
    END;

    -- Provider B does not work at Abu Dhabi.
    BEGIN
        PERFORM public.reserve_slot(
            v_auh, v_svc, v_patient,
            (v_day + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff_b, NULL, 'web'
        );
        PERFORM public.expect(false, 'provider not assigned to branch is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'Selected provider does not work at this branch',
            'provider must work at the branch'
        );
    END;

    -- Outside branch opening hours (21:00 end lands at 22:00 > 20:00).
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '21:00') AT TIME ZONE 'Asia/Dubai', v_staff_p, NULL, 'web'
        );
        PERFORM public.expect(false, '21:00 booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'This timeslot is outside the branch opening hours',
            'outside branch hours rejected'
        );
    END;

    -- Off-grid start (10:15 is not on the 30-minute grid).
    BEGIN
        PERFORM public.reserve_slot(
            v_dxb, v_svc, v_patient,
            (v_day + TIME '10:15') AT TIME ZONE 'Asia/Dubai', v_staff_p, NULL, 'web'
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
            (v_sunday + TIME '10:00') AT TIME ZONE 'Asia/Dubai', v_staff_p, NULL, 'web'
        );
        PERFORM public.expect(false, 'Sunday booking is rejected');
    EXCEPTION WHEN OTHERS THEN
        PERFORM public.expect(
            SQLERRM = 'The branch is closed on this day',
            'closed-day booking rejected'
        );
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- CLEANUP
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.appointments WHERE notes IN
    ('t4', 't4b', 't5', 't5b', 't5c', 't5d', 't6', 't6b', 't6c', 't7', 't8a', 't8b', 't8c');

DELETE FROM public.blocked_periods WHERE reason = 'AV test leave';
DELETE FROM public.holidays        WHERE reason = 'AV test holiday';
DELETE FROM public.branch_closures WHERE reason = 'AV test closure';

DELETE FROM public.service_branches
 WHERE service_id IN (SELECT id FROM public.services WHERE name LIKE 'AV %');
DELETE FROM public.staff_availability
 WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN
   (SELECT id FROM public.profiles WHERE email LIKE 'av.%@test.local'));
DELETE FROM public.staff_branches
 WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN
   (SELECT id FROM public.profiles WHERE email LIKE 'av.%@test.local'));
DELETE FROM public.staff
 WHERE profile_id IN (SELECT id FROM public.profiles WHERE email LIKE 'av.%@test.local');
DELETE FROM public.services WHERE name IN ('AV Test Service', 'AV Buffer Service');
DELETE FROM public.profiles WHERE email LIKE 'av.%@test.local';
DELETE FROM auth.users WHERE email LIKE 'av.%@test.local';

DO $$
BEGIN
    RAISE NOTICE 'T12 availability engine acceptance tests complete';
END;
$$;