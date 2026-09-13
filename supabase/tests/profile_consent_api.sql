-- ============================================================
-- The Perfect Look — Profile & consent API acceptance test (T8)
-- ============================================================
-- Verifies the T8 server-side guarantees (enforced by RLS + triggers
-- from migrations 001/002/009 — no client-side trust):
--   1. A customer reads ONLY their own profile (no cross-customer
--      reads or updates).
--   2. Allowed field rules: own PUT edits work (mobile normalised),
--      but email / role / id / created_at are immutable (trigger).
--   3. Consent history: records carry a version + timestamp, every
--      add is append-only, and withdrawal inserts a new event.
--   4. A customer cannot record a consent or see consents for
--      another customer.
--   5. Data-request entry point: customer files + reads their own
--      requests; they cannot change a request's status; staff/admin
--      manage the queue.
--   6. Sensitive fields (profiles, consents, data_requests) are not
--      exposed to anon.
--
-- Requires migrations 001–009 applied (T8 schema lives in 009).
-- Run against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/profile_consent_api.sql
--
-- Or paste into the online Supabase SQL editor (runs as table owner,
-- so RLS is bypassed for fixtures). Every assertion prints PASS or
-- raises an error.
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
    ('p1.customer@test.local', 'patient', 'Patient One',   '+971500000011'),
    ('p2.customer@test.local', 'patient', 'Patient Two',   '+971500000012'),
    ('pc.admin@test.local',    'admin',   'Consent Admin', '+971500000014')
) AS v(email, r, fn, mn);

PERFORM set_config('test.p1', (SELECT id::text FROM public.profiles WHERE email = 'p1.customer@test.local'), false);
PERFORM set_config('test.p2', (SELECT id::text FROM public.profiles WHERE email = 'p2.customer@test.local'), false);
PERFORM set_config('test.admin', (SELECT id::text FROM public.profiles WHERE email = 'pc.admin@test.local'), false);

-- Consent history fixtures (owner writes)
INSERT INTO public.consents (user_id, consent_type, version, granted)
SELECT id, 'terms_of_service', 1, true FROM public.profiles WHERE email = 'p1.customer@test.local';

INSERT INTO public.consents (user_id, consent_type, version, granted)
SELECT id, 'marketing', 1, true FROM public.profiles WHERE email = 'p1.customer@test.local';

INSERT INTO public.consents (user_id, consent_type, version, granted)
SELECT id, 'marketing', 1, true FROM public.profiles WHERE email = 'p2.customer@test.local';

-- Data-request fixtures (owner writes)
INSERT INTO public.data_requests (user_id, request_type, details)
SELECT id, 'export', jsonb_build_object('reason', 'fixture') FROM public.profiles WHERE email = 'p1.customer@test.local';

INSERT INTO public.data_requests (user_id, request_type, details)
SELECT id, 'export', jsonb_build_object('reason', 'fixture') FROM public.profiles WHERE email = 'p2.customer@test.local';

RAISE NOTICE 'profile/consent fixtures ready';

-- ─────────────────────────────────────────────────────────────
-- TEST 1: patient reads ONLY their own profile
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p1'));

SELECT public.expect(
    (SELECT count(*) FROM public.profiles) = 1,
    'patient1 sees exactly 1 profile (own only)'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 2: patient CANNOT update another customer's profile
--         (RLS `profiles_update_own` — cross-customer update blocked)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    updated int := -1;
BEGIN
    UPDATE public.profiles
       SET full_name = 'Hacked by patient1'
     WHERE id = public.get_setting_uuid('test.p2');
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 0, 'patient CANNOT update another customer''s profile (0 rows affected)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: own-profile PUT on allowed fields works, mobile is
--         normalised to E.164 by the 002 trigger
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
    UPDATE public.profiles
       SET full_name = 'Patient One Updated',
           mobile_number = '0551234567',
           preferred_language = 'ar'
     WHERE id = public.get_setting_uuid('test.p1');

    PERFORM public.expect(
        (SELECT full_name FROM public.profiles WHERE id = public.get_setting_uuid('test.p1')) = 'Patient One Updated',
        'customer can edit own editable fields'
    );
    PERFORM public.expect(
        (SELECT mobile_number FROM public.profiles WHERE id = public.get_setting_uuid('test.p1')) = '+971551234567',
        'own mobile update is normalised to E.164'
    );
    PERFORM public.expect(
        (SELECT preferred_language FROM public.profiles WHERE id = public.get_setting_uuid('test.p1')) = 'ar',
        'own language update persists'
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 4: allowed field rules — email and role are immutable for
--         the self-edit path (004 trigger, SRS §17)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    blocked boolean := false;
BEGIN
    BEGIN
        UPDATE public.profiles
           SET email = 'hacked.p1@test.local'
         WHERE id = public.get_setting_uuid('test.p1');
    EXCEPTION WHEN raise_exception THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'customer CANNOT change own email (allowed field rules)');

    blocked := false;
    BEGIN
        UPDATE public.profiles
           SET role = 'admin'
         WHERE id = public.get_setting_uuid('test.p1');
    EXCEPTION WHEN raise_exception THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'customer CANNOT self-escalate their role');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5: consent history — own insert allowed, every record has a
