-- ============================================================
-- The Perfect Look — RLS acceptance test (T3 + T18 branch scope)
-- ============================================================
-- Verifies (T3 §17 + T18 acceptance criteria):
--   1. A customer can only read their OWN appointments (SRS §17).
--   2. A customer CANNOT insert/update another customer's appointment.
--   3. Staff access is BRANCH-SCOPED: a receptionist reads only the
--      appointments of branches they were granted (T37 branch_access
--      + T18 role model) — never another branch's records.
--   4. Admins see all appointments.
--   5. Customers cannot reach the staff client-search API (SRS §5.3).
--   6. Appointment status enum matches SRS §10 exactly.
--
-- Run against the local db (must be started first):
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_appointments.sql
--
-- Or paste into the online Supabase SQL editor (which runs as the
-- table owner). Every assertion prints PASS or raises an error.
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
-- FIXTURES (as table owner — RLS bypassed)
-- ─────────────────────────────────────────────────────────────

-- T18: handle_new_user() only honours a metadata role while this
-- session flag is set — enables the fixture roles below.
SELECT set_config('app.rbac_role_change_authorized', 'true', false);

DO $$
DECLARE
    svc uuid;
    dxb uuid;
    auh uuid;
    st_id uuid;
BEGIN
    SELECT id INTO dxb FROM public.branches WHERE slug = 'dubai';
    SELECT id INTO auh FROM public.branches WHERE slug = 'abu-dhabi';

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
        ('patient1@test.local', 'customer', 'Patient One',   '+971500000001'),
        ('patient2@test.local', 'customer', 'Patient Two',   '+971500000002'),
        ('rec1@test.local',     'receptionist', 'Receptionist One', '+971500000003'),
        ('mgr1@test.local',     'branch_manager', 'Branch Manager', '+971500000006'),
        ('admin1@test.local',   'administrator', 'Admin One',   '+971500000004')
    ) AS v(email, r, fn, mn);

    -- Staff rows for the staff fixtures (the front desk + manager).
    INSERT INTO public.staff (profile_id, title)
    SELECT id, 'Receptionist'
      FROM public.profiles WHERE email IN ('rec1@test.local', 'mgr1@test.local')
    ON CONFLICT (profile_id) DO NOTHING;

    -- Branch-scoped grants (T37 branch_access drives the RLS scope):
    -- receptionist → Dubai, branch manager → Abu Dhabi.
    INSERT INTO public.branch_access (profile_id, branch_id, role, active)
    SELECT p.id, b.id, 'manager', true
    FROM (VALUES ('rec1@test.local', 'dubai'::text), ('mgr1@test.local', 'abu-dhabi'::text)) AS v(email, slug)
    JOIN public.profiles p ON p.email = v.email
    JOIN public.branches b  ON b.slug = v.slug
    ON CONFLICT (profile_id, branch_id) DO NOTHING;

    INSERT INTO public.services (name, duration_minutes, price, currency)
    VALUES ('Skin Care Treatment', 60, 250.00, 'AED')
    RETURNING id INTO svc;

    -- Three appointments across TWO branches + snapshot columns
    -- (branch_id/client_number/snapshots are NOT NULL after T37/005).
    INSERT INTO public.appointments (
        patient_id, service_id, branch_id, client_number,
        service_name_snapshot, price_snapshot, currency_snapshot,
        scheduled_start, scheduled_end
    )
    SELECT (SELECT id FROM public.profiles WHERE email = 'patient1@test.local'), svc, dxb,
           (SELECT client_number FROM public.profiles WHERE email = 'patient1@test.local'),
           'Skin Care Treatment', 250.00, 'AED',
           '2026-10-01 10:00:00+00', '2026-10-01 11:00:00+00';

    -- patient2 in DUBAI
    INSERT INTO public.appointments (
        patient_id, service_id, branch_id, client_number,
        service_name_snapshot, price_snapshot, currency_snapshot,
        scheduled_start, scheduled_end
    )
    SELECT (SELECT id FROM public.profiles WHERE email = 'patient2@test.local'), svc, dxb,
           (SELECT client_number FROM public.profiles WHERE email = 'patient2@test.local'),
           'Skin Care Treatment', 250.00, 'AED',
           '2026-10-01 11:00:00+00', '2026-10-01 12:00:00+00';

    -- patient2 ALSO in ABU DHABI (cross-branch isolation probe)
    INSERT INTO public.appointments (
        patient_id, service_id, branch_id, client_number,
        service_name_snapshot, price_snapshot, currency_snapshot,
        scheduled_start, scheduled_end
    )
    SELECT (SELECT id FROM public.profiles WHERE email = 'patient2@test.local'), svc, auh,
           (SELECT client_number FROM public.profiles WHERE email = 'patient2@test.local'),
           'Skin Care Treatment', 250.00, 'AED',
           '2026-10-01 14:00:00+00', '2026-10-01 15:00:00+00';

    PERFORM set_config('test.p1', (SELECT id::text FROM public.profiles WHERE email = 'patient1@test.local'), false);
    PERFORM set_config('test.p2', (SELECT id::text FROM public.profiles WHERE email = 'patient2@test.local'), false);
    PERFORM set_config('test.ap2', (SELECT id::text FROM public.appointments a JOIN public.profiles p ON p.id = a.patient_id WHERE p.email = 'patient2@test.local' AND a.branch_id = dxb LIMIT 1), false);
    PERFORM set_config('test.rec', (SELECT id::text FROM public.profiles WHERE email = 'rec1@test.local'), false);
    PERFORM set_config('test.mgr', (SELECT id::text FROM public.profiles WHERE email = 'mgr1@test.local'), false);
    PERFORM set_config('test.admin', (SELECT id::text FROM public.profiles WHERE email = 'admin1@test.local'), false);

    RAISE NOTICE 'fixtures ready';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 1: customer 1 reads ONLY their own appointment
