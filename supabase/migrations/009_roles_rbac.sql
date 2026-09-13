-- ============================================================
-- The Perfect Look — T18: Roles, invitations & branch-scoped RBAC
-- ============================================================
-- Migration: 009_roles_rbac.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             003_seed_data.sql (T4),
--             004_branches_client_number_pricing.sql (T37),
--             005_seed_demo_branches.sql (T37),
--             006_availability_engine.sql (T12),
--             007_branch_providers.sql (T13),
--             008_appointment_booking_api.sql (T14)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T18; SRS v1 §3/§17
--
-- T37 seeded branch-scoped RLS on a minimal viewer/manager grant.
-- T18 extends it into the full 8-value staff role model:
--
-- Responsibilities:
--   1. Migrate user_role from the T3 3-value enum
--      (patient/staff/admin) to the SRS §3 8-value enum:
--      customer, receptionist, branch_manager, provider,
--      nutritionist, finance, administrator, super_admin.
--      Legacy mapping: patient → customer, admin → administrator,
--      staff → provider (then refined by staff title:
--      %nutrition% → nutritionist, %reception% → receptionist).
--   2. Redeclare the T3 helpers against the new enum
--      (is_admin, is_staff_or_admin) — every existing RLS policy
--      that references them inherits the new semantics.
--   3. Harden role assignment:
--      - handle_new_user() never trusts metadata role for public
--        sign-ups. Role from metadata is honoured ONLY while the
--        session sets app.rbac_role_change_authorized ('seed',
--        'accept_invitation', 'admin_set_user_role', tests).
--      - prevent_self_role_change() becomes the single role-change
--        guard: any role mutation requires the same flag.
--      - super_admin can only be granted by a super_admin.
--   4. Staff invitation flow (SRS §3/§17):
--      - invite_staff() by admins / branch managers (own branches),
--      - accept_invitation() applies the invited role, creates the
--        staff row, staff_branches assignments and branch_access
--        grants (manager for branch_manager invites, viewer otherwise),
--      - revoke_invitation() / list_invitations(),
--      - admin_set_user_role() for direct role changes.
--   5. Role-scoped capability helpers consumed by the frontend and
--      future modules (payments T21, nutrition T22, provider
--      schedule T20): current_role, current_staff_id,
--      current_user_branch_ids, is_provider, can_access_payments,
--      can_access_nutrition, ensure_admin, ensure_staff,
--      ensure_branch_access.
--   6. audit_logs: keep admin-role reads, allow authenticated
--      staff to log their own admin actions (admin_user_id = uid).
--   7. search_clients()/set_client_number()/backfills follow the
--      renamed 'customer' role.
--
-- Apply once via Supabase CLI. Not idempotent by design — the enum
-- swap is apply-once DDL; 005-style guards do not apply here.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 0. SESSION FLAG — this migration is an authorized role pathway:
--    every role mutation inside runs under it. (Migrations run as
--    the DB owner; the guard trigger below still fires, so the flag
--    must be visible for the whole file.)
-- ─────────────────────────────────────────────────────────────

SELECT set_config('app.rbac_role_change_authorized', 'true', false);

-- ─────────────────────────────────────────────────────────────
-- 1. ENUM SWAP — user_role 3 values → 8 (SRS §3)
-- ─────────────────────────────────────────────────────────────

CREATE TYPE public.user_role_new AS ENUM (
    'customer',
    'receptionist',
    'branch_manager',
    'provider',
    'nutritionist',
    'finance',
    'administrator',
    'super_admin'
);

-- Drop the default BEFORE the type swap (the old enum cannot be cast).
ALTER TABLE public.profiles
    ALTER COLUMN role DROP DEFAULT;

-- Value-preserving inline swap (value-mapping UPDATEs BEFORE the type
-- swap would reference enum labels that no longer exist, so the
-- mapping lives in the USING CASE).
ALTER TABLE public.profiles
    ALTER COLUMN role TYPE public.user_role_new
    USING (
        CASE role::text
            WHEN 'patient' THEN 'customer'::public.user_role_new
            WHEN 'admin'   THEN 'administrator'::public.user_role_new
            ELSE 'provider'::public.user_role_new  -- legacy 'staff'
        END
    );

