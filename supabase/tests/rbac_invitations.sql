-- ============================================================
-- The Perfect Look — T18 acceptance test: Roles, invitations &
-- branch-scoped RBAC
-- ============================================================
-- Verifies the T18 acceptance criteria on top of main's T37
-- (branch_access grants / can_access_branch) and T3/T5 auth:
--
--   AC1  Public sign-ups ALWAYS become 'customer' — a metadata role
--        is never trusted (no self-escalation via sign-up).
--   AC2  No one can change their own (or anyone else's) role without
--        an authorized pathway (guard trigger).
--   AC3  Invitation flow: admin invites a receptionist; the invitee
--        accepts; gets the receptionist role + staff row +
--        staff_branches assignment + branch_access grant, and a
--        customer still cannot, but is blocked from inviting others.
--   AC4  Branch-scoped RBAC: staff see only their granted branch's
--        appointments (never another branch).
--   AC5  Role-scoped gates: finance → can_access_payments, provider →
--        can_access_nutrition false for finance, super_admin only by
--        a super_admin, branch_manager invites get 'manager' grants.
--   AC6  Audit trail: role changes + invitations are logged; audit
--        rows are readable by admins only.
--
-- Requires migrations 001–009 applied. Run against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rbac_invitations.sql
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

-- Create a fixture auth user (profiles row via the trigger).
CREATE OR REPLACE FUNCTION public.make_user(p_email text, p_mobile text,
                                            p_full_name text, p_role text,
                                            p_flag boolean)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid uuid := gen_random_uuid();
BEGIN
    PERFORM set_config('app.rbac_role_change_authorized', p_flag::text, false);
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', v_uid,
        'authenticated', 'authenticated', lower(btrim(p_email)),
        crypt('Password123!', gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}',
        jsonb_build_object('role', p_role, 'full_name', p_full_name, 'mobile_number', btrim(p_mobile)),
        now(), now()
    );
    PERFORM set_config('app.rbac_role_change_authorized', 'false', false);
    RETURN v_uid;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FIXTURES (as table owner — RLS bypassed)
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    svc uuid;
    dxb uuid;
    auh uuid;
BEGIN
    SELECT id INTO dxb FROM public.branches WHERE slug = 'dubai';
    SELECT id INTO auh FROM public.branches WHERE slug = 'abu-dhabi';

    -- Signups (flag OFF = realistic public registration) → customer.
    PERFORM public.make_user('rbac.cust1@test.local', '+971500000401', 'Rbac Cust1', 'customer', false);
    PERFORM public.make_user('rbac.cust2@test.local', '+971500000402', 'Rbac Cust2', 'customer', false);

    -- Admin bootstrap via the sanctioned pathway (flag ON).
    PERFORM public.make_user('rbac.admin@test.local', '+971500000403', 'Rbac Admin', 'administrator', true);

    INSERT INTO public.services (name, duration_minutes, price, currency, sort_order)
    VALUES ('RBAC Test Service', 30, 100.00, 'AED', 930)
    RETURNING id INTO svc;

    INSERT INTO public.service_branches (service_id, branch_id, available, currency)
    VALUES (svc, dxb, true, 'AED'), (svc, auh, true, 'AED');

    -- One appointment in each branch for the scope probes.
    INSERT INTO public.appointments (
        patient_id, service_id, branch_id, client_number,
        service_name_snapshot, price_snapshot, currency_snapshot,
        scheduled_start, scheduled_end
    )
    SELECT p.id, svc, dxb, p.client_number, 'RBAC Test Service', 100.00, 'AED',
           '2026-11-02 10:00:00+00', '2026-11-02 10:30:00+00'
    FROM public.profiles p WHERE p.email = 'rbac.cust1@test.local';

    INSERT INTO public.appointments (
        patient_id, service_id, branch_id, client_number,
        service_name_snapshot, price_snapshot, currency_snapshot,
        scheduled_start, scheduled_end
    )
    SELECT p.id, svc, auh, p.client_number, 'RBAC Test Service', 100.00, 'AED',
           '2026-11-02 14:00:00+00', '2026-11-02 14:30:00+00'
    FROM public.profiles p WHERE p.email = 'rbac.cust2@test.local';

    PERFORM set_config('test.admin', (SELECT id::text FROM public.profiles WHERE email = 'rbac.admin@test.local'), false);
    PERFORM set_config('test.cust1', (SELECT id::text FROM public.profiles WHERE email = 'rbac.cust1@test.local'), false);
    PERFORM set_config('test.dxb', dxb::text, false);
    PERFORM set_config('test.auh', auh::text, false);
    PERFORM set_config('test.svc', svc::text, false);

    RAISE NOTICE 'T18 fixtures ready';
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 1 (AC1): public sign-ups cannot self-assign a role — a
-- metadata 'administrator' without the flag becomes 'customer'.
-- ─────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_id uuid;
BEGIN
    v_id := public.make_user('rbac.sneaky@test.local', '+971500000404', 'Sneaky', 'administrator', false);
    PERFORM public.expect(
        (SELECT role FROM public.profiles WHERE id = v_id) = 'customer',
        'metadata role is ignored without the RBAC flag → customer (no self-escalation)'
    );
    DELETE FROM public.profiles WHERE id = v_id;
    DELETE FROM auth.users     WHERE id = v_id;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 2 (AC2): nobody can change roles without an authorized
