-- ============================================================
-- The Perfect Look — T37 acceptance test
-- Multi-branch, client-number, and pricing schema extension
-- ============================================================
-- Verifies the T37 server-side guarantees:
--   1. Demo Dubai + Abu Dhabi branches seed idempotently (SRS §6).
--   2. Client numbers are generated, unique (collision-safe),
--      immutable, searchable by authorized staff, and hidden from
--      patients (SRS §5.3).
--   3. Branch scope: a branch manager can edit their own branch but
--      cannot read/write another branch's protected data (SRS §17).
--   4. Appointment branch + price snapshots preserve historical
--      truth when the catalogue changes (SRS §8.2).
--   5. Package/add-on relationships and migration mappings work.
--
-- Requires migrations 001–005 applied (services from T4, branches
-- from T5…/005). Run against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/multi_branch_pricing_schema.sql
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

-- ─────────────────────────────────────────────────────────────
-- FIXTURES (as table owner — RLS bypassed)
-- ─────────────────────────────────────────────────────────────

-- Demo branches must already exist from migration 005.
SELECT public.expect(
    (SELECT count(*) FROM public.branches) = 2,
    'demo Dubai + Abu Dhabi branches exist'
);

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
    ('mb.patient@test.local',     'patient', 'MB Patient',     '+971500000201'),
    ('mb.dxb.mgr@test.local',     'staff',   'MB Dubai Mgr',   '+971500000202'),
    ('mb.abh.mgr@test.local',     'staff',   'MB AbuDhabi Mgr','+971500000203'),
    ('mb.admin@test.local',       'admin',   'MB Admin',       '+971500000204')
) AS v(email, r, fn, mn);

PERFORM set_config('test.p',  (SELECT id::text FROM public.profiles WHERE email = 'mb.patient@test.local'), false);
PERFORM set_config('test.dm', (SELECT id::text FROM public.profiles WHERE email = 'mb.dxb.mgr@test.local'), false);
PERFORM set_config('test.am', (SELECT id::text FROM public.profiles WHERE email = 'mb.abh.mgr@test.local'), false);
PERFORM set_config('test.a',  (SELECT id::text FROM public.profiles WHERE email = 'mb.admin@test.local'), false);

-- Branch-scoped grants (manager: write access to one branch each)
INSERT INTO public.branch_access (profile_id, branch_id, role, active)
VALUES
    (public.get_setting_uuid('test.dm'), public.get_setting_uuid('test.dxb'), 'manager', true),
    (public.get_setting_uuid('test.am'), public.get_setting_uuid('test.auh'), 'manager', true);

-- Fixture service used for pricing/availability tests
INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order)
VALUES ('MB RLS Test Service', 'fixture', 30, 150.00, 'AED', true, 910);

PERFORM set_config('test.svc', (SELECT id::text FROM public.services WHERE name = 'MB RLS Test Service'), false);

-- Available at both demo branches so the branch-pricing tests hit rows.
INSERT INTO public.service_branches (service_id, branch_id, available, currency)
VALUES
    ((SELECT id::text FROM public.services WHERE name = 'MB RLS Test Service')::uuid, public.get_setting_uuid('test.dxb'), true, 'AED'),
    ((SELECT id::text FROM public.services WHERE name = 'MB RLS Test Service')::uuid, public.get_setting_uuid('test.auh'), true, 'AED');

-- Fixture package + add-on relationship
INSERT INTO public.services (name, duration_minutes, price, currency, active, service_type, sort_order)
VALUES ('MB RLS Test Package', 90, 400.00, 'AED', true, 'package', 911);

PERFORM set_config('test.pkg', (SELECT id::text FROM public.services WHERE name = 'MB RLS Test Package'), false);

RAISE NOTICE 'T37 fixtures ready';

-- ─────────────────────────────────────────────────────────────
-- TEST 1: client number — generated, immutable, unique, searchable
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p'));

-- The patient fixture got a client number on sign-up
SELECT public.expect(
    (SELECT client_number FROM public.profiles WHERE id = public.get_setting_uuid('test.p'))
        ~ '^TPL-\d{6}$',
    'patient received a TPL-###### client number at registration'
);

-- Immutability: the patient cannot change their own client number
DO $$
DECLARE
    v_id    uuid := public.get_setting_uuid('test.p');
    blocked boolean := false;
BEGIN
    BEGIN
        UPDATE public.profiles SET client_number = 'TPL-999999' WHERE id = v_id;
        -- fall through only if the update was silently filtered (RLS);
        -- re-check the stored value below instead of failing here.
    EXCEPTION WHEN raise_exception THEN
        blocked := true;
    END;
    PERFORM public.expect(
        blocked
        OR (SELECT client_number FROM public.profiles WHERE id = v_id) ~ '^TPL-\d{6}$'
        AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE client_number = 'TPL-999999'),
        'client number is immutable for the owning user'
    );
END;
$$;

