-- ============================================================
-- The Perfect Look - full SQL schema (consolidated)
-- ============================================================
-- supabase/schema.sql = the final database schema for the MVP.
-- This file is the consolidated snapshot of the applied
-- migrations (supabase/migrations/001_schema.sql through
-- 010_mobile_normalisation.sql).
-- Keep it in sync with migrations; migrations are the source
-- of truth. See docs/PROJECT_TASKS_BREAKDOWN.md task T3 for
-- acceptance criteria (SRS sections 10, 12, 15, 17, 20).
-- ============================================================
-- ============================================================
-- The Perfect Look — MVP Database Schema (T3)
-- ============================================================
-- Migration: 001_schema.sql
-- Source: PROJECT_TASKS_BREAKDOWN.md §T3, SRS v1 §10/§12/§15/§17/§20
-- Supabase project: online DB = System of Record (SRS §12)
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────

-- Appointment statuses — values match SRS §10 exactly.
CREATE TYPE appointment_status AS ENUM (
    'Pending',
    'Confirmed',
    'Completed',
    'Cancelled',
    'Rescheduled',
    'No Show'
);

CREATE TYPE user_role AS ENUM (
    'patient',
    'staff',
    'admin'
);

-- Notification channels — SRS §15.
CREATE TYPE notification_channel AS ENUM (
    'Email',
    'SMS',
    'WhatsApp'
);

-- Notification delivery state (SRS §15: "status should be recorded").
CREATE TYPE notification_status AS ENUM (
    'pending',
    'sent',
    'failed',
    'read'
);

-- ─────────────────────────────────────────────────────────────
-- HELPER FUNCTIONS (RLS) — SECURITY DEFINER to avoid recursion
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_staff_or_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role IN ('staff', 'admin')
    );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_staff_or_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff_or_admin() TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────────────────────

