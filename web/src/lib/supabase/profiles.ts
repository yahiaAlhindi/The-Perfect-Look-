/**
 * Profile & consent API client module (T8).
 * Own-profile GET/PUT with allowed-field rules, password change,
 * versioned consent history, and the data-request entry point.
 *
 * RBAC / isolation enforcement lives on the server via Postgres RLS
 * (supabase/migrations/001/002/009): customers can only read/update their
 * own row, and sensitive fields are never exposed to anon. These
 * helpers only surface the mapped errors — the client never trusts
 * itself (SRS §17).
 */

import { supabase } from './client'
import type {
  Profile,
  ProfileUpdate,
  ConsentRecord,
  ConsentType,
  DataRequest,
  DataRequestType,
} from './types'
import { mapError, type MappedError } from './errors'
import {
  validateProfileUpdate,
  validateConsentInput,
  validateDataRequestInput,
  isValidPassword,
  passwordPolicyHint,
} from './validation'

// ── error mapping ─────────────────────────────────────────────

const PROFILE_ERROR_MAP: Record<string, { code: string; message: string }> = {
  PGRST116: { code: 'PROFILE_NOT_FOUND', message: 'Profile not found' },
  '42501': {
    code: 'FORBIDDEN',
    message: 'You do not have permission to perform this action',
  },
  '23505': {
    code: 'PROFILE_EXISTS',
    message: 'Another account already uses this email or mobile number',
  },
  '23514': {
    code: 'VALIDATION_FAILED',
    message: 'Some of the provided details are not valid',
  },
}

function mapProfileError(error: unknown): MappedError {
  const candidate = error as Error & { code?: string }
  const entry = candidate?.code ? PROFILE_ERROR_MAP[candidate.code] : undefined
  if (entry) {
    return { code: entry.code, message: entry.message, original: error as Error }
  }
  // Fall back to message-based mapping (trigger texts, auth codes…).
  return mapError(error as Error)
}

// ── result shapes ─────────────────────────────────────────────

export interface ProfileResult {
  profile: Profile | null
  error: MappedError | null
}

/** Auth-style result for password change (kept separate for clarity). */
export interface PasswordResult {
  success: boolean
  error: MappedError | null
}

export interface ConsentListResult {
  consents: ConsentRecord[]
  error: MappedError | null
}

export interface ConsentResult {
  consent: ConsentRecord | null
  error: MappedError | null
}

export interface DataRequestListResult {
  requests: DataRequest[]
  error: MappedError | null
}

export interface DataRequestResult {
  request: DataRequest | null
  error: MappedError | null
}

// ── internal helpers ──────────────────────────────────────────

/** Current user id or a mapped error when not authenticated. */
async function currentUserId(): Promise<{ userId: string; error: MappedError | null }> {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()

  if (error || !user) {
    return {
      userId: '',
      error: {
        code: 'NOT_AUTHENTICATED',
        message: 'You must be signed in to view or update your profile',
      },
    }
  }
  return { userId: user.id, error: null }
}

function formatValidationErrors(errors: Record<string, string>): string {
  return Object.values(errors).join('; ')
}

// ── own-profile GET (SRS §7) ──────────────────────────────────

/**
 * Fetch the current user's own profile (RLS-scoped to own data).
 * Returns every profile field — the row is the caller's own, so
 * nothing sensitive is exposed to anyone else.
 */
export async function getMyProfile(): Promise<ProfileResult> {
  try {
    const { userId, error: authError } = await currentUserId()
    if (authError) return { profile: null, error: authError }

    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single()

    if (error) return { profile: null, error: mapProfileError(error) }
    return { profile: data as Profile | null, error: null }
  } catch (err: unknown) {
    return { profile: null, error: mapProfileError(err) }
  }
}

// ── own-profile PUT (SRS §7, allowed field rules) ─────────────

/**
 * Update the current user's own profile. Only the T8 allowed fields
 * (full_name, mobile_number, dob, gender, preferred_language) are
 * accepted — the trigger in 009_consents_data_requests.sql refuses
 * email / role / id / created_at changes server-side.
 *
 * `email` and `role` are intentionally NOT part of `ProfileUpdate`;
 * email changes go through the auth flow, role is set by staff/admin.
 */
export async function updateMyProfile(patch: ProfileUpdate): Promise<ProfileResult> {
  try {
    const validation = validateProfileUpdate(patch)
    if (!validation.valid) {
      return {
        profile: null,
        error: {
          code: 'VALIDATION_FAILED',
          message: formatValidationErrors(validation.errors as Record<string, string>),
        },
      }
    }

    const { userId, error: authError } = await currentUserId()
    if (authError) return { profile: null, error: authError }

    const update = buildProfileUpdate(validation.normalized ?? {})
    if (Object.keys(update).length === 0) {
      // Nothing changed — return the current profile unchanged.
      return getMyProfile()
    }

    const { data, error } = await supabase
      .from('profiles')
      .update(update)
      .eq('id', userId)
      .select()
      .single()

    if (error) return { profile: null, error: mapProfileError(error) }
    return { profile: data as Profile | null, error: null }
  } catch (err: unknown) {
    return { profile: null, error: mapProfileError(err) }
  }
}