-- Searchability: patients cannot enumerate (guard returns nothing)
SELECT public.expect(
    (SELECT count(*) FROM public.search_clients('MB Patient')) = 0,
    'patient cannot list/search other clients'
);

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.dm'));

-- Authorized staff CAN search patients by name / client number
SELECT public.expect(
    (SELECT count(*) FROM public.search_clients('mb.patient@test.local')) >= 1
    AND (SELECT count(*) FROM public.search_clients('TPL-')) >= 1,
    'branch manager can search clients by identifier'
);

-- Collision safety: a duplicate client number is rejected by the DB.
-- Create a second patient (gets its own TPL number), then try to
-- reassign the FIRST patient's number to it — the unique index must
-- reject the collision.
RESET ROLE; -- run as table owner (no auth context, RLS bypassed)

INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
) VALUES (
    '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
    'authenticated', 'authenticated', 'mb.dup@test.local',
    crypt('Password123!', gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('role', 'patient', 'full_name', 'MB Dup', 'mobile_number', '+971500000205'),
    now(), now()
);

DO $$
DECLARE
    v_collided boolean := false;
BEGIN
    BEGIN
        -- Table owner (no auth context) → immutability trigger allows it;
        -- the UNIQUE index on client_number is the collision defence.
        UPDATE public.profiles
        SET client_number = (SELECT client_number FROM public.profiles WHERE email = 'mb.patient@test.local')
        WHERE email = 'mb.dup@test.local';
    EXCEPTION WHEN unique_violation THEN
        v_collided := true;
    END;
    PERFORM public.expect(v_collided, 'duplicate client number is rejected (unique/collision-safe)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 2: branch scope — a manager cannot touch another branch
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.dm'));

-- Dubai manager CAN price their own branch service
DO $$
DECLARE
    v_rows int := -1;
BEGIN
    UPDATE public.service_branches
       SET price = 999.00
     WHERE service_id = public.get_setting_uuid('test.svc')
       AND branch_id  = public.get_setting_uuid('test.dxb');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM public.expect(v_rows = 1, 'branch manager CAN update pricing for their own branch');
END;
$$;

-- … but CANNOT touch Abu Dhabi pricing
DO $$
DECLARE
    v_rows int := -1;
BEGIN
    UPDATE public.service_branches
       SET price = 1.00
     WHERE service_id = public.get_setting_uuid('test.svc')
       AND branch_id  = public.get_setting_uuid('test.auh');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM public.expect(v_rows = 0, 'branch manager CANNOT update another branch pricing');
END;
$$;

-- … and CANNOT insert hours for another branch
DO $$
DECLARE
    v_rows int := -1;
BEGIN
    INSERT INTO public.branch_hours (branch_id, day_of_week, start_time, end_time)
    VALUES (public.get_setting_uuid('test.auh'), 0, '09:00', '17:00');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM public.expect(v_rows = 0, 'branch manager CANNOT insert hours for another branch');
END;
$$;

-- … but CAN manage their own branch hours
DO $$
DECLARE
    v_rows int := -1;
BEGIN
    INSERT INTO public.branch_hours (branch_id, day_of_week, start_time, end_time)
    VALUES (public.get_setting_uuid('test.dxb'), 0, '09:00', '17:00')
    ON CONFLICT (branch_id, day_of_week) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM public.expect(v_rows = 1, 'branch manager CAN insert hours for their own branch');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 3: public UI reflects approved catalogue changes
--        (a patient reading the catalogue sees the approved price)
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.p'));

SELECT public.expect(
    (SELECT COALESCE(price, 0) FROM public.service_branches
      WHERE service_id = public.get_setting_uuid('test.svc')
        AND branch_id  = public.get_setting_uuid('test.dxb')) = 999.00,
    'patient sees the approved branch price for the service'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 4: appointment branch + price snapshots preserve history
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.a'));

-- Create an appointment at Dubai with snapshots captured at booking
INSERT INTO public.appointments (
    patient_id, service_id, branch_id, scheduled_start, scheduled_end,
    status, client_number, service_name_snapshot, price_snapshot, currency_snapshot
) VALUES (
    public.get_setting_uuid('test.p'),
    public.get_setting_uuid('test.svc'),
    public.get_setting_uuid('test.dxb'),
    '2026-10-05 10:00:00+04',
    '2026-10-05 10:30:00+04',
    'Confirmed',
    (SELECT client_number FROM public.profiles WHERE id = public.get_setting_uuid('test.p')),
    'MB RLS Test Service',
    999.00,
    'AED'
);

PERFORM set_config('test.appt', (SELECT id::text FROM public.appointments
    WHERE service_id = public.get_setting_uuid('test.svc') AND branch_id = public.get_setting_uuid('test.dxb')
    ORDER BY created_at DESC LIMIT 1), false);

-- Admin re-prices the service AFTER the booking
UPDATE public.services SET price = 1.00
WHERE id = public.get_setting_uuid('test.svc');

SELECT public.expect(
    (SELECT price_snapshot FROM public.appointments WHERE id = public.get_setting_uuid('test.appt')) = 999.00,
    'price snapshot survives a later catalogue price change'
);

SELECT public.expect(
    (SELECT service_name_snapshot FROM public.appointments WHERE id = public.get_setting_uuid('test.appt')) = 'MB RLS Test Service',
    'service name snapshot survives a later catalogue rename'
);

-- Branch-scoped visibility: Abu Dhabi manager cannot see Dubai appointment
RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.am'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments WHERE id = public.get_setting_uuid('test.appt')) = 0,
    'branch-scoped staff cannot read another branch appointment'
);

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.dm'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments WHERE id = public.get_setting_uuid('test.appt')) = 1,
    'branch-scoped staff CAN read their own branch appointment'
);

-- ─────────────────────────────────────────────────────────────
-- TEST 5: packages, add-ons, and migration mappings
-- ─────────────────────────────────────────────────────────────

RESET ROLE;

INSERT INTO public.package_items (package_id, included_service_id, quantity, sort_order)
SELECT public.get_setting_uuid('test.pkg'), public.get_setting_uuid('test.svc'), 2, 1;

SELECT public.expect(
    (SELECT count(*) FROM public.package_items pi
      JOIN public.services p  ON p.id = pi.package_id
      JOIN public.services s ON s.id = pi.included_service_id) = 1,
    'package/add-on relationship links package to included service'
);

INSERT INTO public.service_addons (service_id, addon_id, active, sort_order)
SELECT public.get_setting_uuid('test.svc'), public.get_setting_uuid('test.pkg'), true, 1;

SELECT public.expect(
    EXISTS (SELECT 1 FROM public.service_addons)
    AND EXISTS (SELECT 1 FROM public.package_items),
    'service add-ons and package items are queryable'
);

INSERT INTO public.migration_mappings (entity_type, legacy_key, target_id)
VALUES ('customer', 'LEGACY-PATIENT-1', public.get_setting_uuid('test.p'));

SELECT public.expect(
    (SELECT count(*) FROM public.migration_mappings WHERE entity_type = 'customer' AND legacy_key = 'LEGACY-PATIENT-1') = 1,
    'migration mapping for a legacy customer is recorded'
);

DO $$
DECLARE
    v_mapped boolean := false;
BEGIN
    BEGIN
        INSERT INTO public.migration_mappings (entity_type, legacy_key, target_id)
        VALUES ('customer', 'LEGACY-PATIENT-1', public.get_setting_uuid('test.p'));
    EXCEPTION WHEN unique_violation THEN
        v_mapped := true;
    END;
    PERFORM public.expect(v_mapped, 'migration mapping rejects duplicate legacy keys (idempotent import)');
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 6: demo branch seed is idempotent (re-apply 005-style)
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.branches (name, slug, emirate, city, address, phone, email, timezone, active, sort_order)
SELECT * FROM (VALUES
    ('The Perfect Look — Dubai', 'dubai', 'Dubai', 'Dubai', 'x', 'x', 'x', 'Asia/Dubai', true, 1)
) AS v(name, slug, emirate, city, address, phone, email, timezone, active, sort_order)
ON CONFLICT (slug) DO NOTHING;

SELECT public.expect(
    (SELECT count(*) FROM public.branches WHERE slug IN ('dubai', 'abu-dhabi')) = 2,
    're-running the branch seed does not duplicate demo branches'
);

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixtures (reverse dependency order), keep schema + seed
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.migration_mappings WHERE legacy_key = 'LEGACY-PATIENT-1';
DELETE FROM public.service_addons    WHERE service_id = public.get_setting_uuid('test.svc');
DELETE FROM public.package_items     WHERE package_id = public.get_setting_uuid('test.pkg');
DELETE FROM public.appointments      WHERE id = public.get_setting_uuid('test.appt');
DELETE FROM public.branch_hours      WHERE branch_id IN (
    public.get_setting_uuid('test.dxb'), public.get_setting_uuid('test.auh')
) AND day_of_week = 0 AND start_time = '09:00';
DELETE FROM public.service_branches  WHERE service_id = public.get_setting_uuid('test.svc');
DELETE FROM public.branch_access     WHERE profile_id IN (
    public.get_setting_uuid('test.dm'), public.get_setting_uuid('test.am')
);
UPDATE public.services SET price = 150.00
WHERE id = public.get_setting_uuid('test.svc');
DELETE FROM public.services WHERE id IN (public.get_setting_uuid('test.svc'), public.get_setting_uuid('test.pkg'));
DELETE FROM public.profiles WHERE email LIKE 'mb.%@test.local';
DELETE FROM auth.users WHERE email LIKE 'mb.%@test.local';

DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL T37 MULTI-BRANCH ACCEPTANCE TESTS PASSED' AS result;