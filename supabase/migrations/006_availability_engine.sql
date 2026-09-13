-- ============================================================
-- The Perfect Look — T12: Branch-aware availability engine
-- ============================================================
-- Migration: 006_availability_engine.sql
-- Depends on: 001–005 (T3/T5/T4/T37)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T12; SRS v2 §6/§8
--
-- Responsibilities:
--   1. Branch capacity (branches.max_concurrent_appointments) —
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
--      - public.get_availability(...) — generates slots for a
--        branch+service+date range, in branch time (Asia/Dubai),
--        from branch hours, service duration/buffers, provider
--        schedules, leave/blocks, holidays, closures, capacity and
--        existing appointments. Every query is scoped by branch and
--        converted through the branch timezone.
--      - public.reserve_slot(...) — atomic, branch-aware booking:
--        re-validates the whole availability stack server-side then
--        inserts the appointment with price/client-number snapshots.
--        Advisory locks on the provider and branch serialise
--        concurrent requests so exactly one overlapping booking for
--        a slot can succeed.
--
-- Every function returns/includes the branch and its timezone, and
-- the database works entirely in Asia/Dubai wall time for slot math
-- (the SRS mandates Asia/Dubai for all appointment times, §8.2).
-- ============================================================

-- GIST operator classes for the btree `=` opclass on uuid (btree_gist)
-- enable the `&&` range overlap exclusion constraint below.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ─────────────────────────────────────────────────────────────
-- 1. BRANCH CAPACITY
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.branches
    ADD COLUMN IF NOT EXISTS max_concurrent_appointments INTEGER
        CHECK (max_concurrent_appointments IS NULL OR max_concurrent_appointments > 0);

COMMENT ON COLUMN public.branches.max_concurrent_appointments
    IS 'Branch capacity — max concurrent active appointments (NULL = unlimited). Slot engine + booking enforce this. T12.';

-- ─────────────────────────────────────────────────────────────
-- 2. APPOINTMENT BUFFER SNAPSHOT
-- ─────────────────────────────────────────────────────────────

-- Snapshot of the buffer in effect at booking time so future buffer
-- edits do not retroactively widen conflicts (same rationale as the
-- T37 price snapshot, SRS §8.2).
ALTER TABLE public.appointments
    ADD COLUMN IF NOT EXISTS buffer_minutes INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.appointments.buffer_minutes
    IS 'Buffer snapshot at booking time — availability conflicts computed against this. T12.';

-- Backfill existing rows from the current service/branch default.
UPDATE public.appointments a
   SET buffer_minutes = COALESCE(sb.buffer_minutes, s.buffer_minutes, 0)
  FROM public.services s
  LEFT JOIN public.service_branches sb
         ON sb.service_id = s.id AND sb.branch_id = a.branch_id
 WHERE s.id = a.service_id;

-- ─────────────────────────────────────────────────────────────
-- 3. OVERLAP EXCLUSION CONSTRAINT (concurrency boundary)
-- ─────────────────────────────────────────────────────────────
-- A staff member can never have two OVERLAPPING active bookings,
-- even at different branches and even with different scheduled_start
-- values (the T3 unique index only pins the exact start instant).
-- The constraint applies to any insert path — including direct
-- table writes that bypass the booking function.

-- Refuse to add the boundary while overlapping historical rows exist
-- (operator must resolve them first — e.g. after importing messy data).
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
            'Cannot add appt_no_overlapping_staff: overlapping active bookings exist — resolve them first';
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
    IS 'T12: no overlapping active bookings per staff across ALL branches — the DB-level concurrency boundary.';

-- ─────────────────────────────────────────────────────────────
-- 4. INTERNAL SETTING READER
-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────
-- 5. SLOT GENERATION — public.get_availability
-- ─────────────────────────────────────────────────────────────
-- SECURITY DEFINER: the engine must read every patient's active
-- appointments to compute conflicts (RLS would otherwise hide the
-- bookings of other patients from a patient caller). It only ever
-- returns generated slot rows — no patient data leaks.

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
        v_dow := EXTRACT(DOW FROM v_day)::int; -- 0=Sun … 6=Sat

        -- Holiday / branch closure → the whole day is unavailable.
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

-- ─────────────────────────────────────────────────────────────
-- 6. ATOMIC RESERVATION — public.reserve_slot
-- ─────────────────────────────────────────────────────────────
-- The concurrency boundary for every channel. Re-checks the full
-- availability stack inside one transaction, serialised per provider
-- and per branch with advisory locks (READ COMMITTED: each statement
-- after acquiring the lock takes a fresh snapshot, so a waiter sees
-- the winner's committed booking and rejects the slot). Raw inserts
-- that bypass this function are still stopped by the EXCLUDE
-- constraint in §3.
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
    -- stepped by slot_interval_minutes — reject off-grid timestamps.
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
    -- EXCLUDE constraint or the T3 unique index → surface a stable error.
    EXCEPTION WHEN exclusion_violation OR unique_violation THEN
        RAISE EXCEPTION 'The selected timeslot is not available anymore';
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_slot(uuid, uuid, uuid, timestamptz, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_slot(uuid, uuid, uuid, timestamptz, uuid, text, text) TO authenticated;