/** Keep only the whitelisted, defined fields (hard boundary). */
function buildProfileUpdate(patch: ProfileUpdate): Record<string, unknown> {
  const allowed: Record<string, unknown> = {}
  if (patch.full_name !== undefined) allowed.full_name = patch.full_name
  if (patch.mobile_number !== undefined) allowed.mobile_number = patch.mobile_number
  if (patch.dob !== undefined) allowed.dob = patch.dob
  if (patch.gender !== undefined) allowed.gender = patch.gender
  if (patch.preferred_language !== undefined) {
    allowed.preferred_language = patch.preferred_language
  }
  return allowed
}

// ── password change (SRS §7) ──────────────────────────────────

/**
 * Change the current user's password: verifies the current password
 * via a password sign-in, then switches to the new one. The new
 * password must meet the policy (validation.ts / SRS §5).
 */
export async function changePassword(
  currentPassword: string,
  newPassword: string,
): Promise<PasswordResult> {
  try {
    if (!isValidPassword(newPassword)) {
      return {
        success: false,
        error: { code: 'VALIDATION_FAILED', message: passwordPolicyHint() },
      }
    }

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser()
    if (userError || !user?.email) {
      return {
        success: false,
        error: { code: 'NOT_AUTHENTICATED', message: 'You must be signed in to change your password' },
      }
    }

    // Verify the current password before allowing the change.
    const { error: verifyError } = await supabase.auth.signInWithPassword({
      email: user.email,
      password: currentPassword,
    })
    if (verifyError) {
      return {
        success: false,
        error: { code: 'INVALID_CREDENTIALS', message: 'Current password is incorrect' },
      }
    }

    const { error } = await supabase.auth.updateUser({ password: newPassword })
    if (error) return { success: false, error: mapError(error) }

    return { success: true, error: null }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── consent history (SRS §5.1/§17) ────────────────────────────

/**
 * List the current user's consent-history events (most recent first).
 * Rows are immutable and versioned; the latest event per
 * consent_type is the current state.
 */
export async function listConsents(): Promise<ConsentListResult> {
  try {
    const { userId, error: authError } = await currentUserId()
    if (authError) return { consents: [], error: authError }

    const { data, error } = await supabase
      .from('consents')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })

    if (error) return { consents: [], error: mapProfileError(error) }
    return { consents: (data ?? []) as ConsentRecord[], error: null }
  } catch (err: unknown) {
    return { consents: [], error: mapProfileError(err) }
  }
}

/** Record a consent grant for the current user (new history event). */
export async function recordConsent(
  consentType: ConsentType,
  version = 1,
): Promise<ConsentResult> {
  return writeConsent(consentType, version, true)
}

/**
 * Withdraw a consent for the current user (new history event with
 * `granted = false`). Required service consents may be legally non-
 * withdrawable — the UI decides which consents show a withdraw action.
 */
export async function withdrawConsent(
  consentType: ConsentType,
  version = 1,
): Promise<ConsentResult> {
  return writeConsent(consentType, version, false)
}

async function writeConsent(
  consentType: ConsentType,
  version: number,
  granted: boolean,
): Promise<ConsentResult> {
  try {
    const validation = validateConsentInput(consentType, version)
    if (!validation.valid) {
      return {
        consent: null,
        error: {
          code: 'VALIDATION_FAILED',
          message: formatValidationErrors(
            validation.errors as Record<string, string>,
          ),
        },
      }
    }

    const { userId, error: authError } = await currentUserId()
    if (authError) return { consent: null, error: authError }

    const { data, error } = await supabase
      .from('consents')
      .insert({ user_id: userId, consent_type: consentType, version, granted })
      .select()
      .single()

    if (error) return { consent: null, error: mapProfileError(error) }
    return { consent: data as ConsentRecord | null, error: null }
  } catch (err: unknown) {
    return { consent: null, error: mapProfileError(err) }
  }
}

// ── data requests (SRS §12/§17) ───────────────────────────────

/**
 * File a data request (export / correction / deletion /
 * consent_withdrawal) on the current user's behalf. This is the
 * "account deletion / data request entry point" from the customer
 * dashboard. Requests start as `submitted`; staff/admin move them
 * through the queue.
 */
export async function submitDataRequest(
  requestType: DataRequestType,
  details?: Record<string, unknown>,
): Promise<DataRequestResult> {
  try {
    const validation = validateDataRequestInput(requestType, details)
    if (!validation.valid) {
      return {
        request: null,
        error: {
          code: 'VALIDATION_FAILED',
          message: formatValidationErrors(
            validation.errors as Record<string, string>,
          ),
        },
      }
    }

    const { userId, error: authError } = await currentUserId()
    if (authError) return { request: null, error: authError }

    const { data, error } = await supabase
      .from('data_requests')
      .insert({ user_id: userId, request_type: requestType, details: details ?? {} })
      .select()
      .single()

    if (error) return { request: null, error: mapProfileError(error) }
    return { request: data as DataRequest | null, error: null }
  } catch (err: unknown) {
    return { request: null, error: mapProfileError(err) }
  }
}

/** List the current user's data requests (most recent first). */
export async function listDataRequests(): Promise<DataRequestListResult> {
  try {
    const { userId, error: authError } = await currentUserId()
    if (authError) return { requests: [], error: authError }

    const { data, error } = await supabase
      .from('data_requests')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })

    if (error) return { requests: [], error: mapProfileError(error) }
    return { requests: (data ?? []) as DataRequest[], error: null }
  } catch (err: unknown) {
    return { requests: [], error: mapProfileError(err) }
  }
}

// ── re-exports for convenience ────────────────────────────────

export type { ConsentType, DataRequestType, ProfileUpdate } from './types'
export type { MappedError } from './errors'