-- pathway — the guard trigger blocks the attempt.
-- ─────────────────────────────────────────────────────────────

RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.cust1'));

DO $$
DECLARE
    blocked boolean := false;
BEGIN
    BEGIN
        UPDATE public.profiles SET role = 'administrator'
        WHERE id = public.get_setting_uuid('test.cust1');
    EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'role self-escalation attempt is blocked by the guard');
END;
$$;

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- TEST 3 (AC3): invitation flow — invite → signup → accept
-- ─────────────────────────────────────────────────────────────

-- 3a. Admin invites a receptionist for Dubai.
RESET ROLE;
SELECT public.act_as(public.get_setting_uuid('test.admin'));

DO $$
DECLARE
    v_inv_id uuid;
BEGIN
    SELECT public.invite_staff(
        'rbac.rec@test.local', 'Rbac Receptionist', '+971500000405',
        'receptionist', ARRAY[public.get_setting_uuid('test.dxb')]
    ) INTO v_inv_id;

    PERFORM public.expect(
        v_inv_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.staff_invitations si
            WHERE si.id = v_inv_id
              AND si.role = 'receptionist'
              AND NOT si.accepted AND NOT si.revoked
              AND si.expires_at > now()
        ),
        'admin can create a receptionist invitation for Dubai'
    );
    PERFORM set_config('test.inv_rec', v_inv_id::text, false);
END;
$$;

-- 3b. Invitee signs up as a normal customer (flag OFF)…
DO $$
DECLARE
    v_id uuid;
    v_code text;
BEGIN
    v_id := public.make_user('rbac.rec@test.local', '+971500000405', 'Rbac Receptionist', 'customer', false);
    SELECT code INTO v_code FROM public.staff_invitations WHERE email = 'rbac.rec@test.local';
    PERFORM set_config('test.inv_code', v_code, false);

    -- …and accepts the invitation themselves.
    RESET ROLE;
    SELECT public.act_as(v_id);
    PERFORM public.accept_invitation(v_code, v_id);

    PERFORM public.expect(
        (SELECT role FROM public.profiles WHERE id = v_id) = 'receptionist',
        'accepted invitation applies the receptionist role'
    );
    PERFORM public.expect(public.is_receptionist(),
        'current_role(): accepted invitee is a receptionist');
    PERFORM public.expect(public.current_staff_id() IS NOT NULL,
        'accept_invitation created a staff row');
    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.staff s
            JOIN public.staff_branches sb ON sb.staff_id = s.id
            WHERE s.profile_id = v_id AND sb.branch_id = public.get_setting_uuid('test.dxb')
        )
        AND EXISTS (
            SELECT 1 FROM public.branch_access ba
            WHERE ba.profile_id = v_id AND ba.branch_id = public.get_setting_uuid('test.dxb')
              AND ba.active AND ba.role = 'viewer'
        ),
        'accept_invitation assigns staff_branches + branch_access (viewer)'
    );

    RESET ROLE;
