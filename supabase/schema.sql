-- ============================================================
-- The Perfect Look - full SQL schema (consolidated)
-- ============================================================
-- supabase/schema.sql = the final database schema for the MVP.
-- This file is the consolidated snapshot of the applied
-- migrations (supabase/migrations/001_schema.sql).
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
