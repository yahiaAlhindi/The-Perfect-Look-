-- ============================================================
-- The Perfect Look — Seed Data (T4)
-- ============================================================
-- Migration: 003_seed_data.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T4, SRS v1 §8/§9/§11/§12
--
-- Responsibility: seed the demo clinic configuration so the
-- app works without any hard-coded front-end data:
--   1. 8 services from SRS §8 (active, demo durations/prices).
--   2. 3 demo staff members with weekly availability.
--   3. app_settings (working hours, slot interval, notice
--      periods, currency, price visibility, …) read by the
--      availability engine and admin/booking APIs.
--   4. Demo holidays.
--
-- The whole migration is IDEMPOTENT — safe to re-run. Existing
-- rows are never overwritten (ON CONFLICT DO NOTHING / NOT
-- EXISTS guards), so clinic edits survive a re-apply.
--
-- ⚠ Demo credentials: the staff accounts below use a dev-only
--    default password. Disable or change them before sharing the
--    project (T35 golden rules; see supabase/seed.sql warning).
--
-- Prices/durations are T35 placeholders until the clinic answers.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. SERVICES (SRS §8)
--    Idempotent by exact name. Prices/durations are demo defaults
--    flagged in T35; price_visibility (app_settings) controls
--    whether patients see prices, not the stored value.
-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────
-- 2. DEMO STAFF (SRS §14)
--    ensure_demo_staff() creates the auth.users row (if missing)
--    -> the handle_new_user trigger creates the profiles row
--    -> then creates the staff row. Returns the staff id.
-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────
-- 3. STAFF WEEKLY AVAILABILITY
--    Mon–Sat, 10:00–20:00 (T35 default working hours).
--    day_of_week: 0=Sun … 6=Sat.
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.staff_availability (staff_id, day_of_week, start_time, end_time)
SELECT s.id, d.day_of_week, '10:00', '20:00'
FROM public.staff s
CROSS JOIN (SELECT generate_series(1, 6) AS day_of_week) d
WHERE s.id IN (SELECT id FROM public.staff WHERE profile_id IN (
        SELECT id FROM public.profiles WHERE email LIKE 'demo.staff%@theperfectlook.ae'
    ))
ON CONFLICT (staff_id, day_of_week) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 4. APP SETTINGS (read from the DB, never hard-coded — SRS §12;
--    T35 defaults). Existing values are preserved.
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.app_settings (key, value)
VALUES
    -- Clinic working hours: Mon–Sat 10:00–20:00 (days: 1=Mon … 6=Sat)
    ('working_hours', '{"start": "10:00", "end": "20:00", "days": [1, 2, 3, 4, 5, 6]}'::jsonb),
    -- Clinic timezone (availability engine converts slot times)
    ('timezone', '"Asia/Dubai"'::jsonb),
    -- Slot grid interval in minutes
    ('slot_interval_minutes', '30'::jsonb),
    -- How far ahead patients can book, in days
    ('booking_window_days', '30'::jsonb),
    -- Cancellation notice period (SRS §11)
    ('cancellation_notice_hours', '24'::jsonb),
    -- Rescheduling notice window (SRS §11)
    ('reschedule_notice_hours', '24'::jsonb),
    -- Default display currency
    ('currency', '"AED"'::jsonb),
    -- 'visible' = patients see prices; 'contact_us' = hidden (T35)
    ('price_visibility', '"contact_us"'::jsonb),
    -- Whether one booking can hold multiple treatments (T35)
    ('multiple_treatments_per_booking', 'false'::jsonb),
    -- No online payment in MVP (T35 default)
    ('online_payment_enabled', 'false'::jsonb),
    -- Notification channels the clinic wants to use (SRS §15)
    ('notification_channels', '["Email"]'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 5. HOLIDAYS (demo placeholders — final calendar per T35)
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.holidays (date, reason)
VALUES
    ('2026-12-02', 'UAE National Day'),
    ('2026-12-25', 'Christmas Day')
ON CONFLICT (date) DO NOTHING;