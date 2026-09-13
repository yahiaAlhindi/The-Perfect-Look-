/**
 * Consents & data-request client API (T8).
 *
 * - `getConsentHistory()` / `recordConsent()`   — append-only consent
 *   records (version + timestamp live in `consents` rows; a withdrawal
 *   is a new record with granted=false, never an UPDATE — enforced by
 *   DB trigger + RLS).
 * - `requestDataExport()` / `getDataRequests()` — the SRS §17
 *   "request my data" entry point. A customer records a request; staff
 *   fulfil it server-side.
 *
 * All reads/writes are RLS-scoped to the caller's own rows — the UI
 * never passes a user id, so there is no way to access another profile.
 */

import { supabase } from './client'
import { mapError, mapped, type MappedError } from './errors'
import type { ConsentRow, ConsentType, DataRequestRow } from './types'

/** Latest consent version this client writes (T8 version field). */
export const CONSENT_VERSION = 'v1'

export interface ConsentListResult {
  success: boolean
  rows: ConsentRow[]
  error?: MappedError
}

export interface ConsentRecordResult {
  success: boolean
  row?: ConsentRow
  error?: MappedError
}

export interface DataRequestListResult {
  success: boolean
  rows: DataRequestRow[]
  error?: MappedError
}

export interface DataRequestResult {
  success: boolean
  row?: DataRequestRow
  error?: MappedError
}

/**
 * Fetch the signed-in user's consent history, newest first (T8).
 * https://www.privacy-style — version + granted_at are preserved per
 * record so the UI can show "you accepted v1 on <date>".
 */
export async function getConsentHistory(): Promise<ConsentListResult> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()
  if (authError || !user) {
    return {
      success: false,
      rows: [],
      error: mapped('NOT_AUTHENTICATED', 'You must be signed in'),
    }
  }

  const { data, error } = await supabase
    .from('consents')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })

  if (error) {
    return { success: false, rows: [], error: mapError(error) }
  }
  return { success: true, rows: (data ?? []) as ConsentRow[] }
}

/**
 * Record a consent decision for the current user (T8).
 * Insert-only: the DB makes records immutable, so a withdrawal is just
 * another row with `granted: false`.
 */
export async function recordConsent(
  consentType: ConsentType,
  granted: boolean,
  source = 'profile',
): Promise<ConsentRecordResult> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()
  if (authError || !user) {
    return {
      success: false,
      error: mapped('NOT_AUTHENTICATED', 'You must be signed in'),
    }
  }

  const { data, error } = await supabase
    .from('consents')
    .insert({
      user_id: user.id,
      consent_type: consentType,
      version: CONSENT_VERSION,
      granted,
      source,
    })
    .select('*')
    .single()

  if (error) {
    return { success: false, error: mapError(error) }
  }
  return { success: true, row: data as ConsentRow }
}

/**
 * Latest consent state for a topic, derived from the history row list.
 * Returns undefined when no record exists yet (consent not given).
 */
export function latestConsent(rows: ConsentRow[], type: ConsentType): boolean | undefined {
  const match = rows.find((r) => r.consent_type === type)
  return match ? match.granted : undefined
}

/** True when the user has actively withdrawn a topic (a record exists). */
export function hasConsentBeenSet(rows: ConsentRow[], type: ConsentType): boolean {
  return rows.some((r) => r.consent_type === type)
}

/**
 * Best-effort bridge from the T6 register page: persist the consent
 * choices made during sign-up. Only runs when a session exists right
 * after `signUp` (auto-confirmed email). When email confirmation is on
 * there is no session here, so the choice is captured on first login via
 * the T7 profile page instead. Never blocks or fails registration.
 */
export async function recordSignupConsents(
  choices: { service: boolean; marketing: boolean },
): Promise<void> {
  try {
    if (!choices.service && !choices.marketing) return
    const {
      data: { user },
      error,
    } = await supabase.auth.getUser()
    if (error || !user) return

    const ops: Array<PromiseLike<unknown>> = []
    if (choices.service) {
      ops.push(
        supabase.from('consents').insert({
          user_id: user.id,
          consent_type: 'terms_service',
          version: CONSENT_VERSION,
          granted: true,
          source: 'signup',
        }),
      )
    }
    if (choices.marketing) {
      ops.push(
        supabase.from('consents').insert({
          user_id: user.id,
          consent_type: 'marketing',
          version: CONSENT_VERSION,
          granted: true,
          source: 'signup',
        }),
      )
    }
    await Promise.all(ops)
  } catch {
    // Intentionally swallowed — consent recording is secondary to sign-up.
  }
}

/**
 * "Request my data" entry point (T8 / SRS §17). Records the request;
 * fulfilment is handled by clinic staff.
 */
export async function requestDataExport(notes?: string): Promise<DataRequestResult> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()
  if (authError || !user) {
    return {
      success: false,
      error: mapped('NOT_AUTHENTICATED', 'You must be signed in'),
    }
  }

  const { data, error } = await supabase
    .from('data_requests')
    .insert({ user_id: user.id, notes: notes ?? null })
    .select('*')
    .single()

  if (error) {
    return { success: false, error: mapError(error) }
  }
  return { success: true, row: data as DataRequestRow }
}

/** Fetch the signed-in user's data requests, newest first (T8). */
export async function getDataRequests(): Promise<DataRequestListResult> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()
  if (authError || !user) {
    return {
      success: false,
      rows: [],
      error: mapped('NOT_AUTHENTICATED', 'You must be signed in'),
    }
  }

  const { data, error } = await supabase
    .from('data_requests')
    .select('*')
    .eq('user_id', user.id)
    .order('requested_at', { ascending: false })

  if (error) {
    return { success: false, rows: [], error: mapError(error) }
  }
  return { success: true, rows: (data ?? []) as DataRequestRow[] }
}

export type { MappedError } from './errors'