DROP TYPE public.user_role;

ALTER TYPE public.user_role_new RENAME TO user_role;

ALTER TABLE public.profiles
    ALTER COLUMN role SET DEFAULT 'customer';

-- Refine generic 'provider' staff into role-specific values using the
-- staff title (SRS §3: nutritionist, receptionist). Guarded by the
-- session flag set at the top of this file.
UPDATE public.profiles p
SET role = CASE
        WHEN lower(COALESCE(st.title, '')) LIKE '%nutrition%' THEN 'nutritionist'::public.user_role
        WHEN lower(COALESCE(st.title, '')) LIKE '%reception%' THEN 'receptionist'::public.user_role
        ELSE p.role
    END
FROM public.staff st
WHERE st.profile_id = p.id
  AND p.role = 'provider';

-- ─────────────────────────────────────────────────────────────
-- 2. ROLE-SCOPED CAPABILITY HELPERS (SRS §3/§17)
--    SECURITY DEFINER to avoid RLS recursion; auth.uid() still
--    resolves from the caller's JWT inside SECURITY DEFINER.
-- ─────────────────────────────────────────────────────────────

-- Current user's user_role value (NULL for anon / no profile).
CREATE OR REPLACE FUNCTION public.current_role()
RETURNS public.user_role
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

-- Staff row of the current user (NULL when not a staff member).
CREATE OR REPLACE FUNCTION public.current_staff_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT id FROM public.staff WHERE profile_id = auth.uid() LIMIT 1;
$$;

-- Branch ids the current user can access (via branch_access grants;
-- admins bypass and see all). Used by invitations and future
-- branch-scoped modules (T19/T20/T21/T22).
CREATE OR REPLACE FUNCTION public.current_user_branch_ids()
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT COALESCE(array_agg(branch_id), '{}')
    FROM public.branch_access
    WHERE profile_id = auth.uid() AND active;
$$;

-- ---- role predicates (all SECURITY DEFINER, stable) ----
CREATE OR REPLACE FUNCTION public.is_customer()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'customer') $$;

CREATE OR REPLACE FUNCTION public.is_receptionist()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'receptionist') $$;

CREATE OR REPLACE FUNCTION public.is_branch_manager()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'branch_manager') $$;

CREATE OR REPLACE FUNCTION public.is_provider()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'provider') $$;

CREATE OR REPLACE FUNCTION public.is_nutritionist()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'nutritionist') $$;

CREATE OR REPLACE FUNCTION public.is_finance()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'finance') $$;

CREATE OR REPLACE FUNCTION public.is_administrator()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'administrator') $$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$ SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'super_admin') $$;

-- Any non-customer staff role (receptionist .. finance).
CREATE OR REPLACE FUNCTION public.is_staff_role()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role IN ('receptionist', 'branch_manager', 'provider',
                       'nutritionist', 'finance')
    );
$$;

-- ─────────────────────────────────────────────────────────────
-- 3. REDECLARE THE T3 HELPERS AGAINST THE NEW ENUM
--    Every existing RLS policy calls these — they inherit the new
--    role semantics without any policy rewrite.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('administrator', 'super_admin')
    );
$$;

CREATE OR REPLACE FUNCTION public.is_staff_or_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid()
          AND role IN ('receptionist', 'branch_manager', 'provider',
                       'nutritionist', 'finance', 'administrator',
                       'super_admin')
    );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_staff_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff_or_admin() TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4. HARDEN ROLE ASSIGNMENT (SRS §17)
-- ─────────────────────────────────────────────────────────────

-- handle_new_user(): public sign-ups ALWAYS become 'customer'.
-- A metadata role is honoured only when the session is explicitly
-- authorized (seed, accept_invitation handled elsewhere, tests) —
-- otherwise a self-registration could self-assign 'administrator'.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role      public.user_role := 'customer';
    v_meta_role text;
