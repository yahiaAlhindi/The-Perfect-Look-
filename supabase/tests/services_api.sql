-- ============================================================
-- The Perfect Look — Services API acceptance test (T9)
-- ============================================================
-- Verifies the T9 server-side guarantees (enforced by RLS from
-- T3's 001_schema.sql — no client-side trust):
--   1. anon/patient read only ACTIVE services (SRS §8).
--   2. patient cannot INSERT / UPDATE / deactivate a service.
--   3. staff can READ all services (incl. inactive) but CANNOT
--      write — services are admin-managed (T11 "guarded to
--      admin").
--   4. admin can create + deactivate, and the change is reflected
--      immediately on the patient side.
--
-- Requires migrations 001–003 applied (services seeded by T4).
-- Run against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/services_api.sql
--
-- Or paste into the online Supabase SQL editor (runs as table
-- owner, so RLS is bypassed for fixtures). Every assertion prints
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
    ('svc.patient@test.local', 'customer', 'Svc Patient', '+971500000101'),
    ('svc.staff@test.local',   'provider', 'Svc Staff',   '+971500000102'),
    ('svc.admin@test.local',   'administrator', 'Svc Admin',   '+971500000103')
) AS v(email, r, fn, mn);

PERFORM set_config('test.p', (SELECT id::text FROM public.profiles WHERE email = 'svc.patient@test.local'), false);
PERFORM set_config('test.s', (SELECT id::text FROM public.profiles WHERE email = 'svc.staff@test.local'), false);
PERFORM set_config('test.a', (SELECT id::text FROM public.profiles WHERE email = 'svc.admin@test.local'), false);

-- Fixture services for visibility checks (active + inactive)
INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order)
SELECT 'RLS Test Active', 'fixture', 30, 120.00, 'AED', true, 900
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'RLS Test Active');

INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order)
SELECT 'RLS Test Inactive', 'fixture', 30, 120.00, 'AED', false, 901
WHERE NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'RLS Test Inactive');

RAISE NOTICE 'services fixtures ready';

-- ─────────────────────────────────────────────────────────────
-- TEST 1: patient (authenticated) reads ACTIVE services only —
--         the inactive fixture is invisible (SRS §8)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p'));

SELECT public.expect(
    (SELECT count(*) FROM public.services WHERE name = 'RLS Test Active') = 1,
    'patient sees the active test service'
);

SELECT public.expect(
    (SELECT count(*) FROM public.services WHERE name = 'RLS Test Inactive') = 0,
    'patient does NOT read the inactive test service'
);

SELECT public.expect(
    (SELECT count(*) FROM public.services)
    = (SELECT count(*) FROM public.services WHERE active = true),
    'patient sees only active services in general'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: patient CANNOT insert a service (admin-only write)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    inserted boolean := false;
BEGIN
    BEGIN
        INSERT INTO public.services (name, duration_minutes, price)
        VALUES ('RLS Patient Insert', 30, 10.00);
        GET DIAGNOSTICS inserted = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        PERFORM public.expect(true, 'patient CANNOT insert a service (RLS)');
        RETURN;
    END;
    PERFORM public.expect(inserted = false, 'patient insert of a service was blocked (0 rows)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: patient CANNOT deactivate a service (update blocked)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    updated int := -1;
BEGIN
    UPDATE public.services
       SET active = false
     WHERE name = 'RLS Test Active';
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 0, 'patient CANNOT deactivate a service (0 rows affected)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4: staff reads ALL services (incl. inactive) but
--         cannot write (services are admin-managed)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.s'));

SELECT public.expect(
    (SELECT count(*) FROM public.services WHERE name = 'RLS Test Inactive') = 1,
    'staff can READ inactive services'
);

DO $$
DECLARE
    inserted boolean := false;
BEGIN
    BEGIN
        INSERT INTO public.services (name, duration_minutes, price)
        VALUES ('RLS Staff Insert', 30, 10.00);
        GET DIAGNOSTICS inserted = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        PERFORM public.expect(true, 'staff CANNOT insert a service (admin-only write, RLS)');
        RETURN;
    END;
    PERFORM public.expect(inserted = false, 'staff insert of a service was blocked (0 rows)');
END;
$$;

DO $$
DECLARE
    updated int := -1;
BEGIN
    UPDATE public.services SET active = false WHERE name = 'RLS Test Active';
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 0, 'staff CANNOT deactivate a service (0 rows affected)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5: admin CRUD works AND the change is reflected on the
--         patient side immediately (T9 acceptance criterion)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.a'));

INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order)
VALUES ('RLS Admin Created', 'created by admin', 30, 99.00, 'AED', true, 902);

DO $$
DECLARE
    v_count int;
BEGIN
    SELECT count(*) INTO v_count FROM public.services WHERE name = 'RLS Admin Created';
    PERFORM public.expect(v_count = 1, 'admin CAN create a service');
END;
$$;

-- The patient immediately sees the admin-created active service
RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p'));

SELECT public.expect(
    (SELECT count(*) FROM public.services WHERE name = 'RLS Admin Created' AND active = true) = 1,
    'admin-created active service is immediately visible to patients'
);

-- Admin deactivates it …
RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.a'));

DO $$
DECLARE
    v_count int;
BEGIN
    UPDATE public.services SET active = false WHERE name = 'RLS Admin Created';
    SELECT count(*) INTO v_count FROM public.services WHERE name = 'RLS Admin Created' AND active = false;
    PERFORM public.expect(v_count = 1, 'admin CAN deactivate a service');
END;
$$;

-- … and it disappears from the patient list immediately
RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p'));

SELECT public.expect(
    (SELECT count(*) FROM public.services WHERE name = 'RLS Admin Created') = 0,
    'deactivated service disappears from the patient list immediately'
);

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixtures (reverse dependency order), keep schema
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.notifications WHERE user_id IN (SELECT id FROM profiles WHERE email LIKE 'svc.%@test.local');
DELETE FROM public.audit_logs      WHERE admin_user_id IN (SELECT id FROM profiles WHERE email LIKE 'svc.%@test.local');
DELETE FROM public.services        WHERE name LIKE 'RLS %';
DELETE FROM public.profiles        WHERE email LIKE 'svc.%@test.local';
DELETE FROM auth.users             WHERE email LIKE 'svc.%@test.local';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL SERVICES API ACCEPTANCE TESTS PASSED' AS result;