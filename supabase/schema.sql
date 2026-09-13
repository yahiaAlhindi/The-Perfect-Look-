-- ============================================================
-- The Perfect Look - full SQL schema (consolidated)
-- ============================================================
-- supabase/schema.sql = the final database schema for the MVP.
-- This file is the consolidated snapshot of the applied
-- migrations (supabase/migrations/001_schema.sql ... 009_roles_rbac.sql).
-- Keep it in sync with migrations; migrations are the source
-- of truth. See docs/PROJECT_TASKS_BREAKDOWN.md for acceptance
-- criteria (T3, T5, T12, T13, T14, T18, T37).
-- ============================================================
-- ============================================================
-- >>> Migration: 001_schema.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” MVP Database Schema (T3)
-- ============================================================
-- Migration: 001_schema.sql
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T3, SRS v1 Â§10/Â§12/Â§15/Â§17/Â§20
-- Supabase project: online DB = System of Record (SRS Â§12)
-- ============================================================

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- ENUMS
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Appointment statuses â€” values match SRS Â§10 exactly.
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

-- Notification channels â€” SRS Â§15.
CREATE TYPE notification_channel AS ENUM (
    'Email',
    'SMS',
    'WhatsApp'
);

-- Notification delivery state (SRS Â§15: "status should be recorded").
CREATE TYPE notification_status AS ENUM (
    'pending',
    'sent',
    'failed',
    'read'
);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- HELPER FUNCTIONS (RLS) â€” SECURITY DEFINER to avoid recursion
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TABLES
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- profiles â€” synced from auth.users via trigger
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

COMMENT ON TABLE public.profiles IS 'User profiles â€” one row per auth.users entry, synced via trigger.';

-- services â€” bookable treatments offered by the clinic
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

COMMENT ON TABLE public.services IS 'Bookable treatments/services (SRS Â§8).';