BEGIN
    IF NEW.raw_user_meta_data ->> 'mobile_number' IS NULL
       OR trim(NEW.raw_user_meta_data ->> 'mobile_number') = '' THEN
        RAISE EXCEPTION 'Mobile number is required for registration';
    END IF;

    IF current_setting('app.rbac_role_change_authorized', true) = 'true' THEN
        v_meta_role := lower(trim(NEW.raw_user_meta_data ->> 'role'));
        IF v_meta_role IN (
            'customer', 'receptionist', 'branch_manager', 'provider',
            'nutritionist', 'finance', 'administrator', 'super_admin'
        ) THEN
            v_role := v_meta_role::public.user_role;
        ELSE
            v_role := 'customer';
        END IF;
    END IF;

    INSERT INTO public.profiles (id, full_name, mobile_number, email, role)
    VALUES (
        NEW.id,
        COALESCE(trim(NEW.raw_user_meta_data ->> 'full_name'), ''),
        NEW.raw_user_meta_data ->> 'mobile_number',
        lower(NEW.email),
        v_role
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name     = EXCLUDED.full_name,
        mobile_number = EXCLUDED.mobile_number,
        email         = EXCLUDED.email;
    RETURN NEW;
END;
$$;

-- Single role-change guard. Replaces the T3 self-escalation guard:
--   * role unchanged                       → allowed
--   * role changed + session authorized    → allowed (super_admin
--     grant still requires a super_admin caller)
--   * role changed + NOT authorized        → blocked (self or not)
CREATE OR REPLACE FUNCTION public.prevent_self_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF current_setting('app.rbac_role_change_authorized', true) = 'true' THEN
            IF NEW.role = 'super_admin' AND NOT public.is_super_admin() THEN
                RAISE EXCEPTION 'Only a super administrator can grant the super admin role';
            END IF;
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'Role change not authorized';
    END IF;
    RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 5. FIX LEGACY 'patient' REFERENCES (runtime code only — the
--    old role literal no longer exists after the enum swap)
-- ─────────────────────────────────────────────────────────────

-- set_client_number(): assign a number only to customers.
CREATE OR REPLACE FUNCTION public.set_client_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.client_number IS NULL AND NEW.role = 'customer' THEN
        NEW.client_number := public.generate_client_number();
    END IF;
    RETURN NEW;
END;
$$;

-- search_clients(): staff search is scoped to customers (SRS §5.3).
CREATE OR REPLACE FUNCTION public.search_clients(p_query text)
RETURNS TABLE (
    client_number text,
    full_name     text,
    email         text,
    mobile_number text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT p.client_number, p.full_name, p.email, p.mobile_number
    FROM public.profiles p
    WHERE p.role = 'customer'
      AND public.is_staff_or_admin()
      AND (
          p.client_number ILIKE '%' || p_query || '%'
          OR p.full_name ILIKE '%' || p_query || '%'
          OR p.email ILIKE '%' || p_query || '%'
          OR p.mobile_number ILIKE '%' || p_query || '%'
      )
    ORDER BY p.client_number
    LIMIT 50;
$$;

-- ─────────────────────────────────────────────────────────────
-- 6. MODULE GATES (T18 acceptance: role-scoped data access)
--    Payments (T21) and nutrition (T22) modules rely on these;
--    they are defined now so no client-side trust is needed later.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.can_access_payments()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT public.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role = 'finance'
        );
$$;

CREATE OR REPLACE FUNCTION public.can_access_nutrition()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT public.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid() AND role IN ('nutritionist', 'provider')
        );
$$;

CREATE OR REPLACE FUNCTION public.is_booking_staff()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT public.is_staff_role() OR public.is_admin();
$$;

