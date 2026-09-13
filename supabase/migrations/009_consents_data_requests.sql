-- ============================================================
-- The Perfect Look — T8: Profile & consent API support
-- ============================================================
-- Migration: 009_consents_data_requests.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T8, SRS v1 §5.1/§12/§17
--
-- Responsibilities (T8 acceptance criteria):
--   1. Consent history — versioned, timestamped, append-only events
--      per user. The current state is the latest row per
--      (user_id, consent_type). Required service consents (ToS,
--      privacy, health disclaimer) stay separate from the optional
--      marketing consent (SRS §5.1).
--   2. Data-request entry point — customers file export / correction
--      / deletion / consent-withdrawal requests from their dashboard
--      (SRS §12 dashboard, §17 compliance).
--   3. Allowed field rules for own-profile PUT — a customer may only
--      update their editable fields (full_name, mobile_number, dob,
--      gender, preferred_language). identity/role/system columns are
--      protected server-side by a trigger (SRS §17).
--
-- RLS: consents and data_requests are visible only to their owner
-- or staff/admin — never to anon (sensitive fields not exposed to
-- public queries).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────

-- Consent families (SRS §5.1 + §17 approved wording list).
CREATE TYPE consent_type AS ENUM (
    'terms_of_service',
    'privacy_policy',
    'health_data_disclaimer',
    'nutrition_disclaimer',
    'cancellation_refund_policy',
    'marketing'
);

-- Customer data requests (SRS §17: export, correction, deletion,
-- consent withdrawal).
CREATE TYPE data_request_type AS ENUM (
    'export',
    'correction',
    'deletion',
    'consent_withdrawal'
);

CREATE TYPE data_request_status AS ENUM (
    'submitted',
    'in_progress',
    'fulfilled',
    'rejected'
);

-- ─────────────────────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────────────────────

-- Versioned, append-only consent history. One row per grant/revoke
-- event; version + created_at satisfy "records include version and
-- timestamp". Never UPDATE/DELETE a row — record a new event instead.
CREATE TABLE public.consents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    consent_type consent_type NOT NULL,
    version      INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    granted      BOOLEAN NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.consents IS
    'Consent history (SRS §5.1/§17) — immutable, versioned, timestamped events.';

CREATE INDEX idx_consents_user
    ON public.consents (user_id, consent_type, created_at DESC);

-- Customer data requests (SRS §12/§17).
CREATE TABLE public.data_requests (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    request_type  data_request_type NOT NULL,
    details       JSONB NOT NULL DEFAULT '{}'::jsonb,
    status        data_request_status NOT NULL DEFAULT 'submitted',
    submitted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    handled_by    UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    handled_at    TIMESTAMPTZ,
    response_note TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.data_requests IS
    'Customer data-request queue (SRS §12/§17) — export, correction, deletion, consent withdrawal.';

CREATE INDEX idx_data_requests_user
    ON public.data_requests (user_id, status, created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: allowed field rules for own-profile PUT (SRS §7/§17)
-- A customer editing their own profile may change only the editable
-- fields: full_name, mobile_number, dob, gender, preferred_language.
-- email / role / id / created_at are immutable from the self-edit
-- path. System-sync writes (auth.users -> profiles trigger, where
-- auth.uid() is NULL) and staff/admin edits pass unchanged.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_profile_update_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- System-trigger writes (auth.users sync) and staff/admin pass.
    IF auth.uid() IS NULL OR public.is_staff_or_admin() THEN
        RETURN NEW;
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'Profile id is immutable';
    END IF;
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        RAISE EXCEPTION 'Email cannot be changed here — use the account settings flow';
    END IF;
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        RAISE EXCEPTION 'Cannot change your own role';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'Profile creation time is immutable';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_update_fields ON public.profiles;

CREATE TRIGGER trg_enforce_profile_update_fields
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_profile_update_fields();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: consent history is append-only through the API
-- Authenticated API users can never modify/delete a consent row;
-- SQL maintenance (no JWT context, auth.uid() NULL) still works.
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.immutify_consents()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Consent records are immutable — record a new consent event instead';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_immutify_consents ON public.consents;

CREATE TRIGGER trg_immutify_consents
    BEFORE UPDATE OR DELETE ON public.consents
    FOR EACH ROW
    EXECUTE FUNCTION public.immutify_consents();

-- ─────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.consents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_requests ENABLE ROW LEVEL SECURITY;

-- RLS policy expressions call the SECURITY DEFINER helpers, so every
-- role the policies apply to must be able to EXECUTE them. anon needs
-- execution so its policy checks resolve to `false` (auth.uid() is
-- NULL for anon) instead of raising permission-denied — anon simply
-- sees 0 rows. The functions leak nothing (they only test the JWT uid).
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;
GRANT EXECUTE ON FUNCTION public.is_staff_or_admin() TO anon;

-- ── consents ─────────────────────────────────────────────────
-- Owner reads/writes own history rows; staff/admin read all.
-- UPDATE/DELETE are allowed ONLY on the owner's own rows so the
-- immutability trigger can surface a clear error through the API
-- (RLS otherwise turns a forbidden write into a silent no-op).

CREATE POLICY consents_select
    ON public.consents FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_staff_or_admin()
    );

CREATE POLICY consents_insert_own
    ON public.consents FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY consents_update_own
    ON public.consents FOR UPDATE
    USING (user_id = auth.uid());

CREATE POLICY consents_delete_own
    ON public.consents FOR DELETE
    USING (user_id = auth.uid());

-- ── data_requests ────────────────────────────────────────────
-- Owner files + reads own requests; staff/admin manage the queue.

CREATE POLICY data_requests_select
    ON public.data_requests FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_staff_or_admin()
    );

CREATE POLICY data_requests_insert_own
    ON public.data_requests FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY data_requests_update_privileged
    ON public.data_requests FOR UPDATE
    USING (public.is_staff_or_admin())
    WITH CHECK (public.is_staff_or_admin());