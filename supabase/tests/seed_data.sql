-- ============================================================
-- The Perfect Look — Seed Data acceptance test (T4)
-- ============================================================
-- Verifies (T4 acceptance criteria):
--   1. The 8 SRS §8 services exist, all active, with demo
--      durations/prices.
--   2. app_settings contains working hours, slot interval,
--      cancellation/reschedule notice periods, currency, and the
--      T35 price_visibility default.
--   3. 3 demo staff members exist with a profile and 6 days of
--      weekly availability each.
--   4. Demo holidays are seeded.
--
-- Run after applying migrations 001–003 against the local db:
--   supabase start
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/seed_data.sql
--
-- Or paste into the online Supabase SQL editor (runs as table
-- owner, so RLS is bypassed for the checks). Every assertion
-- prints PASS or raises an error.
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

-- ─────────────────────────────────────────────────────────────
-- 1. SERVICES (SRS §8)
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    (SELECT count(*) FROM public.services
      WHERE name IN (
        'Skin Care Treatment',
        'Advanced Hair Care Solutions',
        'Laser Hair Removal',
        'Clinical Nutrition & Weight Management',
        'Body Contouring / Fat Reduction',
        'Cellulite Treatment',
        'Slimming / Weight Management',
        'Other Services & Packages'
      )) = 8,
    'all 8 SRS §8 services are seeded'
);

SELECT public.expect(
    (SELECT count(*) FROM public.services
      WHERE name IN (
        'Skin Care Treatment',
        'Advanced Hair Care Solutions',
        'Laser Hair Removal',
        'Clinical Nutrition & Weight Management',
        'Body Contouring / Fat Reduction',
        'Cellulite Treatment',
        'Slimming / Weight Management',
        'Other Services & Packages'
      ) AND active = true) = 8,
    'all seeded services are active by default'
);

SELECT public.expect(
    (SELECT count(*) FROM public.services
      WHERE duration_minutes <= 0 OR price < 0) = 0,
    'seeded durations > 0 and prices >= 0'
);

SELECT public.expect(
    (SELECT count(DISTINCT sort_order) FROM public.services
      WHERE name IN (
        'Skin Care Treatment',
        'Advanced Hair Care Solutions',
        'Laser Hair Removal',
        'Clinical Nutrition & Weight Management',
        'Body Contouring / Fat Reduction',
        'Cellulite Treatment',
        'Slimming / Weight Management',
        'Other Services & Packages'
      )) = 8,
    'seeded services have distinct sort_order values'
);

-- ─────────────────────────────────────────────────────────────
-- 2. APP SETTINGS
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    EXISTS (SELECT 1 FROM public.app_settings WHERE key = 'working_hours')
    AND (SELECT value ->> 'start' FROM public.app_settings WHERE key = 'working_hours') = '10:00'
    AND (SELECT value ->> 'end'   FROM public.app_settings WHERE key = 'working_hours') = '20:00'
    AND jsonb_array_length((SELECT value -> 'days' FROM public.app_settings WHERE key = 'working_hours')) = 6,
    'app_settings.working_hours = Mon-Sat 10:00-20:00'
);

SELECT public.expect(
    (SELECT value::int FROM public.app_settings WHERE key = 'slot_interval_minutes') = 30,
    'app_settings.slot_interval_minutes = 30'
);

SELECT public.expect(
    (SELECT value::int FROM public.app_settings WHERE key = 'cancellation_notice_hours') = 24,
    'app_settings.cancellation_notice_hours = 24'
);

SELECT public.expect(
    (SELECT value::int FROM public.app_settings WHERE key = 'reschedule_notice_hours') = 24,
    'app_settings.reschedule_notice_hours = 24'
);

SELECT public.expect(
    (SELECT value #>> '{}' FROM public.app_settings WHERE key = 'currency') = 'AED',
    'app_settings.currency = AED'
);

SELECT public.expect(
    (SELECT value #>> '{}' FROM public.app_settings WHERE key = 'price_visibility') = 'contact_us',
    'app_settings.price_visibility defaults to contact_us (T35)'
);

-- ─────────────────────────────────────────────────────────────
-- 3. DEMO STAFF + WEEKLY AVAILABILITY
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    (SELECT count(*) FROM public.staff s
      JOIN public.profiles p ON p.id = s.profile_id
     WHERE p.email IN (
        'demo.staff1@theperfectlook.ae',
        'demo.staff2@theperfectlook.ae',
        'demo.staff3@theperfectlook.ae'
     ) AND p.role = 'staff') = 3,
    '3 demo staff accounts exist with staff role'
);

SELECT public.expect(
    (SELECT count(*) FROM public.staff_availability sa
      JOIN public.staff s ON s.id = sa.staff_id
      JOIN public.profiles p ON p.id = s.profile_id
     WHERE p.email IN (
        'demo.staff1@theperfectlook.ae',
        'demo.staff2@theperfectlook.ae',
        'demo.staff3@theperfectlook.ae'
     )) = 18,
    'each of 3 demo staff has 6 weekly availability days (18 total)'
);

-- ─────────────────────────────────────────────────────────────
-- 4. HOLIDAYS
-- ─────────────────────────────────────────────────────────────

SELECT public.expect(
    EXISTS (SELECT 1 FROM public.holidays WHERE date = '2026-12-02')
    AND EXISTS (SELECT 1 FROM public.holidays WHERE date = '2026-12-25'),
    'demo holidays are seeded (Dec 2 + Dec 25)'
);

-- ─────────────────────────────────────────────────────────────
-- Cleanup helper, keep data
-- ─────────────────────────────────────────────────────────────

DROP FUNCTION public.expect(boolean, text);

SELECT 'ALL SEED DATA ACCEPTANCE TESTS PASSED' AS result;