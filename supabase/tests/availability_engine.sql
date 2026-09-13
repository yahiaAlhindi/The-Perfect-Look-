-- ============================================================
-- The Perfect Look — Availability engine acceptance test (T12)
-- ============================================================
-- Verifies the T12 server-side guarantees supplied by migration
-- 006_availability_engine.sql:
--   TEST 1  get_branch_providers lists the branch's active staff.
--   TEST 2  Slots are generated on branch working days, in branch
--           time (Asia/Dubai), on the slot grid, sized by the
--           service duration, and stop before closing time.
--   TEST 3  Clinic-wide holiday closes the whole day.
--   TEST 4  Branch closure closes the whole day.
--   TEST 5  Provider filter narrows slots to that provider; a
--           provider without a weekly schedule yields no slots.
--   TEST 6  An existing appointment removes its slot from that
--           provider (buffer semantics also covered in TEST 7).
--   TEST 7  Service buffer protects the following slot.
--   TEST 8  Cross-branch block: a provider assigned to two branches
--           cannot be double-booked — a Dubai booking removes the
--           same slot at Abu Dhabi.
--   TEST 9  DB unique index still guarantees exactly one successful
--           booking per (staff, start) across all branches.
--   TEST 10 Past dates never produce slots.
--   TEST 11 Advance-notice booking rules are respected.
--
-- Requires migrations 001-006 applied and demo branches seeded
-- (005). Run:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/availability_engine.sql
-- Or paste into the online Supabase SQL editor (runs as the table
-- owner, so RLS is bypassed for fixtures). Every assertion prints
-- PASS or raises.
-- ============================================================

\set ON_ERROR_STOP on

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

CREATE OR REPLACE FUNCTION public.get_setting_uuid(name text)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(name)::uuid;
$$;

CREATE OR REPLACE FUNCTION public.get_setting_date(name text)
RETURNS date
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(name)::date;
$$;

-- ─────────────────────────────────────────────────────────────
-- FIXTURES (as table owner — RLS bypassed)
-- ─────────────────────────────────────────────────────────────

-- A guaranteed working day in the next 1–6 days (Mon–Sat, so the
-- branch is open and providers have a schedule).
PERFORM set_config(
    'test.day',
    (SELECT to_char(min(d), 'YYYY-MM-DD')
       FROM generate_series(now()::date + 1, now()::date + 6, '1 day') AS d
      WHERE EXTRACT(DOW FROM d) BETWEEN 1 AND 6),
    false
);

-- A working day more than a week away (for the advance-notice test).
PERFORM set_config(
    'test.day_far',
    (SELECT to_char(min(d), 'YYYY-MM-DD')
       FROM generate_series(now()::date + 8, now()::date + 20, '1 day') AS d
      WHERE EXTRACT(DOW FROM d) BETWEEN 1 AND 6),
    false
);

PERFORM set_config('test.branch', (SELECT id::text FROM public.branches WHERE slug = 'dubai'), false);
PERFORM set_config('test.branch_auh', (SELECT id::text FROM public.branches WHERE slug = 'abu-dhabi'), false);

-- Fixture service: 60 minutes, no buffer.
INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order)
SELECT 'Availability Test Service', 'fixture', 60, 100.00, 'AED', true, 800
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Availability Test Service');

-- Buffer fixture: 60 minutes with a 15-minute after-booking buffer.
INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order, buffer_minutes)
SELECT 'Availability Buffer Service', 'fixture', 60, 100.00, 'AED', true, 801, 15
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Availability Buffer Service');

-- Advance-notice fixture: requires 7 days notice.
INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order, booking_rules)
SELECT 'Availability Advance Service', 'fixture', 60, 100.00, 'AED', true, 802,
       '{"min_advance_days": 7}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'Availability Advance Service');

-- Fixture providers at the Dubai branch (provider 2 has NO weekly
-- schedule so it can never take a slot).
SELECT public.ensure_demo_staff(
    'avl.provider@test.local', '+971500000301',
    'Avl Test Provider', 'Fixture Provider',
    ARRAY['Fixture']
);
SELECT public.ensure_demo_staff(
    'avl.provider2@test.local', '+971500000302',
    'Avl Test Provider 2', 'Fixture Provider 2',
    ARRAY['Fixture']
);

