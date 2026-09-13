-- ============================================================
-- The Perfect Look — T12 parallel-slot proof (SETUP/TEARDOWN)
-- ============================================================
-- Companion of availability_engine_parallel.ps1 / .sh.
-- Exposes exactly two modes via the psql variable `cleanup`:
--
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup=none \
--        -f availability_engine_parallel_setup.sql     # create fixtures
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup=yes \
--        -f availability_engine_parallel_setup.sql     # drop fixtures
--
-- `cleanup` is defined (any value) -> teardown, otherwise -> setup.
-- Everything is idempotent so the driver can be re-run.
-- ============================================================

\set ON_ERROR_STOP on

\if :{?cleanup}
    -- ── TEARDOWN ─────────────────────────────────────────────
    DROP TABLE IF EXISTS public.availability_parallel_results;

    DELETE FROM public.service_branches
     WHERE service_id = (SELECT id FROM public.services WHERE name = 'AV Parallel Service');
    DELETE FROM public.staff_branches
     WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN
       (SELECT id FROM public.profiles WHERE email LIKE 'avparallel.%@test.local'));
    DELETE FROM public.staff_availability
     WHERE staff_id IN (SELECT id FROM public.staff WHERE profile_id IN
       (SELECT id FROM public.profiles WHERE email LIKE 'avparallel.%@test.local'));
    DELETE FROM public.staff
     WHERE profile_id IN (SELECT id FROM public.profiles WHERE email LIKE 'avparallel.%@test.local');
    DELETE FROM public.profiles WHERE email LIKE 'avparallel.%@test.local';
    DELETE FROM auth.users     WHERE email LIKE 'avparallel.%@test.local';
    DELETE FROM public.services WHERE name = 'AV Parallel Service';

    RAISE NOTICE 'T12 parallel proof: fixtures removed, results table dropped';
\else
    -- ── SETUP ─────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS public.availability_parallel_results (
        worker_id   integer NOT NULL,
        outcome     text    NOT NULL CHECK (outcome IN ('success', 'rejected')),
        detail      text,
        booking_ref text,
        created_at  timestamptz NOT NULL DEFAULT now()
    );

    COMMENT ON TABLE public.availability_parallel_results
        IS 'T12 parallel-slot concurrency proof — one row per concurrent worker attempt.';

    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at
    )
    SELECT '00000000-0000-0000-0000-000000000000', gen_random_uuid(),
           'authenticated', 'authenticated', email,
           crypt('Password123!', gen_salt('bf')), now(),
           '{"provider":"email","providers":["email"]}',
           jsonb_build_object('role', r, 'full_name', fn, 'mobile_number', mn),
           now(), now()
    FROM (VALUES
        ('avparallel.patient@test.local',  'patient', 'AVP Patient',  '+971510000301'),
        ('avparallel.provider@test.local', 'staff',   'AVP Provider', '+971510000304')
    ) AS v(email, r, fn, mn)
    ON CONFLICT (email) DO NOTHING;

    INSERT INTO public.staff (profile_id, title, specializations, active)
    SELECT id, 'Technician', ARRAY['AVP'], true
      FROM public.profiles
     WHERE email = 'avparallel.provider@test.local'
    ON CONFLICT (profile_id) DO NOTHING;

    INSERT INTO public.staff_branches (staff_id, branch_id, primary_branch, active)
    SELECT s.id, b.id, true, true
      FROM public.staff s
      JOIN public.profiles p ON p.id = s.profile_id
      CROSS JOIN public.branches b
     WHERE p.email = 'avparallel.provider@test.local' AND b.slug = 'dubai'
    ON CONFLICT (staff_id, branch_id) DO NOTHING;

    INSERT INTO public.staff_availability (staff_id, day_of_week, start_time, end_time)
    SELECT s.id, d, '10:00', '20:00'
      FROM public.staff s
      JOIN public.profiles p ON p.id = s.profile_id
     CROSS JOIN generate_series(0, 6) AS d
     WHERE p.email = 'avparallel.provider@test.local'
    ON CONFLICT (staff_id, day_of_week) DO NOTHING;

    DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.services WHERE name = 'AV Parallel Service') THEN
            INSERT INTO public.services (name, description, duration_minutes, price, currency, active, sort_order, buffer_minutes)
            VALUES ('AV Parallel Service', 'av parallel 30min', 30, 100.00, 'AED', true, 920, 0);
        END IF;
    END;
    $$;

    DO $$
    DECLARE
        v_svc uuid := (SELECT id FROM public.services WHERE name = 'AV Parallel Service');
    BEGIN
        INSERT INTO public.service_branches (service_id, branch_id, available, currency)
        SELECT v_svc, b.id, true, 'AED'
          FROM public.branches b
         WHERE b.slug = 'dubai'
        ON CONFLICT (service_id, branch_id) DO NOTHING;
    END;
    $$;

    RAISE NOTICE 'T12 parallel proof: fixtures and results table ready';
\endif