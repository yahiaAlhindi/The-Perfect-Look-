-- ============================================================
-- The Perfect Look — T12 parallel-slot worker
-- ============================================================
-- One concurrent attempt at reserving THE SAME slot. Spawn N of
-- these with the same psql variables; the advisory-locked
-- reserve_slot() must admit exactly one winner.
--
-- Psql variables (set by availability_engine_parallel.ps1/.sh):
--   worker_id  : integer label for this attempt
--   branch     : uuid of the branch (dubai)
--   service    : uuid of 'AV Parallel Service'
--   patient    : uuid of the avparallel patient profile
--   staff      : uuid of the avparallel provider
--   start      : the exact slot instant, ISO "YYYY-MM-DDTHH:MM:SS+04"
--
-- Each attempt INSERTs exactly one row into
--   public.availability_parallel_results (worker_id, outcome, detail)
-- so the driver can prove: total rows == workers AND one 'success'.
-- ============================================================

\set ON_ERROR_STOP off
\set QUIET on

SELECT set_config('t.worker',  :'worker_id',  false);
SELECT set_config('t.branch',  :'branch',     false);
SELECT set_config('t.service', :'service',    false);
SELECT set_config('t.patient', :'patient',    false);
SELECT set_config('t.staff',   :'staff',      false);
SELECT set_config('t.start',   :'start',      false);

DO $$
DECLARE
    v_outcome text;
    v_detail  text;
    v_ref     text;
BEGIN
    BEGIN
        SELECT r.appointment_ref INTO v_ref
          FROM public.reserve_slot(
              current_setting('t.branch')::uuid,
              current_setting('t.service')::uuid,
              current_setting('t.patient')::uuid,
              current_setting('t.start')::timestamptz,
              current_setting('t.staff')::uuid,
              'av-parallel-' || current_setting('t.worker'),
              'web'
          ) r;

        v_outcome := 'success';
        v_detail  := COALESCE(v_ref, 'reserved');
    EXCEPTION WHEN OTHERS THEN
        v_outcome := 'rejected';
        v_detail  := SQLERRM;
    END;

    INSERT INTO public.availability_parallel_results (worker_id, outcome, detail)
    VALUES (current_setting('t.worker')::int, v_outcome, v_detail);
END;
$$;