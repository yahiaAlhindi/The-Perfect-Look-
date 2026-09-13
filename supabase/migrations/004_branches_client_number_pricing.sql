-- ============================================================
-- The Perfect Look — T37: Multi-branch, client-number, and
-- pricing schema extension
-- ============================================================
-- Migration: 004_branches_client_number_pricing.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             003_seed_data.sql (T4)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T37; SRS v2 §5.3/§6/§7/§8.2/§15/§16/§17
--
-- Responsibilities:
--   1. Branches: entity + branch hours and branch closures.
--   2. Staff-branch assignments (staff_branches) and branch-scoped
--      access grants (branch_access) that drive branch-scoped RLS.
--   3. Service-branch availability/pricing (service_branches) with
--      per-branch overrides for price, duration, buffers, deposit,
--      and booking rules.
--   4. Catalogue model extensions on services: service_type
--      (service/package/add_on/consultation/membership), buffer_minutes,
--      and an explicit price_on_request flag.
--   5. Package/add-on relationships: package_items, service_addons.
--   6. Immutable, collision-safe client_number on profiles
--      (configurable prefix/width from app_settings).
--   7. Branch + snapshot columns on appointments (branch_id,
--      client_number, service_name_snapshot, price_snapshot,
--      currency_snapshot, package_id, source_channel).
--   8. Migration mappings for the legacy Excel import (T25).
--   9. Branch-scoped RLS policies.
--
-- Backfills and the idempotent demo-branch seed live in 005 so this
-- migration is self-contained DDL. Apply once via Supabase CLI.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────

-- What the services table holds: a single treatment, a bundle of
-- services (package), an add-on, a consultation, or a subscription
-- style offering (SRS §7/§16).
CREATE TYPE public.service_type AS ENUM (
    'service',
    'package',
    'add_on',
    'consultation',
    'membership'
);

-- Minimal branch-scope level for T37 branch-scoped RLS. T18 extends
-- this into the full staff role model (receptionist, branch manager,
-- provider, nutritionist, finance, administrator, …).
CREATE TYPE public.branch_access_role AS ENUM (
    'viewer',
    'manager'
);

-- ─────────────────────────────────────────────────────────────
-- HELPER FUNCTIONS (branch scope) — SECURITY DEFINER to avoid
-- recursion between profiles/branch_access and RLS policies
-- ─────────────────────────────────────────────────────────────

-- Whether the current user can read/browse the given branch's data.
-- Admins always can; everyone else must hold an active grant.
CREATE OR REPLACE FUNCTION public.can_access_branch(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT public.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.branch_access ba
            WHERE ba.profile_id = auth.uid()
              AND ba.branch_id = p_branch_id
              AND ba.active
        );
$$;

