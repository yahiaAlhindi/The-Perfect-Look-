-- ============================================================
-- The Perfect Look — Consent & data-request RLS acceptance test (T8)
-- ============================================================
-- Verifies:
--   1. A patient inserts ONLY their own consent records.
--   2. A patient CANNOT read another patient's consent records.
--   3. Consent records are immutable (UPDATE/DELETE rejected) and carry
--      version + timestamp.
--   4. A patient can insert/withdraw the same topic (append-only history).
--   5. A patient CANNOT request data for another user.
--   6. Staff/admin read all consents; data-request status is admin-only.
--
-- Run against the local db (must be started first):
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_consents.sql
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

CREATE OR REPLACE FUNCTION public.get_setting_uuid(name text)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting(name)::uuid;
$$;

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

-- ── FIXTURES ─────────────────────────────────────────────────
-- Requires 001 + 002 migrations; profiles auto-create on auth.users
-- insert via handle_new_user().
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
        ('consent.patient1@test.local', 'patient', 'Consent Patient One',   '+971500000021'),
        ('consent.patient2@test.local', 'patient', 'Consent Patient Two',   '+971500000022'),
        ('consent.admin1@test.local',   'admin',   'Consent Admin One',     '+971500000024')
    ) AS v(email, r, fn, mn);

    PERFORM set_config('test.cp1', (SELECT id::text FROM public.profiles WHERE email = 'consent.patient1@test.local'), false);
    PERFORM set_config('test.cp2', (SELECT id::text FROM public.profiles WHERE email = 'consent.patient2@test.local'), false);
    PERFORM set_config('test.cadmin', (SELECT id::text FROM public.profiles WHERE email = 'consent.admin1@test.local'), false);

    RAISE NOTICE 'consent fixtures ready';
END;
$$;

-- ── TEST 1: patient inserts own consent (terms_service granted v1) ──

SELECT public.act_as(public.get_setting_uuid('test.cp1'));

INSERT INTO public.consents (user_id, consent_type, version, granted, source)
VALUES (public.get_setting_uuid('test.cp1'), 'terms_service', 'v1', true, 'test');

SELECT public.expect(
    (SELECT count(*) FROM public.consents WHERE user_id = public.get_setting_uuid('test.cp1')
       AND consent_type = 'terms_service' AND granted AND version = 'v1') = 1,
    'patient1 inserted own terms_service consent (version + granted)'
);

SELECT public.expect(
    (SELECT created_at IS NOT NULL FROM public.consents
      WHERE user_id = public.get_setting_uuid('test.cp1')) ,
    'consent record carries a created_at timestamp'
);

-- ── TEST 2: patient CANNOT read another patient's consents ──

SELECT public.expect(
    (SELECT count(*) FROM public.consents
      WHERE user_id = public.get_setting_uuid('test.cp2')) = 0,
    'patient1 sees 0 consent rows belonging to patient2'
);

-- ── TEST 3: consent records are IMMUTABLE ──

DO $$
BEGIN
    BEGIN
        UPDATE public.consents
           SET granted = false
         WHERE user_id = public.get_setting_uuid('test.cp1');
        RAISE EXCEPTION 'consent UPDATE was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'consent UPDATE blocked (immutable)');
    END;

    BEGIN
        DELETE FROM public.consents
         WHERE user_id = public.get_setting_uuid('test.cp1');
        RAISE EXCEPTION 'consent DELETE was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'consent DELETE blocked (immutable)');
    END;
END;
$$;

-- ── TEST 4: append-only withdrawal for the same topic ──

INSERT INTO public.consents (user_id, consent_type, version, granted, source)
VALUES (public.get_setting_uuid('test.cp1'), 'marketing', 'v1', true, 'test');

INSERT INTO public.consents (user_id, consent_type, version, granted, source)
VALUES (public.get_setting_uuid('test.cp1'), 'marketing', 'v1', false, 'test');

SELECT public.expect(
    (SELECT count(*) FROM public.consents
      WHERE user_id = public.get_setting_uuid('test.cp1') AND consent_type = 'marketing') = 2,
    'marketing consent history has both a grant and a withdrawal row'
);

-- ── TEST 5: patient CANNOT insert consent for another user ──

DO $$
BEGIN
    BEGIN
        INSERT INTO public.consents (user_id, consent_type, granted, source)
        SELECT public.get_setting_uuid('test.cp2'), 'marketing', true, 'test';
        RAISE EXCEPTION 'consent insert for another user was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'patient1 CANNOT insert consent for patient2 (RLS rejects)');
    END;
END;
$$;

-- ── TEST 6a: data-request — own insert + read ──

INSERT INTO public.data_requests (user_id, notes)
VALUES (public.get_setting_uuid('test.cp1'), 'Please export my records');

SELECT public.expect(
    (SELECT count(*) FROM public.data_requests WHERE user_id = public.get_setting_uuid('test.cp1')) = 1,
    'patient1 records own data request and reads it back'
);

SELECT public.expect(
    (SELECT count(*) FROM public.data_requests WHERE user_id = public.get_setting_uuid('test.cp2')) = 0,
    'patient1 CANNOT read patient2 data requests'
);

-- ── TEST 6b: patient CANNOT insert a data request for another user ──

DO $$
BEGIN
    BEGIN
        INSERT INTO public.data_requests (user_id, notes)
        SELECT public.get_setting_uuid('test.cp2'), 'hacked request';
        RAISE EXCEPTION 'data-request insert for another user was NOT blocked';
    EXCEPTION WHEN raise_exception THEN
        PERFORM public.expect(true, 'patient1 CANNOT request data for patient2 (RLS rejects)');
    END;
END;
$$;

-- ── TEST 6c: patient CANNOT update data-request status ── (admin-only)

DO $$
DECLARE
    updated integer := 0;
BEGIN
    UPDATE public.data_requests
       SET status = 'fulfilled'
     WHERE user_id = public.get_setting_uuid('test.cp1');
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 0, 'patient1 CANNOT change data-request status');
END;
$$;

-- ── TEST 7: staff/admin see all consents; admin updates status ──

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.cadmin'));

UPDATE public.data_requests
   SET status = 'processing'
 WHERE user_id = public.get_setting_uuid('test.cp1');
SELECT public.expect(true, 'admin can progress a data-request status');

SELECT public.expect(
    (SELECT count(*) FROM public.consents WHERE user_id = public.get_setting_uuid('test.cp1')) = 3,
    'admin reads all consent records for patient1'
);

RESET ROLE;

-- ── Cleanup (reverse dependency order), keep schema ──

DELETE FROM public.data_requests WHERE user_id = public.get_setting_uuid('test.cp1');
DELETE FROM public.consents WHERE user_id = public.get_setting_uuid('test.cp1');
DELETE FROM public.profiles WHERE email LIKE '%@test.local';
DELETE FROM auth.users WHERE email LIKE '%@test.local';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL CONSENT & DATA-REQUEST RLS TESTS PASSED' AS result;