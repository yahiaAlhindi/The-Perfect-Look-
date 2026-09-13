-- ============================================================
-- The Perfect Look — T37: Demo branches + backfills
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
-- ⚠ Demo branch details (addresses/phones) are T35 placeholders.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. DEMO BRANCHES (Dubai + Abu Dhabi) — idempotent by slug
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.branches (name, slug, emirate, city, address, phone, email, timezone, active, sort_order)
SELECT * FROM (VALUES
    (
        'The Perfect Look — Dubai',
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
        'The Perfect Look — Abu Dhabi',
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

-- ─────────────────────────────────────────────────────────────
-- 2. BRANCH HOURS — Mon–Sat 10:00–20:00 (same clinic default as T4),
--    shared by both demo branches
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.branch_hours (branch_id, day_of_week, start_time, end_time)
SELECT b.id, d.day_of_week, '10:00', '20:00'
FROM public.branches b
CROSS JOIN (SELECT generate_series(1, 6) AS day_of_week) d
ON CONFLICT (branch_id, day_of_week) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 3. STAFF-BRANCH ASSIGNMENTS — demo staff to their demo branch
--    (Dr Sarah + Omar → Dubai; Lina → Abu Dhabi)
-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────
-- 4. BRANCH ACCESS — demo staff get manager grants on THEIR demo
--    branch only (drives the branch-scoped RLS acceptance tests).
--    Admins need no rows (public.is_admin() bypasses branch scope).
-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────
-- 5. SERVICE-BRANCH AVAILABILITY — every seeded service is
--    available at both demo branches. No price/duration overrides:
--    NULL falls back to the service defaults (clinic edits later).
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.service_branches (service_id, branch_id, available, currency)
SELECT s.id, b.id, true, 'AED'
FROM public.services s
CROSS JOIN public.branches b
ON CONFLICT (service_id, branch_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 6. APP SETTINGS — client-number format + default branch
--    (existing clinic values are preserved)
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.app_settings (key, value)
VALUES
    -- Format is configurable per SRS §5.3 (prefix + zero-pad width).
    ('client_number_format', '{"prefix": "TPL", "width": 6}'::jsonb),
    -- Default (legacy/fallback) branch used by backfills and new
    -- legacy appointments until the booking API picks the branch.
    ('default_branch', '{"slug": "dubai"}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────
-- 7. BACKFILL CLIENT NUMBERS — existing patient profiles get a
--    generated, collision-safe number. Runs without an auth context,
--    so the immutability trigger permits it; uniqueness is enforced
--    by idx_profiles_client_number.
-- ─────────────────────────────────────────────────────────────

UPDATE public.profiles
SET client_number = public.generate_client_number()
WHERE role = 'patient' AND client_number IS NULL;

-- ─────────────────────────────────────────────────────────────
-- 8. BACKFILL APPOINTMENTS — branch, client number, and price
--    snapshots, then tighten constraints. Re-running is a no-op.
-- ─────────────────────────────────────────────────────────────

-- Branch: default branch for legacy rows with no branch.
UPDATE public.appointments
SET branch_id = (
    SELECT b.id FROM public.branches b
    JOIN public.app_settings s ON s.key = 'default_branch'
    WHERE b.slug = (s.value ->> 'slug')
    LIMIT 1
)
WHERE branch_id IS NULL;

-- Snapshots: preserve historical truth (SRS §8.2).
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

-- NOTE: profiles.client_number stays NULLABLE — numbers are only
-- generated for customer (patient) accounts (SRS §5.3). Staff and
-- admin profiles legitimately have no client number; the
-- appointment/backfill logic snapshots the patient's number instead.