-- ============================================================
-- The Perfect Look — RLS acceptance test (T3)
-- ============================================================
-- Verifies:
--   1. A patient can only read their OWN appointments (SRS §17).
--   2. A patient CANNOT insert/update another patient's appointment.
--   3. Staff see all appointments; admin sees all appointments.
--   4. Appointment status enum matches SRS §10 exactly.
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

DO $$
DECLARE
    svc uuid;
    st_id uuid;
BEGIN
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
        ('patient1@test.local', 'patient', 'Patient One',   '+971500000001'),
        ('patient2@test.local', 'patient', 'Patient Two',   '+971500000002'),
        ('staff1@test.local',   'staff',   'Staff One',     '+971500000003'),
        ('admin1@test.local',   'admin',   'Admin One',     '+971500000004')
    ) AS v(email, r, fn, mn);

    SELECT id INTO st_id FROM public.staff WHERE profile_id = (
        SELECT id FROM public.profiles WHERE email = 'staff1@test.local'
    );
    IF st_id IS NULL THEN
        INSERT INTO public.staff (profile_id, title)
        VALUES ((SELECT id FROM public.profiles WHERE email = 'staff1@test.local'), 'Receptionist');
    END IF;

    INSERT INTO public.services (name, duration_minutes, price, currency)
    VALUES ('Skin Care Treatment', 60, 250.00, 'AED')
    RETURNING id INTO svc;

    INSERT INTO public.appointments (patient_id, service_id, staff_id, scheduled_start, scheduled_end)
    SELECT (SELECT id FROM public.profiles WHERE email = 'patient1@test.local'), svc,
           (SELECT id FROM public.staff LIMIT 1),
           '2026-10-01 10:00:00+00', '2026-10-01 11:00:00+00';

    INSERT INTO public.appointments (patient_id, service_id, staff_id, scheduled_start, scheduled_end)
    SELECT (SELECT id FROM public.profiles WHERE email = 'patient2@test.local'), svc,
           (SELECT id FROM public.staff LIMIT 1),
           '2026-10-01 11:00:00+00', '2026-10-01 12:00:00+00';

    PERFORM set_config('test.p1', (SELECT id::text FROM public.profiles WHERE email = 'patient1@test.local'), false);
    PERFORM set_config('test.p2', (SELECT id::text FROM public.profiles WHERE email = 'patient2@test.local'), false);
    PERFORM set_config('test.ap2', (SELECT id::text FROM public.appointments a JOIN public.profiles p ON p.id = a.patient_id WHERE p.email = 'patient2@test.local'), false);
    PERFORM set_config('test.admin', (SELECT id::text FROM public.profiles WHERE email = 'admin1@test.local'), false);

    RAISE NOTICE 'fixtures ready';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 1: patient 1 reads ONLY their own appointment
-- ─────────────────────────────────────────────────────────────

SELECT public.act_as(public.get_setting_uuid('test.p1'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 1,
    'patient1 sees exactly 1 appointment (own only)'
);

SELECT public.expect(
    (SELECT count(*) FROM public.appointments WHERE patient_id = public.get_setting_uuid('test.p1')) = 1,
    'patient1 sees only their own appointment row'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: patient 1 cannot insert an appointment for patient 2
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    svc_id uuid;
BEGIN
    SELECT id INTO svc_id FROM public.services LIMIT 1;
    BEGIN
        INSERT INTO public.appointments (
            patient_id, service_id, scheduled_start, scheduled_end
        ) VALUES (
            public.get_setting_uuid('test.p2'), svc_id,
            '2026-10-02 09:00:00+00', '2026-10-02 10:00:00+00'
        );
        RAISE EXCEPTION 'insert was NOT blocked';
    EXCEPTION WHEN insufficient_privilege THEN
        PERFORM public.expect(true, 'patient1 CANNOT insert appointment for patient2');
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: patient 1 cannot update patient 2's appointment
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
        PERFORM public.expect(true, 'patient1 CANNOT update patient2 appointment (blocked by RLS)');
        RETURN;
    END;
    PERFORM public.expect(updated = false, 'patient1 cannot update patient2 appointment (no row affected)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4: staff sees ALL appointments
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
)
SELECT '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
       'authenticated', 'authenticated', 'staff2@test.local',
       crypt('Password123!', gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}',
       jsonb_build_object('role','staff','full_name','Staff Two','mobile_number','+971500000005'),
       now(), now();

SELECT public.act_as((SELECT id FROM public.profiles WHERE email = 'staff2@test.local'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 2,
    'staff sees all 2 appointments'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 5: admin sees ALL appointments
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.admin'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 2,
    'admin sees all 2 appointments'
);

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- TEST 6: appointment status enum matches SRS §10 exactly
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
DELETE FROM public.appointments    WHERE patient_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.staff           WHERE profile_id IN (SELECT id FROM profiles WHERE email LIKE '%@test.local');
DELETE FROM public.profiles        WHERE email LIKE '%@test.local';
DELETE FROM auth.users             WHERE email LIKE '%@test.local';
DELETE FROM public.services        WHERE name = 'Skin Care Treatment';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL RLS ACCEPTANCE TESTS PASSED' AS result;