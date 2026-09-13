#!/usr/bin/env bash
# ============================================================
# The Perfect Look — T12 parallel-slot concurrency proof
# ============================================================
# Same proof as availability_engine_parallel.ps1, POSIX edition.
# Spawns N concurrent psql workers that ALL try to reserve the
# exact same slot; the branch-aware availability engine must let
# EXACTLY ONE succeed.
#
# Prereqs:
#   * migration 006 applied to a local Supabase db
#   * psql on PATH
#   * SUPABASE_DB_URL set (or pass as $1), connecting as the table
#     owner (postgres)
#
# Usage:
#   export SUPABASE_DB_URL="postgresql://postgres:postgres@localhost:54322/postgres"
#   ./availability_engine_parallel.sh                # 8 workers
#   ./availability_engine_parallel.sh "$URL" 16
# ============================================================

set -euo pipefail

DB_URL="${1:-${SUPABASE_DB_URL:-}}"
WORKERS="${2:-8}"
RUN_DIR="${TMPDIR:-/tmp}/t12-availability-parallel"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$DIR/availability_engine_parallel_setup.sql"
WORKER="$DIR/availability_engine_parallel_worker.sql"

if [ -z "$DB_URL" ]; then
  echo "Set SUPABASE_DB_URL (or pass it as \$1)." >&2
  exit 2
fi

command -v psql >/dev/null 2>&1 || { echo "psql not found on PATH." >&2; exit 2; }
mkdir -p "$RUN_DIR"

echo "== T12 parallel-slot proof =="

# 1. Fixtures + results table.
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$SETUP" >/dev/null

BRANCH="$(psql "$DB_URL" -t -A -c "SELECT id FROM public.branches WHERE slug = 'dubai'")"
SERVICE="$(psql "$DB_URL" -t -A -c "SELECT id FROM public.services WHERE name = 'AV Parallel Service'")"
PATIENT="$(psql "$DB_URL" -t -A -c "SELECT id FROM public.profiles WHERE email = 'avparallel.patient@test.local'")"
STAFF="$(psql "$DB_URL" -t -A -c "SELECT id FROM public.staff WHERE profile_id = (SELECT id FROM public.profiles WHERE email = 'avparallel.provider@test.local')")"

for v in BRANCH SERVICE PATIENT STAFF; do
  [ -n "${!v}" ] || { echo "Fixture lookup failed for $v." >&2; exit 3; }
done

# 2. Pick a genuinely open slot: next Monday 10:00 Asia/Dubai (+04, no DST).
day="$(TZ=Asia/Dubai date -d 'next monday + 7 days' '+%Y-%m-%d')"
start_iso="${day}T10:00:00+0400"

available=f
for try in 1 2 3 4; do
  available="$(psql "$DB_URL" -t -A -c "SELECT EXISTS (SELECT 1 FROM public.get_availability('$BRANCH'::uuid, '$SERVICE'::uuid, '$day'::date, '$day'::date, '$STAFF'::uuid) a WHERE a.slot_start = '$start_iso'::timestamptz)")"
  if [ "$available" = t ]; then break; fi
  echo "  slot not offered on $day (holiday?), trying the next Monday..."
  day="$(TZ=Asia/Dubai date -d "$day + 7 days" '+%Y-%m-%d')"
  start_iso="${day}T10:00:00+0400"
done
[ "$available" = t ] || { echo "Could not find an available Monday slot." >&2; exit 3; }
echo "  target slot : $start_iso  (Asia/Dubai)"

# 3. Fire N concurrent workers at the exact same slot.
pids=()
for ((i = 1; i <= WORKERS; i++)); do
  psql "$DB_URL" \
      -v "worker_id=$i" \
      -v "branch=$BRANCH" \
      -v "service=$SERVICE" \
      -v "patient=$PATIENT" \
      -v "staff=$STAFF" \
      -v "start=$start_iso" \
      -f "$WORKER" \
      >"$RUN_DIR/worker-$i.out.log" 2>"$RUN_DIR/worker-$i.err.log" &
  pids+=("$!")
done
wait "${pids[@]}"

# 4. The boundary must admit EXACTLY one winner.
summary="$(psql "$DB_URL" -t -A -c "SELECT outcome || '=' || count(*) FROM public.availability_parallel_results GROUP BY outcome ORDER BY outcome")"
total="$(psql "$DB_URL" -t -A -c "SELECT count(*) FROM public.availability_parallel_results")"
success="$(printf '%s\n' "$summary" | awk -F= '/^success=/{print $2; exit}')"
[[ -z "$success" ]] && success=0

echo "  concurrent attempts : $WORKERS"
echo "  results recorded    : $total"
echo "  successes           : $success"
printf '%s\n' "$summary" | sed 's/^/    /'
psql "$DB_URL" -t -A -c "SELECT 'worker ' || worker_id || ' -> ' || outcome || CASE WHEN detail IS NOT NULL THEN ' (' || detail || ')' ELSE '' END FROM public.availability_parallel_results ORDER BY worker_id" | sed 's/^/    /'

# 5. Cleanup fixtures + results.
psql "$DB_URL" -v ON_ERROR_STOP=1 -v cleanup=yes -f "$SETUP" >/dev/null

if [ "$total" -ne "$WORKERS" ] || [ "$success" -ne 1 ]; then
  echo "FAIL: expected exactly 1 success among $WORKERS concurrent reservations." >&2
  exit 1
fi
echo "PASS: exactly one of $WORKERS parallel slot reservations succeeded."