-- Fixture patient (needed to attach appointments).
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
)
SELECT '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
       'authenticated', 'authenticated', 'avl.patient@test.local',
       crypt('Password123!', gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}',
       jsonb_build_object('role', 'patient', 'full_name', 'Avl Test Patient', 'mobile_number', '+971500000303'),
       now(), now();

PERFORM set_config('test.service', (SELECT id::text FROM public.services WHERE name = 'Availability Test Service'), false);
PERFORM set_config('test.svc_buffer', (SELECT id::text FROM public.services WHERE name = 'Availability Buffer Service'), false);
PERFORM set_config('test.svc_advance', (SELECT id::text FROM public.services WHERE name = 'Availability Advance Service'), false);
PERFORM set_config('test.staff', (SELECT st.id::text FROM public.staff st JOIN public.profiles p ON p.id = st.profile_id WHERE p.full_name = 'Avl Test Provider'), false);
PERFORM set_config('test.staff2', (SELECT st.id::text FROM public.staff st JOIN public.profiles p ON p.id = st.profile_id WHERE p.full_name = 'Avl Test Provider 2'), false);
PERFORM set_config('test.patient', (SELECT id::text FROM public.profiles WHERE email = 'avl.patient@test.local'), false);

-- Fixture services available at BOTH demo branches (005 only covers
-- the services that existed when it ran, so we add these here).
INSERT INTO public.service_branches (service_id, branch_id, available, currency)
SELECT id, b.id, true, 'AED'
FROM public.services s
CROSS JOIN public.branches b
WHERE s.name IN ('Availability Test Service', 'Availability Buffer Service', 'Availability Advance Service')
  AND b.slug IN ('dubai', 'abu-dhabi')
ON CONFLICT (service_id, branch_id) DO NOTHING;

-- Provider 1 works at BOTH branch fixtures (multi-branch staff), with
-- a Mon–Sat 10:00–20:00 weekly schedule.
INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active)
SELECT public.get_setting_uuid('test.staff'), b.id, (b.slug = 'dubai'), true
FROM public.branches b
WHERE b.slug IN ('dubai', 'abu-dhabi')
ON CONFLICT (staff_id, branch_id) DO NOTHING;

INSERT INTO public.staff_availability (staff_id, day_of_week, start_time, end_time)
SELECT public.get_setting_uuid('test.staff'), d.day_of_week, '10:00', '20:00'
FROM (SELECT generate_series(1, 6) AS day_of_week) d
ON CONFLICT (staff_id, day_of_week) DO NOTHING;

-- Provider 2 is assigned to Dubai only and has NO weekly schedule.
INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active)
SELECT public.get_setting_uuid('test.staff2'), public.get_setting_uuid('test.branch'), false, true
ON CONFLICT (staff_id, branch_id) DO NOTHING;

RAISE NOTICE 'availability fixtures ready';

-- ─────────────────────────────────────────────────────────────
-- TEST 1: provider list for the branch
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    EXISTS (
        SELECT 1 FROM public.get_branch_providers(public.get_setting_uuid('test.branch'))
        WHERE id = public.get_setting_uuid('test.staff')
          AND full_name = 'Avl Test Provider'
          AND primary_branch = true
    ),
    'branch provider list contains the fixture provider with primary flag'
);