-- Whether the current user can MANAGE (write) the given branch's
-- catalogue/hours data. Admins always can; otherwise a 'manager'
-- grant on the exact branch is required.
CREATE OR REPLACE FUNCTION public.can_manage_branch(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT public.is_admin()
        OR EXISTS (
            SELECT 1 FROM public.branch_access ba
            WHERE ba.profile_id = auth.uid()
              AND ba.branch_id = p_branch_id
              AND ba.active
              AND ba.role = 'manager'
        );
$$;

REVOKE ALL ON FUNCTION public.can_access_branch(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_manage_branch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_branch(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.can_access_branch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_branch(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.can_manage_branch(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- BRANCHES
-- ─────────────────────────────────────────────────────────────

CREATE TABLE public.branches (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL,
    slug         TEXT NOT NULL UNIQUE,
    emirate      TEXT NOT NULL,
    city         TEXT NOT NULL,
    address      TEXT,
    phone        TEXT,
    email        TEXT,
    timezone     TEXT NOT NULL DEFAULT 'Asia/Dubai',
    map_url      TEXT,
    active       BOOLEAN NOT NULL DEFAULT true,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.branches IS 'Clinic branches (SRS §6) — Dubai, Abu Dhabi, future UAE locations.';

-- Branch working hours — weekly recurring open times per branch.
-- Uses the same day_of_week convention as staff_availability
-- (0=Sun … 6=Sat).
CREATE TABLE public.branch_hours (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id   UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time  TIME NOT NULL,
    end_time    TIME NOT NULL CHECK (end_time > start_time),
    UNIQUE (branch_id, day_of_week)
);

COMMENT ON TABLE public.branch_hours IS 'Recurring weekly working hours per branch (SRS §6).';

-- Branch-specific closures (e.g. maintenance, emirate holidays).
-- Clinic-wide non-working days remain in public.holidays.
CREATE TABLE public.branch_closures (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id  UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    date       DATE NOT NULL,
    reason     TEXT,
    UNIQUE (branch_id, date)
);

COMMENT ON TABLE public.branch_closures IS 'Specific dates a branch is closed (SRS §6).';

-- Staff assigned to a branch (for scheduling / availability).
-- A staff member may work in more than one branch.
CREATE TABLE public.staff_branches (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id       UUID NOT NULL REFERENCES public.staff(id) ON DELETE RESTRICT,
    branch_id      UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    primary_branch BOOLEAN NOT NULL DEFAULT false,
    active         BOOLEAN NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (staff_id, branch_id)
);

COMMENT ON TABLE public.staff_branches IS 'Staff-to-branch assignments (SRS §6) — multi-branch staff allowed.';

-- Branch-scoped access grants used by RLS. Every non-admin user who
-- needs to read/manage branch data requires a row here (role scope
-- is extended by T18). Admins bypass via public.is_admin().
CREATE TABLE public.branch_access (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    branch_id   UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    role        branch_access_role NOT NULL DEFAULT 'viewer',
    active      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, branch_id)
);

COMMENT ON TABLE public.branch_access IS 'Branch-scoped RBAC grants (T37; extended by T18).';

-- ─────────────────────────────────────────────────────────────
-- SERVICE-BRANCH AVAILABILITY / PRICING
-- ─────────────────────────────────────────────────────────────

-- Per-branch catalogue data. Rows mark a service as available at a
-- branch and may override the global price, duration, buffer,
-- deposit, and booking rules. NULL price/duration fall back to the
-- service defaults (T12 availability engine reads this).
CREATE TABLE public.service_branches (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id     UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
    branch_id      UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    available      BOOLEAN NOT NULL DEFAULT true,
    price          NUMERIC(10,2) CHECK (price >= 0),
    currency       TEXT NOT NULL DEFAULT 'AED',
    duration_minutes INTEGER CHECK (duration_minutes > 0),
    buffer_minutes INTEGER NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
    deposit_amount NUMERIC(10,2) CHECK (deposit_amount >= 0),
    booking_rules  JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (service_id, branch_id)
);

COMMENT ON TABLE public.service_branches IS 'Branch availability + branch prices/duration/buffers for services (SRS §6/§7).';

CREATE INDEX idx_service_branches_branch ON public.service_branches (branch_id);
CREATE INDEX idx_service_branches_service ON public.service_branches (service_id);

-- ─────────────────────────────────────────────────────────────
-- SERVICES EXTENSIONS (catalogue model)
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.services
    ADD COLUMN service_type    public.service_type NOT NULL DEFAULT 'service',
    ADD COLUMN buffer_minutes  INTEGER NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
    ADD COLUMN price_on_request BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.services.service_type IS 'service | package | add_on | consultation | membership (SRS §7).';
COMMENT ON COLUMN public.services.buffer_minutes IS 'Default cleanup/buffer between bookings of this service (T11/T12).';
COMMENT ON COLUMN public.services.price_on_request IS 'Explicit price-on-request flag — hide price from the public catalogue (SRS §7, T11).';

-- Package content: a package (services.service_type='package') is
-- composed of included services with a quantity.
CREATE TABLE public.package_items (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    package_id         UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
    included_service_id UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
    quantity           INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    sort_order         INTEGER NOT NULL DEFAULT 0,
    UNIQUE (package_id, included_service_id),
    CHECK (package_id <> included_service_id)
);

COMMENT ON TABLE public.package_items IS 'Package composition — included services and quantities (SRS §7/§16).';

-- Add-ons available to purchase alongside a base service/package.
CREATE TABLE public.service_addons (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_id UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
    addon_id   UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
    active     BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE (service_id, addon_id),
    CHECK (service_id <> addon_id)
);

COMMENT ON TABLE public.service_addons IS 'Add-ons offered with a base service (SRS §7/§16).';

-- ─────────────────────────────────────────────────────────────
-- CLIENT NUMBER (immutable, collision-safe, configurable format)
-- ─────────────────────────────────────────────────────────────

-- Single source of number values — nextval is race-free and
-- collision-safe under concurrency.
CREATE SEQUENCE IF NOT EXISTS public.client_number_seq START 1;

-- Format is a clinic config (SRS §5.3): { "prefix": "TPL", "width": 6 }
-- stored in app_settings. Must NOT encode sensitive data (no DOB/phone).
CREATE OR REPLACE FUNCTION public.generate_client_number()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_fmt    jsonb := COALESCE(
        (SELECT value FROM public.app_settings WHERE key = 'client_number_format'),
        '{"prefix":"TPL","width":6}'::jsonb
    );
    v_prefix text  := COALESCE(NULLIF(v_fmt ->> 'prefix', ''), 'TPL');
    v_width  int   := GREATEST(COALESCE((v_fmt ->> 'width')::int, 6), 1);
BEGIN
    RETURN v_prefix || '-' || lpad(nextval('public.client_number_seq')::text, v_width, '0');
END;
$$;

-- Assign the client number for a NEW profile (patients/customers).
-- Imports (T25) pass an explicit number instead — client_number is
-- kept when already provided.
CREATE OR REPLACE FUNCTION public.set_client_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.client_number IS NULL AND NEW.role = 'patient' THEN
        NEW.client_number := public.generate_client_number();
    END IF;
    RETURN NEW;
END;
$$;

-- Immutability guard: once assigned, the client number never changes
-- through the application. Migration/import backfills run without an
-- authenticated context (auth.uid() IS NULL) and are therefore allowed
-- to assign/correct legacy rows (SRS §5.3, T25).
CREATE OR REPLACE FUNCTION public.prevent_client_number_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.client_number IS DISTINCT FROM OLD.client_number
       AND auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Client number is immutable';
    END IF;
    RETURN NEW;
END;
$$;

ALTER TABLE public.profiles
    ADD COLUMN client_number TEXT;

CREATE UNIQUE INDEX idx_profiles_client_number ON public.profiles (client_number);

DROP TRIGGER IF EXISTS trg_set_client_number ON public.profiles;
CREATE TRIGGER trg_set_client_number
    BEFORE INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_client_number();

DROP TRIGGER IF EXISTS trg_prevent_client_number_change ON public.profiles;
CREATE TRIGGER trg_prevent_client_number_change
    BEFORE UPDATE OF client_number ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_client_number_change();

-- Authorized staff search across client identity (SRS §5.3: searchable).
-- SECURITY DEFINER + internal guard — patients cannot enumerate others.
-- T22 builds the full centre-scoped customer lookup on top of this.
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
    WHERE p.role = 'patient'
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

REVOKE ALL ON FUNCTION public.search_clients(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_clients(text) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- APPOINTMENTS EXTENSIONS (branch + price snapshots)
-- ─────────────────────────────────────────────────────────────

-- branch_id is nullable here so existing MVP appointments survive the
-- migration; 005 backfills them to the default branch and tightens the
-- column to NOT NULL. Historical truth is kept via the *_snapshot
-- columns — renaming/re-pricing a service never rewrites history.
ALTER TABLE public.appointments
    ADD COLUMN branch_id            UUID REFERENCES public.branches(id) ON DELETE RESTRICT,
    ADD COLUMN client_number        TEXT,
    ADD COLUMN service_name_snapshot TEXT,
    ADD COLUMN price_snapshot       NUMERIC(10,2),
    ADD COLUMN currency_snapshot    TEXT NOT NULL DEFAULT 'AED',
    ADD COLUMN package_id           UUID REFERENCES public.services(id) ON DELETE RESTRICT,
    ADD COLUMN source_channel       TEXT NOT NULL DEFAULT 'web';

COMMENT ON COLUMN public.appointments.branch_id IS 'Branch where the appointment takes place (SRS §6/§8.2).';
COMMENT ON COLUMN public.appointments.client_number IS 'Snapshot of the patient client number at booking time (SRS §8.2).';
COMMENT ON COLUMN public.appointments.price_snapshot IS 'Price charged at booking time — immune to later catalogue edits (SRS §8.2, T37).';
COMMENT ON COLUMN public.appointments.package_id IS 'Package reference when booked as part of a package (SRS §7).';

CREATE INDEX idx_appointments_branch_id ON public.appointments (branch_id);
CREATE INDEX idx_appointments_scheduled_branch ON public.appointments (branch_id, scheduled_start, scheduled_end);

-- ─────────────────────────────────────────────────────────────
-- MIGRATION MAPPINGS (legacy Excel import, T25)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE public.migration_mappings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type TEXT NOT NULL CHECK (
        entity_type IN ('customer', 'branch', 'service', 'staff',
                        'appointment', 'package', 'add_on')
    ),
    legacy_key  TEXT NOT NULL,
    target_id   UUID NOT NULL,
    batch       TEXT NOT NULL DEFAULT 'legacy',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entity_type, legacy_key)
);

COMMENT ON TABLE public.migration_mappings IS 'Legacy → target record mapping for the controlled Excel migration (SRS §15, T25).';

CREATE INDEX idx_migration_mappings_entity ON public.migration_mappings (entity_type);

-- ─────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.branches          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_hours      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_closures   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_branches    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_access     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_branches  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_addons    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_mappings ENABLE ROW LEVEL SECURITY;

-- ── branches ─────────────────────────────────────────────────
-- Public: active branches only. Staff with access: their branches
-- (including inactive ones). Write: admin or branch manager.
CREATE POLICY branches_select_active
    ON public.branches FOR SELECT
    USING (active = true OR public.can_access_branch(id));

CREATE POLICY branches_insert_admin
    ON public.branches FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY branches_update
    ON public.branches FOR UPDATE
    USING (public.can_manage_branch(id))
    WITH CHECK (public.can_manage_branch(id));

CREATE POLICY branches_delete_admin
    ON public.branches FOR DELETE
    USING (public.is_admin());

-- ── branch_hours ─────────────────────────────────────────────
-- Hours are public so the availability picker works pre-login;
-- writing is restricted to admins/managers of that branch (SRS §6).
CREATE POLICY branch_hours_select
    ON public.branch_hours FOR SELECT
    USING (true);

CREATE POLICY branch_hours_insert
    ON public.branch_hours FOR INSERT
    WITH CHECK (public.can_manage_branch(branch_id));

CREATE POLICY branch_hours_update
    ON public.branch_hours FOR UPDATE
    USING (public.can_manage_branch(branch_id));

CREATE POLICY branch_hours_delete
    ON public.branch_hours FOR DELETE
    USING (public.can_manage_branch(branch_id));

-- ── branch_closures ──────────────────────────────────────────
CREATE POLICY branch_closures_select
    ON public.branch_closures FOR SELECT
    USING (true);

CREATE POLICY branch_closures_insert
    ON public.branch_closures FOR INSERT
    WITH CHECK (public.can_manage_branch(branch_id));

CREATE POLICY branch_closures_update
    ON public.branch_closures FOR UPDATE
    USING (public.can_manage_branch(branch_id));

CREATE POLICY branch_closures_delete
    ON public.branch_closures FOR DELETE
    USING (public.can_manage_branch(branch_id));

-- ── staff_branches ───────────────────────────────────────────
-- Public read of assignments (the availability picker needs them);
-- write restricted to admins/branch managers of the target branch.
CREATE POLICY staff_branches_select
    ON public.staff_branches FOR SELECT
    USING (true);

CREATE POLICY staff_branches_insert
    ON public.staff_branches FOR INSERT
    WITH CHECK (public.can_manage_branch(branch_id));

CREATE POLICY staff_branches_update
    ON public.staff_branches FOR UPDATE
    USING (public.can_manage_branch(branch_id));

CREATE POLICY staff_branches_delete
    ON public.staff_branches FOR DELETE
    USING (public.can_manage_branch(branch_id));

-- ── branch_access ────────────────────────────────────────────
-- Grants are admin-managed (invitations land in T18). Users can see
-- their own grants; admins see all.
CREATE POLICY branch_access_select
    ON public.branch_access FOR SELECT
    USING (profile_id = auth.uid() OR public.is_admin());

CREATE POLICY branch_access_insert_admin
    ON public.branch_access FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY branch_access_update_admin
    ON public.branch_access FOR UPDATE
    USING (public.is_admin());

CREATE POLICY branch_access_delete_admin
    ON public.branch_access FOR DELETE
    USING (public.is_admin());

-- ── service_branches ─────────────────────────────────────────
-- Availability is public. Writes follow branch scope: admin
-- anywhere, branch managers only on their own branch — so a
-- branch-scoped user cannot edit another branch's pricing (T37
-- acceptance criterion; T11 admin UI relies on this).
CREATE POLICY service_branches_select
    ON public.service_branches FOR SELECT
    USING (true);

CREATE POLICY service_branches_insert
    ON public.service_branches FOR INSERT
    WITH CHECK (public.can_manage_branch(branch_id));

CREATE POLICY service_branches_update
    ON public.service_branches FOR UPDATE
    USING (public.can_manage_branch(branch_id))
    WITH CHECK (public.can_manage_branch(branch_id));

CREATE POLICY service_branches_delete
    ON public.service_branches FOR DELETE
    USING (public.can_manage_branch(branch_id));

-- ── package_items / service_addons ───────────────────────────
-- Public read; admin-only writes (catalogue structure is global).
CREATE POLICY package_items_select
    ON public.package_items FOR SELECT
    USING (true);

CREATE POLICY package_items_insert_admin
    ON public.package_items FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY package_items_update_admin
    ON public.package_items FOR UPDATE
    USING (public.is_admin());

CREATE POLICY package_items_delete_admin
    ON public.package_items FOR DELETE
    USING (public.is_admin());

CREATE POLICY service_addons_select
    ON public.service_addons FOR SELECT
    USING (true);

CREATE POLICY service_addons_insert_admin
    ON public.service_addons FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY service_addons_update_admin
    ON public.service_addons FOR UPDATE
    USING (public.is_admin());

CREATE POLICY service_addons_delete_admin
    ON public.service_addons FOR DELETE
    USING (public.is_admin());

-- ── migration_mappings ───────────────────────────────────────
-- Used exclusively by the T25 import tool (service_role / pg).
CREATE POLICY migration_mappings_select_admin
    ON public.migration_mappings FOR SELECT
    USING (public.is_admin());

CREATE POLICY migration_mappings_insert_admin
    ON public.migration_mappings FOR INSERT
    WITH CHECK (public.is_admin());

-- ── appointments (branch scope) ──────────────────────────────
-- Extend the baseline policy (T3) with branch scope: staff only see
-- the appointments of branches they can access (SRS §17). Admins
-- bypass via can_access_branch -> is_admin.
DROP POLICY IF EXISTS appointments_select ON public.appointments;
CREATE POLICY appointments_select
    ON public.appointments FOR SELECT
    USING (
        patient_id = auth.uid()
        OR (
            public.is_staff_or_admin()
            AND (branch_id IS NULL OR public.can_access_branch(branch_id))
        )
    );

-- Patients create appointments (branch is validated server-side by
-- the booking API, T14).
DROP POLICY IF EXISTS appointments_insert_patient ON public.appointments;
CREATE POLICY appointments_insert_patient
    ON public.appointments FOR INSERT
    WITH CHECK (patient_id = auth.uid());

-- Staff/admin create on behalf of a patient, scoped to branches they
-- can access (branch scope enforced here and re-checked by T14).
DROP POLICY IF EXISTS appointments_insert_privileged ON public.appointments;
CREATE POLICY appointments_insert_privileged
    ON public.appointments FOR INSERT
    WITH CHECK (
        public.is_staff_or_admin()
        AND (branch_id IS NULL OR public.can_access_branch(branch_id))
    );

-- Patients update their own; staff/admin update within branch scope.
DROP POLICY IF EXISTS appointments_update ON public.appointments;
CREATE POLICY appointments_update
    ON public.appointments FOR UPDATE
    USING (
        patient_id = auth.uid()
        OR (
            public.is_staff_or_admin()
            AND (branch_id IS NULL OR public.can_access_branch(branch_id))
        )
    );

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: keep updated_at in sync on mutable new tables
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_branches_updated ON public.branches;
CREATE TRIGGER trg_branches_updated
    BEFORE UPDATE ON public.branches
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS trg_service_branches_updated ON public.service_branches;
CREATE TRIGGER trg_service_branches_updated
    BEFORE UPDATE ON public.service_branches
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();