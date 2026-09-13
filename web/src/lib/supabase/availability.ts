/**
 * Availability API client module (T12 + T13).
 *
 * Wraps the branch-aware availability engine RPCs from migration 006
 * (`get_branch_providers`, `get_availability`) plus the public branch
 * tables the picker needs for its day/week navigation:
 *   - branches          (active branches)
 *   - branch_hours      (weekly open days — a day with no hours is "closed")
 *   - branch_closures   (specific closed dates)
 *   - holidays          (clinic-wide closed dates)
 *
 * The engine runs in Asia/Dubai (branch timezone): `slot_start` is an
 * ISO instant and `booking_date` is already the branch-local date, so
 * the UI never hand-rolls timezone math. "UI matches API availability"
 * is guaranteed because every slot comes from `get_availability`; the
 * client only renders the grid and marks unavailable states.
 */

import { supabase } from './client'
import type {
  AvailabilitySlot,
  Branch,
  BranchClosure,
  BranchHours,
  Holiday,
  ProviderSummary,
} from './types'
import { mapped, type MappedError } from './errors'

// ── result shapes ─────────────────────────────────────────────

interface BranchListResult {
  branches: Branch[]
  error: MappedError | null
}

interface ProviderListResult {
  providers: ProviderSummary[]
  error: MappedError | null
}

interface HoursListResult {
  hours: BranchHours[]
  error: MappedError | null
}

interface ClosedDatesResult {
  closures: BranchClosure[]
  holidays: Holiday[]
  error: MappedError | null
}

interface AvailabilityResult {
  slots: AvailabilitySlot[]
  error: MappedError | null
}

// ── public API ────────────────────────────────────────────────

/** Active branches ordered by the clinic sort order (public RLS). */
export async function listBranches(): Promise<BranchListResult> {
  const { data, error } = await supabase
    .from('branches')
    .select('*')
    .eq('active', true)
    .order('sort_order', { ascending: true })
    .order('name', { ascending: true })

  if (error) return { branches: [], error: mapped('AVAILABILITY_BRANCHES', error.message) }
  return { branches: (data ?? []) as Branch[], error: null }
}

/** Providers assigned to a branch (optional provider step, T13). */
export async function listBranchProviders(branchId: string): Promise<ProviderListResult> {
  const { data, error } = await supabase.rpc('get_branch_providers', {
    p_branch_id: branchId,
  })

  if (error) return { providers: [], error: mapped('AVAILABILITY_PROVIDERS', error.message) }
  return { providers: (data ?? []) as ProviderSummary[], error: null }
}

/** Weekly open days for a branch (a missing day means the branch is closed). */
export async function listBranchHours(branchId: string): Promise<HoursListResult> {
  const { data, error } = await supabase
    .from('branch_hours')
    .select('*')
    .eq('branch_id', branchId)

  if (error) return { hours: [], error: mapped('AVAILABILITY_HOURS', error.message) }
  return { hours: (data ?? []) as BranchHours[], error: null }
}

/** Branch closures + clinic-wide holidays within a date range. */
export async function listClosedDates(
  branchId: string,
  from: string,
  to: string,
): Promise<ClosedDatesResult> {
  const closuresQuery = supabase
    .from('branch_closures')
    .select('*')
    .eq('branch_id', branchId)
    .gte('date', from)
    .lte('date', to)

  const holidaysQuery = supabase
    .from('holidays')
    .select('*')
    .gte('date', from)
    .lte('date', to)

  const [closuresRes, holidaysRes] = await Promise.all([closuresQuery, holidaysQuery])

  if (closuresRes.error || holidaysRes.error) {
    return {
      closures: [],
      holidays: [],
      error: mapped(
        'AVAILABILITY_CLOSED',
        (closuresRes.error ?? holidaysRes.error ?? {}).message ?? 'Failed to load closed dates',
      ),
    }
  }

  return {
    closures: (closuresRes.data ?? []) as BranchClosure[],
    holidays: (holidaysRes.data ?? []) as Holiday[],
    error: null,
  }
}

export interface AvailabilityRequest {
  branchId: string
  /** Service whose duration/buffer drives the slot grid. */
  serviceId: string | null
  /** Optional: constrain the slots to one provider. */
  providerId?: string | null
  /** Branch-local dates (YYYY-MM-DD). */
  startDate: string
  endDate: string
}

/**
 * Bookable slots for a branch/service/date window straight from the
 * T12 engine — the single source of truth the UI renders.
 */
export async function queryAvailability(
  request: AvailabilityRequest,
): Promise<AvailabilityResult> {
  if (!request.serviceId) {
    return { slots: [], error: null }
  }

  const { data, error } = await supabase.rpc('get_availability', {
    p_branch_id: request.branchId,
    p_service_id: request.serviceId,
    p_start_date: request.startDate,
    p_end_date: request.endDate,
    p_staff_ids: request.providerId ? [request.providerId] : null,
  })

  if (error) return { slots: [], error: mapped('AVAILABILITY_SLOTS', error.message) }
  return { slots: (data ?? []) as AvailabilitySlot[], error: null }
}