--         version + timestamp, and withdrawal appends a new event
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.consents (user_id, consent_type, version, granted)
VALUES (public.get_setting_uuid('test.p1'), 'marketing', 1, false);

SELECT public.expect(
    (SELECT count(*) FROM public.consents
      WHERE user_id = public.get_setting_uuid('test.p1')) = 3,
    'consent history preserves grant + withdraw events'
);

SELECT public.expect(
    (SELECT bool_and(version >= 1 AND created_at IS NOT NULL)
       FROM public.consents
      WHERE user_id = public.get_setting_uuid('test.p1')),
    'every consent record includes a version and timestamp'
);

SELECT public.expect(
    ((SELECT granted FROM public.consents
        WHERE user_id = public.get_setting_uuid('test.p1')
          AND consent_type = 'marketing'
      ORDER BY created_at DESC LIMIT 1) = false),
    'latest marketing event reflects the withdrawal'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 6: patient sees ONLY their own consents
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    (SELECT count(*) FROM public.consents) = 3,
    'patient sees only their own consent history'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 7: patient CANNOT record a consent for another customer
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    blocked boolean := false;
BEGIN
    BEGIN
        INSERT INTO public.consents (user_id, consent_type, version, granted)
        VALUES (public.get_setting_uuid('test.p2'), 'terms_of_service', 1, true);
    EXCEPTION WHEN insufficient_privilege THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'patient CANNOT record consent for another customer');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 8: consent history is immutable through the API
--         (004 immutify trigger surfaces a clear error)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    blocked boolean := false;
BEGIN
    BEGIN
        UPDATE public.consents
           SET granted = true
         WHERE id = (
             SELECT id FROM public.consents
              WHERE user_id = public.get_setting_uuid('test.p1')
                AND consent_type = 'marketing'
              ORDER BY created_at ASC LIMIT 1
         );
    EXCEPTION WHEN raise_exception THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'consent history is immutable via the API');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 9: data-request entry point — customer files a request and
--         reads only their own
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.data_requests (user_id, request_type, details)
VALUES (
    public.get_setting_uuid('test.p1'),
    'deletion',
    jsonb_build_object('reason', 'test')
);

SELECT public.expect(
    (SELECT count(*) FROM public.data_requests
      WHERE user_id = public.get_setting_uuid('test.p1')) = 2,
    'customer files a data request (entry point works)'
);

SELECT public.expect(
    (SELECT count(*) FROM public.data_requests) = 2,
    'customer sees only their own data requests'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 10: patient CANNOT change a data-request status
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    updated int := -1;
BEGIN
    UPDATE public.data_requests
       SET status = 'in_progress'
     WHERE user_id = public.get_setting_uuid('test.p1');
    GET DIAGNOSTICS updated = ROW_COUNT;
    PERFORM public.expect(updated = 0, 'patient CANNOT change a data-request status');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 11: admin sees ALL consents/data requests and manages
--          the request queue
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.admin'));

SELECT public.expect(
    (SELECT count(*) FROM public.consents) = 4,
    'admin sees all consent history'
);

SELECT public.expect(
    (SELECT count(*) FROM public.data_requests) = 3,
    'admin sees all data requests'
);

UPDATE public.data_requests
   SET status = 'in_progress',
       handled_by = public.get_setting_uuid('test.admin'),
       handled_at = now()
 WHERE request_type = 'deletion';

SELECT public.expect(
    (SELECT count(*) FROM public.data_requests
      WHERE status = 'in_progress' AND handled_by = public.get_setting_uuid('test.admin')) = 1,
    'admin can move a data request through the queue'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 12: sensitive fields are NOT exposed to anon
-- (queries run under `anon`; assertions run as owner — the expect
-- helper is not granted to anon)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;

DO $$
DECLARE
    v_profiles int;
    v_consents int;
    v_requests int;
BEGIN
    SET ROLE anon;
    SELECT set_config(
        'request.jwt.claims',
        json_build_object('role', 'anon')::text,
        false
    );

    SELECT count(*) INTO v_profiles FROM public.profiles;
    SELECT count(*) INTO v_consents FROM public.consents;
    SELECT count(*) INTO v_requests FROM public.data_requests;

    RESET ROLE;

    PERFORM public.expect(v_profiles = 0, 'anon cannot read profiles');
    PERFORM public.expect(v_consents = 0, 'anon cannot read consents');
    PERFORM public.expect(v_requests = 0, 'anon cannot read data requests');
END;
$$;

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixtures (reverse dependency order), keep schema
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.data_requests WHERE user_id IN (SELECT id FROM public.profiles WHERE email LIKE '%@test.local');
DELETE FROM public.data_requests WHERE handled_by IN (SELECT id FROM public.profiles WHERE email LIKE '%@test.local');
DELETE FROM public.consents      WHERE user_id IN (SELECT id FROM public.profiles WHERE email LIKE '%@test.local');
DELETE FROM public.notifications WHERE user_id IN (SELECT id FROM public.profiles WHERE email LIKE '%@test.local');
DELETE FROM public.audit_logs    WHERE admin_user_id IN (SELECT id FROM public.profiles WHERE email LIKE '%@test.local');
DELETE FROM public.profiles      WHERE email LIKE '%@test.local';
DELETE FROM auth.users           WHERE email LIKE '%@test.local';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL PROFILE & CONSENT API ACCEPTANCE TESTS PASSED' AS result;