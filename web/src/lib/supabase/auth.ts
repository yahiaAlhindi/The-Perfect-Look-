import { supabase } from './client'
import type { Profile, ProfileUpdate } from './types'
import {
  normalizeMobile,
  validateEmail,
  normalizeIdentifier,
  InvalidIdentifierError,
} from './validation'
import { mapError, mapped, type MappedError } from './errors'

// ── public result type used by every auth function ─────────────

export interface AuthResult {
  success: boolean
  error?: MappedError
}

// ── sign up (SRS §5) ─────────────────────────────────────────

export interface SignUpParams {
  fullName: string
  email: string
  mobile: string
  password: string
  dob?: string
  gender?: string
  preferredLanguage?: string
}

export async function signUp(params: SignUpParams): Promise<AuthResult> {
  try {
    const normalizedMobile = normalizeMobile(params.mobile)
    const normalizedEmail = params.email.toLowerCase().trim()

    const { error } = await supabase.auth.signUp({
      email: normalizedEmail,
      password: params.password,
      options: {
        data: {
          full_name: params.fullName.trim(),
          mobile_number: normalizedMobile,
          dob: params.dob || null,
          gender: params.gender || null,
          preferred_language: params.preferredLanguage || 'en',
        },
      },
    })

    if (error) {
      return { success: false, error: mapError(error) }
    }

    return { success: true }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── sign in with email OR mobile + password (SRS §6) ──────────

export async function signIn(
  identifier: string,
  password: string,
): Promise<AuthResult> {
  try {
    const normalised = normalizeIdentifier(identifier)

    let email: string

    if (validateEmail(normalised)) {
      email = normalised
    } else {
      // Mobile — resolve to email via DB RPC (SECURITY DEFINER)
      const { data, error: rpcError } = await supabase
        .rpc('resolve_login_identifier', { identifier: normalised })

      if (rpcError || !data || data.length === 0) {
        return {
          success: false,
          error: { code: 'INVALID_CREDENTIALS', message: 'Incorrect email or password' },
        }
      }

      email = data[0].email
    }

    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (error) {
      return { success: false, error: mapError(error) }
    }

    return { success: true }
  } catch (err: unknown) {
    if (err instanceof InvalidIdentifierError) {
      return { success: false, error: { code: 'INVALID_IDENTIFIER', message: err.message } }
    }
    return { success: false, error: mapError(err as Error) }
  }
}

// ── sign out (SRS §6) ─────────────────────────────────────────

export async function signOut(): Promise<AuthResult> {
  try {
    const { error } = await supabase.auth.signOut()
    if (error) {
      return { success: false, error: mapError(error) }
    }
    return { success: true }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── password reset (SRS §6) ───────────────────────────────────

/**
 * Send a password-reset email via Supabase Auth.
 * For a static SPA the redirect URL points back to the app; the
 * new-password form handles the recovery token from the URL hash
 * via `detectSessionInUrl: true` on the client.
 *
 * @param redirectTo optional URL to send in the reset link
 *   (defaults to the Supabase project's Site URL).
 */
export async function resetPassword(
  email: string,
  redirectTo?: string,
): Promise<AuthResult> {
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(
      email.toLowerCase().trim(),
      redirectTo ? { redirectTo } : undefined,
    )
    if (error) {
      return { success: false, error: mapError(error) }
    }
    return { success: true }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── update password (SRS §7) ──────────────────────────────────

/**
 * Update the current user's password. Works both during the
 * recovery flow (when a user arrives from a password-reset link)
 * and while the user is logged in.
 */
export async function updatePassword(newPassword: string): Promise<AuthResult> {
  try {
    const { error } = await supabase.auth.updateUser({
      password: newPassword,
    })
    if (error) {
      return { success: false, error: mapError(error) }
    }
    return { success: true }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── session helpers (SRS §6) ──────────────────────────────────

export async function getSession() {
  const {
    data: { session },
    error,
  } = await supabase.auth.getSession()
  return { session, error }
}

export async function getUser() {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()
  return { user, error }
}

// ── profile (SRS §7) ──────────────────────────────────────────

/**
 * Fetch the current user's profile row (RLS-scoped to own data).
 * Returns `profile` on success or `error` on failure.
 */
export async function getProfile(): Promise<{
  profile: Profile | null
  error: string | null
}> {
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser()

  if (authError || !user) {
    return { profile: null, error: authError?.message ?? 'Not authenticated' }
  }

  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single()

  if (error) {
    return { profile: null, error: error.message }
  }

  return { profile: data as Profile, error: null }
}

// ── update profile — PUT /profile (T8 / SRS §16) ─────────────

export interface UpdateProfileResult {
  success: boolean
  profile?: Profile
  error?: MappedError
}

/**
 * Update the current user's editable profile fields (T8).
 * Only `full_name`, `dob`, `gender` and `preferred_language` are
 * writable by the user — email/mobile changes are restricted/gated
 * pending T35, and `role` is never self-assignable (DB triggers + RLS
 * enforce both even against a direct API call).
 *
 * The public `profiles` row is updated under RLS (own row only) and the
 * account metadata is synced so `auth.user.user_metadata` stays in lock
 * step with the DB.
 */
export async function updateProfile(
  fields: ProfileUpdate,
): Promise<UpdateProfileResult> {
  try {
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()
    if (authError || !user) {
      return {
        success: false,
        error: mapped('NOT_AUTHENTICATED', 'You must be signed in to update your profile'),
      }
    }

    // Never allow a client to set email / mobile / role through this endpoint.
    const { full_name } = fields
    const payload = {
      full_name: full_name.trim(),
      dob: fields.dob ?? null,
      gender: fields.gender ?? null,
      preferred_language: fields.preferred_language ?? user.user_metadata?.preferred_language ?? 'en',
    }

    const { data, error } = await supabase
      .from('profiles')
      .update(payload)
      .eq('id', user.id)
      .select('*')
      .single()

    if (error) {
      return { success: false, error: mapError(error as Error) }
    }

    // Keep auth metadata in sync (best-effort; the DB row is authoritative).
    await supabase.auth.updateUser({
      data: {
        full_name: payload.full_name,
        dob: payload.dob,
        gender: payload.gender,
        preferred_language: payload.preferred_language,
      },
    })

    return { success: true, profile: data as Profile }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── change password — T8 / SRS §7 ─────────────────────────────

export interface ChangePasswordResult {
  success: boolean
  error?: MappedError
}

/**
 * Change the signed-in user's password (T8).
 * The current password is first verified against the active session
 * (`signInWithPassword` with the session user's email) — a wrong current
 * password is rejected before any change is made. Only then is the new
 * password applied via `updateUser({ password })`.
 */
export async function changePassword(
  currentPassword: string,
  newPassword: string,
): Promise<ChangePasswordResult> {
  try {
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()
    if (authError || !user || !user.email) {
      return {
        success: false,
        error: mapped('NOT_AUTHENTICATED', 'You must be signed in to change your password'),
      }
    }

    const { error: verifyError } = await supabase.auth.signInWithPassword({
      email: user.email,
      password: currentPassword,
    })
    if (verifyError) {
      return { success: false, error: mapError(verifyError) }
    }

    const { error } = await supabase.auth.updateUser({ password: newPassword })
    if (error) {
      return { success: false, error: mapError(error) }
    }

    return { success: true }
  } catch (err: unknown) {
    return { success: false, error: mapError(err as Error) }
  }
}

// ── auth state (SRS §6) ───────────────────────────────────────

/**
 * Subscribe to Supabase Auth state changes.
 * Returns an unsubscribe function. Typical usage:
 *
 *   const unsub = onAuthStateChange((event, session) => {
 *     if (event === 'SIGNED_IN') { ... }
 *   })
 *   // in cleanup: unsub()
 */
export function onAuthStateChange(
  callback: (event: string, session: unknown) => void,
): () => void {
  const {
    data: { subscription },
  } = supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session)
  })

  return () => subscription.unsubscribe()
}

export type { MappedError } from './errors'