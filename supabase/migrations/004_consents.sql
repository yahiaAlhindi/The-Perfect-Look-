-- ============================================================
-- The Perfect Look — T8: Consent records & data-request entry
-- ============================================================
-- Migration: 004_consents.sql
-- Depends on: 001_schema.sql (T3) + 002_auth_profiles.sql (T5)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T8, SRS v2 §16/§17
--
-- Responsibilities:
--   1. `consents` — append-only consent history. Every record carries a
--      fixed `version` and a `created_at` timestamp. Withdrawing consent
--      is a NEW row with granted = false — never an UPDATE — so the full
--      audit trail survives (reconsent history, complaint evidence).
--   2. `data_requests` — "request my data" entry point (SRS §17). A
--      customer records a request that staff can later fulfil; rows are
--      own-read/own-insert only, status is staff-managed.
--
-- RLS: users read/insert ONLY their own rows on both tables. There are
-- no update/delete policies on `consents` (immutable), and deletion of
-- `data_requests` is blocked for customers (only admins may update the
-- status; the row itself is never deleted by patients).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. CONSENTS — append-only consent history
-- ─────────────────────────────────────────────────────────────

CREATE TABLE public.consents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    consent_type  TEXT NOT NULL CHECK (consent_type IN ('terms_service', 'marketing')),
    version       TEXT NOT NULL DEFAULT 'v1',
    granted       BOOLEAN NOT NULL,
    source        TEXT NOT NULL DEFAULT 'web',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.consents IS 'Append-only consent history (T8). version + created_at per record; withdrawal = new row with granted=false.';

CREATE INDEX idx_consents_user_type_time ON public.consents (user_id, consent_type, created_at DESC);

-- ─────────────────────────────────────────────────────────────
-- 2. DATA REQUESTS — "request my data" entry point (SRS §17)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE public.data_requests (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status       TEXT NOT NULL DEFAULT 'received' CHECK (status IN ('received', 'processing', 'fulfilled')),
    notes        TEXT
);

COMMENT ON TABLE public.data_requests IS 'Customer "request my data" records (T8/SRS §17). Status is staff-managed; the customer only reads their own.';

CREATE INDEX idx_data_requests_user_time ON public.data_requests (user_id, requested_at DESC);

-- ─────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.consents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_requests ENABLE ROW LEVEL SECURITY;

-- consents: own rows for patients / staff (staff may need to confirm a
-- consent was given); admins see everything.
CREATE POLICY consents_select_own
    ON public.consents FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_staff_or_admin()
    );

CREATE POLICY consents_insert_own
    ON public.consents FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- data_requests: own rows for the requester; admins read all.
CREATE POLICY data_requests_select_own
    ON public.data_requests FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_admin()
    );

CREATE POLICY data_requests_insert_own
    ON public.data_requests FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Staff may progress the fulfilment status (never delete).
CREATE POLICY data_requests_update_status_admin
    ON public.data_requests FOR UPDATE
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- ─────────────────────────────────────────────────────────────
-- GUARDS (defence in depth)
-- ─────────────────────────────────────────────────────────────

-- Consent history is immutable — even the service role cannot rewrite
-- or delete a record (reversing a consent must be a new row).
CREATE OR REPLACE FUNCTION public.prevent_consent_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RAISE EXCEPTION 'Consent records are immutable — record a new consent instead';
    RETURN NULL; -- unreachable, keeps plpgsql happy
END;
$$;

DROP TRIGGER IF EXISTS trg_consents_no_update ON public.consents;
DROP TRIGGER IF EXISTS trg_consents_no_delete ON public.consents;

CREATE TRIGGER trg_consents_no_update
    BEFORE UPDATE ON public.consents
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_consent_mutation();

CREATE TRIGGER trg_consents_no_delete
    BEFORE DELETE ON public.consents
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_consent_mutation();