END;
$$;

-- 3c. The receptionist is branch-scoped to Dubai (AC4) and cannot
--     invite others (she is not a branch manager / admin).
RESET ROLE;
SELECT public.act_as((SELECT id FROM public.profiles WHERE email = 'rbac.rec@test.local'));

SELECT public.expect(
    (SELECT count(*) FROM public.appointments) = 1
    AND (SELECT count(*) FROM public.appointments)
      = (SELECT count(*) FROM public.appointments
          WHERE branch_id = public.get_setting_uuid('test.dxb')),
    'receptionist sees ONLY her Dubai branch appointment (branch-scoped RBAC)'
);

DO $$
DECLARE
    blocked boolean := false;
BEGIN
    BEGIN
        PERFORM public.invite_staff(
            'rbac.other@test.local', 'Other', '+971500000406',
            'receptionist', ARRAY[public.get_setting_uuid('test.dxb')]
        );
    EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'a plain receptionist CANNOT invite staff (admin/branch-manager only)');
END;
$$;

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- TEST 4 (AC5a): branch_manager invites land as 'manager' grants
-- ─────────────────────────────────────────────────────────────

SELECT public.act_as(public.get_setting_uuid('test.admin'));

DO $$
DECLARE
    v_inv_id uuid;
    v_bm_id  uuid;
    v_code   text;
BEGIN
    SELECT public.invite_staff(
        'rbac.bm@test.local', 'Rbac Branch Manager', '+971500000407',
        'branch_manager', ARRAY[public.get_setting_uuid('test.auh')]
    ) INTO v_inv_id;
    PERFORM public.expect(v_inv_id IS NOT NULL, 'admin can create a branch_manager invitation');

    v_bm_id := public.make_user('rbac.bm@test.local', '+971500000407', 'Rbac Branch Manager', 'customer', false);
    SELECT code INTO v_code FROM public.staff_invitations WHERE email = 'rbac.bm@test.local';

    RESET ROLE;
    SELECT public.act_as(v_bm_id);
    PERFORM public.accept_invitation(v_code, v_bm_id);

    PERFORM public.expect(
        (SELECT role FROM public.profiles WHERE id = v_bm_id) = 'branch_manager',
        'accepted branch_manager invitation applies the role'
    );
    PERFORM public.expect(
        EXISTS (
            SELECT 1 FROM public.branch_access ba
            WHERE ba.profile_id = v_bm_id
              AND ba.branch_id = public.get_setting_uuid('test.auh')
              AND ba.role = 'manager' AND ba.active
        )
        AND public.can_manage_branch(public.get_setting_uuid('test.auh')),
        'branch_manager invitation grants a MANAGER branch_access (write scope)'
    );
    PERFORM public.expect(
        NOT public.can_access_branch(public.get_setting_uuid('test.dxb')),
        'branch manager CANNOT access the other branch (Dubai)'
    );

    PERFORM set_config('test.bm', v_bm_id::text, false);
    RESET ROLE;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TEST 5 (AC5b): role-scoped module gates
-- ─────────────────────────────────────────────────────────────

-- 5a. admin promotes a customer to finance (authorized pathway).
SELECT public.act_as(public.get_setting_uuid('test.admin'));

DO $$
DECLARE
    v_fin uuid;