-- staff â€” links to profiles; stores role-specific data
CREATE TABLE public.staff (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id       UUID UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    title            TEXT,
    specializations  TEXT[],
    active           BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE public.staff IS 'Staff members linked to a profile (SRS Â§14).';

-- staff_availability â€” weekly recurring availability per staff
CREATE TABLE public.staff_availability (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id    UUID NOT NULL REFERENCES public.staff(id) ON DELETE RESTRICT,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time  TIME NOT NULL,
    end_time    TIME NOT NULL CHECK (end_time > start_time),
    UNIQUE (staff_id, day_of_week)
);

COMMENT ON TABLE public.staff_availability IS 'Recurring weekly availability per staff member (0=Sun â€¦ 6=Sat).';

-- blocked_periods â€” staff-specific or clinic-wide blocks
CREATE TABLE public.blocked_periods (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id       UUID REFERENCES public.staff(id) ON DELETE RESTRICT,
    start_datetime TIMESTAMPTZ NOT NULL,
    end_datetime   TIMESTAMPTZ NOT NULL CHECK (end_datetime > start_datetime),
    reason         TEXT,
    CHECK (staff_id IS NOT NULL OR reason IS NOT NULL)
);

COMMENT ON TABLE public.blocked_periods IS 'Blocked time â€” clinic-wide (staff_id NULL) or per-staff.';

-- holidays â€” clinic-wide non-working days
CREATE TABLE public.holidays (
    id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date   DATE NOT NULL UNIQUE,
    reason TEXT
);

COMMENT ON TABLE public.holidays IS 'Clinic-wide holidays / non-working days.';

-- appointments â€” the core booking table
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

COMMENT ON TABLE public.appointments IS 'Patient appointment bookings (SRS Â§9/Â§11).';

-- notifications â€” per-user notification log
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

COMMENT ON TABLE public.notifications IS 'Notification log â€” channels: Email/SMS/WhatsApp (SRS Â§15).';

-- audit_logs â€” admin action trail
CREATE TABLE public.audit_logs (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID REFERENCES public.profiles(id) ON DELETE RESTRICT,
    action        TEXT NOT NULL,
    entity        TEXT NOT NULL,
    entity_id     UUID,
    details       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_logs IS 'Admin/audit action log (SRS Â§17).';

-- app_settings â€” key/value store for clinic configuration
CREATE TABLE public.app_settings (
    key   TEXT PRIMARY KEY,
    value JSONB NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.app_settings IS 'Global clinic configuration (working hours, slot interval, etc.).';

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- INDEXES
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Appointments: query by patient, service, staff, and time window
CREATE INDEX idx_appointments_patient_id ON public.appointments (patient_id);
CREATE INDEX idx_appointments_service_id ON public.appointments (service_id);
CREATE INDEX idx_appointments_staff_id   ON public.appointments (staff_id);
CREATE INDEX idx_appointments_status     ON public.appointments (status);
CREATE INDEX idx_appointments_scheduled  ON public.appointments (scheduled_start, scheduled_end);

-- Composite: prevent overlapping bookings for the same staff+time
-- (partial â€” excludes Cancelled and No Show)
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: sync auth.users â†’ profiles
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: auto-generate appointment_ref on insert
-- Race-free serial generator (nextval is safe under concurrency).
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: prevent a user from self-escalating their own role
-- (RLS is row-level only â€” column-level checks need a trigger).
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: update last_modified_at on appointment changes
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- ROW LEVEL SECURITY
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER TABLE public.services           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_periods    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holidays           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings       ENABLE ROW LEVEL SECURITY;

-- â”€â”€ profiles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ staff â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ staff_availability â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ blocked_periods â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ holidays â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ appointments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Patients: own appointments only; staff/admin: all (SRS Â§17)
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

-- â”€â”€ notifications â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ audit_logs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Admins only (read + insert); service-role bypasses RLS anyway.
CREATE POLICY audit_logs_select_admin
    ON public.audit_logs FOR SELECT
    USING (public.is_admin());

CREATE POLICY audit_logs_insert_admin
    ON public.audit_logs FOR INSERT
    WITH CHECK (public.is_admin());

-- â”€â”€ app_settings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
-- >>> Migration: 002_auth_profiles.sql <<<
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
-- >>> Migration: 003_seed_data.sql <<<
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
-- >>> Migration: 004_branches_client_number_pricing.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T37: Multi-branch, client-number, and
-- pricing schema extension
-- ============================================================
-- Migration: 004_branches_client_number_pricing.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             003_seed_data.sql (T4)
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T37; SRS v2 Â§5.3/Â§6/Â§7/Â§8.2/Â§15/Â§16/Â§17
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- ENUMS
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- What the services table holds: a single treatment, a bundle of
-- services (package), an add-on, a consultation, or a subscription
-- style offering (SRS Â§7/Â§16).
CREATE TYPE public.service_type AS ENUM (
    'service',
    'package',
    'add_on',
    'consultation',
    'membership'
);

-- Minimal branch-scope level for T37 branch-scoped RLS. T18 extends
-- this into the full staff role model (receptionist, branch manager,
-- provider, nutritionist, finance, administrator, â€¦).
CREATE TYPE public.branch_access_role AS ENUM (
    'viewer',
    'manager'
);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- HELPER FUNCTIONS (branch scope) â€” SECURITY DEFINER to avoid
-- recursion between profiles/branch_access and RLS policies
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- BRANCHES
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

COMMENT ON TABLE public.branches IS 'Clinic branches (SRS Â§6) â€” Dubai, Abu Dhabi, future UAE locations.';

-- Branch working hours â€” weekly recurring open times per branch.
-- Uses the same day_of_week convention as staff_availability
-- (0=Sun â€¦ 6=Sat).
CREATE TABLE public.branch_hours (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id   UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time  TIME NOT NULL,
    end_time    TIME NOT NULL CHECK (end_time > start_time),
    UNIQUE (branch_id, day_of_week)
);

COMMENT ON TABLE public.branch_hours IS 'Recurring weekly working hours per branch (SRS Â§6).';

-- Branch-specific closures (e.g. maintenance, emirate holidays).
-- Clinic-wide non-working days remain in public.holidays.
CREATE TABLE public.branch_closures (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id  UUID NOT NULL REFERENCES public.branches(id) ON DELETE RESTRICT,
    date       DATE NOT NULL,
    reason     TEXT,
    UNIQUE (branch_id, date)
);

COMMENT ON TABLE public.branch_closures IS 'Specific dates a branch is closed (SRS Â§6).';

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

COMMENT ON TABLE public.staff_branches IS 'Staff-to-branch assignments (SRS Â§6) â€” multi-branch staff allowed.';

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- SERVICE-BRANCH AVAILABILITY / PRICING
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

COMMENT ON TABLE public.service_branches IS 'Branch availability + branch prices/duration/buffers for services (SRS Â§6/Â§7).';

CREATE INDEX idx_service_branches_branch ON public.service_branches (branch_id);
CREATE INDEX idx_service_branches_service ON public.service_branches (service_id);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- SERVICES EXTENSIONS (catalogue model)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER TABLE public.services
    ADD COLUMN service_type    public.service_type NOT NULL DEFAULT 'service',
    ADD COLUMN buffer_minutes  INTEGER NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
    ADD COLUMN price_on_request BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.services.service_type IS 'service | package | add_on | consultation | membership (SRS Â§7).';
COMMENT ON COLUMN public.services.buffer_minutes IS 'Default cleanup/buffer between bookings of this service (T11/T12).';
COMMENT ON COLUMN public.services.price_on_request IS 'Explicit price-on-request flag â€” hide price from the public catalogue (SRS Â§7, T11).';

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

COMMENT ON TABLE public.package_items IS 'Package composition â€” included services and quantities (SRS Â§7/Â§16).';

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

COMMENT ON TABLE public.service_addons IS 'Add-ons offered with a base service (SRS Â§7/Â§16).';

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- CLIENT NUMBER (immutable, collision-safe, configurable format)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Single source of number values â€” nextval is race-free and
-- collision-safe under concurrency.
CREATE SEQUENCE IF NOT EXISTS public.client_number_seq START 1;

-- Format is a clinic config (SRS Â§5.3): { "prefix": "TPL", "width": 6 }
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
-- Imports (T25) pass an explicit number instead â€” client_number is
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
-- to assign/correct legacy rows (SRS Â§5.3, T25).
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

-- Authorized staff search across client identity (SRS Â§5.3: searchable).
-- SECURITY DEFINER + internal guard â€” patients cannot enumerate others.
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- APPOINTMENTS EXTENSIONS (branch + price snapshots)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- branch_id is nullable here so existing MVP appointments survive the
-- migration; 005 backfills them to the default branch and tightens the
-- column to NOT NULL. Historical truth is kept via the *_snapshot
-- columns â€” renaming/re-pricing a service never rewrites history.
ALTER TABLE public.appointments
    ADD COLUMN branch_id            UUID REFERENCES public.branches(id) ON DELETE RESTRICT,
    ADD COLUMN client_number        TEXT,
    ADD COLUMN service_name_snapshot TEXT,
    ADD COLUMN price_snapshot       NUMERIC(10,2),
    ADD COLUMN currency_snapshot    TEXT NOT NULL DEFAULT 'AED',
    ADD COLUMN package_id           UUID REFERENCES public.services(id) ON DELETE RESTRICT,
    ADD COLUMN source_channel       TEXT NOT NULL DEFAULT 'web';

COMMENT ON COLUMN public.appointments.branch_id IS 'Branch where the appointment takes place (SRS Â§6/Â§8.2).';
COMMENT ON COLUMN public.appointments.client_number IS 'Snapshot of the patient client number at booking time (SRS Â§8.2).';
COMMENT ON COLUMN public.appointments.price_snapshot IS 'Price charged at booking time â€” immune to later catalogue edits (SRS Â§8.2, T37).';
COMMENT ON COLUMN public.appointments.package_id IS 'Package reference when booked as part of a package (SRS Â§7).';

CREATE INDEX idx_appointments_branch_id ON public.appointments (branch_id);
CREATE INDEX idx_appointments_scheduled_branch ON public.appointments (branch_id, scheduled_start, scheduled_end);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- MIGRATION MAPPINGS (legacy Excel import, T25)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

COMMENT ON TABLE public.migration_mappings IS 'Legacy â†’ target record mapping for the controlled Excel migration (SRS Â§15, T25).';

CREATE INDEX idx_migration_mappings_entity ON public.migration_mappings (entity_type);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- ROW LEVEL SECURITY
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER TABLE public.branches          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_hours      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_closures   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_branches    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_access     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_branches  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_addons    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.migration_mappings ENABLE ROW LEVEL SECURITY;

-- â”€â”€ branches â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ branch_hours â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Hours are public so the availability picker works pre-login;
-- writing is restricted to admins/managers of that branch (SRS Â§6).
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

-- â”€â”€ branch_closures â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ staff_branches â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ branch_access â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ service_branches â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Availability is public. Writes follow branch scope: admin
-- anywhere, branch managers only on their own branch â€” so a
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

-- â”€â”€ package_items / service_addons â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- â”€â”€ migration_mappings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Used exclusively by the T25 import tool (service_role / pg).
CREATE POLICY migration_mappings_select_admin
    ON public.migration_mappings FOR SELECT
    USING (public.is_admin());

CREATE POLICY migration_mappings_insert_admin
    ON public.migration_mappings FOR INSERT
    WITH CHECK (public.is_admin());

-- â”€â”€ appointments (branch scope) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Extend the baseline policy (T3) with branch scope: staff only see
-- the appointments of branches they can access (SRS Â§17). Admins
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- TRIGGER: keep updated_at in sync on mutable new tables
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
-- ============================================================
-- >>> Migration: 005_seed_demo_branches.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T37: Demo branches + backfills
-- ============================================================
-- Migration: 005_seed_demo_branches.sql
-- Depends on: 004_branches_client_number_pricing.sql (T37)
--
-- Responsibility:
--   1. Idempotently seed the demo Dubai and Abu Dhabi branches,
--      their weekly hours, staff assignments, and branch access.
--   2. Make every existing service available at every branch
--      (service_branches), without overriding clinic prices.
--   3. Backfill client numbers for existing patient profiles with a
--      collision-safe generated number.
--   4. Backfill appointment branch + snapshot columns, then tighten
--      branch_id/client_number/service_name_snapshot/price_snapshot
--      to NOT NULL and add the branch FK.
--   5. Add client_number_format and default_branch app_settings.
--
-- Whole migration is IDEMPOTENT and never overwrites clinic edits
-- (ON CONFLICT DO NOTHING / guarded DDL).
--
-- âš  Demo branch details (addresses/phones) are T35 placeholders.
-- ============================================================

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 1. DEMO BRANCHES (Dubai + Abu Dhabi) â€” idempotent by slug
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.branches (name, slug, emirate, city, address, phone, email, timezone, active, sort_order)
SELECT * FROM (VALUES
    (
        'The Perfect Look â€” Dubai',
        'dubai',
        'Dubai',
        'Dubai',
        'Demo: Sheikh Zayed Road, Dubai (T35 placeholder)',
        '+97140000001',
        'dubai@theperfectlook.ae',
        'Asia/Dubai',
        true, 1
    ),
    (
        'The Perfect Look â€” Abu Dhabi',
        'abu-dhabi',
        'Abu Dhabi',
        'Abu Dhabi',
        'Demo: Corniche Road, Abu Dhabi (T35 placeholder)',
        '+97120000002',
        'abudhabi@theperfectlook.ae',
        'Asia/Dubai',
        true, 2
    )
) AS v(name, slug, emirate, city, address, phone, email, timezone, active, sort_order)
ON CONFLICT (slug) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 2. BRANCH HOURS â€” Monâ€“Sat 10:00â€“20:00 (same clinic default as T4),
--    shared by both demo branches
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.branch_hours (branch_id, day_of_week, start_time, end_time)
SELECT b.id, d.day_of_week, '10:00', '20:00'
FROM public.branches b
CROSS JOIN (SELECT generate_series(1, 6) AS day_of_week) d
ON CONFLICT (branch_id, day_of_week) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 3. STAFF-BRANCH ASSIGNMENTS â€” demo staff to their demo branch
--    (Dr Sarah + Omar â†’ Dubai; Lina â†’ Abu Dhabi)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active)
SELECT s.id, b.id, true, true
FROM (VALUES
    ('Dr. Sarah Al-Naimi', 'dubai'),
    ('Omar Haddad',       'dubai'),
    ('Lina Khoury',       'abu-dhabi')
) AS v(full_name, slug)
JOIN public.profiles p ON LOWER(p.full_name) = LOWER(v.full_name)
JOIN public.staff s    ON s.profile_id = p.id
JOIN public.branches b ON b.slug = v.slug
ON CONFLICT (staff_id, branch_id) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 4. BRANCH ACCESS â€” demo staff get manager grants on THEIR demo
--    branch only (drives the branch-scoped RLS acceptance tests).
--    Admins need no rows (public.is_admin() bypasses branch scope).
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.branch_access (profile_id, branch_id, role, active)
SELECT p.id, b.id, 'manager', true
FROM (
    SELECT 'Dr. Sarah Al-Naimi' AS full_name, 'dubai'     AS slug
    UNION ALL SELECT 'Omar Haddad',                      'dubai'
    UNION ALL SELECT 'Lina Khoury',                      'abu-dhabi'
) AS v
JOIN public.profiles p ON LOWER(p.full_name) = LOWER(v.full_name)
JOIN public.branches b ON b.slug = v.slug
ON CONFLICT (profile_id, branch_id) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 5. SERVICE-BRANCH AVAILABILITY â€” every seeded service is
--    available at both demo branches. No price/duration overrides:
--    NULL falls back to the service defaults (clinic edits later).
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.service_branches (service_id, branch_id, available, currency)
SELECT s.id, b.id, true, 'AED'
FROM public.services s
CROSS JOIN public.branches b
ON CONFLICT (service_id, branch_id) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 6. APP SETTINGS â€” client-number format + default branch
--    (existing clinic values are preserved)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

INSERT INTO public.app_settings (key, value)
VALUES
    -- Format is configurable per SRS Â§5.3 (prefix + zero-pad width).
    ('client_number_format', '{"prefix": "TPL", "width": 6}'::jsonb),
    -- Default (legacy/fallback) branch used by backfills and new
    -- legacy appointments until the booking API picks the branch.
    ('default_branch', '{"slug": "dubai"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 7. BACKFILL CLIENT NUMBERS â€” existing patient profiles get a
--    generated, collision-safe number. Runs without an auth context,
--    so the immutability trigger permits it; uniqueness is enforced
--    by idx_profiles_client_number.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

UPDATE public.profiles
SET client_number = public.generate_client_number()
WHERE role = 'patient' AND client_number IS NULL;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 8. BACKFILL APPOINTMENTS â€” branch, client number, and price
--    snapshots, then tighten constraints. Re-running is a no-op.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Branch: default branch for legacy rows with no branch.
UPDATE public.appointments
SET branch_id = (
    SELECT b.id FROM public.branches b
    JOIN public.app_settings s ON s.key = 'default_branch'
    WHERE b.slug = (s.value ->> 'slug')
    LIMIT 1
)
WHERE branch_id IS NULL;

-- Snapshots: preserve historical truth (SRS Â§8.2).
UPDATE public.appointments a
SET client_number          = p.client_number,
    service_name_snapshot  = s.name,
    price_snapshot         = COALESCE(sb.price, s.price),
    currency_snapshot      = COALESCE(sb.currency, s.currency)
FROM public.profiles p
JOIN public.services s   ON s.id = a.service_id
LEFT JOIN public.service_branches sb
       ON sb.service_id = a.service_id AND sb.branch_id = a.branch_id
WHERE p.id = a.patient_id
  AND a.client_number IS NULL;

-- New appointments must always carry a branch and a price snapshot.
-- (The branch FK was created inline in 004 as appointments_branch_id_fkey.)
ALTER TABLE public.appointments
    ALTER COLUMN branch_id             SET NOT NULL,
    ALTER COLUMN client_number         SET NOT NULL,
    ALTER COLUMN service_name_snapshot SET NOT NULL,
    ALTER COLUMN price_snapshot        SET NOT NULL;

-- NOTE: profiles.client_number stays NULLABLE â€” numbers are only
-- generated for customer (patient) accounts (SRS Â§5.3). Staff and
-- admin profiles legitimately have no client number; the
-- appointment/backfill logic snapshots the patient's number instead.
-- ============================================================
-- >>> Migration: 006_availability_engine.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T12: Branch-aware availability engine
-- ============================================================
-- Migration: 006_availability_engine.sql
-- Depends on: 001â€“005 (T3/T5/T4/T37)
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T12; SRS v2 Â§6/Â§8
--
-- Responsibilities:
--   1. Branch capacity (branches.max_concurrent_appointments) â€”
--      NULL means unlimited. Used by both slot generation and
--      reservation.
--   2. Per-appointment buffer snapshot (appointments.buffer_minutes):
--      conflicts are computed against the buffer that applied at
--      booking time, so later catalogue edits never rewrite history.
--   3. DB-level overlap boundary: a partial EXCLUDE constraint on
--      appointments makes overlapping active bookings for the same
--      staff impossible at the database, REGARDLESS of branch
--      (staff working at two branches cannot be double-booked) and
--      REGARDLESS of the channel that inserts (web, staff, import).
--      Together with the T3 unique index on (staff_id,
--      scheduled_start) this is the core concurrency boundary:
--      parallel requests for one slot produce exactly one success.
--   4. PUBLIC functions:
--      - public.get_availability(...) â€” generates slots for a
--        branch+service+date range, in branch time (Asia/Dubai),
--        from branch hours, service duration/buffers, provider
--        schedules, leave/blocks, holidays, closures, capacity and
--        existing appointments. Every query is scoped by branch and
--        converted through the branch timezone.
--      - public.reserve_slot(...) â€” atomic, branch-aware booking:
--        re-validates the whole availability stack server-side then
--        inserts the appointment with price/client-number snapshots.
--        Advisory locks on the provider and branch serialise
--        concurrent requests so exactly one overlapping booking for
--        a slot can succeed.
--
-- Every function returns/includes the branch and its timezone, and
-- the database works entirely in Asia/Dubai wall time for slot math
-- (the SRS mandates Asia/Dubai for all appointment times, Â§8.2).
-- ============================================================

-- GIST operator classes for the btree `=` opclass on uuid (btree_gist)
-- enable the `&&` range overlap exclusion constraint below.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 1. BRANCH CAPACITY
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ALTER TABLE public.branches
    ADD COLUMN IF NOT EXISTS max_concurrent_appointments INTEGER
        CHECK (max_concurrent_appointments IS NULL OR max_concurrent_appointments > 0);

COMMENT ON COLUMN public.branches.max_concurrent_appointments
    IS 'Branch capacity â€” max concurrent active appointments (NULL = unlimited). Slot engine + booking enforce this. T12.';

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 2. APPOINTMENT BUFFER SNAPSHOT
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Snapshot of the buffer in effect at booking time so future buffer
-- edits do not retroactively widen conflicts (same rationale as the
-- T37 price snapshot, SRS Â§8.2).
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS buffer_minutes INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.appointments.buffer_minutes
    IS 'Buffer snapshot at booking time â€” availability conflicts computed against this. T12.';

-- Backfill existing rows from the current service/branch default.
UPDATE public.appointments a
   SET buffer_minutes = COALESCE(sb.buffer_minutes, s.buffer_minutes, 0)
  FROM public.services s
  LEFT JOIN public.service_branches sb
         ON sb.service_id = s.id AND sb.branch_id = a.branch_id
 WHERE s.id = a.service_id;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 3. OVERLAP EXCLUSION CONSTRAINT (concurrency boundary)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- A staff member can never have two OVERLAPPING active bookings,
-- even at different branches and even with different scheduled_start
-- values (the T3 unique index only pins the exact start instant).
-- The constraint applies to any insert path â€” including direct
-- table writes that bypass the booking function.

-- Refuse to add the boundary while overlapping historical rows exist
-- (operator must resolve them first â€” e.g. after importing messy data).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM public.appointments a1
          JOIN public.appointments a2
            ON a1.staff_id = a2.staff_id
           AND a1.id <> a2.id
           AND a1.status NOT IN ('Cancelled', 'No Show')
           AND a2.status NOT IN ('Cancelled', 'No Show')
           AND tstzrange(a1.scheduled_start, a1.scheduled_end)
                 && tstzrange(a2.scheduled_start, a2.scheduled_end)
    ) THEN
        RAISE EXCEPTION
            'Cannot add appt_no_overlapping_staff: overlapping active bookings exist â€” resolve them first';
    END IF;
END;
$$;

ALTER TABLE public.appointments
    DROP CONSTRAINT IF EXISTS appt_no_overlapping_staff;

ALTER TABLE public.appointments
    ADD CONSTRAINT appt_no_overlapping_staff
    EXCLUDE USING gist (
        staff_id WITH =,
        tstzrange(scheduled_start, scheduled_end) WITH &&
    )
    WHERE (staff_id IS NOT NULL AND status NOT IN ('Cancelled', 'No Show'));

COMMENT ON CONSTRAINT appt_no_overlapping_staff ON public.appointments
    IS 'T12: no overlapping active bookings per staff across ALL branches â€” the DB-level concurrency boundary.';

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 4. INTERNAL SETTING READER
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Reads a scalar JSON value from app_settings ("30"/"Asia/Dubai") with
-- a fallback. Internal use by the availability functions (not exposed
-- through PostgREST).
CREATE OR REPLACE FUNCTION public.availability_setting_text(p_key text, p_default text DEFAULT NULL)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT COALESCE((SELECT s.value #>> '{}' FROM public.app_settings s WHERE s.key = p_key), p_default);
$$;

REVOKE ALL ON FUNCTION public.availability_setting_text(text, text) FROM PUBLIC;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 5. SLOT GENERATION â€” public.get_availability
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- SECURITY DEFINER: the engine must read every patient's active
-- appointments to compute conflicts (RLS would otherwise hide the
-- bookings of other patients from a patient caller). It only ever
-- returns generated slot rows â€” no patient data leaks.

CREATE OR REPLACE FUNCTION public.get_availability(
    p_branch_id  uuid,
    p_service_id uuid,
    p_from       date,
    p_to         date,
    p_staff_id   uuid DEFAULT NULL
)
RETURNS TABLE (
    branch_id        uuid,
    branch_name      text,
    timezone         text,
    slot_date        date,
    slot_start       timestamptz,
    slot_end         timestamptz,
    provider_id      uuid,
    provider_name    text,
    service_id       uuid,
    service_name     text,
    duration_minutes integer,
    buffer_minutes   integer,
    price            numeric,
    currency         text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_branch_name text;
    v_tz          text;
    v_capacity    integer;
    v_service_name text;
    v_duration    integer;
    v_buffer      integer;
    v_price       numeric;
    v_currency    text;
    v_slot_step   integer := 30;
    v_window_days integer := 30;
    v_wh          jsonb := '{}'::jsonb;
    v_day         date;
    v_dow         integer;
    v_open_time   time;
    v_close_time  time;
    v_open_local  timestamp;
    v_close_local timestamp;
    v_av_open_time time;
    v_av_close_time time;
    v_av_open_local timestamp;
    v_av_close_local timestamp;
    v_eff_open    timestamp;
    v_eff_close   timestamp;
    v_dur_iv      interval;
    v_step_iv     interval;
    v_buf_iv      interval;
    v_t           timestamp;
    v_start       timestamptz;
    v_end         timestamptz;
    v_end_buf     timestamptz;
    v_now_local   date;
    v_win_end     timestamptz;
    r_staff       record;
BEGIN
    IF p_from > p_to THEN
        RETURN;
    END IF;

    -- Branch + timezone (branch-aware by construction).
    SELECT b.name, b.timezone, b.max_concurrent_appointments
      INTO v_branch_name, v_tz, v_capacity
      FROM public.branches b
     WHERE b.id = p_branch_id AND b.active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch not found or inactive';
    END IF;

    -- Service effective rules at the branch (T37 service_branches override).
    SELECT s.name,
           COALESCE(sb.duration_minutes, s.duration_minutes),
           COALESCE(sb.buffer_minutes, s.buffer_minutes),
           COALESCE(sb.price, s.price),
           COALESCE(sb.currency, s.currency)
      INTO v_service_name, v_duration, v_buffer, v_price, v_currency
      FROM public.services s
      JOIN public.service_branches sb
        ON sb.service_id = s.id AND sb.branch_id = p_branch_id
     WHERE s.id = p_service_id AND s.active AND sb.available;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service is not available at this branch';
    END IF;

    v_slot_step   := COALESCE(public.availability_setting_text('slot_interval_minutes', '30')::int, 30);
    v_window_days := COALESCE(public.availability_setting_text('booking_window_days', '30')::int, 30);
    v_wh          := COALESCE((SELECT value FROM public.app_settings WHERE key = 'working_hours'), '{}'::jsonb);

    v_dur_iv  := make_interval(mins => v_duration);
    v_step_iv := make_interval(mins => v_slot_step);
    v_buf_iv  := make_interval(mins => v_buffer);

    v_now_local := (now() AT TIME ZONE v_tz)::date;
    v_win_end   := now() + make_interval(days => v_window_days);

    v_day := p_from;
    WHILE v_day <= p_to LOOP
        v_dow := EXTRACT(DOW FROM v_day)::int; -- 0=Sun â€¦ 6=Sat

        -- Holiday / branch closure â†’ the whole day is unavailable.
        IF EXISTS (SELECT 1 FROM public.holidays h WHERE h.date = v_day)
           OR EXISTS (SELECT 1 FROM public.branch_closures c
                       WHERE c.branch_id = p_branch_id AND c.date = v_day) THEN
            v_day := v_day + 1;
            CONTINUE;
        END IF;

        -- Opening hours: branch_hours first, clinic default fallback.
        v_open_time := NULL;
        v_close_time := NULL;
        SELECT start_time, end_time
          INTO v_open_time, v_close_time
          FROM public.branch_hours
         WHERE branch_id = p_branch_id AND day_of_week = v_dow;

        IF v_open_time IS NULL THEN
            SELECT (v_wh #>> '{start}')::time, (v_wh #>> '{end}')::time
              INTO v_open_time, v_close_time
             WHERE EXISTS (
                 SELECT 1 FROM jsonb_array_elements_text(v_wh -> 'days') d
                 WHERE (d::int) = v_dow
             );
        END IF;

        IF v_open_time IS NULL THEN
            v_day := v_day + 1; -- closed this day
            CONTINUE;
        END IF;

        v_open_local  := v_day + v_open_time;
        v_close_local := v_day + v_close_time;

        -- Eligible providers at this branch (optional filter by p_staff_id).
        FOR r_staff IN
            SELECT st.id AS staff_id, pr.full_name AS provider_name
              FROM public.staff st
              JOIN public.staff_branches sb
                ON sb.staff_id = st.id AND sb.branch_id = p_branch_id AND sb.active
              JOIN public.profiles pr ON pr.id = st.profile_id
             WHERE st.active
               AND (p_staff_id IS NULL OR st.id = p_staff_id)
        LOOP
            -- Provider weekly schedule.
            v_av_open_time := NULL;
            v_av_close_time := NULL;
            SELECT start_time, end_time
              INTO v_av_open_time, v_av_close_time
              FROM public.staff_availability
             WHERE staff_id = r_staff.staff_id AND day_of_week = v_dow;

            IF v_av_open_time IS NULL THEN
                CONTINUE; -- provider off this day
            END IF;

            v_av_open_local  := v_day + v_av_open_time;
            v_av_close_local := v_day + v_av_close_time;

            -- Active window = overlap of branch hours and provider hours.
            v_eff_open  := GREATEST(v_open_local, v_av_open_local);
            v_eff_close := LEAST(v_close_local, v_av_close_local);

            IF v_eff_open + v_dur_iv > v_eff_close THEN
                CONTINUE; -- provider can't fit the service this day
            END IF;

            -- Walk the slot grid in branch-local wall time.
            v_t := v_eff_open;
            WHILE v_t + v_dur_iv <= v_eff_close LOOP
                v_start   := v_t AT TIME ZONE v_tz;
                v_end     := v_start + v_dur_iv;
                v_end_buf := v_end + v_buf_iv;

                -- Not in the past, within the booking window.
                IF v_start <= now() OR v_start > v_win_end THEN
                    v_t := v_t + v_step_iv;
                    CONTINUE;
                END IF;

                -- Blocked periods (clinic-wide or this provider).
                IF EXISTS (
                    SELECT 1 FROM public.blocked_periods bp
                     WHERE (bp.staff_id IS NULL OR bp.staff_id = r_staff.staff_id)
                       AND v_start < bp.end_datetime
                       AND v_end_buf > bp.start_datetime
                ) THEN
                    v_t := v_t + v_step_iv;
                    CONTINUE;
                END IF;

                -- Existing appointments for this provider across ALL
                -- branches (multi-branch providers cannot overlap).
                IF EXISTS (
                    SELECT 1 FROM public.appointments a
                     WHERE a.staff_id = r_staff.staff_id
                       AND a.status NOT IN ('Cancelled', 'No Show')
                       AND v_start < (a.scheduled_end + make_interval(mins => a.buffer_minutes))
                       AND v_end_buf > a.scheduled_start
                ) THEN
                    v_t := v_t + v_step_iv;
                    CONTINUE;
                END IF;

                -- Branch capacity (concurrent active bookings).
                IF v_capacity IS NOT NULL
                   AND (SELECT count(*)
                          FROM public.appointments a
                         WHERE a.branch_id = p_branch_id
                           AND a.status NOT IN ('Cancelled', 'No Show')
                           AND v_start < (a.scheduled_end + make_interval(mins => a.buffer_minutes))
                           AND v_end_buf > a.scheduled_start) >= v_capacity THEN
                    v_t := v_t + v_step_iv;
                    CONTINUE;
                END IF;

                RETURN QUERY SELECT
                    p_branch_id, v_branch_name, v_tz, v_day, v_start, v_end,
                    r_staff.staff_id, r_staff.provider_name,
                    p_service_id, v_service_name,
                    v_duration, v_buffer, v_price, v_currency;

                v_t := v_t + v_step_iv;
            END LOOP;
        END LOOP;

        v_day := v_day + 1;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.get_availability(uuid, uuid, date, date, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_availability(uuid, uuid, date, date, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_availability(uuid, uuid, date, date, uuid) TO authenticated;

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 6. ATOMIC RESERVATION â€” public.reserve_slot
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- The concurrency boundary for every channel. Re-checks the full
-- availability stack inside one transaction, serialised per provider
-- and per branch with advisory locks (READ COMMITTED: each statement
-- after acquiring the lock takes a fresh snapshot, so a waiter sees
-- the winner's committed booking and rejects the slot). Raw inserts
-- that bypass this function are still stopped by the EXCLUDE
-- constraint in Â§3.
--
-- Caller checks:
--   * anon JWTs can never book.
--   * a signed-in user may book only for themselves unless staff/admin.
--   * server/import context (no JWT) is allowed (used by tools/T14).

CREATE OR REPLACE FUNCTION public.reserve_slot(
    p_branch_id      uuid,
    p_service_id     uuid,
    p_patient_id     uuid,
    p_start          timestamptz,
    p_staff_id       uuid DEFAULT NULL,
    p_notes          text DEFAULT NULL,
    p_source_channel text DEFAULT 'web'
)
RETURNS public.appointments
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role          text;
    v_tz            text;
    v_capacity      integer;
    v_open_time     time;
    v_close_time    time;
    v_wh            jsonb := '{}'::jsonb;
    v_av_open_time  time;
    v_av_close_time time;
    v_service_name  text;
    v_duration      integer;
    v_buffer        integer;
    v_price         numeric;
    v_currency      text;
    v_provider_name text;
    v_slot_end      timestamptz;
    v_local_date    date;
    v_dow           integer;
    v_start_local   timestamp;
    v_end_local     timestamp;
    v_open_local    timestamp;
    v_close_local   timestamp;
    v_av_open_local timestamp;
    v_av_close_local timestamp;
    v_grid_origin   timestamp;
    v_slot_step     integer := 30;
    v_window_days   integer := 30;
    v_win_end       timestamptz;
    v_dur_iv        interval;
    v_buf_iv        interval;
    v_busy_count    integer;
    v_client_number text;
    v_appt          public.appointments;
BEGIN
    -- Authorization gate.
    v_role := COALESCE(auth.jwt() ->> 'role', ''); -- '' = server/import context
    IF v_role = 'anon' THEN
        RAISE EXCEPTION 'Booking requires a signed-in customer or staff account';
    END IF;
    IF auth.uid() IS NOT NULL
       AND NOT (p_patient_id = auth.uid() OR public.is_staff_or_admin()) THEN
        RAISE EXCEPTION 'Cannot book an appointment for another customer';
    END IF;

    -- Branch + timezone.
    SELECT b.timezone, b.max_concurrent_appointments
      INTO v_tz, v_capacity
      FROM public.branches b
     WHERE b.id = p_branch_id AND b.active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch not found or inactive';
    END IF;

    -- Service effective rules at the branch.
    SELECT s.name,
           COALESCE(sb.duration_minutes, s.duration_minutes),
           COALESCE(sb.buffer_minutes, s.buffer_minutes),
           COALESCE(sb.price, s.price),
           COALESCE(sb.currency, s.currency)
      INTO v_service_name, v_duration, v_buffer, v_price, v_currency
      FROM public.services s
      JOIN public.service_branches sb
        ON sb.service_id = s.id AND sb.branch_id = p_branch_id
     WHERE s.id = p_service_id AND s.active AND sb.available;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Service is not available at this branch';
    END IF;

    -- Provider must exist, be active and work at this branch.
    IF p_staff_id IS NULL THEN
        RAISE EXCEPTION 'This service requires a selected provider';
    END IF;
    SELECT pr.full_name
      INTO v_provider_name
      FROM public.staff st
      JOIN public.staff_branches sb
        ON sb.staff_id = st.id AND sb.branch_id = p_branch_id AND sb.active
      JOIN public.profiles pr ON pr.id = st.profile_id
     WHERE st.id = p_staff_id AND st.active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Selected provider does not work at this branch';
    END IF;

    v_slot_step   := COALESCE(public.availability_setting_text('slot_interval_minutes', '30')::int, 30);
    v_window_days := COALESCE(public.availability_setting_text('booking_window_days', '30')::int, 30);

    v_dur_iv := make_interval(mins => v_duration);
    v_buf_iv := make_interval(mins => v_buffer);
    v_slot_end := p_start + v_dur_iv;
    v_win_end  := now() + make_interval(days => v_window_days);

    -- Serialise concurrent reservations for this provider (any branch,
    -- so a provider at two branches can't be double-booked) and for
    -- this branch (capacity of different-provider bookings).
    PERFORM pg_advisory_xact_lock(hashtextextended(p_staff_id::text, 0));
    PERFORM pg_advisory_xact_lock(hashtextextended(p_branch_id::text, 0));

    -- Time window sanity (compare absolute instants).
    IF p_start <= now() THEN
        RAISE EXCEPTION 'This timeslot is in the past';
    END IF;
    IF p_start > v_win_end THEN
        RAISE EXCEPTION 'This timeslot is outside the booking window';
    END IF;

    -- Day-level availability in branch wall time (Asia/Dubai).
    v_local_date := (p_start AT TIME ZONE v_tz)::date;
    v_dow        := EXTRACT(DOW FROM v_local_date)::int;

    v_wh := COALESCE((SELECT value FROM public.app_settings WHERE key = 'working_hours'), '{}'::jsonb);

    IF EXISTS (SELECT 1 FROM public.holidays h WHERE h.date = v_local_date)
       OR EXISTS (SELECT 1 FROM public.branch_closures c
                   WHERE c.branch_id = p_branch_id AND c.date = v_local_date) THEN
        RAISE EXCEPTION 'This day is a holiday or the branch is closed';
    END IF;

    -- Branch opening hours.
    v_open_time := NULL;
    v_close_time := NULL;
    SELECT start_time, end_time
      INTO v_open_time, v_close_time
      FROM public.branch_hours
     WHERE branch_id = p_branch_id AND day_of_week = v_dow;

    IF v_open_time IS NULL THEN
        SELECT (v_wh #>> '{start}')::time, (v_wh #>> '{end}')::time
          INTO v_open_time, v_close_time
         WHERE EXISTS (
             SELECT 1 FROM jsonb_array_elements_text(v_wh -> 'days') d
             WHERE (d::int) = v_dow
         );
    END IF;

    IF v_open_time IS NULL THEN
        RAISE EXCEPTION 'The branch is closed on this day';
    END IF;

    v_start_local := p_start AT TIME ZONE v_tz;
    v_end_local   := v_slot_end AT TIME ZONE v_tz;
    v_open_local  := v_local_date + v_open_time;
    v_close_local := v_local_date + v_close_time;

    IF v_start_local < v_open_local OR v_end_local > v_close_local THEN
        RAISE EXCEPTION 'This timeslot is outside the branch opening hours';
    END IF;

    -- Provider weekly schedule.
    v_av_open_time := NULL;
    v_av_close_time := NULL;
    SELECT start_time, end_time
      INTO v_av_open_time, v_av_close_time
      FROM public.staff_availability
     WHERE staff_id = p_staff_id AND day_of_week = v_dow;

    IF v_av_open_time IS NULL THEN
        RAISE EXCEPTION 'The provider is not available at this time';
    END IF;

    v_av_open_local  := v_local_date + v_av_open_time;
    v_av_close_local := v_local_date + v_av_close_time;

    IF v_start_local < v_av_open_local OR v_end_local > v_av_close_local THEN
        RAISE EXCEPTION 'This timeslot is outside the provider working hours';
    END IF;

    -- The engine grid is anchored at the effective window start and
    -- stepped by slot_interval_minutes â€” reject off-grid timestamps.
    v_grid_origin := GREATEST(v_open_local, v_av_open_local);
    IF v_start_local < v_grid_origin
       OR (EXTRACT(EPOCH FROM (v_start_local - v_grid_origin)) / 60)::int % v_slot_step <> 0 THEN
        RAISE EXCEPTION 'This timeslot is not aligned to the booking grid';
    END IF;

    -- Blocked periods (clinic-wide or this provider).
    IF EXISTS (
        SELECT 1 FROM public.blocked_periods bp
         WHERE (bp.staff_id IS NULL OR bp.staff_id = p_staff_id)
           AND p_start < bp.end_datetime
           AND v_slot_end + v_buf_iv > bp.start_datetime
    ) THEN
        RAISE EXCEPTION 'This timeslot falls within a blocked period';
    END IF;

    -- Provider double-booking across ALL branches (incl. buffers).
    IF EXISTS (
        SELECT 1 FROM public.appointments a
         WHERE a.staff_id = p_staff_id
           AND a.status NOT IN ('Cancelled', 'No Show')
           AND p_start < (a.scheduled_end + make_interval(mins => a.buffer_minutes))
           AND v_slot_end + v_buf_iv > a.scheduled_start
    ) THEN
        RAISE EXCEPTION 'The selected timeslot is not available anymore';
    END IF;

    -- Branch capacity.
    IF v_capacity IS NOT NULL THEN
        SELECT count(*) INTO v_busy_count
          FROM public.appointments a
         WHERE a.branch_id = p_branch_id
           AND a.status NOT IN ('Cancelled', 'No Show')
           AND p_start < (a.scheduled_end + make_interval(mins => a.buffer_minutes))
           AND v_slot_end + v_buf_iv > a.scheduled_start;
        IF v_busy_count >= v_capacity THEN
            RAISE EXCEPTION 'The selected timeslot is not available anymore';
        END IF;
    END IF;

    -- Customer identity snapshot.
    SELECT client_number INTO v_client_number
      FROM public.profiles
     WHERE id = p_patient_id;
    IF v_client_number IS NULL THEN
        RAISE EXCEPTION 'Customer record not found';
    END IF;

    -- Insert with price/identity snapshots (trigger fills appointment_ref).
    INSERT INTO public.appointments (
        patient_id, service_id, branch_id, staff_id,
        scheduled_start, scheduled_end, status, notes,
        client_number, service_name_snapshot, price_snapshot,
        currency_snapshot, source_channel, buffer_minutes
    ) VALUES (
        p_patient_id, p_service_id, p_branch_id, p_staff_id,
        p_start, v_slot_end, 'Pending', p_notes,
        v_client_number, v_service_name, v_price,
        v_currency, COALESCE(NULLIF(p_source_channel, ''), 'web'), v_buffer
    )
    RETURNING * INTO v_appt;

    RETURN v_appt;

    -- A concurrent winner on the same/overlapping slot is caught by the
    -- EXCLUDE constraint or the T3 unique index â†’ surface a stable error.
    EXCEPTION WHEN exclusion_violation OR unique_violation THEN
        RAISE EXCEPTION 'The selected timeslot is not available anymore';
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_slot(uuid, uuid, uuid, timestamptz, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_slot(uuid, uuid, uuid, timestamptz, uuid, text, text) TO authenticated;
-- ============================================================
-- >>> Migration: 007_branch_providers.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T13: Branch provider list for the picker
-- ============================================================
-- Migration: 007_branch_providers.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             004_branches_client_number_pricing.sql (T37),
--             006_availability_engine.sql (T12, merged as PR #10)
--
-- get_branch_providers() lists the active staff assigned to a branch
-- (primary first). The availability picker (T13) uses it for the
-- optional "choose a provider" step, and feeds the chosen id to
-- get_availability(p_staff_id := ...).
--
-- The function is SECURITY DEFINER because it reads past the public
-- profiles/staff RLS: it exposes only the summary fields the picker
-- needs â€” no PII beyond the staff display name.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_branch_providers(p_branch_id uuid)
RETURNS TABLE (
    id             uuid,
    full_name      text,
    title          text,
    specializations text[],
    active         boolean,
    primary_branch boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT s.id,
           p.full_name,
           s.title,
           s.specializations,
           s.active,
           sb.primary_branch
      FROM public.staff s
      JOIN public.profiles p       ON p.id = s.profile_id
      JOIN public.staff_branches sb
        ON sb.staff_id = s.id
       AND sb.branch_id = p_branch_id
       AND sb.active
     WHERE s.active = true
     ORDER BY sb.primary_branch DESC, p.full_name;
$$;

REVOKE ALL ON FUNCTION public.get_branch_providers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_branch_providers(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.get_branch_providers(uuid) TO authenticated;
-- ============================================================
-- >>> Migration: 008_appointment_booking_api.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T14: Appointment booking API
-- ============================================================
-- Migration: 008_appointment_booking_api.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             004/005 (T37), 006_availability_engine.sql (T12)
--
-- The transactional booking API itself is public.reserve_slot()
-- (migration 006, T12): it re-checks branch, price, service,
-- provider, slot, grid alignment, notice/booking window, capacity,
-- blocked periods, and customer identity server-side inside one
-- atomic statement, then inserts with client-number / price / buffer
-- snapshots and returns the full appointment confirmation record
-- (appointment ID, client number, branch, service, time).
--
-- This migration supplies the ONE piece of the T14 confirmation
-- contract that 006 did not yet store: payment status (T14
-- acceptance criterion: "confirmation data includes ... payment
-- status"). Payment is initially unpaid / pay-at-clinic; T38 owns
-- the full payment domain (invoices, provider webhook transitions)
-- and replaces this minimal status.
-- ============================================================

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
-- ============================================================
-- >>> Migration: 009_roles_rbac.sql <<<
-- ============================================================
-- ============================================================
-- The Perfect Look â€” T18: Roles, invitations & branch-scoped RBAC
-- ============================================================
-- Migration: 009_roles_rbac.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             003_seed_data.sql (T4),
--             004_branches_client_number_pricing.sql (T37),
--             005_seed_demo_branches.sql (T37),
--             006_availability_engine.sql (T12),
--             007_branch_providers.sql (T13),
--             008_appointment_booking_api.sql (T14)
-- Source: PROJECT_TASKS_BREAKDOWN.md Â§T18; SRS v1 Â§3/Â§17
--
-- T37 seeded branch-scoped RLS on a minimal viewer/manager grant.
-- T18 extends it into the full 8-value staff role model:
--
-- Responsibilities:
--   1. Migrate user_role from the T3 3-value enum
--      (patient/staff/admin) to the SRS Â§3 8-value enum:
--      customer, receptionist, branch_manager, provider,
--      nutritionist, finance, administrator, super_admin.
--      Legacy mapping: patient â†’ customer, admin â†’ administrator,
--      staff â†’ provider (then refined by staff title:
--      %nutrition% â†’ nutritionist, %reception% â†’ receptionist).
--   2. Redeclare the T3 helpers against the new enum
--      (is_admin, is_staff_or_admin) â€” every existing RLS policy
--      that references them inherits the new semantics.
--   3. Harden role assignment:
--      - handle_new_user() never trusts metadata role for public
--        sign-ups. Role from metadata is honoured ONLY while the
--        session sets app.rbac_role_change_authorized ('seed',
--        'accept_invitation', 'admin_set_user_role', tests).
--      - prevent_self_role_change() becomes the single role-change
--        guard: any role mutation requires the same flag.
--      - super_admin can only be granted by a super_admin.
--   4. Staff invitation flow (SRS Â§3/Â§17):
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
-- Apply once via Supabase CLI. Not idempotent by design â€” the enum
-- swap is apply-once DDL; 005-style guards do not apply here.
-- ============================================================

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 0. SESSION FLAG â€” this migration is an authorized role pathway:
--    every role mutation inside runs under it. (Migrations run as
--    the DB owner; the guard trigger below still fires, so the flag
--    must be visible for the whole file.)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

SELECT set_config('app.rbac_role_change_authorized', 'true', false);

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 1. ENUM SWAP â€” user_role 3 values â†’ 8 (SRS Â§3)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
-- staff title (SRS Â§3: nutritionist, receptionist). Guarded by the
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 2. ROLE-SCOPED CAPABILITY HELPERS (SRS Â§3/Â§17)
--    SECURITY DEFINER to avoid RLS recursion; auth.uid() still
--    resolves from the caller's JWT inside SECURITY DEFINER.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 3. REDECLARE THE T3 HELPERS AGAINST THE NEW ENUM
--    Every existing RLS policy calls these â€” they inherit the new
--    role semantics without any policy rewrite.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 4. HARDEN ROLE ASSIGNMENT (SRS Â§17)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- handle_new_user(): public sign-ups ALWAYS become 'customer'.
-- A metadata role is honoured only when the session is explicitly
-- authorized (seed, accept_invitation handled elsewhere, tests) â€”
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
--   * role unchanged                       â†’ allowed
--   * role changed + session authorized    â†’ allowed (super_admin
--     grant still requires a super_admin caller)
--   * role changed + NOT authorized        â†’ blocked (self or not)
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 5. FIX LEGACY 'patient' REFERENCES (runtime code only â€” the
--    old role literal no longer exists after the enum swap)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- search_clients(): staff search is scoped to customers (SRS Â§5.3).
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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 6. MODULE GATES (T18 acceptance: role-scoped data access)
--    Payments (T21) and nutrition (T22) modules rely on these;
--    they are defined now so no client-side trust is needed later.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 7. ENFORCED GUARDS (raise 42501 â†’ PostgREST FORBIDDEN)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 8. AUDIT LOG (SRS Â§17) + RLS
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
-- self-audit model â€” authenticated staff log their own actions.
-- The frontend writeAuditLog() includes admin_user_id = the current
-- user so this policy accepts it.
DROP POLICY IF EXISTS audit_logs_insert_admin ON public.audit_logs;

CREATE POLICY audit_logs_insert_self
    ON public.audit_logs FOR INSERT
    WITH CHECK (
        admin_user_id = auth.uid()
        AND public.is_staff_or_admin()
    );

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 9. STAFF INVITATIONS (SRS Â§3/Â§17)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 10. INVITATION RPCs
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 11. GRANTS â€” role helpers for the frontend
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- 12. DROP THE SESSION FLAG
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

RESET app.rbac_role_change_authorized;