-- ─────────────────────────────────────────────────────────────
-- 7. ENFORCED GUARDS (raise 42501 → PostgREST FORBIDDEN)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ensure_admin()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Administrator role required'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_staff()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_staff_or_admin() THEN
        RAISE EXCEPTION 'Staff or administrator role required'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_branch_access(p_branch_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    IF NOT public.can_access_branch(p_branch_id) THEN
        RAISE EXCEPTION 'No access to this branch'
            USING ERRCODE = '42501';
    END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- 8. AUDIT LOG (SRS §17) + RLS
-- ─────────────────────────────────────────────────────────────

-- Programmatic audit writer used by the invitation RPCs. SECURITY
-- DEFINER as the owner bypasses RLS; auth.uid() is preserved from
-- the caller's JWT.
CREATE OR REPLACE FUNCTION public.log_audit(
    p_action     text,
    p_entity     text,
    p_entity_id  uuid,
    p_details    jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.audit_logs (admin_user_id, action, entity, entity_id, details)
    VALUES (auth.uid(), p_action, p_entity, p_entity_id, COALESCE(p_details, '{}'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.log_audit(text, text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_audit(text, text, uuid, jsonb) TO authenticated;

-- audit_logs: reads stay admin-only (T3). Inserts follow the
-- self-audit model — authenticated staff log their own actions.
-- The frontend writeAuditLog() includes admin_user_id = the current
-- user so this policy accepts it.
DROP POLICY IF EXISTS audit_logs_insert_admin ON public.audit_logs;

CREATE POLICY audit_logs_insert_self
    ON public.audit_logs FOR INSERT
    WITH CHECK (
        admin_user_id = auth.uid()
        AND public.is_staff_or_admin()
    );

-- ─────────────────────────────────────────────────────────────
-- 9. STAFF INVITATIONS (SRS §3/§17)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE public.staff_invitations (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inviter_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    email         TEXT NOT NULL,
    full_name     TEXT NOT NULL,
    mobile_number TEXT NOT NULL,
    role          public.user_role NOT NULL CHECK (
        role IN ('receptionist', 'branch_manager', 'provider',
                 'nutritionist', 'finance')
    ),
    title         TEXT,
    branch_ids    UUID[] NOT NULL,
    code          TEXT NOT NULL UNIQUE,
    expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '72 hours',
    accepted      BOOLEAN NOT NULL DEFAULT false,
    accepted_at   TIMESTAMPTZ,
    accepted_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    revoked       BOOLEAN NOT NULL DEFAULT false,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.staff_invitations IS 'Pending staff invitations (T18). One open invite per email.';

-- One OPEN invitation per email (a revoked/accepted invite no longer
-- blocks a fresh one for the same address).
CREATE UNIQUE INDEX idx_staff_invitations_open_email
    ON public.staff_invitations (email)
    WHERE NOT revoked AND NOT accepted;

CREATE INDEX idx_staff_invitations_inviter ON public.staff_invitations (inviter_id);
CREATE INDEX idx_staff_invitations_code    ON public.staff_invitations (code);

ALTER TABLE public.staff_invitations ENABLE ROW LEVEL SECURITY;

-- Inviters see their invites; admins see everything. Writes are
-- managed exclusively through the SECURITY DEFINER RPCs below.
CREATE POLICY staff_invitations_select
    ON public.staff_invitations FOR SELECT
    USING (inviter_id = auth.uid() OR public.is_admin());

-- ─────────────────────────────────────────────────────────────
-- 10. INVITATION RPCs
-- ─────────────────────────────────────────────────────────────

-- Create an invitation. Admins may invite for any branch; branch
-- managers only for branches they can manage. Rejects existing
-- accounts and non-staff target roles.
CREATE OR REPLACE FUNCTION public.invite_staff(
    p_email       text,
    p_full_name   text,
    p_mobile      text,
    p_role        public.user_role,
    p_branch_ids  uuid[],
    p_title       text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inviter_id uuid := auth.uid();
    v_code       text;
    v_id         uuid;
    v_branch_id  uuid;
BEGIN
    IF v_inviter_id IS NULL THEN
        RAISE EXCEPTION 'Sign in to invite staff' USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_admin() THEN
        IF NOT public.is_branch_manager() THEN
            RAISE EXCEPTION 'Only administrators or branch managers can invite staff'
                USING ERRCODE = '42501';
        END IF;
        -- branch manager: every target branch must be manageable
        FOREACH v_branch_id IN ARRAY p_branch_ids LOOP
            IF NOT public.can_manage_branch(v_branch_id) THEN
                RAISE EXCEPTION 'Cannot invite for a branch you do not manage'
                    USING ERRCODE = '42501';
            END IF;
        END LOOP;
    END IF;

    IF p_role::text NOT IN ('receptionist', 'branch_manager', 'provider',
                            'nutritionist', 'finance') THEN
        RAISE EXCEPTION 'Target role is not assignable by invitation';
    END IF;

    IF array_length(p_branch_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'At least one branch is required';
    END IF;

    -- Branch ids must all exist.
    IF EXISTS (
        SELECT 1
        FROM unnest(p_branch_ids) AS b(id)
        LEFT JOIN public.branches br ON br.id = b.id
        WHERE br.id IS NULL
    ) THEN
        RAISE EXCEPTION 'One or more branches do not exist';
    END IF;

    IF EXISTS (
        SELECT 1 FROM auth.users WHERE lower(email) = lower(btrim(p_email))
    ) THEN
        RAISE EXCEPTION 'An account with this email already exists';
    END IF;

    v_code := encode(gen_random_bytes(8), 'hex');

    INSERT INTO public.staff_invitations (
        inviter_id, email, full_name, mobile_number, role, title,
        branch_ids, code
    )
    VALUES (
        v_inviter_id, lower(btrim(p_email)), btrim(p_full_name),
        btrim(p_mobile), p_role, p_title, p_branch_ids, v_code
    )
    RETURNING id INTO v_id;

    PERFORM public.log_audit(
        'staff.invite',
        'staff_invitations',
        v_id,
        jsonb_build_object(
            'email',    lower(btrim(p_email)),
            'role',     p_role::text,
            'branches', p_branch_ids
        )
    );

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.invite_staff(text, text, text, public.user_role, uuid[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_staff(text, text, text, public.user_role, uuid[], text) TO authenticated;

-- List pending invitations visible to the caller (inviter or admin).
CREATE OR REPLACE FUNCTION public.list_invitations()
RETURNS SETOF public.staff_invitations
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT si.*
    FROM public.staff_invitations si
    WHERE public.is_admin() OR si.inviter_id = auth.uid()
    ORDER BY si.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.list_invitations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_invitations() TO authenticated;

-- Revoke a pending invitation (inviter or admin).
CREATE OR REPLACE FUNCTION public.revoke_invitation(p_invitation_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv public.staff_invitations%ROWTYPE;
BEGIN
    SELECT * INTO v_inv
    FROM public.staff_invitations si
    WHERE si.id = p_invitation_id
      AND NOT si.revoked
      AND NOT si.accepted;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invitation not found or already closed';
    END IF;

    IF NOT public.is_admin() AND v_inv.inviter_id <> auth.uid() THEN
        RAISE EXCEPTION 'Only the inviter or an administrator can revoke this invitation'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.staff_invitations
    SET revoked = true
    WHERE id = p_invitation_id;

    PERFORM public.log_audit(
        'staff.invitation.revoke',
        'staff_invitations',
        p_invitation_id,
        jsonb_build_object('email', v_inv.email)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_invitation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_invitation(uuid) TO authenticated;

-- Complete an invitation once the invited person has an account.
-- Callable by the invitee themselves (auth.uid() = p_user_id) or by
-- an administrator. Applies the invited role (under the RBAC flag),
-- creates/updates the staff row, staff_branches assignments and
-- branch_access grants, then closes the invitation.
CREATE OR REPLACE FUNCTION public.accept_invitation(
    p_code     text,
    p_user_id  uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv       public.staff_invitations%ROWTYPE;
    v_staff_id  uuid;
    v_branch_id uuid;
    v_first     boolean := true;
BEGIN
    SELECT * INTO v_inv
    FROM public.staff_invitations si
    WHERE si.code = p_code
      AND NOT si.revoked
      AND NOT si.accepted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invitation not found or already used';
    END IF;
    IF v_inv.expires_at < now() THEN
        RAISE EXCEPTION 'Invitation has expired';
    END IF;

    IF NOT (public.is_admin() OR auth.uid() = p_user_id) THEN
        RAISE EXCEPTION 'Not authorized to accept this invitation'
            USING ERRCODE = '42501';
    END IF;

    -- The target account must carry the invited email.
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = p_user_id AND lower(email) = lower(v_inv.email)
    ) THEN
        RAISE EXCEPTION 'Invitation email does not match the target account';
    END IF;

    -- Authorized role mutation.
    PERFORM set_config('app.rbac_role_change_authorized', 'true', true);
    UPDATE public.profiles SET role = v_inv.role WHERE id = p_user_id;
    PERFORM set_config('app.rbac_role_change_authorized', 'false', true);

    -- Staff row (idempotent: an existing provider row is reused).
    INSERT INTO public.staff (profile_id, title)
    VALUES (p_user_id, v_inv.title)
    ON CONFLICT (profile_id) DO UPDATE
        SET title = COALESCE(EXCLUDED.title, public.staff.title)
    RETURNING id INTO v_staff_id;

    -- Branch assignments + grants drive the T37 branch-scoped RLS.
    FOREACH v_branch_id IN ARRAY v_inv.branch_ids LOOP
        INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active)
        VALUES (v_staff_id, v_branch_id, v_first, true)
        ON CONFLICT (staff_id, branch_id) DO NOTHING;

        INSERT INTO public.branch_access (profile_id, branch_id, role, active)
        VALUES (
            p_user_id,
            v_branch_id,
            CASE WHEN v_inv.role = 'branch_manager'
                 THEN 'manager'::public.branch_access_role
                 ELSE 'viewer'::public.branch_access_role
            END,
            true
        )
        ON CONFLICT (profile_id, branch_id) DO UPDATE
            SET role = EXCLUDED.role, active = true;
        v_first := false;
    END LOOP;

    UPDATE public.staff_invitations
    SET accepted    = true,
        accepted_at = now(),
        accepted_by = auth.uid()
    WHERE id = v_inv.id;

    PERFORM public.log_audit(
        'staff.accept_invitation',
        'staff',
        v_staff_id,
        jsonb_build_object(
            'email',    v_inv.email,
            'role',     v_inv.role::text,
            'branches', v_inv.branch_ids
        )
    );

    RETURN v_staff_id;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_invitation(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invitation(text, uuid) TO authenticated;

-- Direct role assignment for admins (e.g. promotions). Uses the same
-- RBAC flag so every role mutation passes the guard. super_admin can
-- only be granted by a super_admin.
CREATE OR REPLACE FUNCTION public.admin_set_user_role(
    p_user_id uuid,
    p_role    public.user_role
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Administrator role required' USING ERRCODE = '42501';
    END IF;
    IF p_role = 'super_admin' AND NOT public.is_super_admin() THEN
        RAISE EXCEPTION 'Only a super administrator can grant the super admin role';
    END IF;

    PERFORM set_config('app.rbac_role_change_authorized', 'true', true);
    UPDATE public.profiles SET role = p_role WHERE id = p_user_id;
    PERFORM set_config('app.rbac_role_change_authorized', 'false', true);

    PERFORM public.log_audit(
        'staff.role_change',
        'profiles',
        p_user_id,
        jsonb_build_object('role', p_role::text)
    );

    RETURN p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, public.user_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, public.user_role) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 11. GRANTS — role helpers for the frontend
-- ─────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.current_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_staff_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.current_user_branch_ids() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_customer() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_receptionist() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_branch_manager() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_provider() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_nutritionist() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_finance() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_administrator() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_staff_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_access_payments() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_access_nutrition() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_booking_staff() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_staff() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_branch_access(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.current_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_staff_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_branch_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_customer() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_receptionist() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_branch_manager() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_provider() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_nutritionist() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_finance() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_administrator() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_payments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_nutrition() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_booking_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_branch_access(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 12. DROP THE SESSION FLAG
-- ─────────────────────────────────────────────────────────────

RESET app.rbac_role_change_authorized;