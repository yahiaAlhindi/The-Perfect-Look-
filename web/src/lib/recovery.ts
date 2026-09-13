/**
 * Password-recovery helpers (T6).
 *
 * Supabase appends `#access_token=…&type=recovery` to the redirect URL.
 * With a hash-base router the tokens land *after* the route hash
 * (`…/#/auth/reset-password#access_token=…`), which `detectSessionInUrl`
 * does not parse cleanly. We extract the tokens ourselves and exchange
 * them with `setSession` so the recover flow works on static hosting.
 */

import { supabase } from './supabase/client'

export interface RecoveryTokens {
  access_token: string
  refresh_token?: string
}

/**
 * Build the reset-password URL used in the recovery email.
 */
export function buildRecoveryRedirectTo(): string {
  const base = import.meta.env.BASE_URL ?? '/'
  return `${window.location.origin}${base}#/auth/reset-password`
}

/**
 * Pull Supabase auth tokens out of a hash that contains both the app route
 * and the token payload (HashRouter case). Returns null when no usable
 * recovery token is present.
 */
export function extractRecoveryTokens(): RecoveryTokens | null {
  const hash = window.location.hash

  const accessMatch = hash.match(/[#&]access_token=([^&]+)/)
  if (!accessMatch) return null

  // Only treat it as a usable recovery/session link.
  const typeMatch = hash.match(/[#&]type=([^&]+)/)
  const type = typeMatch ? decodeURIComponent(typeMatch[1]) : null
  if (type !== null && type !== 'recovery') return null

  const refreshMatch = hash.match(/[#&]refresh_token=([^&]+)/)
  return {
    access_token: decodeURIComponent(accessMatch[1]),
    refresh_token: refreshMatch
      ? decodeURIComponent(refreshMatch[1])
      : undefined,
  }
}

/**
 * Exchange recovery tokens for a session. Returns true when a session was
 * established, false otherwise. A refresh token is required — Supabase
 * recovery links always carry one.
 */
export async function establishRecoverySession(
  tokens: RecoveryTokens,
): Promise<boolean> {
  if (!tokens.refresh_token) return false
  const { error } = await supabase.auth.setSession({
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
  })
  return !error
}

/** True when the URL carries a recovery-token payload. */
export function hasRecoveryTokens(): boolean {
  return extractRecoveryTokens() !== null
}