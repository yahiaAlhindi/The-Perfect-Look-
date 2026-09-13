/**
 * Availability engine API client module (T12).
 * Thin, typed wrappers over the DB functions built in migration 006:
 *   - getAvailability  -> public.get_availability(...)
 *   - reserveSlot      -> public.reserve_slot(...)
 *
 * The engine does ALL availability math server-side, branch-aware in
 * the branch timezone (Asia/Dubai), so these calls are authoritative
 * and race-safe: slot conflicts (including staff working at two
 * branches) are rejected at the database, and concurrent reservation
 * attempts for one slot yield exactly one success.
 *
 * Errors are mapped to stable codes (see mapAvailabilityError) —
 * raw DB messages never reach the UI (SRS §17).
 */

import { supabase } from './client'
import type { AvailabilitySlot, ReservedAppointment } from './types'
import { mapError, type MappedError } from './errors'

// ── public result shapes ──────────────────────────────────────

export interface GetAvailabilityParams {
  branchId: string
  serviceId: string
  /** Inclusive date range, ISO "YYYY-MM-DD", in branch time. */
  from: string
  to: string
  /** Optional provider filter (multi-branch providers checked). */
  staffId?: string | null
}

export interface AvailabilityResult {
  slots: AvailabilitySlot[]
  error: MappedError | null
}

export interface ReserveSlotParams {
  branchId: string
  serviceId: string
  patientId: string
  /** ISO timestamptz of the slot start, e.g. "2026-09-21T10:00:00+04:00". */
  start: string
  staffId?: string | null
  notes?: string | null
  sourceChannel?: string
}

export interface ReserveSlotResult {
  appointment: ReservedAppointment | null
  error: MappedError | null
}

// ── error mapping ─────────────────────────────────────────────

const AVAILABILITY_ERROR_MAP: Record<string, { code: string; message: string }> = {
  'Branch not found or inactive': {
    code: 'BRANCH_NOT_FOUND',
    message: 'This branch is not available',
  },
  'Service is not available at this branch': {
    code: 'SERVICE_UNAVAILABLE',
    message: 'This service is not offered at the selected branch',
  },
  'This service requires a selected provider': {
    code: 'PROVIDER_REQUIRED',
    message: 'Please choose a provider for this service',
  },
  'Selected provider does not work at this branch': {
    code: 'PROVIDER_UNAVAILABLE',
    message: 'This provider is not available at the selected branch',
  },
  'This timeslot is in the past': {
    code: 'SLOT_PAST',
    message: 'This time has already passed — please pick another slot',
  },
  'This timeslot is outside the booking window': {
    code: 'OUTSIDE_WINDOW',
    message: 'This date is outside the booking window',
  },
  'This day is a holiday or the branch is closed': {
    code: 'DAY_CLOSED',
    message: 'The clinic is closed on this day',
  },
  'The branch is closed on this day': {
    code: 'DAY_CLOSED',
    message: 'The branch is closed on this day',
  },
  'This timeslot is outside the branch opening hours': {
    code: 'OUTSIDE_HOURS',
    message: 'This time is outside the branch opening hours',
  },
  'The provider is not available at this time': {
    code: 'PROVIDER_UNAVAILABLE',
    message: 'This provider is not available at the selected time',
  },
  'This timeslot is outside the provider working hours': {
    code: 'PROVIDER_UNAVAILABLE',
    message: 'This time is outside the provider working hours',
  },
  'This timeslot is not aligned to the booking grid': {
    code: 'INVALID_SLOT',
    message: 'Please pick a slot from the bookable times',
  },
  'This timeslot falls within a blocked period': {
    code: 'SLOT_BLOCKED',
    message: 'This time is no longer available',
  },
  'The selected timeslot is not available anymore': {
    code: 'SLOT_UNAVAILABLE',
    message: 'That slot just became unavailable — please pick another',
  },
  'Customer record not found': {
    code: 'PATIENT_NOT_FOUND',
    message: 'We could not find your customer record',
  },
  'Booking requires a signed-in customer or staff account': {
    code: 'AUTH_REQUIRED',
    message: 'Please sign in to book an appointment',
  },
  'Cannot book an appointment for another customer': {
    code: 'FORBIDDEN',
    message: 'You can only book appointments for yourself',
  },
}

function mapAvailabilityError(error: unknown): MappedError {
  const candidate = error as Error & { code?: string }
  const message = candidate?.message ?? ''

  // PostgREST surfaces RAISE EXCEPTION messages verbatim — match by
  // stable engine message (branch-aware availability stack, migration 006).
  for (const [engineMessage, entry] of Object.entries(AVAILABILITY_ERROR_MAP)) {
    if (message.includes(engineMessage)) {
      return { code: entry.code, message: entry.message, original: error as Error }
    }
  }

  if (candidate?.code && candidate.code === '42501') {
    return {
      code: 'FORBIDDEN',
      message: 'You do not have permission to perform this action',
      original: error as Error,
    }
  }

  return mapError(error as Error)
}

// ── public API ────────────────────────────────────────────────

/**
 * Generate available slots for a branch + service + date range.
 * The engine runs entirely in the branch timezone (SRS §8.2) and
 * already excludes conflicts: branch hours, provider schedules,
 * leave, holidays, closures, blocked periods, capacity and existing
 * appointments (multi-branch staff cannot double-book).
 */
export async function getAvailability(
  params: GetAvailabilityParams,
): Promise<AvailabilityResult> {
  const { data, error } = await supabase.rpc('get_availability', {
    p_branch_id: params.branchId,
    p_service_id: params.serviceId,
    p_from: params.from,
    p_to: params.to,
    p_staff_id: params.staffId ?? null,
  })

  if (error) {
    return { slots: [], error: mapAvailabilityError(error) }
  }

  return { slots: (data ?? []) as AvailabilitySlot[], error: null }
}

/**
 * Atomically reserve a slot (server-validated, race-safe).
 * The reservation re-checks the whole availability stack server-side
 * and serialises concurrent requests per provider + branch, so only
 * one overlapping booking for a slot can ever succeed. Returns the
 * created appointment with price/buffer/client snapshots on success.
 */
export async function reserveSlot(
  params: ReserveSlotParams,
): Promise<ReserveSlotResult> {
  const { data, error } = await supabase.rpc('reserve_slot', {
    p_branch_id: params.branchId,
    p_service_id: params.serviceId,
    p_patient_id: params.patientId,
    p_start: params.start,
    p_staff_id: params.staffId ?? null,
    p_notes: params.notes ?? null,
    p_source_channel: params.sourceChannel ?? 'web',
  })

  if (error) {
    return { appointment: null, error: mapAvailabilityError(error) }
  }

  return { appointment: (data as ReservedAppointment) ?? null, error: null }
}

export type { MappedError } from './errors'