SELECT public.expect(
    EXISTS (
        SELECT 1 FROM public.get_branch_providers(public.get_setting_uuid('test.branch'))
        WHERE id = public.get_setting_uuid('test.staff2')
            AND primary_branch = false
    ),
    'provider 2 is listed for the Dubai branch (assigned, no weekly schedule yet)'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: working day generates a valid slot grid
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day  date := public.get_setting_date('test.day');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc  uuid := public.get_setting_uuid('test.service');
    v_staff uuid := public.get_setting_uuid('test.staff');
    v_count int;
    v_first timestamptz;
    v_ok_first time;
    v_ok_grid boolean;
    v_ok_end boolean;
    v_ok_date boolean;
BEGIN
    SELECT count(*), min(slot_start) INTO v_count, v_first
      FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[]);

    PERFORM public.expect(v_count = 19, format('mon-sat 10:00-20:00, 60min svc, 30min grid -> 19 slots (got %)', v_count));

    v_ok_first := (v_first AT TIME ZONE 'Asia/Dubai')::time = time '10:00';
    PERFORM public.expect(v_ok_first, 'first slot starts at the branch opening time 10:00 (Asia/Dubai)');

    v_ok_grid := NOT EXISTS (
        SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[])
        WHERE extract(minute FROM (slot_start AT TIME ZONE 'Asia/Dubai')) % 30 <> 0
           OR extract(second FROM (slot_start AT TIME ZONE 'Asia/Dubai')) <> 0
    );
    PERFORM public.expect(v_ok_grid, 'every slot sits on the 30-minute grid in branch time');

    v_ok_end := NOT EXISTS (
        SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[])
        WHERE slot_end > (v_day + time '20:00') AT TIME ZONE 'Asia/Dubai'
    );
    PERFORM public.expect(v_ok_end, 'no slot ends after branch closing (20:00)');

    v_ok_date := NOT EXISTS (
        SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[])
        WHERE booking_date <> v_day
    );
    PERFORM public.expect(v_ok_date, 'returned slots carry the requested branch-local date');

    -- Duration is respected: slot length == service duration.
    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[])
            WHERE extract(epoch FROM (slot_end - slot_start))::int <> 3600
        ),
        'every slot lasts exactly the 60-minute service duration'
    );

    -- The engine offers at least one provider for these slots.
    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[])
            WHERE v_staff = ANY (staff_ids)
        ),
        'slot carries the fixture provider id'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: clinic-wide holiday closes the day
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_count int;
BEGIN
    INSERT INTO public.holidays (date, reason) VALUES (v_day, 'test holiday');
    SELECT count(*) INTO v_count FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[]);
    PERFORM public.expect(v_count = 0, 'no slots on a clinic-wide holiday');
    DELETE FROM public.holidays WHERE date = v_day AND reason = 'test holiday';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4: branch closure closes the day
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_count int;
BEGIN
    INSERT INTO public.branch_closures (branch_id, date, reason)
    VALUES (v_branch, v_day, 'test closure');
    SELECT count(*) INTO v_count FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[]);
    PERFORM public.expect(v_count = 0, 'no slots on a branch closure day');
    DELETE FROM public.branch_closures WHERE branch_id = v_branch AND date = v_day;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5: provider filter
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_staff uuid := public.get_setting_uuid('test.staff');
    v_staff2 uuid := public.get_setting_uuid('test.staff2');
    v_count int;
BEGIN
    SELECT count(*) INTO v_count
      FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_staff]::uuid[]);
    PERFORM public.expect(v_count = 19, 'filtering to an available provider keeps the 19 slots');

    SELECT count(*) INTO v_count
      FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_staff2]::uuid[]);
    PERFORM public.expect(v_count = 0, 'a provider without a weekly schedule yields zero slots');

    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[])
             WHERE NOT (v_staff = ANY (staff_ids))
        ),
        'every unfiltered slot is covered by the branch provider'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 6: existing appointment removes its slot
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_staff uuid := public.get_setting_uuid('test.staff');
    v_patient uuid := public.get_setting_uuid('test.patient');
    v_count int;
    v_taken timestamptz := (v_day + time '11:00') AT TIME ZONE 'Asia/Dubai';
BEGIN
    INSERT INTO public.appointments (
        patient_id, service_id, staff_id, branch_id,
        scheduled_start, scheduled_end, status,
        client_number, service_name_snapshot, price_snapshot, currency_snapshot
    )
    SELECT v_patient, v_svc, v_staff, v_branch,
           v_taken, v_taken + interval '1 hour', 'Confirmed',
           p.client_number, s.name, COALESCE(sb.price, s.price), 'AED'
      FROM public.profiles p
      JOIN public.services s ON s.id = v_svc
      LEFT JOIN public.service_branches sb ON sb.service_id = s.id AND sb.branch_id = v_branch
     WHERE p.id = v_patient;

    SELECT count(*) INTO v_count
      FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_staff]::uuid[]);
    PERFORM public.expect(v_count = 18, 'an 11:00 booking removes exactly the 11:00 slot (19 -> 18)');

    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_staff]::uuid[])
            WHERE slot_start = v_taken
        ),
        'the booked slot is unavailable'
    );

    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_staff]::uuid[])
            WHERE slot_start = v_taken + interval '1 hour'
        ),
        'the next free slot (12:00) remains available when there is no buffer'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 7: service buffer protects the following slot
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.svc_buffer');
    v_staff uuid := public.get_setting_uuid('test.staff');
    v_patient uuid := public.get_setting_uuid('test.patient');
    v_15 timestamptz := (v_day + time '15:00') AT TIME ZONE 'Asia/Dubai';
    v_filt uuid := public.get_setting_uuid('test.staff');