-- profiles — synced from auth.users via trigger
CREATE TABLE public.profiles (
    id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
    full_name     TEXT NOT NULL,
    mobile_number TEXT UNIQUE NOT NULL,
    email         TEXT UNIQUE NOT NULL,
    dob           DATE,
    gender        TEXT,
    preferred_language TEXT NOT NULL DEFAULT 'en',
    role          user_role NOT NULL DEFAULT 'patient',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profiles IS 'User profiles — one row per auth.users entry, synced via trigger.';

-- services — bookable treatments offered by the clinic
CREATE TABLE public.services (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT NOT NULL,
    description         TEXT,
    duration_minutes    INTEGER NOT NULL CHECK (duration_minutes > 0),
    price               NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    currency            TEXT NOT NULL DEFAULT 'AED',
    active              BOOLEAN NOT NULL DEFAULT true,
    assigned_staff_type TEXT,
    booking_rules       JSONB NOT NULL DEFAULT '{}'::jsonb,
    sort_order          INTEGER NOT NULL DEFAULT 0
);

COMMENT ON TABLE public.services IS 'Bookable treatments/services (SRS §8).';

-- staff — links to profiles; stores role-specific data
CREATE TABLE public.staff (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id       UUID UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    title            TEXT,
    specializations  TEXT[],
    active           BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE public.staff IS 'Staff members linked to a profile (SRS §14).';

-- staff_availability — weekly recurring availability per staff
CREATE TABLE public.staff_availability (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id    UUID NOT NULL REFERENCES public.staff(id) ON DELETE RESTRICT,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time  TIME NOT NULL,
    end_time    TIME NOT NULL CHECK (end_time > start_time),
    UNIQUE (staff_id, day_of_week)
);

COMMENT ON TABLE public.staff_availability IS 'Recurring weekly availability per staff member (0=Sun … 6=Sat).';

-- blocked_periods — staff-specific or clinic-wide blocks
CREATE TABLE public.blocked_periods (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id       UUID REFERENCES public.staff(id) ON DELETE RESTRICT,
    start_datetime TIMESTAMPTZ NOT NULL,
    end_datetime   TIMESTAMPTZ NOT NULL CHECK (end_datetime > start_datetime),
    reason         TEXT,
    CHECK (staff_id IS NOT NULL OR reason IS NOT NULL)
);

COMMENT ON TABLE public.blocked_periods IS 'Blocked time — clinic-wide (staff_id NULL) or per-staff.';

-- holidays — clinic-wide non-working days
CREATE TABLE public.holidays (
    id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date   DATE NOT NULL UNIQUE,
    reason TEXT
);

COMMENT ON TABLE public.holidays IS 'Clinic-wide holidays / non-working days.';

-- appointments — the core booking table
CREATE TABLE public.appointments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_ref TEXT UNIQUE NOT NULL,
    patient_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    service_id      UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
    staff_id        UUID REFERENCES public.staff(id) ON DELETE RESTRICT,
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end   TIMESTAMPTZ NOT NULL CHECK (scheduled_end > scheduled_start),
    status          appointment_status NOT NULL DEFAULT 'Pending',
    notes           TEXT,
    cancel_reason   TEXT,
    last_modified_by UUID,
    last_modified_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.appointments IS 'Patient appointment bookings (SRS §9/§11).';

-- notifications — per-user notification log
CREATE TABLE public.notifications (
    id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    type      TEXT NOT NULL,
    channel   notification_channel NOT NULL,
    subject   TEXT,
    body      TEXT NOT NULL,
    status    notification_status NOT NULL DEFAULT 'pending',
    sent_at   TIMESTAMPTZ,
    read_at   TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notifications IS 'Notification log — channels: Email/SMS/WhatsApp (SRS §15).';

-- audit_logs — admin action trail
CREATE TABLE public.audit_logs (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    action        TEXT NOT NULL,
    entity        TEXT NOT NULL,
    entity_id     UUID,
    details       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_logs IS 'Admin/audit action log (SRS §17).';

-- app_settings — key/value store for clinic configuration
CREATE TABLE public.app_settings (
    key   TEXT PRIMARY KEY,
    value JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.app_settings IS 'Global clinic configuration (working hours, slot interval, etc.).';

-- ─────────────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────────────

-- Appointments: query by patient, service, staff, and time window
CREATE INDEX idx_appointments_patient_id ON public.appointments (patient_id);
CREATE INDEX idx_appointments_service_id ON public.appointments (service_id);
CREATE INDEX idx_appointments_staff_id   ON public.appointments (staff_id);
CREATE INDEX idx_appointments_status     ON public.appointments (status);
CREATE INDEX idx_appointments_scheduled  ON public.appointments (scheduled_start, scheduled_end);

-- Composite: prevent overlapping bookings for the same staff+time
-- (partial — excludes Cancelled and No Show)
CREATE UNIQUE INDEX idx_appointments_no_double_book
    ON public.appointments (staff_id, scheduled_start)
    WHERE staff_id IS NOT NULL
      AND status NOT IN ('Cancelled', 'No Show');

-- Staff availability: fast lookup by staff + day
CREATE INDEX idx_staff_availability_staff_day ON public.staff_availability (staff_id, day_of_week);

-- Blocked periods: fast lookup by staff and time range
CREATE INDEX idx_blocked_periods_staff ON public.blocked_periods (staff_id);
CREATE INDEX idx_blocked_periods_time  ON public.blocked_periods (start_datetime, end_datetime);

-- Notifications: query by user, status, and created time
CREATE INDEX idx_notifications_user_id   ON public.notifications (user_id);
CREATE INDEX idx_notifications_status    ON public.notifications (status);
CREATE INDEX idx_notifications_created   ON public.notifications (created_at);

-- Audit logs: query by admin and entity
CREATE INDEX idx_audit_logs_admin    ON public.audit_logs (admin_user_id);
CREATE INDEX idx_audit_logs_entity   ON public.audit_logs (entity, entity_id);
CREATE INDEX idx_audit_logs_created  ON public.audit_logs (created_at);

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: sync auth.users → profiles
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, mobile_number, email, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
        COALESCE(NEW.raw_user_meta_data ->> 'mobile_number', ''),
        NEW.email,
        COALESCE((NEW.raw_user_meta_data ->> 'role')::user_role, 'patient')
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name     = EXCLUDED.full_name,
        mobile_number = EXCLUDED.mobile_number,
        email         = EXCLUDED.email;
    RETURN NEW;
END;
$$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: auto-generate appointment_ref on insert
-- Race-free serial generator (nextval is safe under concurrency).
-- ─────────────────────────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS public.appointment_ref_seq START 1;

CREATE OR REPLACE FUNCTION public.set_appointment_ref()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    day_part TEXT;
BEGIN
    day_part := to_char(NEW.scheduled_start, 'YYYYMMDD');
    NEW.appointment_ref := 'TPL-' || day_part || '-' ||
        lpad(nextval('public.appointment_ref_seq')::text, 4, '0');
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_set_appointment_ref
    BEFORE INSERT ON public.appointments
    FOR EACH ROW
    WHEN (NEW.appointment_ref IS NULL OR NEW.appointment_ref = '')
    EXECUTE FUNCTION public.set_appointment_ref();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: prevent a user from self-escalating their own role
-- (RLS is row-level only — column-level checks need a trigger).
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_self_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role AND auth.uid() = OLD.id THEN
        RAISE EXCEPTION 'Cannot change your own role';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_prevent_self_role_change
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_self_role_change();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER: update last_modified_at on appointment changes
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_appointment_modified()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.last_modified_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_appointment_modified
    BEFORE UPDATE ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION public.update_appointment_modified();

-- ─────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.services           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_periods    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holidays           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings       ENABLE ROW LEVEL SECURITY;

-- ── profiles ─────────────────────────────────────────────────
-- Patients: own profile only (read + update); staff/admin: all
CREATE POLICY profiles_select_own
    ON public.profiles FOR SELECT
    USING (
        id = auth.uid()
        OR public.is_staff_or_admin()
    );

CREATE POLICY profiles_update_own
    ON public.profiles FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Admins can update any profile (role assignment, etc.)
CREATE POLICY profiles_update_admin
    ON public.profiles FOR UPDATE
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- Staff/admin can create profiles (e.g. when creating accounts)
CREATE POLICY profiles_insert_privileged
    ON public.profiles FOR INSERT
    WITH CHECK (public.is_staff_or_admin());

-- ── services ─────────────────────────────────────────────────
-- Everyone (incl. anon) can read active services; only staff/admin
-- can manage inactive ones, and only admins write.
CREATE POLICY services_select_active
    ON public.services FOR SELECT
    USING (
        active = true
        OR public.is_staff_or_admin()
    );

CREATE POLICY services_insert_admin
    ON public.services FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY services_update_admin
    ON public.services FOR UPDATE
    USING (public.is_admin());

CREATE POLICY services_delete_admin
    ON public.services FOR DELETE
    USING (public.is_admin());

-- ── staff ────────────────────────────────────────────────────
-- Patients: see all active staff; staff/admin: see all
CREATE POLICY staff_select
    ON public.staff FOR SELECT
    USING (
        active = true
        OR public.is_staff_or_admin()
    );

CREATE POLICY staff_insert_admin
    ON public.staff FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY staff_update_admin
    ON public.staff FOR UPDATE
    USING (public.is_admin());

-- ── staff_availability ───────────────────────────────────────
CREATE POLICY staff_availability_select
    ON public.staff_availability FOR SELECT
    USING (true);

CREATE POLICY staff_availability_insert_admin
    ON public.staff_availability FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY staff_availability_update_admin
    ON public.staff_availability FOR UPDATE
    USING (public.is_admin());

CREATE POLICY staff_availability_delete_admin
    ON public.staff_availability FOR DELETE
    USING (public.is_admin());

-- ── blocked_periods ──────────────────────────────────────────
CREATE POLICY blocked_periods_select
    ON public.blocked_periods FOR SELECT
    USING (true);

CREATE POLICY blocked_periods_insert_admin
    ON public.blocked_periods FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY blocked_periods_update_admin
    ON public.blocked_periods FOR UPDATE
    USING (public.is_admin());

CREATE POLICY blocked_periods_delete_admin
    ON public.blocked_periods FOR DELETE
    USING (public.is_admin());

-- ── holidays ─────────────────────────────────────────────────
CREATE POLICY holidays_select
    ON public.holidays FOR SELECT
    USING (true);

CREATE POLICY holidays_insert_admin
    ON public.holidays FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY holidays_update_admin
    ON public.holidays FOR UPDATE
    USING (public.is_admin());

CREATE POLICY holidays_delete_admin
    ON public.holidays FOR DELETE
    USING (public.is_admin());

-- ── appointments ─────────────────────────────────────────────
-- Patients: own appointments only; staff/admin: all (SRS §17)
CREATE POLICY appointments_select
    ON public.appointments FOR SELECT
    USING (
        patient_id = auth.uid()
        OR public.is_staff_or_admin()
    );

-- Patients create their own appointments
CREATE POLICY appointments_insert_patient
    ON public.appointments FOR INSERT
    WITH CHECK (patient_id = auth.uid());

-- Staff/admin create on behalf of a patient
CREATE POLICY appointments_insert_privileged
    ON public.appointments FOR INSERT
    WITH CHECK (public.is_staff_or_admin());

-- Patients update their own; staff/admin update all
CREATE POLICY appointments_update
    ON public.appointments FOR UPDATE
    USING (
        patient_id = auth.uid()
        OR public.is_staff_or_admin()
    );

-- ── notifications ────────────────────────────────────────────
-- Users see only their own; admins see all
CREATE POLICY notifications_select
    ON public.notifications FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.is_admin()
    );

-- Users mark their own as read; admins can update any
CREATE POLICY notifications_update
    ON public.notifications FOR UPDATE
    USING (
        user_id = auth.uid()
        OR public.is_admin()
    );

-- ── audit_logs ───────────────────────────────────────────────
-- Admins only (read + insert); service-role bypasses RLS anyway.
CREATE POLICY audit_logs_select_admin
    ON public.audit_logs FOR SELECT
    USING (public.is_admin());

CREATE POLICY audit_logs_insert_admin
    ON public.audit_logs FOR INSERT
    WITH CHECK (public.is_admin());

-- ── app_settings ─────────────────────────────────────────────
-- Public read (frontend needs working hours, slot interval, etc.)
-- Admin-only write.
CREATE POLICY app_settings_select
    ON public.app_settings FOR SELECT
    USING (true);

CREATE POLICY app_settings_insert_admin
    ON public.app_settings FOR INSERT
    WITH CHECK (public.is_admin());

CREATE POLICY app_settings_update_admin
    ON public.app_settings FOR UPDATE
    USING (public.is_admin());

CREATE POLICY app_settings_delete_admin
    ON public.app_settings FOR DELETE
    USING (public.is_admin());

-- ============================================================
-- 002_auth_profiles.sql -- migration 002 (T5, auth & profile sync)
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T5: Auth & Session API support
-- ============================================================
-- Migration: 002_auth_profiles.sql
-- Depends on: 001_schema.sql (T3) â€” tables, enums, RLS, and the
--   handle_new_user() trigger on auth.users.
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T5, SRS v1 Â§5/Â§6/Â§7/Â§17
--
-- Responsibilities:
--   1. Normalise mobile_number (UAE â†’ E.164) and lower-case email
--      on profiles via a BEFORE trigger (single source of truth, so
--      both Auth sign-up and direct inserts are covered).
--   2. Enforce required contact fields on profiles (SRS Â§5).
--   3. Require mobile_number in sign-up metadata so every new auth
--      user gets a complete profiles row (SRS Â§5 "Mobile required").
--   4. resolve_login_identifier() RPC â€” lets the client resolve
--      "email OR mobile" sign-in to an auth email (SRS Â§6).
-- Uniqueness (email + mobile) is enforced by the unique indexes
-- created in 001_schema.sql; failures surface as mapped client
-- errors (code 23505 / unique_violation).
-- ============================================================

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 1. NORMALISE CONTACT FIELDS
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION public.normalize_profile_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Lower-case + trim email
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(trim(NEW.email));
    END IF;

    -- Normalise UAE mobile numbers to E.164
    IF NEW.mobile_number IS NOT NULL THEN
        -- Strip separators: spaces, dashes, parentheses, dots
        NEW.mobile_number := regexp_replace(NEW.mobile_number, '[\s\-\(\)\.]', '', 'g');

        -- 0XXXXXXXXX (leading zero, UAE local) -> +971XXXXXXXXX
        IF NEW.mobile_number ~ '^0[5-9]\d{8}$' THEN
            NEW.mobile_number := '+971' || NEW.mobile_number;
        -- 9715XXXXXXXX (no leading +) -> +9715XXXXXXXX
        ELSIF NEW.mobile_number ~ '^971[5-9]\d{8}$' THEN
            NEW.mobile_number := '+' || NEW.mobile_number;
        -- 9-digit local without leading zero (e.g. 55XXXXXXX) -> +9715XXXXXXX
        ELSIF NEW.mobile_number ~ '^[5-9]\d{8}$' THEN
            NEW.mobile_number := '+971' || NEW.mobile_number;
        END IF;

        -- Final guard: must be E.164-ish (+, 1-3 digit country code, 6-14 digits)
        IF NEW.mobile_number !~ '^\+[1-9]\d{6,14}$' THEN
            RAISE EXCEPTION 'Mobile number is not in a valid international format';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_profile_contact ON public.profiles;

CREATE TRIGGER trg_normalize_profile_contact
    BEFORE INSERT OR UPDATE OF mobile_number, email
    ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_profile_contact();

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 2. ENFORCE REQUIRED CONTACT FIELDS (SRS Â§5)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION public.enforce_profile_required_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.email IS NULL OR trim(NEW.email) = '' THEN
        RAISE EXCEPTION 'Email address is required';
    END IF;
    IF NEW.mobile_number IS NULL OR trim(NEW.mobile_number) = '' THEN
        RAISE EXCEPTION 'Mobile number is required';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profile_required_fields ON public.profiles;

CREATE TRIGGER trg_enforce_profile_required_fields
    BEFORE INSERT
    ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_profile_required_fields();

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 3. SIGN-UP REQUIRES MOBILE (replaces 001's version)
--    Every new auth user gets a complete profiles row; a missing
--    mobile_number aborts the auth.users insert (a clean failure
--    instead of a partial account).
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.raw_user_meta_data ->> 'mobile_number' IS NULL
       OR trim(NEW.raw_user_meta_data ->> 'mobile_number') = '' THEN
        RAISE EXCEPTION 'Mobile number is required for registration';
    END IF;

    INSERT INTO public.profiles (id, full_name, mobile_number, email, role)
    VALUES (
        NEW.id,
        COALESCE(trim(NEW.raw_user_meta_data ->> 'full_name'), ''),
        NEW.raw_user_meta_data ->> 'mobile_number',
        lower(NEW.email),
        COALESCE((NEW.raw_user_meta_data ->> 'role')::user_role, 'patient')
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name     = EXCLUDED.full_name,
        mobile_number = EXCLUDED.mobile_number,
        email         = EXCLUDED.email;
    RETURN NEW;
END;
$$;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 4. LOGIN IDENTIFIER RESOLVER (SRS Â§6: email OR mobile)
--    SECURITY DEFINER so anonymous sign-in can resolve a mobile to
--    its account email. Returns ONLY the auth email â€” never any
--    other profile data (SRS Â§17).
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DROP FUNCTION IF EXISTS public.resolve_login_identifier(TEXT);

CREATE OR REPLACE FUNCTION public.resolve_login_identifier(identifier text)
RETURNS TABLE(email text)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT p.email
    FROM public.profiles p
    WHERE lower(p.email) = lower(trim(identifier))
       OR p.mobile_number = identifier
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_login_identifier(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_login_identifier(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.resolve_login_identifier(TEXT) TO authenticated;

-- ============================================================
-- 003_seed_data.sql -- migration 003 (T4, seed data)
-- ============================================================
-- ============================================================
-- The Perfect Look â€” Seed Data (T4)
-- ============================================================
-- Migration: 003_seed_data.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5)
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T4, SRS v1 Â§8/Â§9/Â§11/Â§12
--
-- Responsibility: seed the demo clinic configuration so the
-- app works without any hard-coded front-end data:
--   1. 8 services from SRS Â§8 (active, demo durations/prices).
--   2. 3 demo staff members with weekly availability.
--   3. app_settings (working hours, slot interval, notice
--      periods, currency, price visibility, â€¦) read by the
--      availability engine and admin/booking APIs.
--   4. Demo holidays.
--
-- The whole migration is IDEMPOTENT â€” safe to re-run. Existing
-- rows are never overwritten (ON CONFLICT DO NOTHING / NOT
-- EXISTS guards), so clinic edits survive a re-apply.
--
-- âš  Demo credentials: the staff accounts below use a dev-only
--    default password. Disable or change them before sharing the
--    project (T35 golden rules; see supabase/seed.sql warning).
--
-- Prices/durations are T35 placeholders until the clinic answers.
-- ============================================================

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 1. SERVICES (SRS Â§8)
--    Idempotent by exact name. Prices/durations are demo defaults
--    flagged in T35; price_visibility (app_settings) controls
--    whether patients see prices, not the stored value.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

DO $$
DECLARE
    rec record;
BEGIN
    FOR rec IN SELECT * FROM (VALUES
        (
            'Skin Care Treatment',
            'Personalised facials, cleansing routines and skin-care plans tailored to your skin type.',
            60, 250.00, 'Dermatologist', 1,
            '{"preferred_staff_selectable": true}'::jsonb
        ),
        (
            'Advanced Hair Care Solutions',
            'Scalp analysis and advanced hair growth and treatment plans.',
            90, 400.00, 'Hair Specialist', 2,
            '{"preferred_staff_selectable": true}'::jsonb
        ),
        (
            'Laser Hair Removal',
            'Safe, long-lasting laser hair reduction for face and body.',
            45, 350.00, 'Laser Technician', 3,
            '{"preferred_staff_selectable": true, "min_advance_days": 1}'::jsonb
        ),
        (
            'Clinical Nutrition & Weight Management',
            'Clinical assessments with personalised nutrition and weight-management programmes.',
            60, 300.00, 'Nutritionist', 4,
            '{"preferred_staff_selectable": true}'::jsonb
        ),
        (
            'Body Contouring / Fat Reduction',
            'Non-invasive body contouring and targeted fat-reduction sessions.',
            60, 500.00, 'Body Contouring Specialist', 5,
            '{"preferred_staff_selectable": false}'::jsonb
        ),
        (
            'Cellulite Treatment',
            'Targeted cellulite-reduction therapy for smoother skin.',
            45, 350.00, 'Skin Care Specialist', 6,
            '{"preferred_staff_selectable": false}'::jsonb
        ),
        (
            'Slimming / Weight Management',
            'Structured slimming programme combining guidance and monitoring.',
            45, 300.00, 'Weight Management Specialist', 7,
            '{"preferred_staff_selectable": false}'::jsonb
        ),
        (
            'Other Services & Packages',
            'Additional treatments and combined packages. Contact the clinic for pricing and availability.',
            60, 0.00, NULL, 8,
            '{"preferred_staff_selectable": false, "price_on_request": true}'::jsonb
        )
    ) AS t(
        name, description, duration_minutes, price,
        assigned_staff_type, sort_order, booking_rules
    ) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.services WHERE lower(name) = lower(rec.name)
        ) THEN
            INSERT INTO public.services (
                name, description, duration_minutes, price,
                currency, active, assigned_staff_type,
                booking_rules, sort_order
            ) VALUES (
                rec.name, rec.description, rec.duration_minutes, rec.price,
                'AED', true, rec.assigned_staff_type,
                rec.booking_rules, rec.sort_order
            );
        END IF;
    END LOOP;
END;
$$;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 2. DEMO STAFF (SRS Â§14)
--    ensure_demo_staff() creates the auth.users row (if missing)
--    -> the handle_new_user trigger creates the profiles row
--    -> then creates the staff row. Returns the staff id.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION public.ensure_demo_staff(
    p_email text,
    p_mobile text,
    p_full_name text,
    p_title text,
    p_specializations text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid           uuid := gen_random_uuid();
    v_email         text := lower(btrim(p_email));
    v_existing      uuid;
    v_identity_tbl  regclass;
    v_profile_id    uuid;
    v_staff_id      uuid;
BEGIN
    -- 2.1 auth.users row (skip if the account already exists)
    SELECT id INTO v_existing FROM auth.users WHERE email = v_email;
    IF v_existing IS NULL THEN
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_uid,
            'authenticated',
            'authenticated',
            v_email,
            crypt('Demo-Staff-2026!', gen_salt('bf')),
            now(),
            '{"provider":"email","providers":["email"]}',
            jsonb_build_object(
                'role', 'staff',
                'full_name', p_full_name,
                'mobile_number', p_mobile
            ),
            now(),
            now()
        )
        ON CONFLICT (email) DO NOTHING;

        -- GoTrue identities (needed for password sign-in on current
        -- Supabase). Tolerates a schema without auth.identities.
        SELECT to_regclass('auth.identities') INTO v_identity_tbl;
        IF v_identity_tbl IS NOT NULL THEN
            INSERT INTO auth.identities (
                id, user_id, provider_id, provider, identity_data,
                last_sign_in_at, created_at, updated_at
            ) VALUES (
                v_uid, v_uid, v_uid, 'email',
                jsonb_build_object(
                    'sub', v_uid,
                    'email', v_email,
                    'email_verified', false,
                    'phone_verified', false
                ),
                now(), now(), now()
            )
            ON CONFLICT (provider_id, provider) DO NOTHING;
        END IF;
    END IF;

    -- 2.2 staff row (created by the on_auth_user_created trigger)
    SELECT id INTO v_profile_id FROM public.profiles WHERE email = v_email;
    IF v_profile_id IS NULL THEN
        RAISE EXCEPTION 'profiles row not created for demo staff %', v_email;
    END IF;

    SELECT id INTO v_staff_id FROM public.staff WHERE profile_id = v_profile_id;
    IF v_staff_id IS NULL THEN
        INSERT INTO public.staff (profile_id, title, specializations)
        VALUES (v_profile_id, p_title, p_specializations)
        RETURNING id INTO v_staff_id;
    END IF;

    RETURN v_staff_id;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_demo_staff(text, text, text, text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_demo_staff(text, text, text, text, text[]) TO postgres;

-- 2.3 seed the three demo staff members (idempotent)
SELECT public.ensure_demo_staff(
    'demo.staff1@theperfectlook.ae', '+971501000001',
    'Dr. Sarah Al-Naimi', 'Dermatologist',
    ARRAY['Skin Care', 'Laser Treatments']
);
SELECT public.ensure_demo_staff(
    'demo.staff2@theperfectlook.ae', '+971501000002',
    'Omar Haddad', 'Laser Technician',
    ARRAY['Laser Hair Removal']
);
SELECT public.ensure_demo_staff(
    'demo.staff3@theperfectlook.ae', '+971501000003',
    'Lina Khoury', 'Nutritionist',
    ARRAY['Clinical Nutrition', 'Weight Management']
);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 3. STAFF WEEKLY AVAILABILITY
--    Monâ€“Sat, 10:00â€“20:00 (T35 default working hours).
--    day_of_week: 0=Sun â€¦ 6=Sat.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.staff_availability (staff_id, day_of_week, start_time, end_time)
SELECT s.id, d.day_of_week, '10:00', '20:00'
FROM public.staff s
CROSS JOIN (SELECT generate_series(1, 6) AS day_of_week) d
WHERE s.id IN (SELECT id FROM public.staff WHERE profile_id IN (
        SELECT id FROM public.profiles WHERE email LIKE 'demo.staff%@theperfectlook.ae'
    ))
ON CONFLICT (staff_id, day_of_week) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 4. APP SETTINGS (read from the DB, never hard-coded â€” SRS Â§12;
--    T35 defaults). Existing values are preserved.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.app_settings (key, value)
VALUES
    -- Clinic working hours: Monâ€“Sat 10:00â€“20:00 (days: 1=Mon â€¦ 6=Sat)
    ('working_hours', '{"start": "10:00", "end": "20:00", "days": [1, 2, 3, 4, 5, 6]}'::jsonb),
    -- Clinic timezone (availability engine converts slot times)
    ('timezone', '"Asia/Dubai"'::jsonb),
    -- Slot grid interval in minutes
    ('slot_interval_minutes', '30'::jsonb),
    -- How far ahead patients can book, in days
    ('booking_window_days', '30'::jsonb),
    -- Cancellation notice period (SRS Â§11)
    ('cancellation_notice_hours', '24'::jsonb),
    -- Rescheduling notice window (SRS Â§11)
    ('reschedule_notice_hours', '24'::jsonb),
    -- Default display currency
    ('currency', '"AED"'::jsonb),
    -- 'visible' = patients see prices; 'contact_us' = hidden (T35)
    ('price_visibility', '"contact_us"'::jsonb),
    -- Whether one booking can hold multiple treatments (T35)
    ('multiple_treatments_per_booking', 'false'::jsonb),
    -- No online payment in MVP (T35 default)
    ('online_payment_enabled', 'false'::jsonb),
    -- Notification channels the clinic wants to use (SRS Â§15)
    ('notification_channels', '["Email"]'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 5. HOLIDAYS (demo placeholders â€” final calendar per T35)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.holidays (date, reason)
VALUES
    ('2026-12-02', 'UAE National Day'),
    ('2026-12-25', 'Christmas Day')
ON CONFLICT (date) DO NOTHING;

-- ============================================================
-- 009_consents_data_requests.sql -- migration 009 (T8, profile & consent API)
-- ============================================================
-- The Perfect Look â€” T8: Profile & consent API support
-- ============================================================
-- Migration: 009_consents_data_requests.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5)
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T8, SRS v1 Â§5.1/Â§12/Â§17
--
-- Responsibilities (T8 acceptance criteria):
--   1. Consent history â€” versioned, timestamped, append-only events
--      per user. The current state is the latest row per
--      (user_id, consent_type). Required service consents (ToS,
--      privacy, health disclaimer) stay separate from the optional
--      marketing consent (SRS Â§5.1).
--   2. Data-request entry point â€” customers file export / correction
--      / deletion / consent-withdrawal requests from their dashboard
--      (SRS Â§12 dashboard, Â§17 compliance).
--   3. Allowed field rules for own-profile PUT â€” a customer may only
--      update their editable fields (full_name, mobile_number, dob,
--      gender, preferred_language). identity/role/system columns are
--      protected server-side by a trigger (SRS Â§17).
--
-- RLS: consents and data_requests are visible only to their owner
-- or staff/admin â€” never to anon (sensitive fields not exposed to
-- public queries).
-- ============================================================

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- ENUMS
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Consent families (SRS Â§5.1 + Â§17 approved wording list).
CREATE TYPE consent_type AS ENUM (
    'terms_of_service',
    'privacy_policy',
    'health_data_disclaimer',
    'nutrition_disclaimer',
    'cancellation_refund_policy',
    'marketing'
);

-- Customer data requests (SRS Â§17: export, correction, deletion,
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TABLES
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Versioned, append-only consent history. One row per grant/revoke
-- event; version + created_at satisfy "records include version and
-- timestamp". Never UPDATE/DELETE a row â€” record a new event instead.
CREATE TABLE public.consents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    consent_type consent_type NOT NULL,
    version      INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
    granted      BOOLEAN NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.consents IS
    'Consent history (SRS Â§5.1/Â§17) â€” immutable, versioned, timestamped events.';

CREATE INDEX idx_consents_user
    ON public.consents (user_id, consent_type, created_at DESC);

-- Customer data requests (SRS Â§12/Â§17).
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
    'Customer data-request queue (SRS Â§12/Â§17) â€” export, correction, deletion, consent withdrawal.';

CREATE INDEX idx_data_requests_user
    ON public.data_requests (user_id, status, created_at DESC);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: allowed field rules for own-profile PUT (SRS Â§7/Â§17)
-- A customer editing their own profile may change only the editable
-- fields: full_name, mobile_number, dob, gender, preferred_language.
-- email / role / id / created_at are immutable from the self-edit
-- path. System-sync writes (auth.users -> profiles trigger, where
-- auth.uid() is NULL) and staff/admin edits pass unchanged.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        RAISE EXCEPTION 'Email cannot be changed here â€” use the account settings flow';
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: consent history is append-only through the API
-- Authenticated API users can never modify/delete a consent row;
-- SQL maintenance (no JWT context, auth.uid() NULL) still works.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

CREATE OR REPLACE FUNCTION public.immutify_consents()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Consent records are immutable â€” record a new consent event instead';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_immutify_consents ON public.consents;

CREATE TRIGGER trg_immutify_consents
    BEFORE UPDATE OR DELETE ON public.consents
    FOR EACH ROW
    EXECUTE FUNCTION public.immutify_consents();

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- ROW LEVEL SECURITY
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER TABLE public.consents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_requests ENABLE ROW LEVEL SECURITY;

-- â”€â”€ consents â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ data_requests â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- ============================================================
-- 010_mobile_normalisation.sql -- migration 010 (T8, E.164 fix)
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T8: E.164 mobile normalisation fix
-- ============================================================
-- Migration: 010_mobile_normalisation.sql
-- Depends on: 002_auth_profiles.sql (T5)
-- Source: T8 "server-side validation"; SRS v1 Â§5.1
--
-- The T5 normaliser (002) mapped a leading-zero local mobile
-- `05XXXXXXXX` to `+97105XXXXXXXX` â€” the leading `0` of the national
-- number was kept, which is NOT valid E.164 (leading zero must be
-- dropped after the country code). The code comments in 002 and in
-- web/src/lib/supabase/validation.ts both state the intent to output
-- `+9715XXXXXXXX`, so this migration corrects the server-side branch
-- to match (kept in sync with the client normaliser).
--
-- End-to-end consistency is preserved: sign-up stores the same
-- E.164 value that sign-in resolves, and the profile PUT normaliser
-- (T8) produces a clean E.164 mobile for the `profiles` row.
-- ============================================================

CREATE OR REPLACE FUNCTION public.normalize_profile_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Lower-case + trim email
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(trim(NEW.email));
    END IF;

    -- Normalise UAE mobile numbers to E.164
    IF NEW.mobile_number IS NOT NULL THEN
        -- Strip separators: spaces, dashes, parentheses, dots
        NEW.mobile_number := regexp_replace(NEW.mobile_number, '[\s\-\(\)\.]', '', 'g');

        -- 0XXXXXXXXX (leading zero, UAE local) -> +971XXXXXXXXX
        IF NEW.mobile_number ~ '^0[5-9]\d{8}$' THEN
            NEW.mobile_number := '+971' || substr(NEW.mobile_number, 2);
        -- 9715XXXXXXXX (no leading +) -> +9715XXXXXXXX
        ELSIF NEW.mobile_number ~ '^971[5-9]\d{8}$' THEN
            NEW.mobile_number := '+' || NEW.mobile_number;
        -- 9-digit local without leading zero (e.g. 55XXXXXXX) -> +9715XXXXXXX
        ELSIF NEW.mobile_number ~ '^[5-9]\d{8}$' THEN
            NEW.mobile_number := '+971' || NEW.mobile_number;
        END IF;

        -- Final guard: must be E.164-ish (+, 1-3 digit country code, 6-14 digits)
        IF NEW.mobile_number !~ '^\+[1-9]\d{6,14}$' THEN
            RAISE EXCEPTION 'Mobile number is not in a valid international format';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- RLS policy functions must be executable by "anon" (see migration 009).
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon;
GRANT EXECUTE ON FUNCTION public.is_staff_or_admin() TO anon;

-- ─────────────────────────────────────────────────────────────
-- T14 — appointment booking API (migration 008)
-- The transactional booking function is public.reserve_slot()
-- (T12, migration 006). This snapshot adds the booking-time payment
-- state the T14 confirmation contract reports.
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS payment_status text
        NOT NULL DEFAULT 'unpaid'
        CHECK (payment_status IN (
            'unpaid',
            'pay_at_clinic',
            'partially_paid',
            'paid',
            'refunded'
        ));

COMMENT ON COLUMN public.appointments.payment_status IS
    'Booking-time payment state (T14). Confirmation reports this; T38 introduces the full payment domain (invoices, provider transitions).';
