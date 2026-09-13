# ============================================================
# The Perfect Look — T12 parallel-slot concurrency proof (Windows)
# ============================================================
# Spawns N concurrent psql workers that ALL try to reserve the
# exact same slot. The branch-aware availability engine must let
# exactly ONE of them succeed (advisory-locked reserve_slot +
# DB EXCLUDE/unique boundary). Fails otherwise.
#
# Prereqs:
#   * migration 006 applied to a local Supabase db
#   * psql on PATH
#   * $env:SUPABASE_DB_URL (or -DbUrl) pointing at that db,
#     connecting as the table owner (postgres)
#
# Usage:
#   $env:SUPABASE_DB_URL = "postgresql://postgres:postgres@localhost:54322/postgres"
#   ./availability_engine_parallel.ps1            # 8 workers
#   ./availability_engine_parallel.ps1 -Workers 16
# ============================================================

#requires -Version 5.1
param(
    [string]$DbUrl   = $env:SUPABASE_DB_URL,
    [int]$Workers    = 8,
    [string]$TestDir = $PSScriptRoot,
    [string]$RunDir  = (Join-Path $env:TEMP 't12-availability-parallel')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $DbUrl) { throw 'Set $env:SUPABASE_DB_URL (or pass -DbUrl) to the local db psql URL.' }

$psql = (Get-Command psql -ErrorAction Stop).Source
$setupFile  = Join-Path $TestDir 'availability_engine_parallel_setup.sql'
$workerFile = Join-Path $TestDir 'availability_engine_parallel_worker.sql'
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null

function Invoke-Sql([string]$command) {
    & $psql $DbUrl -t -A -c $command | ForEach-Object { $_.Trim() }
}

function Invoke-SqlFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$Variables = @(),
        [switch]$StopOnError
    )
    $args = @($DbUrl)
    if ($StopOnError) { $args += @('-v', 'ON_ERROR_STOP=1') }
    $args += $Variables
    $args += @('-f', $Path)
    & $psql $args
    if ($LASTEXITCODE -ne 0) { throw "psql failed: $Path" }
}

Write-Host "== T12 parallel-slot proof =="

# 1. Fixtures + results table.
Invoke-SqlFile -Path $setupFile -StopOnError

$branchUuid  = (Invoke-Sql "SELECT id FROM public.branches WHERE slug = 'dubai'")
$serviceUuid = (Invoke-Sql "SELECT id FROM public.services WHERE name = 'AV Parallel Service'")
$patientUuid = (Invoke-Sql "SELECT id FROM public.profiles WHERE email = 'avparallel.patient@test.local'")
$staffUuid   = (Invoke-Sql "SELECT id FROM public.staff WHERE profile_id = (SELECT id FROM public.profiles WHERE email = 'avparallel.provider@test.local')")

if (-not ($branchUuid -and $serviceUuid -and $patientUuid -and $staffUuid)) {
    throw 'Fixture lookup failed — did the setup run against the right db?'
}

# 2. Pick a genuinely open slot: next Monday 10:00 Asia/Dubai (+04, no DST).
$day = (Get-Date).Date
while ($day.DayOfWeek -ne [DayOfWeek]::Monday) { $day = $day.AddDays(1) }
$day = $day.AddDays(7)   # >= 7 days out, safely inside the 30-day booking window
$startIso = '{0:yyyy-MM-dd}T10:00:00+0400' -f $day

$available = 'f'
for ($try = 0; $try -lt 4 -and $available -ne 't'; $try++) {
    $datePart = $startIso.Substring(0, 10)
    $available = (Invoke-Sql "SELECT EXISTS (SELECT 1 FROM public.get_availability('$branchUuid'::uuid, '$serviceUuid'::uuid, '$datePart'::date, '$datePart'::date, '$staffUuid'::uuid) a WHERE a.slot_start = '$startIso'::timestamptz)")
    if ($available -ne 't') {
        Write-Host "  slot not offered on $datePart (holiday?), trying the next Monday..."
        $day = $day.AddDays(7)
        $startIso = '{0:yyyy-MM-dd}T10:00:00+0400' -f $day
    }
}
if ($available -ne 't') { throw 'Could not find an available Monday slot for the parallel run.' }
Write-Host "  target slot : $startIso  (Asia/Dubai)" -ForegroundColor Gray

# 3. Fire N concurrent workers at the exact same slot.
$procs = @()
for ($i = 1; $i -le $Workers; $i++) {
    $args = @(
        $DbUrl,
        '-v', "worker_id=$i",
        '-v', "branch=$branchUuid",
        '-v', "service=$serviceUuid",
        '-v', "patient=$patientUuid",
        '-v', "staff=$staffUuid",
        '-v', "start=$startIso",
        '-f', $workerFile
    )
    $out = Join-Path $RunDir "worker-$i.out.log"
    $err = Join-Path $RunDir "worker-$i.err.log"
    $procs += Start-Process -FilePath $psql -ArgumentList $args -PassThru -NoNewWindow `
        -RedirectStandardOutput $out -RedirectStandardError $err
}
foreach ($p in $procs) { $null = $p | Wait-Process }

# 4. The boundary must admit EXACTLY one winner.
$summary = & $psql $DbUrl -t -A -c "SELECT outcome || '=' || count(*)::text FROM public.availability_parallel_results GROUP BY outcome ORDER BY outcome"
$total = [int](& $psql $DbUrl -t -A -c "SELECT count(*) FROM public.availability_parallel_results")

$success = 0
$rejected = 0
foreach ($line in $summary) {
    if ($line -eq '') { continue }
    $parts = $line -split '='
    if ($parts[0] -eq 'success') { $success = [int]$parts[1] }
    if ($parts[0] -eq 'rejected') { $rejected = [int]$parts[1] }
}

Write-Host "  concurrent attempts : $Workers"
Write-Host "  results recorded    : $total"
Write-Host "  successes           : $success"
Write-Host "  rejected            : $rejected"
$summary | ForEach-Object { Write-Host "    $_" }
$details = & $psql $DbUrl -t -A -c "SELECT 'worker ' || worker_id || ' -> ' || outcome || CASE WHEN detail IS NOT NULL THEN ' (' || detail || ')' ELSE '' END FROM public.availability_parallel_results ORDER BY worker_id"
$details | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

# 5. Cleanup fixtures + results.
Invoke-SqlFile -Path $setupFile -Variables @('-v', 'cleanup=yes') -StopOnError

if ($total -ne $Workers -or $success -ne 1 -or $rejected -ne ($Workers - 1)) {
    Write-Host "FAIL: expected exactly 1 success among $Workers concurrent reservations." -ForegroundColor Red
    exit 1
}
Write-Host "PASS: exactly one of $Workers parallel slot reservations succeeded." -ForegroundColor Green