BEGIN
    -- 15:00–16:00 booking for the buffer service (15 min buffer).
    -- (11:00 is already taken by TEST 6 — same provider/start would
    -- trip the double-booking index.)
    INSERT INTO public.appointments (
        patient_id, service_id, staff_id, branch_id,
        scheduled_start, scheduled_end, status,
        client_number, service_name_snapshot, price_snapshot, currency_snapshot
    )
    SELECT v_patient, v_svc, v_staff, v_branch,
           v_15, v_15 + interval '1 hour', 'Confirmed',
           p.client_number, s.name, 100.00, 'AED'
      FROM public.profiles p
      JOIN public.services s ON s.id = v_svc
     WHERE p.id = v_patient;

    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_filt]::uuid[])
            WHERE slot_start = v_15 + interval '1 hour'
        ),
        'buffer service: 16:00 is blocked while the post-booking buffer (until 16:15) is open'
    );

    -- The 16:30 grid slot starts after the 16:15 buffer clears.
    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.get_availability(v_branch, v_svc, v_day, v_day, ARRAY[v_filt]::uuid[])
            WHERE slot_start = v_15 + interval '1 hour 30 minutes'
        ),
        'buffer service: the next grid slot (16:30) is available once the buffer clears'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 8: cross-branch block (provider at two branches)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_dubai uuid := public.get_setting_uuid('test.branch');
    v_auh uuid := public.get_setting_uuid('test.branch_auh');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_staff uuid := public.get_setting_uuid('test.staff');
    v_patient uuid := public.get_setting_uuid('test.patient');
    v_14 timestamptz := (v_day + time '14:00') AT TIME ZONE 'Asia/Dubai';
BEGIN
    -- Book provider 1 at Dubai 14:00. (The service is available at
    -- the Abu Dhabi branch via the 005 cross-join seed.)
    INSERT INTO public.appointments (
        patient_id, service_id, staff_id, branch_id,
        scheduled_start, scheduled_end, status,
        client_number, service_name_snapshot, price_snapshot, currency_snapshot
    )
    SELECT v_patient, v_svc, v_staff, v_dubai,
           v_14, v_14 + interval '1 hour', 'Confirmed',
           p.client_number, s.name, COALESCE(sb.price, s.price), 'AED'
      FROM public.profiles p
      JOIN public.services s ON s.id = v_svc
      LEFT JOIN public.service_branches sb ON sb.service_id = s.id AND sb.branch_id = v_dubai
     WHERE p.id = v_patient;

    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.service_branches
            WHERE service_id = v_svc AND branch_id = v_auh AND available = true
        ),
        'fixture service is available at the Abu Dhabi branch'
    );

    PERFORM public.expect(
        NOT EXISTS (
            SELECT 1 FROM public.get_availability(v_auh, v_svc, v_day, v_day, ARRAY[v_staff]::uuid[])
            WHERE slot_start = v_14
        ),
        'a Dubai 14:00 booking removes the Abu Dhabi 14:00 slot for the same provider'
    );

    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.get_availability(v_auh, v_svc, v_day, v_day, ARRAY[v_staff]::uuid[])
        ),
        'the provider still has other slots at the second branch'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 9: DB-level single-success guarantee under parallelism
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_dubai uuid := public.get_setting_uuid('test.branch');
    v_auh uuid := public.get_setting_uuid('test.branch_auh');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_staff uuid := public.get_setting_uuid('test.staff');
    v_patient uuid := public.get_setting_uuid('test.patient');
    v_16 timestamptz := (v_day + time '16:00') AT TIME ZONE 'Asia/Dubai';
    v_second_ok boolean := true;