-- ─────────────────────────────────────────────────────────────

SELECT public.act_as(public.get_setting_uuid('test.p1'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 1,
    'customer1 sees exactly 1 appointment (own only)'
);

SELECT public.expect(
    (SELECT count(*) FROM public.appointments WHERE patient_id = public.get_setting_uuid('test.p1')) = 1,
    'customer1 sees only their own appointment row'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: customer 1 cannot insert an appointment for another
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    svc_id uuid;
    dxb    uuid;
BEGIN
    SELECT id INTO svc_id FROM public.services LIMIT 1;
    SELECT id INTO dxb    FROM public.branches WHERE slug = 'dubai';
    BEGIN
        INSERT INTO public.appointments (
            patient_id, service_id, branch_id, client_number,
            service_name_snapshot, price_snapshot, currency_snapshot,
            scheduled_start, scheduled_end
        ) VALUES (
            public.get_setting_uuid('test.p2'), svc_id, dxb, 'TPL-000000',
            'Skin Care Treatment', 250.00, 'AED',
            '2026-10-02 09:00:00+00', '2026-10-02 10:00:00+00'
        );
        RAISE EXCEPTION 'insert was NOT blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        PERFORM public.expect(true, 'customer1 CANNOT insert appointment for customer2');
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: customer 1 cannot update customer 2's appointment
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    updated boolean := false;
BEGIN
    BEGIN
        UPDATE public.appointments
           SET status = 'Confirmed'
         WHERE id = public.get_setting_uuid('test.ap2');
        GET DIAGNOSTICS updated = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        PERFORM public.expect(true, 'customer1 CANNOT update customer2 appointment (blocked by RLS)');
        RETURN;
    END;
    PERFORM public.expect(updated = false, 'customer1 cannot update customer2 appointment (no row affected)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4 (T18): branch-scoped staff access — receptionist sees
--               ONLY Dubai appointments (2), never Abu Dhabi (1)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.rec'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 2,
    'receptionist sees only the 2 appointments of her Dubai branch'
);

SELECT public.expect(
    (SELECT count(*) FROM public.appointments
      WHERE branch_id = (SELECT id FROM public.branches WHERE slug = 'dubai')) = 2
    AND (SELECT count(*) FROM public.appointments
      WHERE branch_id = (SELECT id FROM public.branches WHERE slug = 'abu-dhabi')) = 0,
    'receptionist cannot read the Abu Dhabi branch records (branch isolation)'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 5 (T18): branch manager sees only HIS branch (Abu Dhabi = 1)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.mgr'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 1,
    'branch manager (Abu Dhabi) sees only his branch appointment'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 6: admin sees ALL appointments
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.admin'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 3,
    'admin sees all 3 appointments across both branches'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 7 (T18): customers cannot reach the staff client search
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p1'));

SELECT public.expect(
    EXISTS (
        SELECT 1 FROM public.search_clients('Patient One')
    ) = false,
    'customer CANNOT search/look-up other clients (staff API blocked)'
);

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- TEST 8: appointment status enum matches SRS §10 exactly
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    (SELECT array_agg(enumlabel ORDER BY enumlabel)
       FROM pg_enum
      WHERE enumtypid = 'appointment_status'::regtype)
    = ARRAY['Cancelled','Completed','Confirmed','No Show','Pending','Rescheduled'],
    'appointment_status enum matches SRS §10 (Pending/Confirmed/Completed/Cancelled/Rescheduled/No Show)'
);

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixture users (reverse dependency order), keep schema
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
DELETE FROM public.notifications WHERE user_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.audit_logs      WHERE admin_user_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.branch_access   WHERE profile_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.staff_branches  WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local'));
DELETE FROM public.appointments    WHERE patient_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.staff           WHERE profile_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.profiles        WHERE email LIKE '%@test.local';
DELETE FROM auth.users             WHERE email LIKE '%@test.local';
DELETE FROM public.services        WHERE name = 'Skin Care Treatment';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL RLS ACCEPTANCE TESTS PASSED' AS result;