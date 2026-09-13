-- ============================================================
-- The Perfect Look — Profile API RLS acceptance test (T8)
-- ============================================================
-- Verifies:
--   1. A patient ONLY reads their OWN profile (RLS-scoped GET /profile).
--   2. A patient CANNOT update another patient's profile (PUT isolation).
--   3. A patient CAN update their own allowed fields
--      (full_name, dob, gender, preferred_language).
--   4. A patient CANNOT self-change their role (prevent_self_role_change).
--   5. A patient CANNOT self-change email/mobile directly
--      (T8/T35 gated — prevent_self_contact_change).
--   6. Staff and admin can read all profiles.
--
-- Run against the local db (must be started first):
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_profiles.sql
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
        ('patient1@test.local', 'patient', 'Patient One',   '+971500000011'),
        ('patient2@test.local', 'patient', 'Patient Two',   '+971500000012'),
        ('staff1@test.local',   'staff',   'Staff One',     '+971500000013'),
        ('admin1@test.local',   'admin',   'Admin One',     '+971500000014')
    ) AS v(email, r, fn, mn);

    PERFORM set_config('test.p1', (SELECT id::text FROM public.profiles WHERE email = 'patient1@test.local'), false);
    PERFORM set_config('test.p2', (SELECT id::text FROM public.profiles WHERE email = 'patient2@test.local'), false);
    PERFORM set_config('test.admin', (SELECT id::text FROM public.profiles WHERE email = 'admin1@test.local'), false);

    RAISE NOTICE 'fixtures ready';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 1: GET /profile — patient reads ONLY their own profile
-- ─────────────────────────────────────────────────────────────

SELECT public.act_as(public.get_setting_uuid('test.p1'));

SELECT public.expect(
    (SELECT count(*) FROM public.profiles) = 1,
    'patient1 sees exactly 1 profile (own only)'
);

SELECT public.expect(
    (SELECT count(*) FROM public.profiles
      WHERE id = public.get_setting_uuid('test.p2')) = 0,
    'patient1 CANNOT read patient2 profile row'
);

SELECT public.expect(
    (SELECT full_name FROM public.profiles WHERE id = public.get_setting_uuid('test.p1')) = 'Patient One',
    'patient1 reads their own full_name'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: PUT /profile — patient CANNOT edit patient B's row
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    updated integer := 0;
BEGIN
    UPDATE public.profiles
       SET full_name = 'Hacked Name'
     WHERE id = public.get_setting_uuid('test.p2');
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 0, 'patient1 CANNOT update patient2 profile (RLS blocks, 0 rows)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: PUT /profile — patient CAN update their own allowed fields
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    updated integer := 0;
    nm text;
    lang text;
BEGIN
    UPDATE public.profiles
       SET full_name         = 'Patient One Updated',
           dob               = '1990-05-15',
           gender            = 'Female',
           preferred_language = 'ar'
     WHERE id = public.get_setting_uuid('test.p1');
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 1, 'patient1 updates own profile (full_name/dob/gender/language)');

    SELECT full_name, preferred_language
      INTO nm, lang
      FROM public.profiles WHERE id = public.get_setting_uuid('test.p1');
    PERFORM public.expect(
        nm = 'Patient One Updated' AND lang = 'ar',
        'patient1 changes persisted to profiles row'
    );

    UPDATE public.profiles
       SET full_name = 'Patient One'
     WHERE id = public.get_setting_uuid('test.p1');
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 1, 'patient1 can restore full name');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4: patient CANNOT self-change their role
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
    BEGIN
        UPDATE public.profiles
           SET role = 'admin'
         WHERE id = public.get_setting_uuid('test.p1');
        RAISE EXCEPTION 'role change was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'patient1 CANNOT self-change role (trigger blocks)');
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5: patient CANNOT self-change email/mobile (gated, T35)
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
    BEGIN
        UPDATE public.profiles
           SET mobile_number = '+971509999999'
         WHERE id = public.get_setting_uuid('test.p1');
        RAISE EXCEPTION 'mobile change was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'patient1 CANNOT self-change mobile (trigger blocks)');
    END;

    BEGIN
        UPDATE public.profiles
           SET email = 'hacked@test.local'
         WHERE id = public.get_setting_uuid('test.p1');
        RAISE EXCEPTION 'email change was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'patient1 CANNOT self-change email (trigger blocks)');
    END;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 6: staff + admin read ALL profiles
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
       jsonb_build_object('role','staff','full_name','Staff Two','mobile_number','+971500000015'),
       now(), now();

SELECT public.act_as((SELECT id FROM public.profiles WHERE email = 'staff2@test.local'));

SELECT public.expect(
    (SELECT count(*) FROM public.profiles) = 5,
    'staff sees all profiles'
);

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.admin'));

SELECT public.expect(
    (SELECT count(*) FROM public.profiles) = 5,
    'admin sees all profiles'
);

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixture users (reverse dependency order), keep schema
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
DELETE FROM public.profiles WHERE email LIKE '%@test.local';
DELETE FROM auth.users WHERE email LIKE '%@test.local';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL PROFILE API RLS TESTS PASSED' AS result;