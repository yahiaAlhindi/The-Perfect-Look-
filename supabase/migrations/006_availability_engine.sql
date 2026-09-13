-- ============================================================
-- The Perfect Look — T12: Branch-aware availability engine
-- ============================================================
-- Migration: 006_availability_engine.sql
-- Depends on: 001_schema.sql (T3), 002_auth_profiles.sql (T5),
--             003_seed_data.sql (T4), 004 + 005 (T37)
-- Source: PROJECT_TASKS_BREAKDOWN.md §T12; SRS §6/§7/§9
--
-- Responsibilities:
--   1. get_branch_providers()  — public provider (staff) list for a
--      branch, used by the optional provider step of the picker.
--   2. get_availability()      — generate bookable slots from:
--        - branch weekly hours + branch closures
--        - clinic-wide holidays
--        - service duration + buffer (`service_branches` overrides,
--          global `services` defaults otherwise)
--        - provider weekly schedules and branch assignments
--        - blocked periods (per-staff AND clinic-wide)
--        - existing appointments at ANY branch (a provider working
--          at two branches can never be double-booked)
--        - booking window, advance-notice rules, past-time cut-off
--      All date/time logic runs in the branch timezone
--      (Asia/Dubai for the demo branches).
--
-- Both functions are SECURITY DEFINER: they deliberately read past
-- the `appointments` RLS policy (which hides other patients' rows)
-- so that booked slots become unavailable to everyone. They expose
-- only aggregate availability — no patient identity leaks.
--
-- Concurrency boundary: the DB-level guarantee is the existing
-- partial unique index idx_appointments_no_double_book on
-- (staff_id, scheduled_start) for non-cancelled appointments (T3).
-- It is global (not per branch), so "one slot = one booking" holds
-- even for staff working at multiple branches; T14 wraps the final
-- insert + recheck in a booking transaction.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- PROVIDER LIST (public read for the availability picker)
-- ─────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────
-- STAFF-FREE CHECK (internal availability primitive)
-- ─────────────────────────────────────────────────────────────
-- True when the provider can take a slot [p_start, p_end):
--   - their weekly schedule covers the whole slot in branch time,
--   - no blocked period (staff-specific or clinic-wide) overlaps,
--   - no non-cancelled appointment (no matter which branch) lies in
--     [start, end + buffer). The after-booking buffer belongs to the
--     existing appointment, so the next booking cannot start inside it.

CREATE OR REPLACE FUNCTION public.is_staff_free(
    p_staff_id uuid,
    p_day date,
    p_dow   int,
    p_start timestamptz,
    p_end   timestamptz,
    p_buffer int,
    p_tz    text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_local_start time;
    v_local_end   time;
BEGIN
    v_local_start := (p_start AT TIME ZONE p_tz)::time;
    v_local_end   := (p_end   AT TIME ZONE p_tz)::time;

    -- 1. Recurring weekly schedule must cover the whole slot.
    IF NOT EXISTS (
        SELECT 1 FROM public.staff_availability sa
         WHERE sa.staff_id   = p_staff_id
           AND sa.day_of_week = p_dow
           AND sa.start_time <= v_local_start
           AND sa.end_time   >= v_local_end
    ) THEN
        RETURN false;
    END IF;

    -- 2. Blocked periods: staff-specific or clinic-wide.
    IF EXISTS (
        SELECT 1 FROM public.blocked_periods bp
         WHERE (bp.staff_id IS NULL OR bp.staff_id = p_staff_id)
           AND bp.start_datetime < p_end
           AND bp.end_datetime   > p_start
    ) THEN
        RETURN false;
    END IF;

    -- 3. Existing appointments at ANY branch (multi-branch staff).
    --    The existing appointment owns its after-service buffer.
    IF EXISTS (
        SELECT 1 FROM public.appointments a
         WHERE a.staff_id = p_staff_id
           AND a.status NOT IN ('Cancelled', 'No Show')
           AND a.scheduled_start < p_end
           AND a.scheduled_end + make_interval(mins => p_buffer) > p_start
    ) THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.is_staff_free(uuid, date, int, timestamptz, timestamptz, int, text) FROM PUBLIC;

-- ─────────────────────────────────────────────────────────────
-- BRANCH-AWARE AVAILABILITY GENERATOR
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_availability(
    p_branch_id  uuid,
    p_service_id uuid,
    p_start_date date,
    p_end_date   date,
    p_staff_ids  uuid[] DEFAULT NULL
)
RETURNS TABLE (
    booking_date date,
    slot_start   timestamptz,
    slot_end     timestamptz,
    staff_ids    uuid[],
    staff_names  text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tz            text;
    v_interval      int;
    v_window_days   int;
    v_today         date;
    v_duration      int;
    v_buffer        int;
    v_service_ok    boolean;
    v_advance_days  int := 0;
    v_advance_hours int := 0;
    v_first         date;
    v_last          date;
    v_day           date;
    v_dow           int;
    v_open_time     time;
    v_close_time    time;
    v_open          timestamptz;
    v_close         timestamptz;
    v_slot          timestamptz;
    v_slot_end      timestamptz;
    v_step          interval;
    v_advance       interval;
    v_staff_ids     uuid[];
    v_free_ids      uuid[];
    v_free_names    text[];
    v_staff         record;
    v_last_name     text;
BEGIN
    -- Branch timezone (defaults to the clinic timezone).
    SELECT COALESCE(b.timezone, 'Asia/Dubai')
      INTO v_tz
      FROM public.branches b
     WHERE b.id = p_branch_id;
    IF v_tz IS NULL THEN
        RETURN;
    END IF;

    -- Grid + booking-window settings from the database (SRS §12).
    SELECT COALESCE((SELECT (s.value#>>'{}')::int FROM public.app_settings s WHERE s.key = 'slot_interval_minutes'), 30),
           COALESCE((SELECT (s.value#>>'{}')::int FROM public.app_settings s WHERE s.key = 'booking_window_days'), 30)
      INTO v_interval, v_window_days;
    v_interval    := GREATEST(v_interval, 5);
    v_window_days := GREATEST(v_window_days, 1);
    v_step        := make_interval(mins => v_interval);

    -- Service must exist, be active, and be available at this branch.
    SELECT (s.active AND COALESCE(sb.available, false))
      INTO v_service_ok
      FROM public.services s
      LEFT JOIN public.service_branches sb
             ON sb.service_id = s.id AND sb.branch_id = p_branch_id
      WHERE s.id = p_service_id;
    IF NOT COALESCE(v_service_ok, false) THEN
        RETURN;
    END IF;

    -- Effective duration/buffer: branch override, else service default.
    SELECT COALESCE(sb.duration_minutes, s.duration_minutes)::int,
           COALESCE(sb.buffer_minutes,   s.buffer_minutes)::int
      INTO v_duration, v_buffer
      FROM public.services s
      LEFT JOIN public.service_branches sb
             ON sb.service_id = s.id AND sb.branch_id = p_branch_id
     WHERE s.id = p_service_id
     LIMIT 1;
    v_duration := GREATEST(COALESCE(v_duration, 1), 1);
    v_buffer   := GREATEST(COALESCE(v_buffer, 0), 0);

    -- Advance-notice rules from the service booking_rules jsonb.
    SELECT COALESCE((s.booking_rules->>'min_advance_days')::int, 0),
           COALESCE((s.booking_rules->>'min_advance_hours')::int, 0)
      INTO v_advance_days, v_advance_hours
      FROM public.services s
     WHERE s.id = p_service_id;
    v_advance := make_interval(mins => v_advance_days * 1440 + v_advance_hours * 60);

    -- Candidate providers: requested subset, else all branch providers.
    IF p_staff_ids IS NOT NULL AND cardinality(p_staff_ids) > 0 THEN
        SELECT array_agg(s.id)
          INTO v_staff_ids
          FROM public.staff s
          JOIN public.staff_branches sb
            ON sb.staff_id = s.id AND sb.branch_id = p_branch_id AND sb.active
         WHERE s.active = true AND s.id = ANY(p_staff_ids);
    ELSE
        SELECT array_agg(s.id)
          INTO v_staff_ids
          FROM public.staff s
          JOIN public.staff_branches sb
            ON sb.staff_id = s.id AND sb.branch_id = p_branch_id AND sb.active
         WHERE s.active = true;
    END IF;

    IF v_staff_ids IS NULL OR cardinality(v_staff_ids) = 0 THEN
        RETURN;
    END IF;

    -- Date window: never before today, never beyond the booking window.
    v_today := (now() AT TIME ZONE v_tz)::date;
    v_first := GREATEST(COALESCE(p_start_date, v_today), v_today);
    v_last  := LEAST(COALESCE(p_end_date, v_today), v_today + (v_window_days - 1));
    IF v_first > v_last THEN
        RETURN;
    END IF;

    FOR v_day IN
        SELECT d::date
          FROM generate_series(v_first::timestamp, v_last::timestamp, '1 day') AS d
    LOOP
        -- day_of_week convention: 0 = Sunday … 6 = Saturday.
        v_dow := EXTRACT(DOW FROM v_day)::int;

        SELECT start_time, end_time
          INTO v_open_time, v_close_time
          FROM public.branch_hours bh
         WHERE bh.branch_id = p_branch_id AND bh.day_of_week = v_dow;
        CONTINUE WHEN v_open_time IS NULL;

        -- Branch closure or clinic-wide holiday -> no slots.
        CONTINUE WHEN EXISTS (
            SELECT 1 FROM public.branch_closures c
             WHERE c.branch_id = p_branch_id AND c.date = v_day
        );
        CONTINUE WHEN EXISTS (
            SELECT 1 FROM public.holidays h WHERE h.date = v_day
        );

        v_open  := (v_day + v_open_time) AT TIME ZONE v_tz;
        v_close := (v_day + v_close_time) AT TIME ZONE v_tz;

        v_slot := v_open;
        WHILE v_slot + make_interval(mins => v_duration) <= v_close LOOP
            v_slot_end := v_slot + make_interval(mins => v_duration);

            -- Past / advance-notice cut-off.
            IF v_slot <= now() + v_advance THEN
                v_slot := v_slot + v_step;
                CONTINUE;
            END IF;

            v_free_ids   := '{}';
            v_free_names := '{}';
            FOR v_staff IN SELECT unnest(v_staff_ids) AS id LOOP
                IF public.is_staff_free(
                       v_staff.id, v_day, v_dow,
                       v_slot, v_slot_end, v_buffer, v_tz
                   ) THEN
                    SELECT p.full_name
                      INTO v_last_name
                      FROM public.staff st
                      JOIN public.profiles p ON p.id = st.profile_id
                     WHERE st.id = v_staff.id;
                    v_free_ids   := v_free_ids   || v_staff.id;
                    v_free_names := v_free_names || COALESCE(v_last_name, '');
                END IF;
            END LOOP;

            IF cardinality(v_free_ids) > 0 THEN
                booking_date := v_day;
                slot_start   := v_slot;
                slot_end     := v_slot_end;
                staff_ids    := v_free_ids;
                staff_names  := v_free_names;
                RETURN NEXT;
            END IF;

            v_slot := v_slot + v_step;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.get_availability(uuid, uuid, date, date, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_availability(uuid, uuid, date, date, uuid[]) TO anon;
GRANT EXECUTE ON FUNCTION public.get_availability(uuid, uuid, date, date, uuid[]) TO authenticated;