BEGIN
    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE indexname = 'idx_appointments_no_double_book'
        ),
        'partial unique index (staff_id, scheduled_start) exists'
    );

    -- First "parallel" request wins the 16:00 slot (at Dubai).
    INSERT INTO public.appointments (
        patient_id, service_id, staff_id, branch_id,
        scheduled_start, scheduled_end, status,
        client_number, service_name_snapshot, price_snapshot, currency_snapshot
    )
    SELECT v_patient, v_svc, v_staff, v_dubai,
           v_16, v_16 + interval '1 hour', 'Pending',
           p.client_number, s.name, COALESCE(sb.price, s.price), 'AED'
      FROM public.profiles p
      JOIN public.services s ON s.id = v_svc
      LEFT JOIN public.service_branches sb ON sb.service_id = s.id AND sb.branch_id = v_dubai
     WHERE p.id = v_patient;

    -- Second concurrent request for the SAME slot at another branch
    -- must fail with a unique violation — one booking only.
    BEGIN
        INSERT INTO public.appointments (
            patient_id, service_id, staff_id, branch_id,
            scheduled_start, scheduled_end, status,
            client_number, service_name_snapshot, price_snapshot, currency_snapshot
        )
        SELECT v_patient, v_svc, v_staff, v_auh,
               v_16, v_16 + interval '1 hour', 'Pending',
               p.client_number, s.name, COALESCE(sb.price, s.price), 'AED'
          FROM public.profiles p
          JOIN public.services s ON s.id = v_svc
          LEFT JOIN public.service_branches sb ON sb.service_id = s.id AND sb.branch_id = v_auh
         WHERE p.id = v_patient;
        v_second_ok := false;
    EXCEPTION WHEN unique_violation THEN
        NULL; -- expected
    END;

    PERFORM public.expect(v_second_ok, 'the second concurrent request for one slot fails (exactly one booking)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 10: past dates never produce slots
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.service');
    v_past date := (now() AT TIME ZONE 'Asia/Dubai')::date - 1;
    v_count int;
BEGIN
    SELECT count(*) INTO v_count
      FROM public.get_availability(v_branch, v_svc, v_past, v_past, NULL::uuid[]);
    PERFORM public.expect(v_count = 0, 'no slots for a past date');

    -- A range ending before today also yields nothing: the engine
    -- clamps the window to today..today + booking_window - 1.
    SELECT count(*) INTO v_count
      FROM public.get_availability(v_branch, v_svc, v_past - 3, v_past, NULL::uuid[]);
    PERFORM public.expect(v_count = 0, 'no slots when the whole requested range is in the past');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 11: advance-notice booking rule
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_day date := public.get_setting_date('test.day');
    v_day_far date := public.get_setting_date('test.day_far');
    v_branch uuid := public.get_setting_uuid('test.branch');
    v_svc uuid := public.get_setting_uuid('test.svc_advance');
    v_count int;
    v_count_far int;
BEGIN
    SELECT count(*) INTO v_count
      FROM public.get_availability(v_branch, v_svc, v_day, v_day, NULL::uuid[]);
    PERFORM public.expect(v_count = 0, '7-day advance notice blocks this weeks slots');

    SELECT count(*) INTO v_count_far
      FROM public.get_availability(v_branch, v_svc, v_day_far, v_day_far, NULL::uuid[]);
    PERFORM public.expect(v_count_far > 0, 'slots reappear beyond the 7-day notice window');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixtures (reverse dependency order), keep schema
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.appointments         WHERE patient_id = public.get_setting_uuid('test.patient');
DELETE FROM public.branch_closures      WHERE reason = 'test closure';
DELETE FROM public.holidays             WHERE reason = 'test holiday';
DELETE FROM public.staff_availability   WHERE staff_id IN (public.get_setting_uuid('test.staff'), public.get_setting_uuid('test.staff2'));
DELETE FROM public.staff_branches       WHERE staff_id IN (public.get_setting_uuid('test.staff'), public.get_setting_uuid('test.staff2'));
DELETE FROM public.service_branches     WHERE service_id IN (
    SELECT id FROM public.services WHERE name IN (
        'Availability Test Service', 'Availability Buffer Service', 'Availability Advance Service'
    )
);
DELETE FROM public.services             WHERE name IN (
    'Availability Test Service', 'Availability Buffer Service', 'Availability Advance Service'
);
DELETE FROM public.staff                WHERE profile_id IN (
    SELECT id FROM public.profiles WHERE email LIKE 'avl.%@test.local'
);
DELETE FROM public.profiles             WHERE email LIKE 'avl.%@test.local';
DELETE FROM auth.users                  WHERE email LIKE 'avl.%@test.local';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.get_setting_date(text);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL AVAILABILITY ENGINE ACCEPTANCE TESTS PASSED' AS result;