BEGIN
    v_fin := public.make_user('rbac.fin@test.local', '+971500000408', 'Rbac Finance', 'customer', false);
    PERFORM public.admin_set_user_role(v_fin, 'finance');

    RESET ROLE;
    SELECT public.act_as(v_fin);

    PERFORM public.expect(
        (SELECT role FROM public.profiles WHERE id = v_fin) = 'finance'
        AND public.is_finance()
        AND public.can_access_payments()
        AND NOT public.can_access_nutrition(),
        'finance role: can_access_payments true, nutrition gate false'
    );
    PERFORM public.expect(
        (SELECT count(*) FROM public.audit_logs WHERE entity = 'profiles' AND entity_id = v_fin) >= 1,
        'admin_set_user_role writes an audit trail entry'
    );
    RESET ROLE;
    PERFORM set_config('test.fin', v_fin::text, false);
END;
$$;

-- 5b. super_admin grant requires a super_admin caller.
SELECT public.act_as(public.get_setting_uuid('test.admin'));

DO $$
DECLARE
    blocked boolean := false;
BEGIN
    BEGIN
        PERFORM public.admin_set_user_role(public.get_setting_uuid('test.fin'), 'super_admin');
    EXCEPTION WHEN raise_exception THEN
        blocked := true;
    END;
    PERFORM public.expect(blocked, 'a plain administrator CANNOT grant super_admin');
END;
$$;

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- TEST 6 (AC6): audit trail visibility
-- ─────────────────────────────────────────────────────────────

-- Customer: no audit read access.
SELECT public.act_as(public.get_setting_uuid('test.cust1'));
SELECT public.expect(
    (SELECT count(*) FROM public.audit_logs) = 0,
    'customer CANNOT read audit logs'
);

RESET ROLE;

-- Admin: sees the audit entries written by the invitation flow.
SELECT public.act_as(public.get_setting_uuid('test.admin'));
SELECT public.expect(
    (SELECT count(*) FROM public.audit_logs WHERE action IN ('staff.invite', 'staff.accept_invitation')) >= 2
    AND (SELECT count(*) FROM public.audit_logs) >= 3,
    'admin sees the invitation + role-change audit trail'
);

RESET ROLE;

-- ─────────────────────────────────────────────────────────────
-- Cleanup fixture data (reverse dependency order), keep schema
-- ─────────────────────────────────────────────────────────────

DELETE FROM public.branch_access   WHERE profile_id IN (SELECT id FROM profiles WHERE email LIKE 'rbac.%@test.local');
DELETE FROM public.staff_branches  WHERE staff_id IN (SELECT id FROM public.staff s JOIN public.profiles p ON p.id = s.profile_id WHERE p.email LIKE 'rbac.%@test.local');
DELETE FROM public.staff_invitations WHERE inviter_id IN (SELECT id FROM profiles WHERE email LIKE 'rbac.%@test.local')
   OR email IN ('rbac.rec@test.local', 'rbac.bm@test.local');
DELETE FROM public.notifications   WHERE user_id IN (SELECT id FROM profiles WHERE email LIKE 'rbac.%@test.local');
DELETE FROM public.audit_logs      WHERE admin_user_id IN (SELECT id FROM profiles WHERE email LIKE 'rbac.%@test.local');
DELETE FROM public.appointments    WHERE patient_id IN (SELECT id FROM profiles WHERE email LIKE 'rbac.%@test.local');
DELETE FROM public.staff           WHERE profile_id IN (SELECT id FROM profiles WHERE email LIKE 'rbac.%@test.local');
DELETE FROM public.profiles        WHERE email LIKE 'rbac.%@test.local';
DELETE FROM auth.users             WHERE email LIKE 'rbac.%@test.local';
DELETE FROM public.service_branches WHERE service_id = public.get_setting_uuid('test.svc');
DELETE FROM public.services        WHERE name = 'RBAC Test Service';

DROP FUNCTION public.make_user(text, text, text, text, boolean);
DROP FUNCTION public.get_setting_uuid(text);
DROP FUNCTION public.act_as(uuid);
DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL T18 RBAC/INVITATION ACCEPTANCE TESTS PASSED' AS result;